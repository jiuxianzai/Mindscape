import AppKit
import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.10), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 620
            )

            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 10) {
                        Image("BrandMark")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                        Text("开始一张新的导图")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("纯本地保存 · 无需登录 · 随时回滚")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 50)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(MapTemplate.allCases) { template in
                            TemplateCard(template: template) {
                                app.createDocument(template: template)
                            }
                        }
                    }
                    .frame(maxWidth: 700)

                    HStack(spacing: 18) {
                        hint(key: "Tab", text: "子主题")
                        hint(key: "↩", text: "同级主题")
                        hint(key: "双击", text: "编辑节点")
                        hint(key: "⌘0", text: "适配画布")
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func hint(key: String, text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct TemplateCard: View {
    let template: MapTemplate
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: template.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(nsColor: NSColor(hex: "#C26A4A")))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.09))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(template.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(hovering ? 0.08 : 0.03), radius: hovering ? 10 : 4, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        hovering ? Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.45) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
