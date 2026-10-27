# Mindscape

<p align="center">
  <img src="docs/screenshots/icon.png" width="96" alt="Mindscape app icon">
</p>

<p align="center">
  <strong>A local-first mind map for macOS</strong><br>
  SwiftUI · AppKit · SQLite · zero third-party dependencies
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange?style=flat-square" alt="Swift 5">
  <img src="https://img.shields.io/badge/dependencies-0-brightgreen?style=flat-square" alt="No dependencies">
  <img src="https://img.shields.io/badge/data-local-blue?style=flat-square" alt="Local only">
  <img src="https://img.shields.io/badge/tests-136-brightgreen?style=flat-square" alt="136 tests">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/status-0.5.4-lightgrey?style=flat-square" alt="Status 0.5.4">
</p>

<p align="center">
  <a href="README.md">中文</a> · <strong>English</strong> · <a href="https://jiuxianzai.github.io/Mindscape/">Website</a>
</p>

> Every mind map you make lives in one local SQLite file. No account, no cloud, no telemetry — offline by default, and the only network call is an update check.

Mindscape is a native macOS mind-mapping app built for people who want to think on a canvas and keep the result on their own disk. It opens straight into a canvas, saves continuously, and never asks you to sign in.

**Current version: 0.5.4** — early software. Features and the data format may still change.

---

## Screenshots

Sample data. Some screenshots were taken on earlier 0.5.x builds; shortcuts and UI details follow the current release.

<p align="center">
  <img src="docs/screenshots/main.png" width="100%" alt="Mindscape main window">
</p>

<p align="center">
  <img src="docs/screenshots/inspector.png" width="49%" alt="Node inspector and icon library">
  <img src="docs/screenshots/dark.png" width="49%" alt="Dark theme with logic-chart layout">
</p>

<p align="center">
  <img src="docs/screenshots/export.png" width="28%" alt="Export and share">
  <img src="docs/screenshots/settings.png" width="49%" alt="Settings">
</p>

<p align="center">
  <img src="docs/gifs/ime.gif" width="78%" alt="The node widens as you type with a CJK input method">
</p>

---

## Why Mindscape

- **Local-first.** All maps sit in a single SQLite file. Works offline, no login, nothing uploaded.
- **Native, and small.** The canvas is a hand-drawn `NSView`, not a WebView. The whole app is a 3.9 MB download with zero third-party libraries — no Electron runtime, no bundled browser.
- **CJK input-method friendly.** While you compose text with Pinyin or Zhuyin, the node grows as you type instead of wrapping and snapping back, and the candidate window stays glued to the caret. This is the detail that usually breaks in Web-canvas mind maps.
- **Restrained motion.** Collapsing a branch staggers children by depth instead of flashing the whole screen; ghosts fade under the real nodes.
- **Good-looking out of the box.** 8 themes and 8 layouts. You don't have to style anything.
- **Actually organized.** Nested folders, an outline panel, full-map search, focus mode, favorites, and a trash can.
- **Easy to leave.** Export to PNG, PDF, Markdown, OPML, and JSON; import Markdown, OPML, and JSON.
- **Quiet updates.** No automatic network access by default; the update question appears once, and downloads are verified with SHA-256.

---

## Features

### Canvas

- Infinite canvas: two-finger pan, pinch zoom, ⌘ + scroll, ⌘0 to fit
- Nodes: add, rename, collapse, multi-select, drag, cut/copy/paste, duplicate
- Multiple root nodes; double-click empty space to start a new tree
- Drag to re-parent; hold ⌥ while dragging to reorder among siblings
- Canvas keys: `Space` to edit, `Enter` for a sibling, `Tab` for a child
- Multi-line in-place editing at any zoom level, with IME composition handled correctly
- Search bar (⌘F) highlights matches as you type, ↑↓ to jump
- Branch zoom (⇧⌘B) and focus mode (⇧⌘F) to isolate one subtree

### Collapse

- Collapse control appears on hover, no selection needed
- Collapsed branches show a persistent count badge of hidden nodes
- Clicking the badge expands; rapid clicks are never swallowed as a double-click
- Depth-staggered animation (20 ms per level, max 2 levels)

### Layouts & themes

- 8 layouts: mind map (balanced both sides), logic chart (right/left), org chart, tree, timeline, brace map, free-form with alignment guides and snapping
- 8 themes: Paper, Midnight, Morandi, Corporate, Blueprint, Neon, Sand, Ink
- Each map remembers a light and a dark theme separately; light mode lists light themes, dark mode lists dark themes, defaulting to Paper / Midnight

