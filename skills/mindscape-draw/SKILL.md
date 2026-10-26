---
name: mindscape-draw
description: 把对话里的内容画成思维导图，直接显示在用户的 Mindscape app 里；也能修改用户已有的导图。当用户说「画成导图」「整理成脑图」「拆解成图」「把这份笔记变成图」时使用。
---

# Mindscape 绘图

Mindscape 是用户本机的 macOS 思维导图。你通过 `mindscape` 工具往里投递内容，app 负责排版、套主题、落库。

## 什么时候用

- 用户要「一张图」：会议纪要、需求拆解、读书笔记、方案对比、项目里程碑
- 用户要「改刚才那张图」：加一支、删一支、换个布局、给某个节点补备注
- 用户问「我现在在看哪张图」

不要用它处理：正在编辑中的那张图（会被拒），超过 2000 个节点的图，需要图片/附件的内容。

## 两个动作

### 1. 新建（create_map）

```json
{
  "tree": {
    "text": "Q4 规划",
    "note": "北极星：DAU +30%",
    "icon": "target",
    "children": [
      { "text": "增长", "children": [{ "text": "渠道" }, { "text": "留存" }] },
      { "text": "风险", "color": "#c26a4a", "children": [{ "text": "预算超支" }] }
    ]
  },
  "layout": "mindMap",
  "theme": "paper"
}
```

- `text` 必填；`note` / `icon` / `color`（`#rrggbb`）/ `children` 可选
- `icon` 用 SF Symbols 名，常用的：`target` `flag` `lightbulb` `exclamationmark.triangle` `calendar` `person.2` `chart.line.uptrend.xyaxis` `checkmark.circle` `book` `link`
- `layout`：`mindMap`（默认，左右平衡）/ `logicRight` / `logicLeft` / `orgChart` / `tree` / `timeline` / `braceMap` / `free`
- `theme`：`paper`（默认）/ `midnight`（深空）/ `morandi` / `corporate`（商务）/ `blueprint` / `neon` / `sand` / `ink`
- 不要自己编 ID、坐标、排序，工具和 app 会生成
- 层级 ≤ 12，节点 ≤ 2000，单个 text ≤ 500 字

**怎么选布局**：讲流程/时间用 `timeline`；讲组织/汇报关系用 `orgChart`；并列要点用 `mindMap`；纯层级罗列用 `tree`。**怎么选主题**：用户没指定就 `paper`，别自作主张换深色。

### 2. 修改（patch_map）

改之前**必须先** `get_context`：

- `appRunning: false` → app 没开，可以照常投递，文件会排队
- `editingNode != null` 或 `unsaved: true` 且 `docID` 正是要改的那张 → **不要投**，直接告诉用户「先保存一下那张图我再改」
- 否则用 `get_map` 拿到树（节点带 `id`），再发 edits

```json
{
  "doc": "0F3C…",
  "baseUpdatedAt": 1730000000.0,
  "edits": [
    { "kind": "addChildren", "target": { "id": "…" }, "nodes": [{ "text": "预算超支" }] },
    { "kind": "setColor", "target": { "id": "…" }, "color": "#c26a4a" },
    { "kind": "setLayout", "layout": "timeline" }
  ]
}
```

- `target` 用 `{"id": "…"}`（推荐，来自 `get_map`）或 `{"path": ["根", "子"]}`
- `kind`：`setText` `setNote` `setColor` `setIcon` `addChildren` `remove` `move` `setLayout` `setTheme` `setTitle`
- 整批原子：一条失败整批不生效
- 一次别超过 500 条 edit

## 结果怎么讲给用户

工具返回 JSON，按 `ok` 分三种说法：

| 返回 | 你该说的话 |
|---|---|
| `{"ok":true,"action":"created"}` | 「画好了，已经在你 Mindscape 里」 |
| `{"ok":true,"queued":true}` | 「Mindscape 没开着，我把图放它收件箱了，你打开就能看到」 |
| `{"ok":false,"reason":"busy"}` | 原样转述 `message`，**不要重试**，不要换个方式硬写 |
| `{"ok":false,"reason":"stale"}` | 「这张图你刚改过，我重新读一遍再改」→ 重新 `get_map` 再来一次 |

`reason` 是 `too_large` / `invalid` 时，说明你的请求有问题：减少节点、缩短文字、检查 `layout` 拼写，然后重试一次；再失败就告诉用户具体原因。

## 内容质量

- 根节点写**主题**，不是「思维导图」这种占位词
- 一级分支 3–7 个；每个分支下面不超过 5 个二级节点，再多就分文件
- 节点文字尽量 ≤ 20 字，长内容放 `note`
- 同一层的文字风格统一（都是名词短语，或都是动宾短语）
- 只在真正需要强调的地方用 `color`

## 命令行等价物

MCP 不可用时可以直接跑：

```bash
python3 <repo>/tools/mindscape.py create -f plan.json
python3 <repo>/tools/mindscape.py patch -f edits.json
python3 <repo>/tools/mindscape.py context
python3 <repo>/tools/mindscape.py list
python3 <repo>/tools/mindscape.py get <docID>
```
