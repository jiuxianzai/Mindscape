---
name: mindscape
description: Create, edit, and export Mindscape mind maps through the local OpenAPI gateway. Use when the user asks for a mind map, brainstorm, project plan, meeting notes, outline, or export.
---

# Mindscape

Mindscape is a local-first macOS mind map app. This skill lets you operate it through a local OpenAPI service owned by the running app.

## Prerequisites

The user must enable **Settings → General → AI Agent → Allow local AI agents** once. The app never exposes a public port: the gateway binds `127.0.0.1`, uses a per-session bearer token, and stops after the configured idle timeout.

Prefer the `mindscape` CLI. It starts the gateway on demand and handles the token.

```bash
mindscape health
```

If `mindscape` is not installed, read the gateway descriptor:

```bash
cat "$HOME/Library/Application Support/Mindscape/agent-gateway.json"
```

It contains `url` and `token`. Never print the token in your answer or write it to a file.

## Discover before writing

1. `GET /v1/health`
2. `GET /v1/folders`
3. `GET /v1/maps` — choose by title, keep the `id`
4. `GET /v1/maps/{id}` — read `rootIds` and node IDs

Use IDs, not titles, for every subsequent mutation. Save returned IDs in your working notes.

## Request flow

```
You ── shell ──▶ mindscape CLI ── HTTP + Bearer ──▶ 127.0.0.1 gateway
                                                        │ MainActor
                                                        ▼
                                              AgentService → SQLite / export
```

The gateway is stopped by default and after 10 idle minutes. `mindscape` starts it on demand and reads the token from the gateway file. Prefer the CLI over raw HTTP: it handles discovery, token rotation, and JSON envelopes.

## API map

| Goal | Call |
|---|---|
| Check service | `GET /v1/health` |
| List folders / maps | `GET /v1/folders` · `GET /v1/maps` |
| Create folder / map | `POST /v1/folders` · `POST /v1/maps` |
| Read full map (IDs) | `GET /v1/maps/{mapId}` |
| Add / update / move / delete node | `POST .../nodes` · `PATCH/DELETE .../nodes/{nodeId}` · `POST .../nodes/{nodeId}/move` |
| Bulk create/edit | `POST /v1/maps/{mapId}/batch` (≤ 500 ops) |
| Export | `POST /v1/maps/{mapId}/export` |
| Import | `POST /v1/import` |
| Full spec | `GET /v1/openapi.json` |

All responses are `{"ok":true,"data":...}` or `{"ok":false,"error":{"code","message"}}`. HTTP status is meaningful: 400/401/403/404/409/413/429/503.

## Standard workflow

### Create a map

```bash
mindscape map create "Q4 规划" --folder <folder-id> --layout mindMap --theme paper
```

Or:

```http
POST /v1/maps
Content-Type: application/json

{"title":"Q4 规划","folderId":"<folder-id>","template":"project"}
```

The response contains the map `id` and its initial nodes.

### Add branches

```bash
mindscape node add <map-id> --parent <node-id> --text "目标"
```

Bulk creation is faster:

```http
POST /v1/maps/<map-id>/batch
Content-Type: application/json

{"operations":[
  {"op":"addNode","parentId":"<root-id>","text":"目标"},
  {"op":"addNode","parentId":"<root-id>","text":"风险"},
  {"op":"updateNode","nodeId":"<node-id>","note":"补充说明"}
]}
```

Batch accepts up to 500 operations and saves once. Prefer it for more than 10 nodes.

### Edit

```http
PATCH /v1/maps/<map-id>/nodes/<node-id>
Content-Type: application/json

{"text":"新标题","note":"备注","icon":"lightbulb","color":"#C26A4A","collapsed":false}
```

- Use `""` for `icon` or `color` to clear them.
- `PATCH /v1/maps/<map-id>` changes title, layout, theme, or folder.
- `POST /v1/maps/<map-id>/nodes/<node-id>/move` moves a node; the gateway rejects cycles.

### Export

```http
POST /v1/maps/<map-id>/export
Content-Type: application/json

{"format":"markdown","path":"~/Downloads/q4-plan.md"}
```

Formats: `markdown`, `opml`, `json`, `png`, `pdf`. PNG accepts `scale` 1–3. The path must be under the user's home directory or `/tmp`, and must end with the matching extension.

### Import

```http
POST /v1/import
Content-Type: application/json

{"path":"~/Downloads/plan.opml","folderId":"<folder-id>"}
```

Supports Markdown, OPML, and Mindscape JSON.

## If the CLI is unavailable

Read `~/Library/Application Support/Mindscape/agent-gateway.json` and use the `url` and `token` fields:

```bash
curl -s "$URL/v1/health" -H "Authorization: Bearer $TOKEN"
```

Only call `127.0.0.1` / `localhost`; do not send an `Origin` header. If the file is missing, ask the user to enable **Settings → General → AI Agent**, then retry once.

## Safety rules

- Ask the user before deleting a map, deleting a branch, or overwriting an export file.
- Do not delete every root node; the gateway rejects it.
- Do not expose the bearer token, gateway file, or full API responses containing local paths in public messages.
- If a request returns `401`, re-read the gateway file (the token may have rotated).
- If `503`, the app gateway is disabled or stopped; ask the user to enable AI Agent access, then retry once.
- Treat map titles/notes as user data; do not send them to external services.

## CLI quick reference

```bash
mindscape folder list
mindscape folder create "项目"
mindscape map list
mindscape map create "项目规划" --folder <id>
mindscape map show <map-id>
mindscape node add <map-id> --parent <node-id> --text "目标"
mindscape node set <map-id> <node-id> --text "新标题" --note "备注"
mindscape node move <map-id> <node-id> --parent <node-id>
mindscape node delete <map-id> <node-id>
mindscape map export <map-id> --format md --out ~/Downloads/plan.md
mindscape openapi
```

Full API: `GET /openapi.json` or `mindscape openapi`.