### Outline & presentation

- ⇧⌘O opens an outline panel synced with canvas folding state; click to locate
- ⇧⌘P opens a separate presentation window, paginated by first-level branches

### Files & history

- Nested folders with drag-to-file, "Move to…", favorites, search, trash
- Undo/redo up to 150 steps
- SQLite autosave (600 ms debounce), manual snapshots plus automatic snapshots every 10 minutes
- Version history with rollback (a snapshot is taken before each rollback)
- Configurable data directory; each directory keeps its own `mindscape.sqlite`

### Import / export

- Export: PNG (1x/2x/3x), PDF (vector), Markdown outline, OPML, JSON
- Import: Markdown, OPML, JSON (⇧⌘I or File → Import)
- Imports always create a new document; existing maps are never overwritten
- System share sheet (AirDrop, Mail, Messages), and per-map "Export as…" from the sidebar

### Accessibility & language

- Canvas nodes are exposed to VoiceOver with level, collapsed state, and notes
- UI is bilingual (English and Chinese) and follows the system language

### Menu bar

Always-available menu bar item: open the app, quick new map, new from template, recent maps, empty trash, settings, check for updates, reveal data folder in Finder, quit.

### Updates

- Check manually under Settings → About or from the menu bar's “Check for Updates…”
- The first launch asks whether to check automatically and whether to install the agent skill (both off by default); change them later in Settings
- The update window shows release notes and download size; the DMG is verified with SHA-256 before it opens
- If the GitHub API is rate-limited, the app falls back to the Releases Atom feed and then a 302 redirect; network and verification run off the main thread

---

## Install

### Download

