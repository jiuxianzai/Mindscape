import SwiftUI

@main
struct MindscapeApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
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
    }
}
