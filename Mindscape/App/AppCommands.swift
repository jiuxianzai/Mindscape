import AppKit
import SwiftUI

struct AppCommands: Commands {
    let app: AppModel
    @ObservedObject var shortcuts: ShortcutStore

    init(app: AppModel) {
        self.app = app
        self._shortcuts = ObservedObject(wrappedValue: app.shortcuts)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建导图") {
                app.createDocument(template: .blank)
            }
            .appShortcut(shortcuts.combo(for: .newDocument))
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
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                app.editor?.saveNow()
            }
            .appShortcut(shortcuts.combo(for: .saveDocument))
        }

        CommandMenu("导图") {
            Button("历史版本…") {
                NotificationCenter.default.post(name: .mindscapeShowHistory, object: nil)
            }
            .appShortcut(shortcuts.combo(for: .showHistory))

            Button("创建快照") {
                app.editor?.createSnapshot()
            }

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
                ForEach(MapTheme.all) { theme in
                    Button(theme.name) {
                        app.editor?.setTheme(theme.id)
                    }
                }
            }

            Divider()

            Menu("导出") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.title) {
                        app.export(format)
                    }
                }
            }
        }
    }
}
