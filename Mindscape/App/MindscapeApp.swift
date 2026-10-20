import SwiftUI

@main
struct MindscapeApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        Window("Mindscape", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 840)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppCommands(app: app)
        }

        Settings {
            SettingsView()
                .environment(app)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(app)
        } label: {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .accessibilityLabel("Mindscape")
        }
        .menuBarExtraStyle(.menu)
    }
}
