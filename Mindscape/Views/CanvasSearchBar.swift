import AppKit
import SwiftUI

/// 画布顶部的图内搜索栏
struct CanvasSearchBar: View {
    @Binding var text: String
    let matchCount: Int
    let activeIndex: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    @FocusState private var focused: Bool

    private var counter: String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        guard matchCount > 0 else { return String(localized: "无结果") }
        return "\(activeIndex + 1) / \(matchCount)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索节点文字、备注或图标", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 210)
                .focused($focused)
                .onSubmit(onNext)
                .onExitCommand(perform: onClose)

            Text(counter)
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 38, alignment: .trailing)

            searchButton("chevron.up", help: "上一个结果", action: onPrevious)
                .disabled(matchCount == 0)
            searchButton("chevron.down", help: "下一个结果", action: onNext)
                .disabled(matchCount == 0)

            Divider()
                .frame(height: 13)
                .padding(.horizontal, 1)

            searchButton("xmark", help: "关闭搜索", action: onClose)
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .onAppear {
            DispatchQueue.main.async {
                focused = true
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private func searchButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help.l10n)
        .accessibilityLabel(help.l10n)
    }
}
