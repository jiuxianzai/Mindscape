# Mindscape ↔ AI Agent 打通方案（v1）

> 状态：已实现并通过验证（转换器单测、全量类型检查、端到端投递）。验证细节见文末 §14。
> 目标版本 0.6.0。本文是实现依据，含数据契约、改动点、验收标准。
> 原则：**AI 只投递文件，写库和判定都在 app 里**；内部格式不对外暴露。

---

## 1. 目标

在任意支持 MCP 或 shell 的 agent（Claude Code / Codex / Cursor / 本机 harness）里说一句话，就能：

1. **出一张成品图** —— app 自动出现排好版、套好主题、带图标的导图，可直接编辑 / 演示。
2. **原地改现有图** —— 同一张图、同一个位置、标题不变，⌘Z 可撤。
3. **AI 知道我在看什么** —— 能读当前文档、选中节点，接着手上的活干。
4. **app 没开也不丢** —— 请求排队，下次启动补导入。

### 非目标（本版不做）

- 实时流式绘制（agent 是回合制的，推送无收益）
- 多人协作 / CRDT 合并
- 修改用户**有未保存改动**的文档（一律拒绝，见 §8）
- 直写 SQLite（只读，不写）
- PNG/PDF 导出工具（M4 再说，需要 app 跑着渲染）

---

## 2. 架构

```
┌──────────────┐   MCP(stdio) / shell   ┌─────────────────────────┐
│  AI Agent    │ ─────────────────────► │  mindscape (Python 3)   │
│ Claude/Codex │ ◄───────────────────── │  create/patch/read/ctx  │
└──────────────┘    JSON 结果 + 错误     └───────────┬─────────────┘
                                                    │ 原子写 JSON
                                                    ▼
                              <dataDir>/inbox/req-<uuid>.json
                                                    │ FSEvents
┌───────────────────────────────────────────────────▼─────────────┐
│ Mindscape.app (Swift)                                            │
│  校验 → 忙判定 → 转 MindMap → store.save + snapshot → 刷新 UI    │
│  写回 ack-<uuid>.json（成功/失败原因）                            │
│  选中变化 → outbox/state.json（供 agent 读"我在看什么"）          │
└──────────────────────────────────────────────────────────────────┘
```

三个进程角色，一条文件契约。没有端口、没有常驻 socket、没有账号。

---

## 3. 目录布局（跟随 app 的数据目录）

```
<dataDir>/                      默认 ~/Library/Application Support/Mindscape
├── mindscape.sqlite            app 独占写；工具只读
├── inbox/
│   ├── req-<uuid>.json         agent 投递（工具写，app 消费）
│   ├── ack-<uuid>.json         app 回执（2s 内写）
│   ├── done/                   已成功应用
│   └── rejected/               被拒（保留现场，便于排查）
└── outbox/
    └── state.json              app 写：当前文档 / 选中 / 是否在编辑
```

**数据目录发现顺序**（工具侧）：
1. 环境变量 `MINDSCAPE_DATA_DIR`
2. `defaults read com.youyanping.mindscape dataDirectory`
3. `~/Library/Application Support/Mindscape`

---

## 4. 数据契约

### 4.1 `create`

```json
{
  "op": "create",
  "title": "Q4 规划",
  "layout": "mindMap",
  "theme": "paper",
  "tree": {
    "text": "Q4 规划",
    "note": "北极星：DAU 提升 30%",
    "icon": "target",
    "color": "#C26A4A",
    "children": [
      {"text": "增长", "children": [{"text": "渠道"}, {"text": "留存"}]},
      {"text": "风险", "color": "#C26A4A", "children": [{"text": "预算超支"}]}
    ]
  }
}
```

- `title` 缺省 = 根节点 text；`layout` 缺省 `mindMap`；`theme` 缺省 `paper`。
- `icon` 必须在 `IconCatalog.all` 里，否则**静默丢弃**（不报错，避免模型被 102 个名字卡住）。
- `color` 必须 `#RRGGBB`，否则丢弃。
- 节点可选字段：`text`（必填）、`note`、`icon`、`color`、`children`。

### 4.2 `patch`

