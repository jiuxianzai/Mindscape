import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 Mindscape") {
            showMainWindow()
        }

        Divider()

        Button("新建导图") {
            create(.blank)
        }

        Menu("从模板新建") {
            ForEach(MapTemplate.allCases.filter { $0 != .blank }) { template in
                Button(template.title) {
                    create(template)
                }
            }
        }

        if !app.recentDocuments.isEmpty {
            Menu("最近导图") {
                ForEach(app.recentDocuments.prefix(6)) { document in
                    Button(document.title) {
                        open(document.id)
                    }
                }
            }
        }

        Divider()

        Button("检查更新…") {
            showUpdateWindow()
        }

        if case .available = app.updates.phase {
            Button("有可用更新：Mindscape \(app.updates.release?.version.description ?? "")") {
                showUpdateWindow()
            }
        }

        Button("AI Agent 接入…") {
            AgentSetupWindowController.shared.show(coordinator: .shared)
        }

        SettingsLink {
            Text("设置…")
        }

        Button("清空回收站…") {
            clearTrash()
        }
        .disabled(app.trashDocuments.isEmpty)

        Button("在 Finder 中打开数据目录") {
            if let url = app.store.directoryURL {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("退出 Mindscape") {
            NSApp.terminate(nil)
        }
    }

    private func showUpdateWindow() {
        UpdateWindowController.shared.show(checker: app.updates)
        Task { await app.updates.check(manual: true) }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func create(_ template: MapTemplate) {
        app.createDocument(template: template)
        showMainWindow()
    }

    private func open(_ id: UUID) {
        app.selectDocument(id)
        showMainWindow()
    }

    private func clearTrash() {
        let count = app.trashDocuments.count
        guard count > 0 else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "清空回收站？")
        alert.informativeText = String(localized: "回收站里的 \(count) 张导图将被彻底删除，无法恢复。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "清空"))
        alert.addButton(withTitle: String(localized: "取消"))
        if alert.runModal() == .alertFirstButtonReturn {
            app.emptyTrash()
        }
    }
}
