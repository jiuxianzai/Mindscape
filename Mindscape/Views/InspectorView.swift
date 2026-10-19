import SwiftUI

struct InspectorView: View {
    @Bindable var editor: MapEditor
    var onShowHistory: () -> Void = {}

    private var selectedNode: MindNode? {
        guard editor.selection.count == 1, let id = editor.selection.first else { return nil }
        return editor.map.node(id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let node = selectedNode {
                    nodeSection(node)
                } else {
                    documentSection
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.32))
        .frame(minWidth: 250)
    }

    // MARK: - Node

    @ViewBuilder
    private func nodeSection(_ node: MindNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("节点文字")
            TextField("节点文字", text: Binding(
                get: { editor.map.node(node.id)?.text ?? "" },
                set: { editor.setText($0, for: node.id) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .font(.system(size: 13.5))
            .padding(9)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("备注")
            TextEditor(text: Binding(
                get: { editor.map.node(node.id)?.note ?? "" },
                set: { editor.setNote($0, for: node.id) }
            ))
            .font(.system(size: 12.5))
            .scrollContentBackground(.hidden)
            .frame(height: 86)
            .padding(6)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("图标")
            HStack(spacing: 6) {
                ForEach(["💡", "⭐️", "🚀", "✅", "⚠️", "📌", "❤️", "🔥"], id: \.self) { emoji in
                    Button {
                        editor.setEmoji(node.emoji == emoji ? nil : emoji, for: node.id)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 15))
                            .frame(width: 25, height: 25)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(node.emoji == emoji ? Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.16) : Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("颜色")
            HStack(spacing: 8) {
                colorSwatch(hex: nil, current: node.colorHex, id: node.id)
                ForEach(["#E8836B", "#E6B450", "#7FB89A", "#7BA7D9", "#A28BC9", "#4A4A52"], id: \.self) { hex in
                    colorSwatch(hex: hex, current: node.colorHex, id: node.id)
                }
            }
        }

        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("操作")
            HStack(spacing: 8) {
                Button {
                    if let newID = editor.addChild(to: node.id) {
                        editor.select(newID)
                    }
                } label: {
                    Label("添加子主题", systemImage: "plus")
                }
                .controlSize(.small)

                if !editor.map.children(of: node.id).isEmpty {
                    Button {
                        editor.toggleCollapse(node.id)
                    } label: {
                        Label(node.collapsed ? "展开" : "折叠", systemImage: node.collapsed ? "chevron.down" : "chevron.right")
                    }
                    .controlSize(.small)
                }
            }

            Button(role: .destructive) {
                editor.delete(id: node.id)
            } label: {
                Label("删除节点", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(node.id == editor.map.rootID)
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            Text("\(editor.map.nodes.count) 个节点")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text("更新于 \(RelativeDate.short(editor.map.updatedAt))")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func colorSwatch(hex: String?, current: String?, id: UUID) -> some View {
        let isSelected = (hex ?? "") == (current ?? "")
        return Button {
            editor.setColor(hex, for: id)
        } label: {
            ZStack {
                Circle()
                    .fill(hex.map { Color(nsColor: NSColor(hex: $0)) } ?? Color.primary.opacity(0.08))
                    .frame(width: 19, height: 19)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
                if hex == nil {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color(nsColor: NSColor(hex: "#C26A4A")), lineWidth: isSelected ? 1.6 : 0)
                    .frame(width: 23, height: 23)
            )
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "默认颜色" : "使用该颜色")
    }

    // MARK: - Document

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(editor.map.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(3)
                Text("\(editor.map.nodes.count) 个节点 · \(editor.map.layout.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                infoRow("布局", value: editor.map.layout.title)
                Divider().padding(.vertical, 7)
                infoRow("主题", value: editor.theme.name)
                Divider().padding(.vertical, 7)
                infoRow("创建", value: RelativeDate.full(editor.map.createdAt))
                Divider().padding(.vertical, 7)
                infoRow("更新", value: RelativeDate.short(editor.map.updatedAt))
            }
            .padding(11)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Menu {
                ForEach(MapLayout.allCases) { layout in
                    Button(layout.title) { editor.setLayout(layout) }
                }
            } label: {
                Label("切换布局", systemImage: "square.grid.2x2")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)

            Menu {
                ForEach(MapTheme.all) { theme in
                    Button(theme.name) { editor.setTheme(theme.id) }
                }
            } label: {
                Label("切换主题", systemImage: "paintpalette")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Button {
                    editor.requestFit()
                } label: {
                    Label("适配画布", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .controlSize(.small)

                Button {
                    onShowHistory()
                } label: {
                    Label("历史版本", systemImage: "clock.arrow.circlepath")
                }
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("小提示")
                Text("单击选中，双击编辑；Tab 新建子主题，回车新建同级主题；拖动节点到另一个节点上可调整层级。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
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