```json
{
  "op": "patch",
  "doc": "0F3C…-UUID",
  "baseUpdatedAt": 1730000000.0,
  "edits": [
    {"kind": "setText",     "target": {"id": "…"}, "text": "新的文字"},
    {"kind": "setNote",     "target": {"id": "…"}, "note": "…"},
    {"kind": "setColor",    "target": {"id": "…"}, "color": "#8C857B"},
    {"kind": "addChildren", "target": {"id": "…"}, "nodes": [{"text": "…"}]},
    {"kind": "remove",      "target": {"id": "…"}},
    {"kind": "setLayout",   "layout": "timeline"},
    {"kind": "setTheme",    "theme": "ink"},
    {"kind": "setTitle",    "title": "…"}
  ]
}
```

- `target` 二选一：`{"id": "节点UUID"}`（精确）或 `{"path": ["Q4 规划","增长"]}`（按标题路径，名字重复时取深度优先第一个）。
- `baseUpdatedAt`：读取时的 `updatedAt`。不一致 → `stale`，工具返回当前值让模型重读（**不自动合并**）。
- **整批原子**：全部校验通过才落盘一次 `save` + 一次 `addSnapshot(kind:"ai")`；任一 edit 失败则整批不生效。

### 4.3 读取

`list_maps` →
```json
[{"id":"…","title":"Q4 规划","updatedAt":1730000000.0,"nodeCount":42,"preview":"增长 · 渠道 · 留存"}]
```

`get_map` →
```json
{"id":"…","title":"…","layout":"mindMap","theme":"paper","updatedAt":…,
 "tree":{"id":"…","text":"…","children":[…]}}
```

`get_context` →（读 outbox/state.json，`ts` 超过 15s 视为 app 未运行）
```json
{"appRunning":true,"docID":"…","title":"Q4 规划","layout":"mindMap",
 "selection":[{"id":"…","text":"增长"}],"editingNode":null,"unsaved":false,"ts":…}
```

### 4.4 回执

```json
{"ok": true,  "docID": "…", "title": "…", "action": "created|patched", "nodeCount": 42}
{"ok": false, "reason": "busy", "doc": "…", "state": "unsaved|editing",
 "message": "该文档还有未保存的改动，已拒绝写入"}
```

错误码：`busy` `stale` `not_found` `invalid` `too_large` `unsupported`。

### 4.5 限制（app 侧强制，工具侧预校验同一套数）

| 项 | 上限 | 超限行为 |
|---|---|---|
| 节点数 | 2000 | `too_large` |
| 深度 | 12 | `too_large` |
| 单个 text | 500 字符 | 截断、附 warning |
| 单个 note | 4000 字符 | 截断 |
| 请求文件 | 2 MB | `too_large` |
| edits 条数 | 500 | `too_large` |

### 4.6 同步语义（关键）

工具写 `req-<uuid>.json` 后**等待** `ack-<uuid>.json`，默认最多 5s：

- 有 ack → 把结果作为 MCP 工具返回值（`busy`/`stale` 能传到对话里）
- 0.4s 还没回执、且 `outbox/state.json` 显示 app 没在运行 → `open -b com.youyanping.mindscape` 拉起 app，再等最多 6s（冷启动要读库、建窗口）
- 仍超时 → 返回 `{"ok":true,"queued":true}`（文件排队，下次启动导入）
- `MINDSCAPE_NO_LAUNCH=1` 可关掉自动拉起（测试和 CI 用）

这就是"拒绝写入"能变成一句人话的原因。

---

## 5. app 侧改动

估约 **+330 行 / 改 3 个文件**，不新增依赖，不动数据库 schema。

### 5.1 新增 `Mindscape/Support/AIInboxFormat.swift`（约 150 行）

**只 import Foundation**（不 import SwiftUI/AppKit）——这是硬约束，保证它能脱离 Xcode、用 `swiftc` 单独编译和测试。

- `struct AIRequest` / `AIEdit` / `AITreeNode`：`Decodable`
- `enum AIRequestError: LocalizedError`：对应 §4.5
- `func makeMap(_ req: AIRequest, themeID: String, layout: MapLayout) throws -> MindMap`
  - 广度优先分配 `order`、生成 `UUID`
  - `color` 用现有 `NSColor+Hex` 的正则校验（该文件只 import AppKit… → 校验逻辑在此处内联，不依赖它）
