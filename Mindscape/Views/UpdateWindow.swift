import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController {
    static let shared = UpdateWindowController()

    private var window: NSWindow?
    private var didPosition = false

    func show(checker: UpdateChecker) {
        if window == nil {
            let root = UpdateWindowView(onClose: { [weak self] in
                self?.window?.close()
            })
            .environment(checker)

            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "软件更新")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 500, height: 560))
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            let screen = hostScreen()
            if !didPosition {
                position(window, on: screen)
                didPosition = true
            } else if let screen, !screen.visibleFrame.intersects(window.frame) {
                position(window, on: screen)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// 多显示器 / 虚拟屏下 `center()` 可能把窗口放到屏幕外，跟随主窗口所在屏幕。
    private func hostScreen() -> NSScreen? {
        if let main = NSApp.windows.first(where: { $0.title == "Mindscape" && $0.isVisible })?.screen {
            return main
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func position(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}

struct UpdateWindowView: View {
    @Environment(UpdateChecker.self) private var updates
    let onClose: () -> Void

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 500, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mindscape")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(versionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if updates.phase == .checking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var versionLine: String {
        let current = updates.installedVersionDescription
        if let next = updates.release?.version.description,
           updates.phase == .available || updates.phase == .ready || updates.phase.isDownloading {
            return "\(current)  →  \(next)"
        }
        return String(localized: "版本 \(current)")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch updates.phase {
        case .idle:
            message(
                icon: "arrow.triangle.2.circlepath",
                title: String(localized: "检查更新"),
                detail: String(localized: "从 GitHub Releases 获取最新版本。")
            )

        case .checking:
            VStack(spacing: 10) {
                ProgressView()
                Text("正在检查更新…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)

        case .upToDate:
            message(
                icon: "checkmark.circle.fill",
                title: String(localized: "已是最新版本"),
                detail: String(localized: "当前版本 \(updates.installedVersionDescription) 已经是最新。")
            )

        case .available:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Mindscape \(updates.release?.version.description ?? "")")
                        .font(.system(size: 13.5, weight: .semibold))
                    if let published = updates.release?.publishedAt {
                        Text(RelativeDate.short(published))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !updates.downloadSizeDescription.isEmpty {
                        Text(updates.downloadSizeDescription)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                notes

                Text("下载完成后会打开 DMG，需要把 Mindscape 拖进 Applications 覆盖旧版本。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

        case .downloading(let progress, let received, let total):
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: progress)
                    .tint(accent)
                HStack {
                    Text("正在下载…")
                        .font(.system(size: 11.5))
                    Spacer()
                    Text("\(byteText(received)) / \(byteText(total))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("下载完成后会校验 SHA-256，然后打开安装包。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                message(
                    icon: "checkmark.circle.fill",
                    title: String(localized: "下载完成"),
                    detail: downloadedPath
                )

                HStack(spacing: 6) {
                    Image(systemName: updates.checksumState == .verified ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(updates.checksumState == .verified ? Color.green : Color.orange)
                    Text(checksumText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                installSteps
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("更新失败")
                            .font(.system(size: 13, weight: .semibold))
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button("打开发布页") {
                    updates.openReleasePage()
                }
                .buttonStyle(SettingsActionButtonStyle())
            }
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var notes: some View {
        ScrollView {
            Text(verbatim: notesText)
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }

    private var notesText: String {
        guard let raw = updates.release?.notes, !raw.isEmpty else {
            return String(localized: "这个版本没有附带更新说明，可以打开发布页查看。")
        }
        return raw
    }

    private var downloadedPath: String {
        guard let url = updates.downloadedFile else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home + "/") {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    private var checksumText: String {
        switch updates.checksumState {
        case .verified:
            return String(localized: "SHA-256 已校验")
        case .notProvided:
            return String(localized: "发布方没有提供校验文件，未做完整性校验")
        case .unknown:
            return String(localized: "未校验")
        }
    }

    private var installSteps: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("安装步骤")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            step(1, String(localized: "打开 DMG"))
            step(2, String(localized: "把 Mindscape 拖进 Applications，覆盖旧版本"))
            step(3, String(localized: "推出磁盘映像，再重新打开 Mindscape"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Circle().fill(accent))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(0.82))
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch updates.phase {
        case .available:
            HStack(spacing: 8) {
                Button("跳过此版本") {
                    updates.skipCurrentVersion()
                    onClose()
                }
                .buttonStyle(SettingsActionButtonStyle())

                Spacer()

                Button("稍后") {
                    onClose()
                }
                .buttonStyle(SettingsActionButtonStyle())

                Button("下载更新") {
                    Task { await updates.download() }
                }
                .buttonStyle(SettingsActionButtonStyle(primary: true))
                .disabled(updates.release?.preferredAsset == nil)
            }

        case .downloading:
            HStack {
                Spacer()
                Button("取消下载") {
                    updates.cancelDownload()
                }
                .buttonStyle(SettingsActionButtonStyle())
            }

        case .ready:
            HStack(spacing: 8) {
                Button("在 Finder 中显示") {
                    updates.revealDownloaded()
                }
                .buttonStyle(SettingsActionButtonStyle())

                Spacer()

                Button("打开安装包") {
                    updates.openDownloaded()
                }
                .buttonStyle(SettingsActionButtonStyle(primary: true))
            }

        case .failed:
            HStack(spacing: 8) {
                Button("打开发布页") {
                    updates.openReleasePage()
                }
                .buttonStyle(SettingsActionButtonStyle())

                Spacer()

                Button("重试") {
                    Task { await updates.check(manual: true) }
                }
                .buttonStyle(SettingsActionButtonStyle(primary: true))
            }

        case .checking:
            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .buttonStyle(SettingsActionButtonStyle())
            }

        case .idle, .upToDate:
            HStack(spacing: 8) {
                Spacer()
                Button("关闭") { onClose() }
                    .buttonStyle(SettingsActionButtonStyle())
                Button("检查更新") {
                    Task { await updates.check(manual: true) }
                }
                .buttonStyle(SettingsActionButtonStyle(primary: true))
            }
        }
    }

    private func byteText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
