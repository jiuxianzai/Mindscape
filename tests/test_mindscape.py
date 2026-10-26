#!/usr/bin/env python3
"""tools/mindscape.py 的测试。只用标准库：python3 -m unittest discover -s tests"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import mindscape as ms  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class ValidationTests(unittest.TestCase):
    def test_minimal_create(self):
        out = ms.normalize(fixture("authoring-minimal.json"), {}, None)
        self.assertEqual(out["request"]["op"], "create")
        self.assertEqual(out["request"]["layout"], "mindMap")
        self.assertEqual(out["request"]["theme"], "paper")
        self.assertEqual(out["nodeCount"], 1)
        self.assertNotIn("title", out["request"])

    def test_full_create(self):
        out = ms.normalize(fixture("authoring-full.json"), {}, None)
        req = out["request"]
        self.assertEqual(req["title"], "Q4 规划")
        self.assertEqual(out["nodeCount"], 7)
        self.assertEqual(req["tree"]["children"][1]["color"], "#c26a4a")
        self.assertEqual(out["warnings"], [])

    def test_bare_tree_is_accepted(self):
        out = ms.normalize({"text": "裸树", "children": [{"text": "子"}]}, {}, None)
        self.assertEqual(out["request"]["tree"]["text"], "裸树")

    def test_empty_text_rejected(self):
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.normalize(fixture("invalid-empty-text.json"), {}, None)
        self.assertEqual(ctx.exception.reason, "invalid")

    def test_too_many_nodes(self):
        tree = {"text": "根", "children": [{"text": f"n{i}"} for i in range(ms.LIMITS["nodes"] + 1)]}
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.normalize({"tree": tree}, {}, None)
        self.assertEqual(ctx.exception.reason, "too_large")

    def test_too_deep(self):
        node = {"text": "leaf"}
        for _ in range(ms.LIMITS["depth"] + 1):
            node = {"text": "x", "children": [node]}
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.normalize({"tree": node}, {}, None)
        self.assertEqual(ctx.exception.reason, "too_large")

    def test_bad_color_is_warning_not_error(self):
        out = ms.normalize({"tree": {"text": "根", "color": "red"}}, {}, None)
        self.assertNotIn("color", out["request"]["tree"])
        self.assertTrue(out["warnings"])

    def test_long_text_truncated(self):
        out = ms.normalize({"tree": {"text": "根" * 10, "note": "n" * 9000}}, {}, None)
        self.assertEqual(len(out["request"]["tree"]["note"]), ms.LIMITS["note"])
        self.assertTrue(any("note" in w for w in out["warnings"]))

    def test_unknown_layout_rejected(self):
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.normalize({"tree": {"text": "根"}, "layout": "radial"}, {}, None)
        self.assertEqual(ctx.exception.reason, "invalid")

    def test_patch_paths(self):
        out = ms.normalize(fixture("patch-add.json"), {}, None)
        edits = out["request"]["edits"]
        self.assertEqual(edits[0]["target"], {"path": ["Q4 规划", "风险"]})
        self.assertEqual(edits[1]["target"], {"id": "aaa"})
        self.assertEqual(out["request"]["baseUpdatedAt"], 1730000000.0)

    def test_patch_unknown_kind(self):
        payload = {"doc": "d", "edits": [{"kind": "explode", "target": {"id": "x"}}]}
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.normalize(payload, {}, None)
        self.assertEqual(ctx.exception.reason, "invalid")

    def test_patch_needs_doc(self):
        with self.assertRaises(ms.BridgeError):
            ms.normalize({"edits": [{"kind": "setTitle", "title": "x"}]}, {}, None)


class SubmitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        os.environ["MINDSCAPE_DATA_DIR"] = str(self.root)
        os.environ["MINDSCAPE_NO_LAUNCH"] = "1"

    def tearDown(self):
        os.environ.pop("MINDSCAPE_DATA_DIR", None)
        os.environ.pop("MINDSCAPE_NO_LAUNCH", None)
        self.tmp.cleanup()

    def test_timeout_queues_request(self):
        reply = ms.submit(self.root, {"op": "create", "tree": {"text": "根"}}, wait=0.3)
        self.assertTrue(reply["queued"])
        pending = list((self.root / "inbox").glob("req-*.json"))
        self.assertEqual(len(pending), 1)

    def test_ack_roundtrip_and_cleanup(self):
        """模拟 app：读到 req -> 写 ack -> 移入 done。"""
        stop = threading.Event()

        def fake_app():
            inbox = self.root / "inbox"
            while not stop.is_set():
                for req in sorted(inbox.glob("req-*.json")):
                    key = req.name[len("req-") : -len(".json")]
                    (inbox / f"ack-{key}.json").write_text(
                        json.dumps({"ok": True, "action": "created", "docID": "d1"}), encoding="utf-8"
                    )
                    req.rename(inbox / "done" / req.name)
                time.sleep(0.02)

        thread = threading.Thread(target=fake_app, daemon=True)
        thread.start()
        try:
            reply = ms.submit(self.root, {"op": "create", "tree": {"text": "根"}}, wait=2.0)
        finally:
            stop.set()
            thread.join(timeout=1)

        self.assertTrue(reply["ok"])
        self.assertEqual(reply["docID"], "d1")
        self.assertEqual(list((self.root / "inbox").glob("ack-*.json")), [])
        self.assertEqual(len(list((self.root / "inbox" / "done").glob("req-*.json"))), 1)

    def test_atomic_write_leaves_no_tmp(self):
        ms.atomic_write_json(self.root / "x.json", {"a": 1})
        self.assertEqual([p.name for p in self.root.glob("*.json")], ["x.json"])
        self.assertEqual((self.root / "x.json").stat().st_mode & 0o777, 0o600)


def make_db(root: Path) -> Path:
    db = root / "mindscape.sqlite"
    conn = sqlite3.connect(db)
    conn.executescript(
        """
        CREATE TABLE documents (
            id TEXT PRIMARY KEY, title TEXT, content TEXT, layout TEXT, theme TEXT,
            starred INTEGER, created_at REAL, updated_at REAL, deleted_at REAL,
            node_count INTEGER, preview TEXT, folder_id TEXT
        );
        """
    )
    content = {
        "id": "doc-1",
        "title": "Q4 规划",
        "layout": "mindMap",
        "themeID": "paper",
        "nodes": [
            {"id": "r", "text": "Q4 规划", "order": 0},
            {"id": "a", "parentID": "r", "text": "增长", "order": 1},
            {"id": "b", "parentID": "r", "text": "风险", "order": 0},
            {"id": "b1", "parentID": "b", "text": "预算", "order": 0, "colorHex": "#C26A4A"},
        ],
    }
    conn.execute(
        "INSERT INTO documents (id,title,content,layout,theme,starred,created_at,updated_at,"
        "deleted_at,node_count,preview,folder_id) VALUES (?,?,?,?,?,0,0,1730000000,NULL,4,'增长 · 风险',NULL)",
        ("doc-1", "Q4 规划", json.dumps(content), "mindMap", "paper"),
    )
    conn.commit()
    conn.close()
    return db


class ReadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        os.environ["MINDSCAPE_DATA_DIR"] = str(self.root)
        os.environ["MINDSCAPE_NO_LAUNCH"] = "1"
        make_db(self.root)

    def tearDown(self):
        os.environ.pop("MINDSCAPE_DATA_DIR", None)
        os.environ.pop("MINDSCAPE_NO_LAUNCH", None)
        self.tmp.cleanup()

    def test_list(self):
        docs = ms.list_documents(self.root)
        self.assertEqual(len(docs), 1)
        self.assertEqual(docs[0]["title"], "Q4 规划")
        self.assertEqual(docs[0]["nodeCount"], 4)

    def test_tree_order_and_shape(self):
        record, content = ms.load_document(self.root, "doc-1")
        tree = ms.build_tree(content)
        root = tree["tree"]
        self.assertEqual([c["text"] for c in root["children"]], ["风险", "增长"])  # order 优先
        self.assertEqual(root["children"][0]["children"][0]["color"], "#C26A4A")
        self.assertEqual(tree["theme"], "paper")

    def test_missing_doc(self):
        with self.assertRaises(ms.BridgeError) as ctx:
            ms.load_document(self.root, "nope")
        self.assertEqual(ctx.exception.reason, "not_found")

    def test_context_when_no_outbox(self):
        ctx = ms.read_context(self.root)
        self.assertFalse(ctx["appRunning"])

    def test_context_fresh_and_stale(self):
        outbox = self.root / "outbox"
        outbox.mkdir()
        (outbox / "state.json").write_text(json.dumps({"ts": time.time(), "title": "A"}), encoding="utf-8")
        self.assertTrue(ms.read_context(self.root)["appRunning"])
        (outbox / "state.json").write_text(json.dumps({"ts": time.time() - 60}), encoding="utf-8")
        self.assertFalse(ms.read_context(self.root)["appRunning"])


class MCPTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        os.environ["MINDSCAPE_DATA_DIR"] = str(self.root)
        os.environ["MINDSCAPE_NO_LAUNCH"] = "1"

    def tearDown(self):
        os.environ.pop("MINDSCAPE_DATA_DIR", None)
        os.environ.pop("MINDSCAPE_NO_LAUNCH", None)
        self.tmp.cleanup()

    def test_initialize(self):
        reply = ms.handle_message({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        self.assertEqual(reply["result"]["serverInfo"]["name"], "mindscape")
        self.assertIn("tools", reply["result"]["capabilities"])

    def test_initialized_notification_is_silent(self):
        self.assertIsNone(ms.handle_message({"jsonrpc": "2.0", "method": "notifications/initialized"}))

    def test_tools_list(self):
        reply = ms.handle_message({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        names = {t["name"] for t in reply["result"]["tools"]}
        self.assertEqual(names, {"create_map", "patch_map", "list_maps", "get_map", "get_context"})

    def test_unknown_method(self):
        reply = ms.handle_message({"jsonrpc": "2.0", "id": 3, "method": "nope"})
        self.assertEqual(reply["error"]["code"], -32601)

    def test_create_tool_queues(self):
        os.environ["MINDSCAPE_ACK_TIMEOUT"] = "0.2"
        try:
            reply = ms.handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "tools/call",
                    "params": {"name": "create_map", "arguments": {"tree": {"text": "根"}}},
                }
            )
        finally:
            os.environ.pop("MINDSCAPE_ACK_TIMEOUT", None)
        payload = json.loads(reply["result"]["content"][0]["text"])
        self.assertTrue(payload["queued"])
        self.assertEqual(len(list((self.root / "inbox").glob("req-*.json"))), 1)

    def test_bad_arguments_are_tool_error_not_protocol_error(self):
        reply = ms.handle_message(
            {
                "jsonrpc": "2.0",
                "id": 5,
                "method": "tools/call",
                "params": {"name": "create_map", "arguments": {"tree": {"text": ""}}},
            }
        )
        self.assertTrue(reply["result"]["isError"])
        payload = json.loads(reply["result"]["content"][0]["text"])
        self.assertEqual(payload["reason"], "invalid")


class DoctorTests(unittest.TestCase):
    def test_empty_dir_reports_not_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["MINDSCAPE_DATA_DIR"] = tmp
            try:
                import io
                from contextlib import redirect_stdout

                buf = io.StringIO()
                with redirect_stdout(buf):
                    code = ms.main(["doctor"])
                report = json.loads(buf.getvalue())
            finally:
                os.environ.pop("MINDSCAPE_DATA_DIR", None)
            self.assertEqual(code, 1)
            self.assertFalse(report["ok"])
            self.assertFalse(report["appRunning"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
