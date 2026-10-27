import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AgentCoordinator {
    static let shared = AgentCoordinator()
    static let startNotification = "com.youyanping.mindscape.agent.start"
    static let gatewayFileName = "agent-gateway.json"

    enum State: Equatable {
        case disabled
        case stopped
        case running(port: UInt16)
        case error(String)

        var label: String {
            switch self {
            case .disabled: return "未启用"
            case .stopped: return "已停止"
            case .running(let port): return "运行中 · 127.0.0.1:\(port)"
            case .error: return "启动失败"
            }
        }
    }

    private enum Key {
        static let enabled = "agent.enabled"
        static let idleMinutes = "agent.idleMinutes"
    }

    private(set) var state: State = .disabled
    private(set) var lastError: String?
    private(set) var runningSince: Date?

    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Key.enabled)
            if enabled {
                start()
            } else {
                stop()
                state = .disabled
            }
        }
    }

    var idleMinutes: Int {
        didSet {
            guard idleMinutes != oldValue else { return }
            UserDefaults.standard.set(idleMinutes, forKey: Key.idleMinutes)
        }
    }

    private weak var app: AppModel?
    private var server: AgentHTTPServer?
    private var service: AgentService?
    private var idleTask: Task<Void, Never>?
    private var notificationObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?

    private init() {
        enabled = UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? false
        let stored = UserDefaults.standard.object(forKey: Key.idleMinutes) as? Int ?? 10
        idleMinutes = [5, 10, 30, 0].contains(stored) ? stored : 10
        state = enabled ? .stopped : .disabled
    }

    var gatewayURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mindscape/\(Self.gatewayFileName)")
    }

    var baseURL: URL? {
        guard case .running(let port) = state else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    var statusDescription: String {
        switch state {
        case .disabled:
            return "AI Agent 无法连接。开启后，Agent 调用时才会启动本地服务。"
        case .stopped:
            return "已启用，等待 Agent 调用；空闲 \(idleMinutes == 0 ? "不自动关闭" : "\(idleMinutes) 分钟") 后自动停止。"
        case .running(let port):
            return "服务运行在 127.0.0.1:\(port)，仅接受带访问令牌的本机请求。"
        case .error(let message):
            return message
        }
    }

    func attach(app: AppModel) {
        self.app = app

        if notificationObserver == nil {
            notificationObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(Self.startNotification),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.requestExternalStart() }
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--agent-start") {
            requestExternalStart()
        } else if enabled {
            // 按需启动：App 常驻时不主动开端口，等 Agent 发通知或用户点“测试连接”。
            state = .stopped
            removeGatewayFile()
        } else {
            state = .disabled
            removeGatewayFile()
        }
    }

    func requestExternalStart() {
        guard enabled else {
            lastError = "需要先在 Mindscape 中允许 AI Agent 操作。"
            SettingsRouter.shared.requestAgentTab()
            return
        }
        start()
    }

    // MARK: - Lifecycle

    func start() {
        guard enabled, let app else { return }
        if case .running = state { return }

        do {
            let service = AgentService(store: app.store) { [weak app] documentID in
                app?.reloadAfterExternalChange(documentID: documentID)
            }
            let server = AgentHTTPServer()
            server.handler = { [weak self] request in
                guard let self else {
                    return .json(AgentErrorEnvelope(error: AgentErrorInfo(code: "unavailable", message: "服务已关闭")), status: 503)
                }
                return self.respond(to: request)
            }

            let port = try server.start(preferredPort: 47821)
            self.server = server
            self.service = service
            self.runningSince = Date()
            writeGateway(token: server.token, port: port)
            state = .running(port: port)
            lastError = nil
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Mindscape local AI Agent gateway"
            )
            startIdleMonitor()
        } catch {
            self.server = nil
            self.service = nil
            state = .error(error.localizedDescription)
            lastError = error.localizedDescription
            removeGatewayFile()
        }
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        server?.stop()
        server = nil
        service = nil
        runningSince = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        removeGatewayFile()
        if enabled {
            state = .stopped
        } else {
            state = .disabled
        }
    }

    func restart() {
        stop()
        if enabled { start() }
    }

    func testConnection() async -> String {
        if case .running = state {} else if enabled { start() }
        guard case .running(let port) = state, let server else {
            return lastError ?? "服务未启动"
        }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/health")!)
        request.timeoutInterval = 3
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "连接失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)）"
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let dataObject = object?["data"] as? [String: Any]
            let version = dataObject?["version"] as? String ?? "?"
            return "连接正常 · Mindscape \(version)"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }

    // MARK: - HTTP bridge

    private nonisolated func respond(to request: AgentHTTPRequest) -> AgentHTTPResponse {
        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor [weak self] in
            box.response = self?.service?.handle(request)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            return .json(
                AgentErrorEnvelope(error: AgentErrorInfo(code: "timeout", message: "操作超时")),
                status: 504
            )
        }
        return box.response ?? .json(
            AgentErrorEnvelope(error: AgentErrorInfo(code: "unavailable", message: "服务未就绪")),
            status: 503
        )
    }

    // MARK: - Idle

    private func startIdleMonitor() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.stopIfIdle()
            }
        }
    }

    private func stopIfIdle() {
        guard case .running = state, idleMinutes > 0, let server else { return }
        let idle = Date().timeIntervalSince(server.lastActivity)
        if idle >= Double(idleMinutes * 60) {
            stop()
        }
    }

    // MARK: - Gateway file

    private struct GatewayDescriptor: Codable {
        let version: Int
        let url: String
        let token: String
        let pid: Int
        let startedAt: String
    }

    private func writeGateway(token: String, port: UInt16) {
        let descriptor = GatewayDescriptor(
            version: 1,
            url: "http://127.0.0.1:\(port)",
            token: token,
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            startedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try FileManager.default.createDirectory(
                at: gatewayURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(descriptor)
            try data.write(to: gatewayURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: gatewayURL.path
            )
        } catch {
            lastError = "无法写入 Agent 配置文件：\(error.localizedDescription)"
        }
    }

    private func removeGatewayFile() {
        try? FileManager.default.removeItem(at: gatewayURL)
    }

    // MARK: - Skills

    func installSkill(target: AgentSkillInstaller.Target) throws -> AgentSkillInstaller.InstallResult {
        try AgentSkillInstaller().install(target: target)
    }

    var skillPrompt: String {
        AgentSkillInstaller().prompt
    }
}

private final class ResponseBox: @unchecked Sendable {
    var response: AgentHTTPResponse?
}
