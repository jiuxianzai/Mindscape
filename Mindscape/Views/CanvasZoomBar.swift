import AppKit
import SwiftUI

/// 画布底部的缩放 / 居中操作栏
struct CanvasZoomBar: View {
    @Bindable var bridge: CanvasBridge

    @State private var draft = "100%"
    @State private var lastCommitted = "100%"
    @FocusState private var isEditing: Bool

    private var percentText: String {
        String(format: "%.0f%%", bridge.zoom * 100)
    }

    var body: some View {
        HStack(spacing: 2) {
            BarIconButton(systemName: "minus", help: "缩小 5%") {
                step(-5)
            }

            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary.opacity(0.86))
                .frame(width: 52, height: 22)
                .background(
                    Color.primary.opacity(isEditing ? 0.09 : 0.045),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .focused($isEditing)
                .onSubmit(commit)
                .onExitCommand {
                    draft = percentText
                    lastCommitted = draft
                    isEditing = false
                }
                .onChange(of: isEditing) { _, editing in
                    if editing {
                        draft = percentText
                        lastCommitted = draft
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    } else {
                        commit()
                        // 编辑期间可能用触控板缩放过，失焦后以画布实际比例为准
                        draft = percentText
                        lastCommitted = draft
                    }
                }
                .onChange(of: bridge.zoom) { _, _ in
                    guard !isEditing else { return }
                    draft = percentText
                    lastCommitted = draft
                }
                .onAppear {
                    draft = percentText
                    lastCommitted = draft
                }
                .accessibilityLabel("缩放比例")

            BarIconButton(systemName: "plus", help: "放大 5%") {
                step(5)
            }

            BarIconButton(systemName: nil, help: "回到 100% 比例", title: "100%") {
                if isEditing { commit() }
                isEditing = false
                bridge.resetZoom()
                draft = percentText
                lastCommitted = draft
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            BarIconButton(
                systemName: "dot.squareshape.split.2x2",
                help: "水平 + 垂直居中",
                title: "居中"
            ) {
                if isEditing { commit() }
                isEditing = false
                bridge.centerContent()
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
    }

    private func step(_ points: CGFloat) {
        if isEditing { commit() }
        isEditing = false
        bridge.stepZoom(byPercentPoints: points)
        draft = percentText
        lastCommitted = draft
    }

    private func commit() {
        guard draft != lastCommitted else { return }
        guard let percent = Int(draft.filter(\.isNumber)) else {
            draft = percentText
            lastCommitted = draft
            return
        }
        let minPercent = Int((CanvasCamera.minZoom * 100).rounded())
        let maxPercent = Int((CanvasCamera.maxZoom * 100).rounded())
        let clamped = min(max(percent, minPercent), maxPercent)
        bridge.setZoomPercent(Double(clamped))
        draft = "\(clamped)%"
        lastCommitted = draft
        isEditing = false
    }
}

private struct BarIconButton: View {
    var systemName: String? = nil
    let help: String
    var title: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: title == nil ? 11.5 : 10.5, weight: .semibold))
                }
                if let title {
                    Text(title.l10n)
                        .font(.system(size: 10.5, weight: .medium))
                }
            }
            .foregroundStyle(Color.primary.opacity(hovering ? 0.95 : 0.7))
            .padding(.horizontal, title == nil ? 0 : 6)
            .frame(width: title == nil ? 27 : nil, height: 24)
            .background(
                Color.primary.opacity(hovering ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
