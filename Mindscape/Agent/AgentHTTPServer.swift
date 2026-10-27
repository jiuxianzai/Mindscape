import Darwin
import Foundation
import Security

/// 只绑定 127.0.0.1 的极简 HTTP/1.1 服务。
/// 只支持 Content-Length、每条连接一个请求、响应后关闭，避免 chunked / keep-alive 带来的解析面。
final class AgentHTTPServer {
    enum ServerError: LocalizedError {
        case socket(String)
        case bind(String)

        var errorDescription: String? {
            switch self {
            case .socket(let message): return "无法创建本地服务：\(message)"
            case .bind(let message): return "无法绑定本地端口：\(message)"
            }
        }
    }

    let token: String
    var handler: ((AgentHTTPRequest) -> AgentHTTPResponse)?

    private let acceptQueue = DispatchQueue(label: "com.youyanping.mindscape.agent.accept")
    private let workerQueue = DispatchQueue(
        label: "com.youyanping.mindscape.agent.workers",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let connectionLimit = DispatchSemaphore(value: 8)
    private let activityLock = NSLock()
    private var _lastActivity = Date()
    private let rateLock = NSLock()
    private var requestTimes: [Date] = []
    private let stateLock = NSLock()

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var _port: UInt16 = 0

    var port: UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _port
    }

    private static let maxHeaderBytes = 32 * 1024
    private static let maxBodyBytes = 1024 * 1024
    private static let connectionTimeout: Int = 10

    init(token: String = AgentHTTPServer.makeToken()) {
        self.token = token
    }

    var lastActivity: Date {
        activityLock.lock()
        defer { activityLock.unlock() }
        return _lastActivity
    }

    // MARK: - Lifecycle

