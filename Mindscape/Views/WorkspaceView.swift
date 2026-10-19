import AppKit
import SwiftUI

struct MapCanvasRepresentable: NSViewRepresentable {
    let editor: MapEditor
    let revision: Int
    let themeID: String

    func makeNSView(context: Context) -> MindCanvasView {
        let view = MindCanvasView(frame: .zero)
        view.attach(editor: editor, theme: MapTheme.byID(themeID))
        return view
    }

    func updateNSView(_ nsView: MindCanvasView, context: Context) {
        _ = revision
        nsView.attach(editor: editor, theme: MapTheme.byID(themeID))
    }
}

struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Bindable var editor: MapEditor
    @State private var showHistory = false

    var body: some View {
        @Bindable var app = app
        MapCanvasRepresentable(editor: editor, revision: editor.revision, themeID: editor.map.themeID)
            .background(Color(nsColor: editor.theme.background))
            .inspector(isPresented: $app.showInspector) {
                InspectorView(editor: editor, onShowHistory: { showHistory = true })
                    .inspectorColumnWidth(min: 250, ideal: 286, max: 350)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showHistory) {
                HistoryView(editor: editor)
            }
            .navigationTitle("")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            TextField("未命名导图", text: Binding(
                get: { editor.map.title },
                set: { editor.setTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13.5, weight: .semibold))
            .frame(width: 190)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(MapLayout.allCases) { layout in
                    Button {
                        editor.setLayout(layout)
                    } label: {
                        if editor.map.layout == layout {
                            Label(layout.title, systemImage: "checkmark")
                        } else {
                            Label(layout.title, systemImage: layout.symbol)
                        }
                    }
                }
            } label: {
                Label("布局", systemImage: "square.grid.2x2")
            }
            .help("切换布局")

            Menu {
                ForEach(MapTheme.all) { theme in
                    Button {
                        editor.setTheme(theme.id)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(nsColor: theme.accent))
                                .frame(width: 8, height: 8)
                            Text(theme.name)
                            if editor.map.themeID == theme.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("主题", systemImage: "paintpalette")
            }
            .help("切换主题")

            Button {
                showHistory = true
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
            .help("历史版本")

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        app.export(format)
                    } label: {
                        Label(format.title, systemImage: format.symbol)
                    }
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出")

            Button {
                app.showInspector.toggle()
            } label: {
                Label("属性", systemImage: "sidebar.right")
            }
            .help("显示 / 隐藏属性面板")
        }
    }
}
