import AppKit
import SwiftUI

struct UpdateBanner: View {
    @Environment(AppModel.self) private var app

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text("Mindscape \(app.updates.release?.version.description ?? "") 可用")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("查看更新说明，下载后拖进 Applications 即可覆盖")
                    .font(.system(size: 9.5))
                    .opacity(0.82)
            }

            Spacer(minLength: 12)

            Button("查看") {
                app.updates.dismissBanner()
                showWindow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )

            Button {
                app.updates.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("稍后提醒")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func showWindow() {
        UpdateWindowController.shared.show(checker: app.updates)
    }
}
