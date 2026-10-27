import AppKit
import SwiftUI

/// 全局只自动展开一次新手提示。
/// 有数据的用户第一次打开导图、没数据的用户第一次新建导图，
/// 都会第一次进入 WorkspaceView，因此一个用户级标记即可覆盖两种情况。
struct CanvasTipsGate {
    static let storageKey = "mindscape.canvasTipsShown.v2"

    var defaults: UserDefaults = .standard

    var shouldShow: Bool {
        !defaults.bool(forKey: Self.storageKey)
    }

    func markShown() {
        defaults.set(true, forKey: Self.storageKey)
    }
}

/// 工具栏灯泡弹出的画布操作提示。所有零散的小提示集中在这里。
struct CanvasTipsPopover: View {
    @ObservedObject var store: ShortcutStore
    var onClose: () -> Void

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    private var modifier: String { store.selectionModifier.symbol }

    private var deleteKey: String {
        let combo = store.combo(for: .deleteNode)
        return combo.isEmpty ? "Delete" : combo.display
    }

    private func key(_ action: ShortcutAction) -> String {
        let combo = store.combo(for: action)
        return combo.isEmpty ? action.defaultCombo.display : combo.display
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    section("编辑节点", icon: "square.and.pencil", items: [
                        TipItem(keys: key(.editNode), text: "编辑当前节点"),
                        TipItem(keys: key(.newSibling), text: "新建同级节点"),
                        TipItem(keys: key(.newChild), text: "新建子节点"),
                        TipItem(keys: "双击空白", text: "新建头部节点"),
                        TipItem(keys: key(.duplicateNode), text: "创建副本")
                    ])

                    section("多选与批量", icon: "square.on.square", items: [
                        TipItem(keys: "\(modifier) 点击", text: "加选 / 减选节点"),
                        TipItem(keys: "\(modifier) 拖拽空白", text: "框选多个节点"),
                        TipItem(keys: deleteKey, text: "删除所选节点"),
                        TipItem(keys: "拖动选中节点", text: "整组移动（自由布局保持相对位置）")
                    ])

                    section("拖动与层级", icon: "arrow.up.and.down.and.arrow.left.and.right", items: [
                        TipItem(keys: "拖到节点上", text: "挂到该节点下面"),
                        TipItem(keys: "⌥ 拖到同级", text: "调整兄弟顺序"),
                        TipItem(keys: "⌘ 拖动", text: "自由布局下暂时关闭吸附"),
                        TipItem(keys: key(.fitCanvas), text: "适配整张画布")
                    ])

                    section("查找与视图", icon: "magnifyingglass", items: [
                        TipItem(keys: key(.findNode), text: "图内搜索节点"),
                        TipItem(keys: "\(key(.undo)) / \(key(.redo))", text: "撤销 / 重做"),
                        TipItem(keys: key(.zoomToBranch), text: "缩放到当前分支"),
                        TipItem(keys: key(.focusMode), text: "专注当前分支")
                    ])
                }
                .padding(16)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 430)
            Divider()
            footer
        }
        .frame(width: 392)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("画布操作提示")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("先看这些就够开始了，开始绘图后会自动收起。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("之后可点工具栏的灯泡随时查看")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Button("开始使用", action: onClose)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func section(_ title: String, icon: String, items: [TipItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    TipRow(keys: item.keys, text: item.text)
                }
            }
        }
    }
}

private struct TipItem: Identifiable {
    let id = UUID()
    let keys: String
    let text: String
}

private struct TipRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(minWidth: 94, alignment: .leading)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )

            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