    @discardableResult
    func start(preferredPort: UInt16 = 47821) throws -> UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        if listenFD >= 0 { return _port }
        do {
            try bind(preferredPort: preferredPort)
        } catch {
            if preferredPort != 0 {
                try bind(preferredPort: 0)
            } else {
                throw error
            }
        }
        source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: acceptQueue)
        source?.setEventHandler { [weak self] in self?.acceptPending() }
        source?.resume()
        return _port
    }

    func stop() {
        stateLock.lock()
        let source = self.source
        self.source = nil
        let fd = listenFD
        listenFD = -1
        _port = 0
        stateLock.unlock()

        source?.cancel()
        if fd >= 0 {
            close(fd)
        }
    }

    private func bind(preferredPort: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket(String(cString: strerror(errno))) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = preferredPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.bind(message)
        }
        guard listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.bind(message)
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        listenFD = fd
        _port = UInt16(bigEndian: bound.sin_port)
    }

    // MARK: - Accept / serve

    private func acceptPending() {
        while true {
            stateLock.lock()
            let fd = listenFD
            let localPort = _port
            stateLock.unlock()
            guard fd >= 0 else { return }

            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(fd, &address, &length)
            guard client >= 0 else { return }

            guard connectionLimit.wait(timeout: .now()) == .success else {
                close(client)
                continue
            }
            workerQueue.async { [weak self] in
                defer { self?.connectionLimit.signal() }
                self?.serve(client, port: localPort)
            }
        }
    }

    private func serve(_ fd: Int32, port: UInt16) {
        defer { close(fd) }
        // accept 会继承监听 socket 的 O_NONBLOCK；必须恢复阻塞，否则客户端稍晚发包就被误判超时。
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: Self.connectionTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        do {
            let request = try readRequest(fd)
            try validate(request, port: port)
            guard allowRequest() else {
                try write(response: Self.failure(429, "rate_limited", "请求过于频繁"), to: fd)
                return
            }
            touch()
            guard let handler else {
                try write(response: .json(AgentErrorEnvelope(error: AgentErrorInfo(code: "unavailable", message: "服务未就绪")), status: 503), to: fd)
                return
            }
            try write(response: handler(request), to: fd)
        } catch let error as HTTPFailure {
            try? write(response: error.response, to: fd)
        } catch {
            try? write(response: .json(AgentErrorEnvelope(error: AgentErrorInfo(code: "bad_request", message: "请求无法解析")), status: 400), to: fd)
        }
    }

    private func allowRequest() -> Bool {
        rateLock.lock()
        defer { rateLock.unlock() }
        let cutoff = Date().addingTimeInterval(-10)
        requestTimes.removeAll { $0 < cutoff }
        guard requestTimes.count < 60 else { return false }
        requestTimes.append(Date())
        return true
    }

    private func touch() {
        activityLock.lock()
        _lastActivity = Date()
        activityLock.unlock()
    }

    struct HTTPFailure: Error {
        let response: AgentHTTPResponse
    }

    // MARK: - Request parsing

    private func readRequest(_ fd: Int32) throws -> AgentHTTPRequest {
        var buffer = Data()
        var headerRange: Range<Data.Index>?

        while headerRange == nil {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count == 0 {
                throw HTTPFailure(response: Self.failure(400, "empty_request", "请求为空"))
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw HTTPFailure(response: Self.failure(408, "timeout", "读取请求超时"))
                }
                throw HTTPFailure(response: Self.failure(400, "read_failed", "读取请求失败"))
            }
            buffer.append(chunk, count: count)
            if buffer.count > Self.maxHeaderBytes {
                throw HTTPFailure(response: Self.failure(431, "headers_too_large", "请求头过大"))
            }
            headerRange = buffer.range(of: Data("\r\n\r\n".utf8))
        }

        guard let headerRange else {
            throw HTTPFailure(response: Self.failure(400, "bad_request", "缺少请求头"))
        }
        let headerData = buffer[..<headerRange.lowerBound]
        let head = String(decoding: headerData, as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw HTTPFailure(response: Self.failure(400, "bad_request", "请求行缺失"))
        }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else {
            throw HTTPFailure(response: Self.failure(400, "bad_request", "请求行不完整"))
        }
        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])
        guard ["GET", "POST", "PATCH", "DELETE"].contains(method) else {
            throw HTTPFailure(response: Self.failure(405, "method_not_allowed", "不支持的方法"))
        }
        guard target.hasPrefix("/"), !target.contains(" ") else {
            throw HTTPFailure(response: Self.failure(400, "bad_request", "请求路径无效"))
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPFailure(response: Self.failure(400, "bad_request", "请求头格式错误"))
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if headers[key] != nil {
                throw HTTPFailure(response: Self.failure(400, "duplicate_header", "重复的请求头"))
            }
            headers[key] = value
        }

        if headers["transfer-encoding"] != nil {
            throw HTTPFailure(response: Self.failure(400, "unsupported_transfer_encoding", "不支持 chunked 请求"))
        }

        let contentLength: Int
        if let raw = headers["content-length"] {
            guard let value = Int(raw), value >= 0 else {
                throw HTTPFailure(response: Self.failure(400, "bad_content_length", "Content-Length 无效"))
            }
            contentLength = value
        } else {
            contentLength = 0
        }
        guard contentLength <= Self.maxBodyBytes else {
            throw HTTPFailure(response: Self.failure(413, "body_too_large", "请求体超过 1 MB"))
        }

        var body = Data(buffer[headerRange.upperBound...])
        while body.count < contentLength {
            var chunk = [UInt8](repeating: 0, count: min(4096, contentLength - body.count))
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else {
                throw HTTPFailure(response: Self.failure(400, "incomplete_body", "请求体不完整"))
            }
            body.append(chunk, count: count)
        }
        if body.count > contentLength {
            body = Data(body.prefix(contentLength))
        }

        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
            throw HTTPFailure(response: Self.failure(400, "bad_target", "请求路径无效"))
        }
        let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        return AgentHTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    // MARK: - Security

    private func validate(_ request: AgentHTTPRequest, port: UInt16) throws {
        guard let host = request.headers["host"]?.lowercased(),
              ["127.0.0.1:\(port)", "localhost:\(port)"].contains(host) else {
            throw HTTPFailure(response: Self.failure(403, "invalid_host", "Host 校验失败"))
        }
        guard request.headers["origin"] == nil else {
            throw HTTPFailure(response: Self.failure(403, "browser_origin", "不允许浏览器来源"))
        }
        let expected = "Bearer \(token)"
        guard let authorization = request.headers["authorization"],
              Self.secureCompare(authorization, expected) else {
            throw HTTPFailure(response: Self.failure(401, "unauthorized", "缺少或无效的访问令牌"))
        }
        if request.body.count > 0 {
            let contentType = request.headers["content-type"]?.lowercased() ?? ""
            guard contentType.hasPrefix("application/json") else {
                throw HTTPFailure(response: Self.failure(415, "unsupported_media_type", "请求体必须是 application/json"))
            }
        }
    }

    static func secureCompare(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<left.count {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    // MARK: - Response

    private func write(response: AgentHTTPResponse, to fd: Int32) throws {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        headers["Cache-Control"] = "no-store"
        headers["X-Content-Type-Options"] = "nosniff"
        headers["Referrer-Policy"] = "no-referrer"
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }

        let reason = Self.reason(response.status)
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(response.body)
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = send(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                if count <= 0 {
                    throw HTTPFailure(response: Self.failure(500, "send_failed", "响应写入失败"))
                }
                sent += count
            }
        }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    private static func failure(_ status: Int, _ code: String, _ message: String) -> AgentHTTPResponse {
        .json(AgentErrorEnvelope(error: AgentErrorInfo(code: code, message: message)), status: status)
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
