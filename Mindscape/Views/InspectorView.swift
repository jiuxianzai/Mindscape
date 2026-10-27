import SwiftUI

struct InspectorView: View {
    @Bindable var editor: MapEditor
    var onShowHistory: () -> Void = {}

    @State private var showLayoutPicker = false

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
                    if editor.selection.count > 1 {
                        batchContent
                    } else if let node = selectedNode {
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
                    actionButton("复制子树", icon: "doc.on.doc") {
                        editor.copySelection()
                    }
                    actionButton("创建副本", icon: "plus.square.on.square") {
                        editor.duplicateSelection()
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
                        enabled: !editor.map.rootIDs.contains(node.id) || editor.map.rootIDs.count > 1
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

    // MARK: - Batch

    private var batchColorValues: Set<String> {
        Set(editor.selectedNodes.map { $0.colorHex ?? "" })
    }

    private var batchIconValues: Set<String> {
        Set(editor.selectedNodes.map { $0.icon ?? "" })
    }

    private var batchIcon: String? {
        let values = batchIconValues
        guard values.count == 1, let value = values.first, !value.isEmpty else { return nil }
        return value
    }

    private var batchContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("已选择 \(editor.selection.count) 个节点")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("批量修改会作为一次操作撤销。Shift 拖拽空白处可框选，Delete 删除所选，拖动任一选中节点可整组移动。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("批量颜色")
                HStack(spacing: 8) {
                    batchColorSwatch(hex: nil)
                    ForEach(["#E8836B", "#E6B450", "#7FB89A", "#7BA7D9", "#A28BC9", "#4A4A52"], id: \.self) { hex in
                        batchColorSwatch(hex: hex)
                    }
                }
            }

            IconPickerView(
                editor: editor,
                nodeIDs: Array(editor.selection),
                currentIcon: batchIcon
            )

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("操作")
                LazyVGrid(columns: actionColumns, spacing: 6) {
                    actionButton("复制所选", icon: "doc.on.doc") {
                        editor.copySelection()
                    }
                    actionButton("创建副本", icon: "plus.square.on.square") {
                        editor.duplicateSelection()
                    }
                    actionButton("折叠 / 展开", icon: "chevron.up.chevron.down") {
                        editor.toggleCollapse(ids: editor.selection)
                    }
                    actionButton("删除所选", icon: "trash", destructive: true) {
                        editor.deleteSelection()
                    }
                }
            }

            if editor.map.layout == .free {
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel("对齐与等距")
                    LazyVGrid(columns: actionColumns, spacing: 6) {
                        ForEach(MapEditor.FreeArrangement.allCases) { option in
                            actionButton(
                                option.title,
                                icon: option.symbol,
                                enabled: !option.needsThree || editor.selection.count >= 3
                            ) {
                                let frames = LayoutEngine.layout(editor.map).frames
                                editor.arrangeSelection(option, frames: frames)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("信息")
                infoRow("节点数", value: "\(editor.map.nodes.count)")
                infoRow("已选", value: "\(editor.selection.count)")
            }
        }
    }

    private func batchColorSwatch(hex: String?) -> some View {
        let values = batchColorValues
        let isSelected = values.count == 1 && values.first == (hex ?? "")
        return Button {
            editor.setColor(hex, for: editor.selection)
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
        .help(hex == nil ? "恢复默认颜色" : "应用到所选节点")
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
                // 直接铺成两列网格：当前浅色/深色外观对应的主题完整显示，
                // 不会因为菜单滚动只看到选中项附近的几个。
                ThemePickerGrid(selectedID: editor.map.themeID) { themeID in
                    editor.setTheme(themeID)
                }
                Text("浅色 / 深色主题分别保存")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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
                Text("Space 编辑，Enter 新建同级 / 头部，Tab 新建子节点；双击空白新建头部。拖到节点上改层级；⌥ 拖到同级节点排序。方向键移动，⌘↑ / ↓ / ← / → 跳父级 / 子级 / 同级；⌘F 搜索，Shift 拖拽框选，Delete 删除所选，拖动任一选中节点可整组移动，⌘D 创建副本。")
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

    private func pickerOption(title: String, icon: String?, selected: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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
                Text(title.l10n)
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
        .accessibilityLabel(hex == nil ? String(localized: "默认颜色") : String(format: String(localized: "颜色：%@"), colorName(for: hex)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorName(for hex: String?) -> String {
        switch hex {
        case "#E8836B": return String(localized: "珊瑚")
        case "#E6B450": return String(localized: "琥珀")
        case "#7FB89A": return String(localized: "薄荷")
        case "#7BA7D9": return String(localized: "天蓝")
        case "#A28BC9": return String(localized: "紫罗兰")
        case "#4A4A52": return String(localized: "石墨")
        default: return hex ?? String(localized: "默认颜色")
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.l10n)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.l10n)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}
