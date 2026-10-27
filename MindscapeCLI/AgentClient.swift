import Foundation

struct AgentGatewayInfo: Decodable {
    let url: URL
    let token: String
    let pid: Int?
}

enum AgentClientError: LocalizedError {
    case gatewayUnavailable(String)
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .gatewayUnavailable(let message): return message
        case .http(let status, let body): return "HTTP \(status)：\(body)"
        case .invalidResponse: return "服务返回了无法解析的数据"
        }
    }
}

final class AgentClient {
    static let defaultGatewayURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Mindscape/agent-gateway.json")

    private let gatewayURL: URL
    private let launchApp: Bool
    private let session: URLSession

    init(gatewayURL: URL = AgentClient.defaultGatewayURL, launchApp: Bool = true) {
        self.gatewayURL = gatewayURL
        self.launchApp = launchApp
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func readGateway() -> AgentGatewayInfo? {
        guard let data = try? Data(contentsOf: gatewayURL) else { return nil }
        return try? JSONDecoder().decode(AgentGatewayInfo.self, from: data)
    }

    func ensureGateway() async throws -> AgentGatewayInfo {
        if let info = readGateway(), await healthy(info) {
            return info
        }
        guard launchApp else {
            throw AgentClientError.gatewayUnavailable("Mindscape 本地服务未启动")
        }

        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.youyanping.mindscape.agent.start"),
            object: nil
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", "com.youyanping.mindscape", "--args", "--agent-start"]
        try? process.run()

        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(200))
            if let info = readGateway(), await healthy(info) {
                return info
            }
        }
        throw AgentClientError.gatewayUnavailable(
            "无法连接 Mindscape。请打开 App，在 设置 → 通用 → AI Agent 中允许本地 Agent 操作。"
        )
    }

    func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> (Data, Int) {
        let gateway = try await ensureGateway()
        var components = URLComponents(url: gateway.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw AgentClientError.gatewayUnavailable("本地服务地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(gateway.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentClientError.invalidResponse
        }
        if http.statusCode >= 400 {
            throw AgentClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http.statusCode)
    }

    private func healthy(_ info: AgentGatewayInfo) async -> Bool {
        var request = URLRequest(url: info.url.appendingPathComponent("v1/health"))
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
