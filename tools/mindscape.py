#!/usr/bin/env python3
"""Mindscape <-> AI agent bridge.

协议（详见 AI-INTEGRATION.md）：
    工具写  <dataDir>/inbox/req-<uuid>.json
    app 读  并回写 ack-<uuid>.json，然后移动 req 到 done/ 或 rejected/
    工具等  ack，最多 3 秒；超时视为 app 未运行，请求排队。

同一个模块既是对人用的 CLI，也是给 agent 用的 MCP stdio server：

    python3 mindscape.py create -f plan.json
    python3 mindscape.py mcp

只用标准库，无第三方依赖。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

TOOL_VERSION = "1.0.0"
APP_BUNDLE_ID = "com.youyanping.mindscape"
MCP_PROTOCOL_VERSION = "2025-06-18"
ACK_TIMEOUT = float(os.environ.get("MINDSCAPE_ACK_TIMEOUT", "3.0"))

LIMITS = {
    "nodes": 2000,
    "depth": 12,
    "text": 500,
    "note": 4000,
    "file_bytes": 2 * 1024 * 1024,
    "edits": 500,
}

LAYOUTS = {
    "mindMap": "思维导图",
    "logicRight": "逻辑图（右）",
    "logicLeft": "逻辑图（左）",
    "orgChart": "组织架构图",
    "tree": "树形图",
    "timeline": "时间轴",
    "braceMap": "括号图",
    "free": "自由布局",
}

THEMES = {"paper", "midnight", "morandi", "corporate", "blueprint", "neon", "sand", "ink"}

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
NODE_EDIT_KINDS = {"setText", "setNote", "setColor", "setIcon", "addChildren", "remove", "move"}
MAP_EDIT_KINDS = {"setLayout", "setTheme", "setTitle"}
ALL_EDIT_KINDS = NODE_EDIT_KINDS | MAP_EDIT_KINDS


class BridgeError(Exception):
    def __init__(self, reason: str, message: str):
        super().__init__(message)
        self.reason = reason
        self.message = message

    def payload(self) -> dict:
        return {"ok": False, "reason": self.reason, "message": self.message}


def log(*args: Any) -> None:
    if os.environ.get("MINDSCAPE_DEBUG"):
        print("[mindscape]", *args, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# 数据目录
# --------------------------------------------------------------------------


def data_dir() -> Path:
    """按 AI-INTEGRATION.md §3 的顺序定位数据目录。"""
    env = os.environ.get("MINDSCAPE_DATA_DIR")
    if env:
        return Path(env).expanduser()

    configured: str | None = None
    try:
        out = subprocess.run(
            ["defaults", "read", APP_BUNDLE_ID, "dataDirectory"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if out.returncode == 0:
            configured = out.stdout.strip()
    except Exception:  # defaults 不存在 / 超时 / 非 macOS
        configured = None

    if configured:
        return Path(configured).expanduser()
    return Path.home() / "Library" / "Application Support" / "Mindscape"


def inbox_dir(root: Path) -> Path:
    return root / "inbox"


def outbox_dir(root: Path) -> Path:
    return root / "outbox"


def ensure_dirs(root: Path) -> None:
    for path in (inbox_dir(root), inbox_dir(root) / "done", inbox_dir(root) / "rejected", outbox_dir(root)):
        path.mkdir(parents=True, exist_ok=True)


def atomic_write_json(path: Path, payload: Any) -> None:
    tmp = path.with_name(path.name + ".tmp")
    data = json.dumps(payload, ensure_ascii=False, indent=1).encode("utf-8")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# 校验与规范化
# --------------------------------------------------------------------------


def _truncate(value: str, limit: int, warnings: list[str], label: str) -> str:
    if len(value) <= limit:
        return value
    warnings.append(f"{label} 超过 {limit} 字符，已截断")
    return value[:limit]


def _validate_tree(node: Any, depth: int, counter: list[int], warnings: list[str]) -> dict:
    if depth > LIMITS["depth"]:
        raise BridgeError("too_large", f"层级超过 {LIMITS['depth']} 层")
    if not isinstance(node, dict):
        raise BridgeError("invalid", f"第 {depth} 层的节点不是对象")

    counter[0] += 1
    if counter[0] > LIMITS["nodes"]:
        raise BridgeError("too_large", f"节点数超过 {LIMITS['nodes']}")

    text = node.get("text")
    if not isinstance(text, str) or not text.strip():
        raise BridgeError("invalid", "节点缺少非空的 text")

    out: dict[str, Any] = {"text": _truncate(text.strip(), LIMITS["text"], warnings, "text")}

    note = node.get("note")
    if isinstance(note, str) and note:
        out["note"] = _truncate(note, LIMITS["note"], warnings, "note")

    icon = node.get("icon")
    if isinstance(icon, str) and icon:
        # 图标白名单在 app 的 IconCatalog 里，工具不复制那 102 个名字；
        # 不认识的图标由 app 静默丢弃，避免模型被列表困住。
        out["icon"] = icon[:64]

    color = node.get("color")
    if isinstance(color, str) and color:
        if HEX_RE.match(color):
            out["color"] = color.lower()
        else:
            warnings.append(f"忽略非法颜色 {color!r}（需要 #RRGGBB）")

    children = node.get("children")
    if children is not None:
        if not isinstance(children, list):
            raise BridgeError("invalid", "children 必须是数组")
        if children:
            out["children"] = [
                _validate_tree(child, depth + 1, counter, warnings) for child in children
            ]
    return out


def normalize_create(payload: dict, overrides: dict) -> dict:
    tree = payload.get("tree")
    if tree is None and isinstance(payload.get("text"), str):
        tree = payload  # 允许直接传一棵裸树
    if tree is None:
        raise BridgeError("invalid", "缺少 tree")

    warnings: list[str] = []
    counter = [0]
    clean = _validate_tree(tree, 0, counter, warnings)

    layout = overrides.get("layout") or payload.get("layout") or "mindMap"
    if layout not in LAYOUTS:
        raise BridgeError(
            "invalid", f"未知布局 {layout!r}，可选：{', '.join(LAYOUTS)}"
        )
    theme = overrides.get("theme") or payload.get("theme") or "paper"
    if not isinstance(theme, str) or not theme:
        raise BridgeError("invalid", "theme 必须是字符串")
    if theme not in THEMES:
        raise BridgeError("invalid", f"未知主题 {theme!r}，可选：{', '.join(sorted(THEMES))}")

    title = overrides.get("title") or payload.get("title")
    if title is not None and not isinstance(title, str):
        raise BridgeError("invalid", "title 必须是字符串")
    title = title.strip() if isinstance(title, str) else None
    if not title:
        title = None

    request = {
        "op": "create",
        "title": _truncate(title, 120, warnings, "title") if title else None,
        "layout": layout,
        "theme": theme,
        "tree": clean,
    }
    if request["title"] is None:
        del request["title"]
    return {"request": request, "warnings": warnings, "nodeCount": counter[0]}


def _validate_target(target: Any) -> dict:
    if not isinstance(target, dict):
        raise BridgeError("invalid", "edit 缺少 target")
    if isinstance(target.get("id"), str) and target["id"]:
        return {"id": target["id"]}
    path = target.get("path")
    if isinstance(path, list) and path and all(isinstance(p, str) for p in path):
        return {"path": path}
    raise BridgeError("invalid", 'target 需要 {"id": "…"} 或 {"path": ["根", "子"]}')


def _validate_edit(edit: Any) -> dict:
    if not isinstance(edit, dict):
        raise BridgeError("invalid", "edit 不是对象")
    kind = edit.get("kind")
    if kind not in ALL_EDIT_KINDS:
        raise BridgeError("invalid", f"未知 edit kind {kind!r}")

    if kind in MAP_EDIT_KINDS:
        key = {"setLayout": "layout", "setTheme": "theme", "setTitle": "title"}[kind]
        value = edit.get(key)
        if not isinstance(value, str) or not value.strip():
            raise BridgeError("invalid", f"{kind} 缺少 {key}")
        if kind == "setLayout" and value not in LAYOUTS:
            raise BridgeError("invalid", f"未知布局 {value!r}")
        if kind == "setTheme" and value not in THEMES:
            raise BridgeError("invalid", f"未知主题 {value!r}")
        return {"kind": kind, key: value.strip()}

    out: dict[str, Any] = {"kind": kind, "target": _validate_target(edit.get("target"))}
    if kind == "setText":
        text = edit.get("text")
        if not isinstance(text, str) or not text.strip():
            raise BridgeError("invalid", "setText 缺少 text")
        out["text"] = text.strip()[: LIMITS["text"]]
    elif kind == "setNote":
        note = edit.get("note")
        if not isinstance(note, str):
            raise BridgeError("invalid", "setNote 缺少 note")
        out["note"] = note[: LIMITS["note"]]
    elif kind == "setColor":
        color = edit.get("color")
        if not isinstance(color, str) or not HEX_RE.match(color):
            raise BridgeError("invalid", "setColor 需要 #RRGGBB")
        out["color"] = color.lower()
    elif kind == "setIcon":
        icon = edit.get("icon")
        if not isinstance(icon, str):
            raise BridgeError("invalid", "setIcon 缺少 icon")
        out["icon"] = icon.strip()[:64]
    elif kind == "addChildren":
        nodes = edit.get("nodes")
        if not isinstance(nodes, list) or not nodes:
            raise BridgeError("invalid", "addChildren 缺少 nodes")
        warnings: list[str] = []
        counter = [0]
        out["nodes"] = [_validate_tree(n, 1, counter, warnings) for n in nodes]
        if counter[0] > LIMITS["nodes"]:
            raise BridgeError("too_large", f"新增节点超过 {LIMITS['nodes']}")
    elif kind == "move":
        out["newParent"] = _validate_target(edit.get("newParent")) if edit.get("newParent") else None
    return out


def normalize_patch(payload: dict, doc_override: str | None) -> dict:
    doc = doc_override or payload.get("doc")
    if not isinstance(doc, str) or not doc:
        raise BridgeError("invalid", "缺少 doc（导图 id）")

    edits = payload.get("edits")
    if not isinstance(edits, list) or not edits:
        raise BridgeError("invalid", "edits 必须是非空数组")
    if len(edits) > LIMITS["edits"]:
        raise BridgeError("too_large", f"edits 超过 {LIMITS['edits']}")

    base = payload.get("baseUpdatedAt")
    if base is not None and not isinstance(base, (int, float)):
        raise BridgeError("invalid", "baseUpdatedAt 必须是数字或 null")

    return {
        "request": {
            "op": "patch",
            "doc": doc,
            "baseUpdatedAt": base,
            "edits": [_validate_edit(e) for e in edits],
        },
        "warnings": [],
        "nodeCount": 0,
    }


def normalize(payload: Any, overrides: dict, doc_override: str | None) -> dict:
    if not isinstance(payload, dict):
        raise BridgeError("invalid", "请求必须是 JSON 对象")
    op = payload.get("op")
    if op is None:
        op = "patch" if doc_override or payload.get("edits") else "create"
    if op == "create":
        return normalize_create(payload, overrides)
    if op == "patch":
        return normalize_patch(payload, doc_override)
    raise BridgeError("invalid", f"未知 op {op!r}（只支持 create / patch）")


# --------------------------------------------------------------------------
# 投递与回执
# --------------------------------------------------------------------------


def launch_app() -> None:
    """把 Mindscape 带到前台；没运行就启动它。失败不报错。"""
    if os.environ.get("MINDSCAPE_NO_LAUNCH") == "1":
        return
    try:
        subprocess.run(
            ["open", "-b", APP_BUNDLE_ID],
            capture_output=True,
            timeout=3,
            check=False,
        )
        log("launched app")
    except Exception as exc:  # open 不存在 / 超时 / 非 macOS
        log("launch failed", exc)


def submit(root: Path, request: dict, wait: float | None = None, launch: bool = True) -> dict:
    """投递请求并等回执。

    app 没在运行时（outbox/state.json 太旧或不存在）会顺手 `open` 它一次，
    这样"关着 app 让 AI 画一张"也能在几秒内看到结果；启动失败就退化成排队。
    """
    if wait is None:
        wait = float(os.environ.get("MINDSCAPE_ACK_TIMEOUT", "5.0"))
    ensure_dirs(root)
    key = uuid.uuid4().hex
    req_path = inbox_dir(root) / f"req-{key}.json"
    ack_path = inbox_dir(root) / f"ack-{key}.json"

    atomic_write_json(req_path, request)
    log("submitted", req_path.name)

    if wait <= 0:
        return {"ok": True, "queued": True, "request": req_path.name}

    started = time.monotonic()
    deadline = started + wait
    tried_launch = False

    while time.monotonic() < deadline:
        if ack_path.exists():
            try:
                reply = json.loads(ack_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                time.sleep(0.05)
                continue
            ack_path.unlink(missing_ok=True)
            reply.setdefault("request", req_path.name)
            return reply

        if launch and not tried_launch and time.monotonic() - started > 0.4:
            tried_launch = True
            if not read_context(root).get("appRunning"):
                launch_app()
                # 冷启动要读库、建窗口，给足时间；超时仍会退化成排队
                deadline = max(deadline, time.monotonic() + 6.0)

        time.sleep(0.05)

    # app 没开：请求留在 inbox，下次启动补导入。不删文件，不报错。
    return {"ok": True, "queued": True, "request": req_path.name}


# --------------------------------------------------------------------------
# 读库（只读）
# --------------------------------------------------------------------------


def database_path(root: Path) -> Path:
    return root / "mindscape.sqlite"


def open_readonly(db_path: Path) -> sqlite3.Connection | None:
    if not db_path.exists():
        return None
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2)
    conn.row_factory = sqlite3.Row
    return conn


def list_documents(root: Path) -> list[dict]:
    conn = open_readonly(database_path(root))
    if conn is None:
        return []
    try:
        rows = conn.execute(
            "SELECT id, title, layout, theme, updated_at, node_count, preview, folder_id "
            "FROM documents WHERE deleted_at IS NULL ORDER BY updated_at DESC"
        ).fetchall()
    except sqlite3.Error as exc:
        raise BridgeError("unsupported", f"数据库结构不匹配：{exc}") from exc
    finally:
        conn.close()
    return [
        {
            "id": row["id"],
            "title": row["title"],
            "layout": row["layout"],
            "theme": row["theme"],
            "updatedAt": row["updated_at"],
            "nodeCount": row["node_count"],
            "preview": row["preview"],
            "folder": row["folder_id"],
        }
        for row in rows
    ]


def load_document(root: Path, doc_id: str) -> tuple[dict, dict]:
    """返回 (记录行, 原始 content 字典)。"""
    conn = open_readonly(database_path(root))
    if conn is None:
        raise BridgeError("not_found", "数据库不存在，app 可能还没运行过")
    try:
        row = conn.execute(
            "SELECT id, title, layout, theme, updated_at, content FROM documents "
            "WHERE id = ? AND deleted_at IS NULL",
            (doc_id,),
        ).fetchone()
    finally:
        conn.close()
    if row is None:
        raise BridgeError("not_found", f"找不到导图 {doc_id}")
    try:
        content = json.loads(row["content"])
    except json.JSONDecodeError as exc:
        raise BridgeError("unsupported", f"导图内容不是合法 JSON：{exc}") from exc
    record = {
        "id": row["id"],
        "title": row["title"],
        "layout": row["layout"],
        "theme": row["theme"],
        "updatedAt": row["updated_at"],
    }
    return record, content


def build_tree(content: dict) -> dict:
    """把内部扁平节点表折成树。

    工具只认四个字段：id / parentID / text / children。其余原样不动。
    这是工具唯一需要知道的内部结构，doctor 会在结构变化时报错。
    """
    nodes = content.get("nodes")
    if not isinstance(nodes, list):
        raise BridgeError("unsupported", "导图内容缺少 nodes 数组")

    by_parent: dict[str | None, list[dict]] = {}
    for node in nodes:
        if not isinstance(node, dict) or "id" not in node:
            raise BridgeError("unsupported", "节点结构不符合预期（缺少 id）")
        by_parent.setdefault(node.get("parentID"), []).append(node)

    for bucket in by_parent.values():
        bucket.sort(key=lambda n: (n.get("order", 0), n.get("id", "")))

    existing = {n["id"] for n in nodes}

    def convert(node: dict, depth: int = 0) -> dict:
        if depth > LIMITS["depth"] + 2:
            raise BridgeError("unsupported", "节点层级异常，可能存在环")
        out: dict[str, Any] = {"id": node["id"], "text": node.get("text", "")}
        if node.get("note"):
            out["note"] = node["note"]
        if node.get("icon"):
            out["icon"] = node["icon"]
        if node.get("colorHex"):
            out["color"] = node["colorHex"]
        kids = by_parent.get(node["id"], [])
        if kids:
            out["children"] = [convert(k, depth + 1) for k in kids]
        return out

    roots = [n for n in nodes if n.get("parentID") not in existing]
    roots.sort(key=lambda n: (n.get("order", 0), n.get("id", "")))
    if not roots:
        raise BridgeError("unsupported", "找不到根节点")
    return {
        "title": content.get("title", ""),
        "layout": content.get("layout", "mindMap"),
        "theme": content.get("themeID", "paper"),
        "tree": convert(roots[0]),
        "roots": [convert(r) for r in roots],
    }


def read_context(root: Path) -> dict:
    path = outbox_dir(root) / "state.json"
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"appRunning": False, "reason": "没有 outbox/state.json", "docID": None}
    ts = state.get("ts", 0)
    fresh = isinstance(ts, (int, float)) and (time.time() - ts) < 15
    state["appRunning"] = bool(fresh)
    if not fresh:
        state["reason"] = "state.json 超过 15 秒未更新，app 可能没在运行"
    return state


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def _emit(payload: dict, code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=1))
    return code


def load_json_arg(path: str | None, use_stdin: bool) -> Any:
    if use_stdin or path in (None, "-"):
        raw = sys.stdin.read()
    else:
        p = Path(path).expanduser()
        if p.stat().st_size > LIMITS["file_bytes"]:
            raise BridgeError("too_large", "请求文件超过 2MB")
        raw = p.read_text(encoding="utf-8")
    if not raw.strip():
        raise BridgeError("invalid", "输入为空")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise BridgeError("invalid", f"不是合法 JSON：{exc}") from exc


def cmd_create(args: argparse.Namespace) -> int:
    payload = load_json_arg(args.file, args.stdin)
    overrides = {"layout": args.layout, "theme": args.theme, "title": args.title}
    normalized = normalize(payload, overrides, None)
    reply = submit(data_dir(), normalized["request"], args.wait)
    reply.setdefault("warnings", normalized["warnings"])
    reply.setdefault("nodeCount", normalized["nodeCount"])
    return _emit(reply, 0 if reply.get("ok") else 1)


def cmd_patch(args: argparse.Namespace) -> int:
    payload = load_json_arg(args.file, args.stdin)
    normalized = normalize(payload, {}, args.doc)
    reply = submit(data_dir(), normalized["request"], args.wait)
    return _emit(reply, 0 if reply.get("ok") else 1)


def cmd_list(args: argparse.Namespace) -> int:
    return _emit({"ok": True, "documents": list_documents(data_dir())})


def cmd_get(args: argparse.Namespace) -> int:
    root = data_dir()
    record, content = load_document(root, args.doc)
    if args.raw:
        return _emit({"ok": True, **record, "content": content})
    tree = build_tree(content)
    return _emit({"ok": True, **record, **tree})


def cmd_context(args: argparse.Namespace) -> int:
    return _emit({"ok": True, **read_context(data_dir())})


def cmd_doctor(args: argparse.Namespace) -> int:
    root = data_dir()
    report: dict[str, Any] = {"ok": True, "dataDir": str(root), "checks": []}

    def check(name: str, passed: bool, detail: str) -> None:
        report["checks"].append({"name": name, "ok": passed, "detail": detail})
        if not passed:
            report["ok"] = False

    check("dataDir", root.exists(), str(root))
    check("database", database_path(root).exists(), str(database_path(root)))
    check("inbox", inbox_dir(root).exists() or os.access(root, os.W_OK), str(inbox_dir(root)))

    docs: list[dict] = []
    try:
        docs = list_documents(root)
        check("documents", True, f"{len(docs)} 张导图")
    except BridgeError as exc:
        check("documents", False, exc.message)

    if docs:
        try:
            _, content = load_document(root, docs[0]["id"])
            build_tree(content)
            check("content", True, "能解析 content 并折成树")
        except BridgeError as exc:
            check("content", False, exc.message)

    state = read_context(root)
    report["appRunning"] = state.get("appRunning", False)
    report["inboxPending"] = len(list(inbox_dir(root).glob("req-*.json"))) if inbox_dir(root).exists() else 0
    return _emit(report, 0 if report["ok"] else 1)


# --------------------------------------------------------------------------
# MCP（stdio，换行分隔 JSON-RPC 2.0）
# --------------------------------------------------------------------------

TOOLS = [
    {
        "name": "create_map",
        "description": (
            "在 Mindscape 里新建一张思维导图并立即显示。当用户要求把内容整理成导图、脑图、"
            "大纲图、拆解图时使用。传一棵树，不要自己编 ID。节点字段：text（必填）、"
            "note、icon（SF Symbols 名，如 lightbulb/target/flag）、color（#RRGGBB）、children。"
            "layout 可选 mindMap/logicRight/logicLeft/orgChart/tree/timeline/braceMap/free；"
            "theme 可选 paper/midnight/morandi/corporate/blueprint/neon/sand/ink 之一。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "tree": {"type": "object", "description": "根节点，含 text 与 children"},
                "title": {"type": "string", "description": "导图标题，缺省用根节点文字"},
                "layout": {"type": "string"},
                "theme": {"type": "string"},
            },
            "required": ["tree"],
        },
    },
    {
        "name": "patch_map",
        "description": (
            "修改一张已存在的导图。改之前先调用 get_context：如果用户正在编辑那张图或有未保存改动，"
            "app 会拒绝写入并返回 busy，把原因转告用户即可，不要重试。"
            "每条 edit 形如 {kind:'addChildren', target:{id:'…'}, nodes:[…]}，"
            "kind 支持 setText/setNote/setColor/setIcon/addChildren/remove/move/setLayout/setTheme/setTitle。"
            "整批原子生效。baseUpdatedAt 传 get_map 拿到的 updatedAt。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "doc": {"type": "string"},
                "baseUpdatedAt": {"type": "number"},
                "edits": {"type": "array", "items": {"type": "object"}},
            },
            "required": ["doc", "edits"],
        },
    },
    {
        "name": "list_maps",
        "description": "列出 Mindscape 里的导图（id、标题、更新时间、节点数、预览）。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_map",
        "description": "读取一张导图的完整树结构（节点带 id，可用于 patch 的 target）。",
        "inputSchema": {
            "type": "object",
            "properties": {"doc": {"type": "string"}},
            "required": ["doc"],
        },
    },
    {
        "name": "get_context",
        "description": "查看用户当前在 Mindscape 里看哪张导图、选中了哪些节点、是否正在编辑。",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def tool_result(payload: dict, is_error: bool = False) -> dict:
    return {
        "content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}],
        "isError": is_error,
    }


def call_tool(name: str, args: dict) -> dict:
    root = data_dir()
    try:
        if name == "create_map":
            overrides = {
                "layout": args.get("layout"),
                "theme": args.get("theme"),
                "title": args.get("title"),
            }
            normalized = normalize(args, overrides, None)
            reply = submit(root, normalized["request"])
            reply.setdefault("warnings", normalized["warnings"])
            return tool_result(reply, is_error=reply.get("ok") is False)
        if name == "patch_map":
            normalized = normalize(args, {}, args.get("doc"))
            reply = submit(root, normalized["request"])
            return tool_result(reply, is_error=reply.get("ok") is False)
        if name == "list_maps":
            return tool_result({"ok": True, "documents": list_documents(root)})
        if name == "get_map":
            record, content = load_document(root, args.get("doc", ""))
            return tool_result({"ok": True, **record, **build_tree(content)})
        if name == "get_context":
            return tool_result({"ok": True, **read_context(root)})
        return tool_result({"ok": False, "reason": "invalid", "message": f"未知工具 {name}"}, True)
    except BridgeError as exc:
        return tool_result(exc.payload(), True)
    except Exception as exc:  # 兜底：不让协议层崩掉
        return tool_result({"ok": False, "reason": "invalid", "message": str(exc)}, True)


def handle_message(message: Any) -> dict | None:
    if isinstance(message, list):
        replies = [handle_message(m) for m in message]
        return [r for r in replies if r is not None]
    if not isinstance(message, dict):
        return {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "Invalid Request"}}

    method = message.get("method")
    msg_id = message.get("id")
    is_notification = "id" not in message

    if method == "initialize":
        result = {
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "mindscape", "version": TOOL_VERSION},
            "instructions": (
                "Mindscape 是本地思维导图 app。用户说“画成导图/整理成脑图”时用 create_map；"
                "改现有图前先 get_context，返回 busy 就直接转告用户，不要重试。"
            ),
        }
        return None if is_notification else {"jsonrpc": "2.0", "id": msg_id, "result": result}

    if method == "ping":
        return None if is_notification else {"jsonrpc": "2.0", "id": msg_id, "result": {}}

    if method == "tools/list":
        return None if is_notification else {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {"tools": TOOLS},
        }

    if method == "tools/call":
        params = message.get("params") or {}
        name = params.get("name", "")
        args = params.get("arguments") or {}
        if not isinstance(args, dict):
            return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32602, "message": "arguments 必须是对象"}}
        result = call_tool(name, args)
        return None if is_notification else {"jsonrpc": "2.0", "id": msg_id, "result": result}

    if method in ("notifications/initialized", "notifications/cancelled"):
        return None

    if is_notification:
        return None
    return {
        "jsonrpc": "2.0",
        "id": msg_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def serve_mcp() -> int:
    log("mcp ready, data dir =", data_dir())
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": str(exc)}}
        else:
            reply = handle_message(message)
        if reply is None:
            continue
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    return 0


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mindscape",
        description="Mindscape ↔ AI agent bridge（投递 JSON，app 负责落库）",
    )
    parser.add_argument("--version", action="version", version=f"mindscape {TOOL_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_create = sub.add_parser("create", help="新建一张导图")
    p_create.add_argument("-f", "--file", help="请求 JSON（省略或 - 读 stdin）")
    p_create.add_argument("--stdin", action="store_true")
    p_create.add_argument("--title")
    p_create.add_argument("--layout", choices=sorted(LAYOUTS))
    p_create.add_argument("--theme")
    p_create.add_argument("--wait", type=float, default=None, help="等回执秒数，0 = 不等待")
    p_create.set_defaults(func=cmd_create)

    p_patch = sub.add_parser("patch", help="修改已有导图")
    p_patch.add_argument("-f", "--file")
    p_patch.add_argument("--stdin", action="store_true")
    p_patch.add_argument("--doc")
    p_patch.add_argument("--wait", type=float, default=None)
    p_patch.set_defaults(func=cmd_patch)

    p_list = sub.add_parser("list", help="列出导图")
    p_list.set_defaults(func=cmd_list)

    p_get = sub.add_parser("get", help="读取一张导图")
    p_get.add_argument("doc")
    p_get.add_argument("--raw", action="store_true", help="输出内部原始 JSON")
    p_get.set_defaults(func=cmd_get)

    p_ctx = sub.add_parser("context", help="查看 app 当前状态")
    p_ctx.set_defaults(func=cmd_context)

    p_doc = sub.add_parser("doctor", help="自检")
    p_doc.set_defaults(func=cmd_doctor)

    p_mcp = sub.add_parser("mcp", help="以 MCP stdio server 运行")
    p_mcp.set_defaults(func=lambda _args: serve_mcp())

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except BridgeError as exc:
        return _emit(exc.payload(), 1)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
