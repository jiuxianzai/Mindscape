import SwiftUI

struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建导图") {
                app.createDocument(template: .blank)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("撤销") {
                app.editor?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("重做") {
                app.editor?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                app.editor?.saveNow()
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("导图") {
            Button("适配画布") {
                app.editor?.requestFit()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("创建快照") {
                app.editor?.createSnapshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

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
