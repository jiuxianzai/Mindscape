# Mindscape

<p align="center">
  <img src="docs/screenshots/icon.png" width="96" alt="Mindscape app icon">
</p>

<p align="center">
  <strong>本地优先的 macOS 思维导图</strong><br>
  SwiftUI · AppKit · SQLite · 零第三方依赖
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange?style=flat-square" alt="Swift 5">
  <img src="https://img.shields.io/badge/dependencies-0-brightgreen?style=flat-square" alt="No dependencies">
  <img src="https://img.shields.io/badge/data-local-blue?style=flat-square" alt="Local only">
  <img src="https://img.shields.io/badge/status-0.4.0-lightgrey?style=flat-square" alt="Status 0.4.0">
</p>

> A local-first mind map app for macOS. All data lives in a local SQLite file — no account, no cloud, no telemetry.

Mindscape 是一个纯本地的 macOS 思维导图应用：打开即画，数据全部保存在本机。它没有登录、没有云同步、不会发起网络请求，也不依赖任何第三方库。

当前版本：**0.4.0**（早期版本，功能和数据结构仍可能调整）

---

## 截图

截图使用示例数据。

<p align="center">
  <img src="docs/screenshots/main.png" width="100%" alt="Mindscape 主界面">
</p>

<p align="center">
  <img src="docs/screenshots/inspector.png" width="49%" alt="节点属性与图标库">
  <img src="docs/screenshots/dark.png" width="49%" alt="深色主题与逻辑图布局">
</p>

<p align="center">
  <img src="docs/screenshots/export.png" width="28%" alt="导出与分享">
  <img src="docs/screenshots/settings.png" width="49%" alt="设置">
</p>

<p align="center">
  <img src="docs/screenshots/shortcuts.png" width="49%" alt="快捷键设置">
</p>

---

## 为什么是 Mindscape

- **本地优先**：所有导图在一个 SQLite 文件里，断网可用，不登录，不上传。
- **原生性能**：画布是自绘 `NSView`，不是 Web/Electron；大图缩放、拖拽仍然跟手。
- **开箱好看**：8 套主题、8 种布局、现代留白与陶土色视觉，不需要自己调样式。
- **真的能整理**：左侧多级目录、收藏、搜索、回收站，不是一次性玩具。
- **能带走**：PNG、PDF、Markdown、OPML、JSON 五种导出格式，支持系统分享。

---

## 功能

### 画布

- 无限画布：双指平移、捏合缩放、⌘ + 滚轮缩放、⌘0 适配
- 节点：新增、删除、重命名、折叠、多选、拖动
- 拖动改层级：拖到节点上挂到它下面；按住 ⌥ 拖到同级节点可调整顺序
- 多行就地编辑：进入编辑不跳动、超出宽度自动换行、节点随内容扩展
- `Enter` 提交，`Shift+Enter` 换行，`Esc` 取消并恢复
- 选中节点后直接打字即可编辑
- 方向键在节点之间跳转

### 布局（8 种）

- 思维导图（左右平衡）
- 逻辑图（右 / 左）
- 组织架构图
- 树形图
- 时间轴
- 括号图
- 自由布局

### 主题（8 套）

纸白、深空、莫兰迪、商务蓝、蓝图、霓虹、暖砂、墨线。

主题只影响画布；窗口和侧栏跟随系统外观。当前导图的主题可以在工具栏或属性面板切换。

### 图标

- 102 个 SF Symbols（系统图标库，无第三方依赖）
- 按中文/英文含义搜索，如「目标」「风险」「时间」「goal」
- 可滚动浏览、可收起，不一次性占满属性面板
- 节点图标按主题文字色自动着色

### 文件树

- 多级目录，支持新建、子目录、重命名、删除
- 删除目录时内容自动上移到上一级，不丢数据
- 文档可拖到目录归档，也可以右键「移动到」
- 收藏、搜索、回收站、恢复、彻底删除

### 数据与历史

- SQLite 自动保存（600ms 防抖）
- 撤销 / 重做 150 步
- 手动快照 + 每 10 分钟自动快照
- 历史版本回滚，回滚前自动留档
- 数据目录可更换，设置里保留「最近目录」，可一键切回
- 每个目录的导图存在该目录自己的 `mindscape.sqlite` 中

### 导入导出 / 分享

- PNG（1x / 2x / 3x）
- PDF（矢量）
- Markdown 大纲
- OPML（可导入 XMind、OmniOutliner 等）
- JSON（完整结构，适合备份迁移）
- 系统分享：AirDrop、邮件、信息等
- 目录右键「导出为」可快速保存单张导图

### 快捷键

- 设置页按分类管理，可逐个重新录制
- 菜单快捷键至少需要一个 ⌘ / ⌥ / ⌃ 修饰键
- 冲突检测、单项恢复默认、全部恢复默认

### 菜单栏

常驻菜单栏图标，支持：

- 打开 Mindscape
- 快速新建导图
- 从模板新建
- 最近导图
- 清空回收站（带确认）
- 设置
- 在 Finder 中打开数据目录
- 退出

---

## 安装

### 下载

发布后可以从 GitHub Releases 下载 `Mindscape-<version>.dmg`，拖入 Applications 即可。

