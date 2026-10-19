import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 272, max: 340)
        } detail: {
            Group {
                if let editor = app.editor {
                    WorkspaceView(editor: editor)
                        .id(editor.map.id)
                } else {
                    EmptyStateView()
                }
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .tint(Color(nsColor: NSColor(hex: "#C26A4A")))
        .alert("提示", isPresented: Binding(
            get: { app.startupError != nil },
            set: { if !$0 { app.startupError = nil } }
        )) {
            Button("好") { app.startupError = nil }
        } message: {
            Text(app.startupError ?? "")
        }
    }
}
