import SwiftUI

struct InspectorView: View {
    @Bindable var editor: MapEditor
    var onShowHistory: () -> Void = {}

    @State private var showLayoutPicker = false
    @State private var showThemePicker = false

    private var selectedNode: MindNode? {
        guard editor.selection.count == 1, let id = editor.selection.first else { return nil }
        return editor.map.node(id)
    }

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))
    private let actionColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let node = selectedNode {
                        nodeContent(node)
                    } else {
                        documentContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.32))
        .frame(minWidth: 250)
    }

    private var header: some View {
        HStack {
            Text("属性")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Node

    private func nodeContent(_ node: MindNode) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
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

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("备注")
                TextEditor(text: Binding(
                    get: { editor.map.node(node.id)?.note ?? "" },
                    set: { editor.setNote($0, for: node.id) }
                ))
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(height: 82)
                .padding(6)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            IconPickerView(editor: editor, node: node)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("颜色")
                HStack(spacing: 8) {
                    colorSwatch(hex: nil, current: node.colorHex, id: node.id)
                    ForEach(["#E8836B", "#E6B450", "#7FB89A", "#7BA7D9", "#A28BC9", "#4A4A52"], id: \.self) { hex in
                        colorSwatch(hex: hex, current: node.colorHex, id: node.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("操作")
                LazyVGrid(columns: actionColumns, spacing: 6) {
                    actionButton("添加子主题", icon: "plus") {
                        editor.addChild(to: node.id)
                    }
                    actionButton("添加同级主题", icon: "arrow.turn.down.right") {
                        editor.addSibling(after: node.id)
                    }
                    actionButton(
                        node.collapsed ? "展开" : "折叠",
                        icon: node.collapsed ? "chevron.down" : "chevron.right",
                        enabled: !editor.map.children(of: node.id).isEmpty
                    ) {
                        editor.toggleCollapse(node.id)
                    }
                    actionButton(
                        "删除节点",
                        icon: "trash",
                        destructive: true,
                        enabled: node.id != editor.map.rootID
                    ) {
                        editor.delete(id: node.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("信息")
                infoRow("节点数", value: "\(editor.map.nodes.count)")
                infoRow("更新", value: RelativeDate.short(editor.map.updatedAt))
            }
        }
    }

    // MARK: - Document

    private var documentContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(editor.map.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(3)
                Text("\(editor.map.nodes.count) 个节点")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("文档信息")
                infoRow("创建", value: RelativeDate.full(editor.map.createdAt))
                infoRow("更新", value: RelativeDate.short(editor.map.updatedAt))
            }

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("布局")
                layoutPickerButton
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("主题")
                HStack(spacing: 7) {
                    ForEach(MapTheme.all) { theme in
                        themeSwatch(theme)
                    }
                }
                themePickerButton
            }

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("操作")
                LazyVGrid(columns: actionColumns, spacing: 6) {
                    actionButton("适配画布", icon: "arrow.up.left.and.arrow.down.right") {
                        editor.requestFit()
                    }
                    actionButton("历史版本", icon: "clock.arrow.circlepath") {
                        onShowHistory()
                    }
                }
                actionButton("创建快照", icon: "camera") {
                    editor.createSnapshot()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("小提示")
                Text("拖到节点上改层级；按住 ⌥ 拖到同级节点上下排序。双击编辑，选中后直接打字也能编辑。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Controls

    private var layoutPickerButton: some View {
        Button {
            showLayoutPicker.toggle()
        } label: {
            pickerLabel(icon: "square.grid.2x2", title: editor.map.layout.title)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showLayoutPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MapLayout.allCases) { layout in
                    Button {
                        editor.setLayout(layout)
                        showLayoutPicker = false
                    } label: {
                        pickerOption(
                            title: layout.title,
                            icon: layout.symbol,
                            color: nil,
                            selected: editor.map.layout == layout
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 200)
        }
    }

    private var themePickerButton: some View {
        Button {
            showThemePicker.toggle()
        } label: {
            pickerLabel(icon: "paintpalette", title: editor.theme.name)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showThemePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MapTheme.all) { theme in
                    Button {
                        editor.setTheme(theme.id)
                        showThemePicker = false
                    } label: {
                        pickerOption(
                            title: theme.name,
                            icon: nil,
                            color: Color(nsColor: theme.accent),
                            selected: editor.map.themeID == theme.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 200)
        }
    }

    private func pickerLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func pickerOption(title: String, icon: String?, color: Color?, selected: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else if let color {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .frame(width: 14)
            }
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .contentShape(Rectangle())
    }

    private func actionButton(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(destructive ? Color.red : Color.primary.opacity(0.78))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(destructive ? Color.red.opacity(0.07) : Color.primary.opacity(0.045))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
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

    private func themeSwatch(_ theme: MapTheme) -> some View {
        let selected = editor.map.themeID == theme.id
        return Button {
            editor.setTheme(theme.id)
        } label: {
            ZStack {
                Circle().fill(Color(nsColor: theme.background))
                Circle().fill(Color(nsColor: theme.accent)).frame(width: 9, height: 9)
            }
            .frame(width: 19, height: 19)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .overlay(
                Circle()
                    .strokeBorder(Color(nsColor: NSColor(hex: "#C26A4A")), lineWidth: selected ? 1.8 : 0)
                    .frame(width: 24, height: 24)
            )
        }
        .buttonStyle(.plain)
        .help(theme.name)
        .accessibilityLabel(theme.name)
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