- `func apply(_ edits: [AIEdit], to map: inout MindMap) throws`
- `func validate(_ tree: AITreeNode) throws`：节点数/深度/长度

### 5.2 新增 `Mindscape/Support/AIInbox.swift`（约 130 行）

- `final class AIInbox`：`DispatchSource.makeFileSystemObjectSource` 监听 `inbox/`（`.write` 掩码，目录级）
- `func scanPending()`：启动时 + 每次事件 + 窗口激活时扫一遍（防 FSEvents 合并丢事件）
- `func handle(url:)`：读 → 解码 → §8 忙判定 → 应用 → 写 ack → 移入 `done/` 或 `rejected/`
- `func publishContext()`：防抖 200ms 原子写 `outbox/state.json`
- 原子写：`Data.write(to:options:.atomic)`

### 5.3 改 `Mindscape/Editor/MapEditor.swift`（约 +25 行）

```swift
var hasPendingSave: Bool { saveTask != nil }          // scheduleSave 建、saveNow 清，天然表示"有东西没落盘"
var editingNodeID: UUID?                              // 由画布 beginEditing/commitEditing 同步
func applyExternal(_ map: MindMap)                    // 外部写入后替换模型
```

`applyExternal` 保留撤销：`undoStack.append(self.map)` → 赋值 → prune 选择 → `revision += 1`（**不**调 `scheduleSave`，数据已在库里）。

### 5.4 改 `Mindscape/Canvas/MindCanvasView.swift`（约 +6 行）

`beginEditing` / `commitEditing` / `cancelEditing` 三处同步 `editor?.editingNodeID`。

### 5.5 改 `Mindscape/App/AppModel.swift`（约 +30 行）

- `init` 末尾：`AIInbox.shared.start(store: store, currentEditor: { self.editor })` + `scanPending()`
- 加 `didBecomeActive` 观察：`refreshQuietly()`（现在只有 `didResignActive` 存盘）
- 导入成功后：`reload()` → `selectDocument(newID)`（`selectDocument` 内部已先 `saveNow`，不会丢数据）
- `selectDocument` / `MapEditor.select` 后触发 `publishContext()`

### 5.6 提示条（可选，约 +25 行）

`WorkspaceView` 顶部一条非模态 banner：「AI 想修改《X》，已暂缓（还有未保存的改动）」。数据来自 `AIInbox.lastRejection`。

---

## 6. 工具侧：`tools/mindscape.py`（单文件，Python 3 标准库）

约 **600 行**，无 pip 依赖。CLI 与 MCP 是**同一个模块的两个入口**，核心逻辑只写一遍：

```
core:       discover_data_dir / load_schema / validate / atomic_write / wait_ack
            read_db (sqlite3 readonly) / tree_out
cli:        create | patch | list | get | context | doctor | mcp
mcp:        stdin JSON-RPC 2.0 loop（initialize / tools/list / tools/call）
```

### 6.1 子命令

```bash
mindscape create -f plan.json          # 或 --stdin
mindscape patch  -f edits.json
mindscape list   [--json]
mindscape get    <docID> [--json]
mindscape context
mindscape doctor                        # 自检：数据目录、schema 版本、能否 decode
mindscape mcp                           # 协议入口
```

### 6.2 MCP 工具

| name | 入参 | 返回 |
|---|---|---|
| `create_map` | `{tree, title?, layout?, theme?}` | ack |
| `patch_map` | `{doc, baseUpdatedAt, edits}` | ack |
| `list_maps` | `{}` | 列表 |
| `get_map` | `{doc}` | 树（带 id） |
| `get_context` | `{}` | 当前文档/选中/忙状态 |

工具描述里直接写明："当用户要求把内容整理成思维导图时使用；patch 前先 get_context 确认没在编辑。"

### 6.3 读库

`sqlite3.connect("file:" + db + "?mode=ro", uri=True)`，只读，不写。

`list_maps` 只取列：
`SELECT id,title,layout,theme,updated_at,node_count,preview,folder_id FROM documents WHERE deleted_at IS NULL ORDER BY updated_at DESC`