Grab `Mindscape-0.5.4.dmg` from [Releases](https://github.com/jiuxianzai/Mindscape/releases), open it, and drag Mindscape into Applications.

You can also check for updates in-app: **Settings → About → Check for Updates**, or the menu bar. The update question appears once at first launch (off by default); the agent skill has a separate question. Downloads are verified with SHA-256 before the DMG opens.

This build is **ad-hoc signed and not notarized**. If Gatekeeper blocks the first launch, run:

```bash
xattr -dr com.apple.quarantine /Applications/Mindscape.app
```

Proper Developer ID signing and notarization are on the roadmap.

### Build from source

Requirements: macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen

make run        # generate the project, build, launch
# or
xcodegen generate && open Mindscape.xcodeproj
```

Packaging and local install:

```bash
make package    # writes dist/Mindscape-0.5.4.dmg, .zip, and .dmg.sha256
make publish    # creates the GitHub Release via gh (requires gh auth login)
make install    # installs to /Applications and launches
```

Tests:

```bash
xcodebuild test -project Mindscape.xcodeproj -scheme Mindscape -derivedDataPath build
```

---

## Coming from XMind, MindNode, or FreeMind

Mindscape can't read `.xmind` files directly yet, but **OPML is the bridge** — XMind, MindNode, FreeMind, and most outliners can export it.

**From XMind**

1. Open the map in XMind, choose **File → Export → OPML**.
2. In Mindscape, press ⇧⌘I (or **File → Import OPML…**) and pick the file.

**From FreeMind / Freeplane**

1. **File → Export → OPML** (Freeplane: **File → Export → OPML**).
2. Import the same way.

**From Markdown / Obsidian**

Import any nested Markdown outline directly with ⇧⌘I; heading levels and list indentation become node levels.

Notes:

- Import always creates a **new document**, so nothing you already have is touched.
- Notes, icons, relationships, and summaries are not carried over by OPML — structure and text are. Verify a sample before migrating a large set.
- Direct `.xmind` import is on the roadmap.

---

## AI Agent

Mindscape can expose a local OpenAPI gateway to AI agents, with a bundled skill manual. Agents can create folders, build maps, edit nodes, and export through the CLI or HTTP.

Illustrated setup guide (screenshots, architecture, four-agent paths, troubleshooting): [docs/ai-agent.md](docs/ai-agent.md).

### One-time setup

1. Open **Settings → AI Agent** and enable **Allow local AI agents**.
2. Install the skill from the same page for:
   - **Claude Code** → `~/.claude/skills/mindscape`
   - **Codex** → managed block in `~/.codex/AGENTS.md`
   - **DSH** → `~/.dsh/skills/mindscape`
   - **OpenCode** → `~/.config/opencode/skills/mindscape`
3. Tell the agent: “Read `~/.agents/skills/mindscape/SKILL.md` and create a project-plan mind map with Mindscape.”

The gateway is off by default, starts only when an agent calls it, and stops after 10 idle minutes. It binds `127.0.0.1` only and uses a fresh bearer token per session, stored in `~/Library/Application Support/Mindscape/agent-gateway.json` (0600).

### Install the CLI

```bash
make install-cli PREFIX=$HOME/.local/bin   # or sudo make install-cli
```

### Common commands

```bash
mindscape health
mindscape folder create "Project A"
mindscape map create "Q4 Plan" --template project
mindscape map list
mindscape node add <map-id> --parent <node-id> --text "Goal"
mindscape map export <map-id> --format md --out ~/Downloads/q4.md
mindscape openapi > openapi.json
mindscape guide
```

The live OpenAPI document is at `http://127.0.0.1:47821/openapi.json` (see the gateway file for the actual port and token). Full API and examples: [`AgentSkill/SKILL.md`](AgentSkill/SKILL.md).

---

## Data & privacy

Default data directory:

```
~/Library/Application Support/Mindscape/mindscape.sqlite
```

- All maps live in **one SQLite file**, not one file per map
- Change the location under **Settings → General → Data directory**
- "Recent directories" remembers previous locations with map counts and a switch button
- Switching directories never deletes the old data
- Offline by default; the update question appears once (change it under Settings → General); the only network request is the update check; no telemetry, no account

Tables: `documents` (metadata + full map JSON + folder), `folders`, `snapshots` (version JSON), `settings`.

---

## Tech stack

| Layer | Implementation |
|---|---|
| UI | SwiftUI + AppKit |
| Canvas | Hand-drawn `NSView` + Core Graphics |
| Icons | SF Symbols (102 symbols) |
| Storage | System `libsqlite3`, WAL mode |
| Project | XcodeGen (`project.yml`) |
| Tests | XCTest, 67 cases including canvas interaction and render regressions |
| Minimum OS | macOS 14 |
| Architecture | Universal (arm64 + x86_64) |
| Third-party dependencies | None |

### Design notes

- **The canvas is drawn, not composed.** Nodes and connectors go through Core Graphics; zoom transforms the coordinate system instead of scaling thousands of SwiftUI views.
- **Layout is a pure function.** `MindMap -> LayoutResult(frames, bounds)` is shared by the canvas, presentation mode, and export.
- **One editor object owns editing state.** `MapEditor` (`@Observable`) handles edits, undo, and autosave; the canvas, inspector, outline, and toolbar all read and write through it.
- **What you see is what you can click.** Hit testing uses the currently visible frames during animations.
- **One directory, one database.** Map bodies are JSON; title, layout, theme, node count, and folder are denormalized into columns for listing and search.

---

## Roadmap

- [x] Markdown / OPML / JSON import
- [x] Outline panel with canvas location
- [x] Presentation mode, focus mode
- [x] Free-form alignment guides and snapping
- [x] XCTest target
- [ ] FreeMind / XMind import
- [ ] Two-way sync between outline and canvas
- [ ] Relationships, summaries, boundaries
- [ ] Image / attachment nodes
- [ ] FTS5 full-text search
- [ ] Developer ID signing + notarization
- [ ] CI (build + test + release)
- [ ] Stable 1.0 data format

## Known limitations

- Import covers Markdown, OPML, and Mindscape's own JSON; `.xmind` and `.freemind` are not supported yet
- The outline panel is read-only for now (locate and inspect, no editing)
- No relationships, summaries, boundaries, or image/attachment nodes
- Free-form layout is manual, with alignment snapping only — no auto-arrange
- Folders can't be reordered by dragging yet
- Presentation mode paginates by first-level branch; page order isn't adjustable
- Ad-hoc signing only; suitable for local and internal distribution

---

## Contributing

Issues and pull requests are welcome.

- Open an issue describing the bug or change before sending a PR, to avoid duplicate work
- Use `make run` for development and `make package` for builds; run the tests before submitting
- The project is deliberately dependency-free — discuss before adding one
- Keep the existing layering: Models / Storage / Editor / Canvas / Views
- Canvas interaction changes should come with an XCTest that reproduces the bug; most bugs in this project are pinned that way

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE).

## Credits

- [SF Symbols](https://developer.apple.com/sf-symbols/) — system icon library
- [SQLite](https://www.sqlite.org/) — local storage
- SwiftUI / AppKit — native UI and canvas
