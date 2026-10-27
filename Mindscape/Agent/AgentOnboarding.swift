import AppKit
import Foundation

@MainActor
enum AgentOnboarding {
    static let didAskKey = "agent.didAskInstall"
    static let guideURL = URL(string: "https://jiuxianzai.github.io/Mindscape/#ai-agent")!

    static func presentIfNeeded() {
        guard !UpdateChecker.isRunningUnitTests else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAskKey) else { return }

        let installer = AgentSkillInstaller()
        if installer.hasAnyInstalled {
            defaults.set(true, forKey: didAskKey)
            return
        }
        guard let window = mainWindow else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(named: "BrandMark")
        alert.messageText = String(localized: "安装 AI Agent Skill？")
        alert.informativeText = String(localized: "开启后会给本机已检测到的 Agent 安装一份说明书：Claude Code、Codex、DSH、OpenCode。默认关闭，不会联网；之后可在「设置 → AI Agent」中随时安装或更新。安装后需在「设置 → AI Agent」开启开关，Agent 才能连接。\n\n安装后对 Agent 说：「请阅读 ~/.agents/skills/mindscape/SKILL.md，然后通过 Mindscape 建一张导图。」\n\n详细教程：https://jiuxianzai.github.io/Mindscape/#ai-agent")
        alert.addButton(withTitle: String(localized: "暂不"))
        alert.addButton(withTitle: String(localized: "一键安装"))
        widen(alert)

        alert.beginSheetModal(for: window) { response in
            defaults.set(true, forKey: didAskKey)
            guard response == .alertSecondButtonReturn else { return }
            DispatchQueue.main.async {
                install(installer: installer, window: window)
            }
        }
    }

    private static func install(installer: AgentSkillInstaller, window: NSWindow) {
        do {
            let results = try installer.installAllDetected()
            if results.isEmpty {
                _ = try installer.installCanonical()
            }
            showSuccess(
                installer: installer,
                installedCount: results.count,
                window: window
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "AI Agent Skill 安装失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "好"))
            DispatchQueue.main.async {
                alert.beginSheetModal(for: window)
            }
        }
    }

    private static func showSuccess(
        installer: AgentSkillInstaller,
        installedCount: Int,
        window: NSWindow
    ) {
        let detail: String
        if installedCount > 0 {
            detail = String(localized: "已安装到 \(installedCount) 个 Agent。使用前请在「设置 → AI Agent」开启开关；之后可在同一页更新或重新安装。")
        } else {
            detail = String(localized: "未检测到已安装的 Agent，已把说明书放到公共目录 ~/.agents/skills/mindscape。使用前请在「设置 → AI Agent」开启开关。")
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(named: "BrandMark")
        alert.messageText = String(localized: "AI Agent Skill 已安装")
        alert.informativeText = """
        \(detail)

        \(installer.prompt)

        \(String(localized: "简要教程与四 Agent 安装位置："))
        https://jiuxianzai.github.io/Mindscape/#ai-agent
        """
        alert.addButton(withTitle: String(localized: "复制这句话"))
        alert.addButton(withTitle: String(localized: "查看教程"))
        alert.addButton(withTitle: String(localized: "完成"))
        widen(alert)

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installer.prompt, forType: .string)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(guideURL)
            default:
                break
            }
        }
    }

    /// NSAlert 默认宽度约 420，长教程文案会在右侧留下很大的换行空白。
    /// 用一个透明 accessory 把 sheet 撑到 700，正文会自然占满。
    private static func widen(_ alert: NSAlert) {
        alert.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 1))
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == "Mindscape" }
            ?? NSApp.keyWindow
            ?? NSApp.windows.first { $0.isVisible }
    }
}