`get_map` 需要把扁平的 `nodes` 折成树，所以工具**只额外认识四个内部字段**：`id` / `parentID` / `text` / `order`。
其余字段（`note` / `icon` / `colorHex`）原样透传。字段缺失时 `build_tree` 抛 `unsupported`，
`mindscape doctor` 会把它显式报出来——这是内部格式变化时唯一的告警点。

### 6.4 注册

```bash
# Claude Code
claude mcp add mindscape -- python3 ~/Mindscape/tools/mindscape.py mcp
```

```toml
# ~/.codex/config.toml
[mcp_servers.mindscape]
command = "python3"
args = ["/path/to/Mindscape/tools/mindscape.py", "mcp"]
```

### 6.5 `skills/mindscape-draw/SKILL.md`

触发条件（用户说"画成导图/整理成脑图/拆成图"）、authoring 格式、3 个完整示例（会议纪要 / 拆解需求 / 读书笔记）、"改图前先 `get_context`"。

---

## 7. 双写冲突策略（状态机）

| 目标文档状态 | 判定 | 动作 |
|---|---|---|
| app 未运行 | 无 ack | 文件留在 inbox，下次启动导入 |
| 未打开 | `editor == nil` 或 `editor.map.id != doc` | `store.load` → 应用 → `save` + `addSnapshot("AI 修改","ai")` |
| 打开且干净 | `!hasPendingSave && editingNodeID == nil` | 直接 `save`，再 `editor.applyExternal(map)`（相机不动，⌘Z 可撤） |
| 打开且忙 | 否则 | **拒绝**：写 ack `busy` + banner，文件移 `rejected/`，库一个字节不动 |

判定只发生在 app 内，工具无法绕过。**拒绝永不丢请求**：`rejected/` 保留原文件，修好状态后工具重发即可。

---

## 8. 安全

- 只处理 `inbox/` 下 `req-*.json`，不跟随符号链接，路径做 `standardizedFileURL` 包含性检查
- 文件体积 ≤ 2MB、`edits` ≤ 500、节点 ≤ 2000、深度 ≤ 12
- 不新增监听端口、不注册 URL scheme（`open -a Mindscape` 即可唤前台）——**故意少一个外部可触发的入口**
- Python 工具写文件 `0600`；只读打开数据库
- 用户可在设置里关闭「AI 集成」（关掉即退回 0.5.3 行为）

---

## 9. 兼容与回退

- 不改 `MindMap` / `MindNode` 的 Codable 结构 → 旧版本 app 打开新数据无影响
- 不改 SQLite schema → 不需要迁移
- 回退 = 删 `inbox/`、`outbox/` + 关监听；数据库里已产生的文档就是普通文档
- 每个 AI 写入前都有 snapshot，误改可在「历史版本」回滚

---

## 10. 测试（无完整 Xcode 的策略）

| 层 | 方式 |
|---|---|
| 转换器（Swift） | 只 import Foundation → `swiftc AIInboxFormat.swift MindMap.swift MindNode.swift tests/main.swift` 直接用 CTL 跑断言 |
| 格式校验（Python） | `python3 -m unittest tests/test_core.py`：合法/非法样本、体积上限、路径寻址 |
| 契约 | 金样本 `tests/fixtures/{minimal,full,invalid-*}.json`，两侧共用 |
| 全量类型检查 | `scripts/typecheck.sh`：`swiftc -typecheck -target arm64-apple-macos14.0 -swift-version 5 Mindscape/**/*.swift` |
| 手工验收 | §11 |

---

## 11. 验收清单（逐条手动过）

1. app 关着 → `create` → 打开 app，侧栏出现该图，主题/布局/图标正确
2. app 开着且空闲 → `create` → 3s 内出现在画布并选中
3. 看 A 图 → `patch A` → 节点出现，缩放/滚动不跳，⌘Z 可撤
4. 光标在某节点输入框里 → `patch` → 返回 `busy`，画布无变化，出现提示条
5. 刚拖完节点（600ms 内）→ `patch` → `busy`
6. `patch` 带过期 `baseUpdatedAt` → `stale` → 重读后成功
7. `patch` 删一个不存在的节点 → 整批不生效，返回 `not_found`
8. 2001 节点 / 13 层 / 非法 icon / 非法 color / 3MB 文件 → 全部被拒或降级，app 不崩
9. 关掉「AI 集成」→ 投递文件不被消费，app 行为与 0.5.3 一致

