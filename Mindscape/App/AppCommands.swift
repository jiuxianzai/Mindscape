import AppKit
import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    let app: AppModel
    @ObservedObject var shortcuts: ShortcutStore

    init(app: AppModel) {
        self.app = app
        self._shortcuts = ObservedObject(wrappedValue: app.shortcuts)
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                UpdateWindowController.shared.show(checker: app.updates)
                Task { await app.updates.check(manual: true) }
            }

            Button("AI Agent 接入…") {
                SettingsRouter.shared.requestedTab = .agent
                openSettings()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("新建导图") {
                app.createDocument(template: .blank)
            }
            .appShortcut(shortcuts.combo(for: .newDocument))

            Button("导入 Markdown / OPML…") {
                app.importDocument()
            }
            .appShortcut(shortcuts.combo(for: .importDocument))
        }

        CommandGroup(replacing: .undoRedo) {
            Button("撤销") {
                app.editor?.undo()
            }
            .appShortcut(shortcuts.combo(for: .undo))

            Button("重做") {
                app.editor?.redo()
            }
            .appShortcut(shortcuts.combo(for: .redo))

            Divider()

            Button("查找节点…") {
                NotificationCenter.default.post(name: .mindscapeFind, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .findNode))

            Button("创建副本") {
                app.editor?.duplicateSelection()
            }
            .appShortcut(shortcuts.combo(for: .duplicateNode))
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                app.editor?.saveNow()
            }
            .appShortcut(shortcuts.combo(for: .saveDocument))
        }

        CommandMenu("导图") {
            Button("导出…") {
                NotificationCenter.default.post(name: .mindscapeShowExport, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .exportDocument))

            Button("历史版本…") {
                NotificationCenter.default.post(name: .mindscapeShowHistory, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .showHistory))

            Button("创建快照") {
                app.editor?.createSnapshot()
            }

            Divider()

            Button("显示 / 隐藏大纲") {
                NotificationCenter.default.post(name: .mindscapeToggleOutline, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .toggleOutline))

            Divider()

            Button("专注当前分支") {
                app.editor?.toggleFocus()
            }
            .appShortcut(shortcuts.combo(for: .focusMode))

            Button("缩放到分支") {
                app.editor?.requestZoomToBranch()
            }
            .appShortcut(shortcuts.combo(for: .zoomToBranch))

            Button("折叠全部子分支") {
                app.editor?.collapseAll()
            }
            .appShortcut(shortcuts.combo(for: .collapseAll))

            Button("展开全部") {
                app.editor?.expandAll()
            }
            .appShortcut(shortcuts.combo(for: .expandAll))

            Divider()

            Button("演示模式") {
                NotificationCenter.default.post(name: .mindscapePresent, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .presentMode))

            Divider()

            Button("适配画布") {
                app.editor?.requestFit()
            }
            .appShortcut(shortcuts.combo(for: .fitCanvas))

            Button("放大") {
                app.editor?.requestZoom(1.2)
            }
            .appShortcut(shortcuts.combo(for: .zoomIn))

            Button("缩小") {
                app.editor?.requestZoom(0.83)
            }
            .appShortcut(shortcuts.combo(for: .zoomOut))

            Divider()

            Button("显示 / 隐藏属性面板") {
                NotificationCenter.default.post(name: .mindscapeToggleInspector, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .toggleInspector))

            Divider()

            Menu("布局") {
                ForEach(MapLayout.allCases) { layout in
                    Button(layout.title) {
                        app.editor?.setLayout(layout)
                    }
                }
            }

            Menu("主题") {
                ForEach(MapTheme.all.filter {
                    ThemePolicy.allows($0.id, isDark: NSApplication.shared.isDarkAppearance)
                }) { theme in
                    Button(theme.name) {
                        app.editor?.setTheme(theme.id)
                    }
                }
            }

            Divider()

        }
    }
}
