import SwiftUI

struct ExportSheet: View {
    @Bindable var editor: MapEditor
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .png
    @State private var pngScale = 2
    @State private var errorMessage: String?

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("导出「\(editor.map.title)」")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text("保存成独立文件，或直接通过系统分享。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("格式")

                    VStack(spacing: 6) {
                        ForEach(ExportFormat.allCases) { item in
                            formatRow(item)
                        }
                    }

                    if format.supportsScale {
                        HStack {
                            Text("PNG 清晰度")
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                            Picker("PNG 清晰度", selection: $pngScale) {
                                Text("1x").tag(1)
                                Text("2x").tag(2)
                                Text("3x").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Text("PNG / PDF 适合直接发出去；Markdown / OPML 适合导入其他大纲工具；JSON 适合备份和迁移。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    share()
                } label: {
                    Label("分享…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.regular)

                Spacer()

                Button {
                    save()
                } label: {
                    Label("保存到文件…", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("导出失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func formatRow(_ item: ExportFormat) -> some View {
        let selected = format == item
        return Button {
            format = item
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.opacity(selected ? 0.14 : 0.07))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.symbol)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(item.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accent)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? accent.opacity(0.07) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? accent.opacity(0.32) : Color.primary.opacity(0.055),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let layout = LayoutEngine.layout(editor.map)
        if ExportService.save(
            map: editor.map,
            layout: layout,
            format: format,
            scale: CGFloat(pngScale)
        ) {
            dismiss()
        }
    }

    private func share() {
        do {
            let layout = LayoutEngine.layout(editor.map)
            let url = try ExportService.temporaryURL(
                map: editor.map,
                layout: layout,
                format: format,
                scale: CGFloat(pngScale)
            )
            ExportService.share(url)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}
