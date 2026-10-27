import AppKit
import SwiftUI

@MainActor
final class AgentSetupWindowController {
    static let shared = AgentSetupWindowController()

    private var window: NSWindow?

    func show(coordinator: AgentCoordinator) {
        if window == nil {
            let root = AgentSetupView(onClose: { [weak self] in self?.window?.close() })
                .environment(coordinator)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "AI Agent 接入")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 720))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AgentSetupView: View {
    @Environment(AgentCoordinator.self) private var coordinator
    let onClose: () -> Void

    @State private var message: String?
    @State private var isTesting = false
    @State private var refreshToken = 0

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    skillSection
                    promptCard
                }
                .padding(.bottom, 8)
            }
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 620, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Agent 接入")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("通过本地 OpenAPI 让 Agent 创建、编辑和导出导图")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(coordinator.state.label)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { coordinator.enabled },
                    set: { coordinator.enabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text(coordinator.statusDescription)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if coordinator.enabled {
                HStack(spacing: 8) {
                    Text("空闲关闭")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { coordinator.idleMinutes },
                        set: { coordinator.idleMinutes = $0 }
                    )) {
                        Text("5 分钟").tag(5)
                        Text("10 分钟").tag(10)
                        Text("30 分钟").tag(30)
                        Text("不自动关闭").tag(0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    Spacer()
                    if let baseURL = coordinator.baseURL {
                        Text(baseURL.absoluteString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: 8) {
                    Button("测试连接") {
                        testConnection()
                    }
                    .buttonStyle(SettingsActionButtonStyle(primary: true))
                    .disabled(isTesting)

                    Button("复制接入提示") {
                        copyPrompt()
                    }
                    .buttonStyle(SettingsActionButtonStyle())

                    Button("重新生成令牌") {
                        coordinator.restart()
                        message = "已重新生成访问令牌。"
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("安装给 Agent 的说明书")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            Text("Skill 只是一份说明书，不含访问令牌。安装后 Agent 才能自动发现本地 OpenAPI 的用法。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(AgentSkillInstaller.Target.allCases) { target in
                    skillRow(target)
                    if target != AgentSkillInstaller.Target.allCases.last {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )

            HStack(spacing: 8) {
                Button("安装到所有已检测到的 Agent") {
                    installAll()
                }
                .buttonStyle(SettingsActionButtonStyle())
                Button("打开 Skill 目录") {
                    NSWorkspace.shared.open(AgentSkillInstaller().canonicalDirectory)
                }
                .buttonStyle(SettingsActionButtonStyle())
                Spacer()
            }
        }
        .id(refreshToken)
    }

    private func skillRow(_ target: AgentSkillInstaller.Target) -> some View {
        let installer = AgentSkillInstaller()
        let state = installer.state(for: target)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text(stateLabel(state))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(state == .notDetected ? "安装" : "安装 / 更新") {
                install(target)
            }
            .buttonStyle(SettingsActionButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("给 Agent 的第一句话")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(coordinator.skillPrompt)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
        }
    }

    private var footer: some View {
        HStack {
            Text(message ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("完成") { onClose() }
                .buttonStyle(SettingsActionButtonStyle(primary: true))
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .running: return .green
        case .error: return .orange
        case .stopped: return .yellow
        case .disabled: return .secondary
        }
    }

    private func stateLabel(_ state: AgentSkillInstaller.InstallState) -> String {
        switch state {
        case .notDetected: return "未检测到该 Agent 的配置目录"
        case .notInstalled: return "未安装"
        case .installed(let version): return "已安装 · v\(version)"
        case .outdated(let version): return "可更新 · 当前 v\(version)"
        }
    }

    private func install(_ target: AgentSkillInstaller.Target) {
        do {
            let result = try coordinator.installSkill(target: target)
            message = "已安装到 \(result.path)"
            refreshToken += 1
        } catch {
            message = "安装失败：\(error.localizedDescription)"
        }
    }

    private func installAll() {
        do {
            let results = try AgentSkillInstaller().installAllDetected()
            message = results.isEmpty ? "没有检测到可安装的 Agent" : "已安装 \(results.count) 个 Agent 的 Skill"
            refreshToken += 1
        } catch {
            message = "安装失败：\(error.localizedDescription)"
        }
    }

    private func testConnection() {
        isTesting = true
        Task {
            let result = await coordinator.testConnection()
            message = result
            isTesting = false
        }
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinator.skillPrompt, forType: .string)
        message = "已复制接入提示。"
    }
}
