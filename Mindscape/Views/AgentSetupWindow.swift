import AppKit
import SwiftUI

struct AgentSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(
                title: "AI Agent",
                subtitle: "本地 OpenAPI、Skill 安装与测试"
            )
            AgentSetupContent()
        }
    }
}

struct AgentSetupContent: View {
    @State private var coordinator = AgentCoordinator.shared
    @State private var message: String?
    @State private var isTesting = false
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusCard
            skillSection
            promptCard

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Text("安装给 AGENT 的说明书")
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
            Text("给 AGENT 的第一句话")
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