当前构建为 **ad-hoc 签名**，适合本机使用。对外分发需要 Developer ID 签名 + notarization。

### 从源码构建

环境要求：

- macOS 14 或更高
- Xcode 15 或更高
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen

make run        # 生成工程、编译、启动
# 或
xcodegen generate
open Mindscape.xcodeproj
```

打包与本地安装：

```bash
make package    # 生成 dist/Mindscape-0.4.0.dmg 和 .zip
make install    # 安装到 /Applications 并启动
```

---

## 数据与隐私

默认数据目录：

```
~/Library/Application Support/Mindscape/mindscape.sqlite
```

- 所有导图保存在**一个 SQLite 文件**里，不是每个导图一个文件
- 可以在「设置 → 通用 → 数据目录」更换位置
- 「最近目录」会列出用过的目录、导图数量和切换按钮
- 切换目录不会删除原目录的数据
- 没有网络请求、没有遥测、没有账号

数据库表：

- `documents`：文档元信息 + 完整导图 JSON + 所属目录
- `folders`：目录树
- `snapshots`：历史快照 JSON
- `settings`：预留键值配置

---

## 默认快捷键

| 操作 | 快捷键 |
|---|---|
| 新建导图 | ⌘N |
| 保存 | ⌘S |
| 导出 / 分享 | ⌘E |
| 新建子主题 | Tab |
| 新建同级主题 | ↩ |
| 编辑当前节点 | 双击 / F2 / 直接打字 |
| 删除节点 | Delete |
| 折叠 / 展开 | Space |
| 移动选择 | 方向键 |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |
| 适配画布 | ⌘0 |
| 放大 / 缩小 | ⌘= / ⌘- |
| 显示 / 隐藏属性面板 | ⌥⌘I |
| 历史版本 | ⇧⌘H |

以上都可以在「设置 → 快捷键」中修改。

---

## 技术栈

| 层 | 实现 |
|---|---|
| UI | SwiftUI + AppKit |
| 画布 | 自绘 `NSView` + Core Graphics |
| 图标 | SF Symbols |
| 数据 | 系统 `libsqlite3`，WAL 模式 |
| 工程 | XcodeGen（`project.yml`） |
| 最低系统 | macOS 14 |
| 架构 | Universal（arm64 + x86_64） |
| 第三方依赖 | 无 |

## 设计约定

- **画布自绘**：节点与连线走 Core Graphics，缩放时直接变换坐标系，避免大量 SwiftUI 视图带来的性能问题。
- **布局是纯函数**：`MindMap -> LayoutResult(frames, bounds)`，画布和导出复用同一份结果。
- **编辑状态集中**：`MapEditor`（`@Observable`）负责编辑、撤销、自动保存；画布、属性面板、工具栏都读写它。
- **一个目录一个库**：文档主体存 JSON，列表/搜索所需的标题、布局、主题、节点数、目录冗余成列。
- **本地优先**：没有网络层，没有账号系统，没有遥测。

---

## 项目结构

```
Mindscape/
├── project.yml                 # XcodeGen 工程描述
├── Makefile                    # build / run / package / install
├── docs/screenshots/           # README 截图
└── Mindscape/
    ├── App/                    # 入口、全局状态、菜单命令
    ├── Models/                 # 节点 / 文档 / 布局 / 主题 / 模板 / 图标目录
    ├── Storage/                # SQLite 封装、文档与目录仓库
    ├── Editor/                 # MapEditor：编辑、撤销、自动保存
    ├── Canvas/                 # 布局引擎、测量、渲染、NSView 交互
    ├── Views/                  # 侧栏、工作区、属性面板、导出、历史、设置、菜单栏
    ├── Support/                # 颜色、相对时间、快捷键、导出
    └── Assets.xcassets/        # AppIcon / BrandMark
```

---

## 路线图

- [ ] 导入 Markdown / OPML / FreeMind / XMind
- [ ] 大纲视图与画布双向同步
- [ ] 演示模式、专注模式
- [ ] 关系线、概要、边界框
- [ ] 图片 / 附件节点
- [ ] FTS5 全文搜索
- [ ] 正式签名、notarization
- [ ] XCTest 测试 target 与 CI
- [ ] 稳定 1.0 数据格式

## 已知限制

- 目前只能导出，还不能导入其他思维导图格式
- 还没有大纲视图、演示模式、专注模式
- 没有关系线、概要、附件、图片节点
- 自由布局需要手动摆放，暂无网格吸附
- 目录本身还不能拖动排序
- 当前是 ad-hoc 签名，只适合本机开发使用
- 还没有 XCTest target

---

## 贡献

欢迎 issue 和 PR。

- 提交前请先开 issue 描述问题或改动，避免重复工作
- 开发用 `make run`，打包用 `make package`
- 项目刻意保持零第三方依赖；新增依赖前请先讨论
- 代码风格保持现有的分层：Models / Storage / Editor / Canvas / Views

---

## License

项目准备开源，许可证尚未最终确定。建议使用 MIT；确定后会在仓库根目录添加 `LICENSE` 文件。

## 致谢

- [SF Symbols](https://developer.apple.com/sf-symbols/)：系统图标库
- [SQLite](https://www.sqlite.org/)：本地存储
- SwiftUI / AppKit：原生界面与画布
