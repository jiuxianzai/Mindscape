# Mindscape

本地优先的 macOS 思维导图应用。Swift 原生开发，数据全部保存在本机 SQLite，不联网、不需要账号。

当前版本：**0.1.0（MVP 骨架）**

## 技术栈

| 层 | 实现 |
|---|---|
| UI | SwiftUI + AppKit |
| 画布 | 自绘 `NSView`（Core Graphics，非 Web 渲染） |
| 数据 | 系统 `libsqlite3`，WAL 模式，无第三方依赖 |
| 工程 | XcodeGen（`project.yml` 是唯一工程描述） |
| 最低系统 | macOS 14 |

## 已实现

**画布与编辑**
- 无限画布：触控板双指平移、捏合缩放、⌘ + 滚轮缩放、适配画布
- 节点：新增 / 删除 / 重命名 / 折叠 / 拖动改父级 / 多选
- 双击就地编辑，Enter 提交，Esc 取消
- 节点备注、emoji 图标、自定义颜色
- 方向键在节点之间跳转

**布局（8 种）**
- 思维导图（左右平衡）
- 逻辑图（右 / 左）
- 组织架构图
- 树形图
- 时间轴
- 括号图
- 自由布局

**主题（8 套）**
- 纸白、深空、莫兰迪、商务蓝、蓝图、霓虹、暖砂、墨线
- 切换主题只换视觉，不改结构

**数据与历史**
- SQLite 自动保存（600ms 防抖）
- 撤销 / 重做（150 步）
- 手动快照 + 每 10 分钟自动快照（自动快照保留 20 份）
- 历史版本回滚，回滚前自动留档
- 收藏、搜索、回收站、恢复、彻底删除

**导入导出**
- 导出 PNG（2x）、PDF、Markdown 大纲、JSON
- 模板：空白、项目规划、会议纪要、读书笔记、SWOT、周计划

## 快捷键

| 操作 | 快捷键 |
|---|---|
| 新建导图 | ⌘N |
| 新建子主题 | Tab |
| 新建同级主题 | ↩ |
| 编辑当前节点 | 双击 / F2 |
| 删除节点 | Delete |
| 折叠 / 展开 | Space |
| 移动选择 | 方向键 |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z |
| 保存 | ⌘S（平时自动保存） |
| 适配画布 | ⌘0 |
| 放大 / 缩小 | ⌘+ / ⌘- |

## 运行

```bash
# 安装工程生成器（只需一次）
brew install xcodegen

make run             # 生成工程、编译、启动
# 或
xcodegen generate
open Mindscape.xcodeproj
```

构建产物在 `build/Build/Products/Debug/Mindscape.app`。

## 数据位置

```
~/Library/Application Support/Mindscape/mindscape.sqlite
```

表结构：

- `documents`：文档元信息 + 完整导图 JSON
- `snapshots`：历史快照 JSON
- `settings`：预留键值配置

文档主体用 JSON 存储（保存快、天然适合快照），列表所需的标题、布局、主题、节点数冗余成列，便于排序和搜索。后续接全文搜索时再加 FTS5 虚表。

## 项目结构

```
Mindscape/
├── project.yml                 # XcodeGen 工程描述
├── Makefile
└── Mindscape/
    ├── App/                    # 入口、全局状态、菜单命令
    ├── Models/                 # 节点 / 文档 / 布局 / 主题 / 模板
    ├── Storage/                # SQLite 封装与文档仓库
    ├── Editor/                 # MapEditor：编辑、撤销、自动保存
    ├── Canvas/                 # 布局引擎、测量、渲染、NSView 交互
    ├── Views/                  # 侧栏、工作区、属性面板、历史、设置
    ├── Support/                # 颜色、相对时间、导出
    └── Assets.xcassets/
```

## 设计约定

- 画布是**自绘**的：节点与连线都走 Core Graphics，缩放时直接变换坐标系，避免大量 SwiftUI 视图带来的性能问题。433 节点布局约 10ms。
- 布局引擎是纯函数：`MindMap -> LayoutResult(frames, bounds)`，渲染和导出复用同一份结果。
- 编辑状态集中在 `MapEditor`（`@Observable`），画布、属性面板、工具栏都读写它；保存与撤销只在 Editor 里发生。
- 主题只影响画布，窗口 chrome 跟随系统外观，避免深色画布配浅色侧栏时割裂。

## 已知限制 / 下一步

- 尚未支持导入（Markdown / OPML / FreeMind / XMind）
- 还没有大纲视图、演示模式、专注模式
- 没有关系线、概要、附件、图片节点
- 自由布局只能手动摆放，暂无网格吸附
- 尚未做滚动备份、导入导出冲突检测
- 未签名 / 未公证，只适合本机开发运行
- 暂无单元测试 target（核心链路的自测脚本在开发时验证过）

建议下一阶段（P1）：大纲视图 → 演示模式 → 全文搜索（FTS5）→ 导入 → 附件。

## License

私有项目，未指定许可证。