---

## 12. 里程碑

| # | 内容 | 依赖 | 产物 |
|---|---|---|---|
| **M0** | 工具链（Xcode 15+ 或 Command Line Tools 15+）+ `scripts/typecheck.sh` | 见 README「从源码构建」 | 全量 typecheck 通过 |
| **M1** | `AIInboxFormat.swift` + 金样本 + 无 UI 测试 | M0 | 转换器可独立跑通 |
| **M2** | `AIInbox.swift` + MapEditor/Canvas/AppModel 改动 + banner | M1 | 手工丢文件进 inbox 即可出图；busy 生效 |
| **M3** | `mindscape.py`（core+cli+mcp）+ SKILL.md + 注册 | M2 | 对话里 `create_map` 成功 |
| **M4**（可选） | 导出 PNG/PDF 请求通道 | M3 | "导出 2x PNG 放桌面" |

M1 可完全脱离 app 验证；M2 起每次改动都能 typecheck + 手工跑。

---

## 13. 风险

| 风险 | 影响 | 处置 |
|---|---|---|
| 无完整 Xcode，跑不了 67 个 XCTest | 回归无自动化 | typecheck + headless 测试 + §11 清单；装 Xcode 后补 XCTest |
| FSEvents 丢事件 | 请求卡在 inbox | `scanPending()` 在启动/激活/每次事件后都扫，幂等（按文件名去重） |
| 模型写出超大树 | 卡 UI | 工具侧预校验 + app 侧硬上限 + `too_large` |
| 内部 JSON 将来变化 | 工具读挂 | 工具只透传 `content`，不做结构映射；`doctor` 命令报"格式已变" |
| app 卡住不写 ack | 每次等 5s | 超时返回 `queued`，不阻塞对话 |

---

## 14. 已落地的东西（对应文件）

| 文件 | 作用 | 验证方式 |
|---|---|---|
| `tools/mindscape.py` | core + CLI + MCP stdio，单文件零依赖 | `python3 -m unittest discover -s tests`（27 例） |
| `tests/fixtures/*.json` | 金样本：最小 / 完整 / patch / 非法 | 两侧共用 |
| `Mindscape/Support/AIInboxFormat.swift` | authoring → `MindMap` 转换、patch、校验 | `scripts/test-aibridge.sh`（无 UI，无需 Xcode 工程） |
| `tests/ai_inbox_format/main.swift` | 转换器断言：树形、寻址、原子性、上限 | 同上 |
| `Mindscape/Support/AIInbox.swift` | 目录监听、忙判定、ack、outbox | 类型检查 + §11 手工清单 |
| `Mindscape/Views/AIRejectionBanner.swift` | 拒绝提示条 | 同上 |
| `Mindscape/Editor/MapEditor.swift` | `hasPendingSave` / `editingNodeID` / `applyExternal` | 同上 |
| `Mindscape/Canvas/MindCanvasView.swift` | 编辑态同步 | 同上 |
| `Mindscape/App/AppModel.swift` | 启动监听、激活刷新、选中回调 | 同上 |
| `Mindscape/Views/RootView.swift` | 提示条挂载 | 同上 |
| `skills/mindscape-draw/SKILL.md` | 给 agent 的用法与写作规范 | 人工读 |

命令：

```bash
python3 -m unittest discover -s tests -v     # 工具侧，现在就能跑
scripts/test-aibridge.sh                     # 转换器，需要 Swift 5.9+
scripts/typecheck.sh                         # 全量类型检查，需要 Swift 5.9+
```

## 15. 已定参数（不再询问）

- 数据目录：跟随 app 设置
- 请求/回执目录：`inbox/`，成功 → `done/`，失败 → `rejected/`
- ack 超时：5s（自动拉起 app 后再给 6s）
- outbox 防抖：200ms；`ts` 超过 15s 视为 app 未运行
- 上限：见 §4.5
- 不注册 URL scheme
- 工具语言：Python 3 标准库，单文件
- 颜色统一小写 `#rrggbb`（工具与转换器都做规范化）
