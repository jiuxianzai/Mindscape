import AppKit
import Foundation

@MainActor
enum AgentOnboarding {
    static let didAskKey = "agent.didAskInstall"
    static let guideURL = URL(string: "https://jiuxianzai.github.io/Mindscape/#ai-agent")!

    static func presentIfNeeded(onFinish: (() -> Void)? = nil) {
        guard !UpdateChecker.isRunningUnitTests else {
            onFinish?()
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAskKey) else {
            onFinish?()
            return
        }

        let installer = AgentSkillInstaller()
        if installer.hasAnyInstalled {
            defaults.set(true, forKey: didAskKey)
            onFinish?()
            return
        }
        guard let window = mainWindow else {
            onFinish?()
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(named: "BrandMark")
        alert.messageText = String(localized: "安装 AI Agent Skill？")
        alert.informativeText = String(localized: "给已检测到的 Agent 安装本地说明书（Claude Code / Codex / DSH / OpenCode）。默认关闭，不联网；之后可在「设置 → AI Agent」安装或更新。可在下方勾选安装后直接开启。\n\n安装后对 Agent 说：「请阅读 ~/.agents/skills/mindscape/SKILL.md 建一张导图。」\n\n教程：jiuxianzai.github.io/Mindscape/#ai-agent")

        let enableCheckbox = NSButton(
            checkboxWithTitle: String(localized: "安装后开启 AI Agent"),
            target: nil,
            action: nil
        )
        enableCheckbox.state = .on
        enableCheckbox.controlSize = .small
        enableCheckbox.font = .systemFont(ofSize: 11)
        enableCheckbox.frame = NSRect(x: 0, y: 0, width: 220, height: 20)
        alert.accessoryView = enableCheckbox

        alert.addButton(withTitle: String(localized: "暂不"))
        alert.addButton(withTitle: String(localized: "一键安装"))

        alert.beginSheetModal(for: window) { response in
            defaults.set(true, forKey: didAskKey)
            guard response == .alertSecondButtonReturn else {
                onFinish?()
                return
            }
            let enableAgent = enableCheckbox.state == .on
            DispatchQueue.main.async {
                install(
                    installer: installer,
                    enableAgent: enableAgent,
                    window: window,
                    onFinish: onFinish
                )
            }
        }
    }

    private static func install(
        installer: AgentSkillInstaller,
        enableAgent: Bool,
        window: NSWindow,
        onFinish: (() -> Void)?
    ) {
        do {
            let results = try installer.installAllDetected()
            if results.isEmpty {
                _ = try installer.installCanonical()
            }
            if enableAgent {
                AgentCoordinator.shared.enabled = true
            }
            showSuccess(
                installer: installer,
                installedCount: results.count,
                agentEnabled: AgentCoordinator.shared.enabled,
                window: window,
                onFinish: onFinish
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "AI Agent Skill 安装失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "好"))
            DispatchQueue.main.async {
                alert.beginSheetModal(for: window) { _ in
                    onFinish?()
                }
            }
        }
    }

    private static func showSuccess(
        installer: AgentSkillInstaller,
        installedCount: Int,
        agentEnabled: Bool,
        window: NSWindow,
        onFinish: (() -> Void)?
    ) {
        let agentState = agentEnabled
            ? String(localized: "已为你开启 AI Agent。")
            : String(localized: "AI Agent 仍关闭，可在「设置 → AI Agent」开启。")
        let detail: String
        if installedCount > 0 {
            detail = String(localized: "已安装到 \(installedCount) 个 Agent。") + agentState
                + String(localized: "之后可在同一页更新或重新安装。")
        } else {
            detail = String(localized: "未检测到已安装的 Agent，已把说明书放到公共目录 ~/.agents/skills/mindscape。") + agentState
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
            onFinish?()
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == "Mindscape" }
            ?? NSApp.keyWindow
            ?? NSApp.windows.first { $0.isVisible }
    }
}
