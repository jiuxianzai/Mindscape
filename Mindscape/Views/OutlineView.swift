import AppKit
import SwiftUI

/// 画布左侧的大纲面板：按层级列出节点，点击定位到画布
struct OutlineView: View {
    @Bindable var editor: MapEditor
    var onReveal: (UUID) -> Void = { _ in }

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    OutlineSubtree(
                        editor: editor,
                        nodeID: editor.map.rootID,
                        depth: 0,
                        onReveal: onReveal
                    )
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.36))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("大纲")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text("\(editor.map.nodes.count)")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                editor.collapseAll()
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("折叠全部子分支")

            Button {
                editor.expandAll()
            } label: {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("展开全部")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct OutlineSubtree: View {
    @Bindable var editor: MapEditor
    let nodeID: UUID
    let depth: Int
    var onReveal: (UUID) -> Void

    var body: some View {
        if let node = editor.map.node(nodeID) {
            OutlineRow(
                editor: editor,
                node: node,
                depth: depth,
                onReveal: onReveal
            )
            if !node.collapsed {
                ForEach(editor.map.children(of: nodeID)) { child in
                    OutlineSubtree(
                        editor: editor,
                        nodeID: child.id,
                        depth: depth + 1,
                        onReveal: onReveal
                    )
                }
            }
        }
    }
}

private struct OutlineRow: View {
    @Bindable var editor: MapEditor
    let node: MindNode
    let depth: Int
    var onReveal: (UUID) -> Void

    @State private var hovering = false

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    private var isSelected: Bool { editor.selection.contains(node.id) }
    private var children: [MindNode] { editor.map.children(of: node.id) }
    private var hasNote: Bool {
        !node.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 5) {
            if children.isEmpty {
                Color.clear.frame(width: 12, height: 12)
            } else {
                Button {
                    editor.toggleCollapse(node.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(node.collapsed ? 0 : 90))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let icon = node.icon {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.65))
                    .frame(width: 14)
            } else {
                Circle()
                    .fill(isSelected ? accent : Color.primary.opacity(0.22))
                    .frame(width: 4, height: 4)
                    .frame(width: 14)
            }

            Text(node.text.isEmpty ? String(localized: "未命名") : node.text)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))

            if hasNote {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 2)

            if node.collapsed, !children.isEmpty {
                Text("\(descendantCount)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 12 + 4)
        .padding(.trailing, 6)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            editor.select(node.id)
            onReveal(node.id)
        }
        .help(node.text)
    }

    private var background: Color {
        if isSelected { return accent.opacity(0.11) }
        if hovering { return Color.primary.opacity(0.04) }
        return .clear
    }

    private var descendantCount: Int {
        editor.map.subtreeIDs(of: node.id).count - 1
    }
}
