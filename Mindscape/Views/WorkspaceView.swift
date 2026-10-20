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
    @Bindable var editor: MapEditor
    @State private var showHistory = false
    @State private var showInspector = true
    @State private var showExport = false

    var body: some View {
        MapCanvasRepresentable(editor: editor, revision: editor.revision, themeID: editor.map.themeID)
            .background(Color(nsColor: editor.theme.background))
            .inspector(isPresented: $showInspector) {
                InspectorView(
                    editor: editor,
                    onShowHistory: { showHistory = true }
                )
                .inspectorColumnWidth(min: 250, ideal: 286, max: 360)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showHistory) {
                HistoryView(editor: editor)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(editor: editor)
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindscapeShowHistory)) { _ in
                showHistory = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindscapeShowExport)) { _ in
                showExport = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindscapeToggleInspector)) { _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    showInspector.toggle()
                }
            }
            .background(
                InspectorTitlebarToggle()
                    .frame(width: 1, height: 1)
            )
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
            .frame(width: 200)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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

            Picker("主题", selection: Binding(
                get: { editor.map.themeID },
                set: { editor.setTheme($0) }
            )) {
                ForEach(MapTheme.all) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 96)
            .help("切换主题")

            Button {
                showHistory = true
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
            .help("历史版本")

            Button {
                showExport = true
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出 / 分享")

        }
    }
}
