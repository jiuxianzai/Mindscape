import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("defaultThemeID") private var themeID = MapTheme.defaultThemeID
    @AppStorage("defaultLayout") private var layoutRaw = MapLayout.mindMap.rawValue

    var body: some View {
        Form {
            Section("新建导图") {
                Picker("默认布局", selection: $layoutRaw) {
                    ForEach(MapLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                Picker("默认主题", selection: $themeID) {
                    ForEach(MapTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
            }

            Section("数据") {
                LabeledContent("存储位置") {
                    Text(app.store.databaseURL?.path ?? "内存模式")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Button("在 Finder 中打开") {
                    if let url = app.store.databaseURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Text("所有数据仅保存在本机 SQLite 数据库中，不会上传。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                }
                LabeledContent("Mindscape") {
                    Text("本地优先的思维导图")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
    }
}
