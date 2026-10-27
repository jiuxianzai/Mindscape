import Darwin
import Foundation
import XCTest
@testable import Mindscape

final class AgentHTTPServerTests: XCTestCase {
    private var server: AgentHTTPServer!
    private var port: UInt16 = 0

    override func setUpWithError() throws {
        server = AgentHTTPServer(token: "test-token")
        server.handler = { _ in
            .json(AgentSuccessEnvelope(data: AgentHealth(status: "ok", version: "test", apiVersion: 1)))
        }
        port = try server.start(preferredPort: 0)
    }

    override func tearDownWithError() throws {
        server.stop()
    }

    func testValidRequest() async throws {
        let (data, response) = try await request(path: "v1/health")
        XCTAssertEqual(response.statusCode, 200)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["data"] as? [String: Any])?["status"] as? String, "ok")
    }

    func testMissingTokenIsRejected() async throws {
        let (_, response) = try await request(path: "v1/health", token: nil)
        XCTAssertEqual(response.statusCode, 401)
    }

    func testWrongTokenIsRejected() async throws {
        let (_, response) = try await request(path: "v1/health", token: "wrong")
        XCTAssertEqual(response.statusCode, 401)
    }

    func testBrowserOriginIsRejected() async throws {
        let raw = rawRequest(
            "GET /v1/health HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nAuthorization: Bearer test-token\r\nOrigin: https://evil.example\r\n\r\n"
        )
        XCTAssertTrue(raw.contains(" 403 "), raw)
    }

    func testInvalidHostIsRejected() throws {
        let raw = rawRequest(
            "GET /v1/health HTTP/1.1\r\nHost: evil.example\r\nAuthorization: Bearer test-token\r\n\r\n"
        )
        XCTAssertTrue(raw.contains(" 403 "), raw)
    }

    func testOversizedBodyIsRejected() throws {
        let header = "POST /v1/health HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nAuthorization: Bearer test-token\r\nContent-Type: application/json\r\nContent-Length: \(1024 * 1024 + 1)\r\n\r\n"
        // 服务在读 body 之前就应按 Content-Length 拒绝，不需要真的传 1 MB。
        let raw = rawRequest(header)
        XCTAssertTrue(raw.contains(" 413 "), raw)
    }

    func testTransferEncodingIsRejected() throws {
        let raw = rawRequest(
            "POST /v1/health HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nAuthorization: Bearer test-token\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
        )
        XCTAssertTrue(raw.contains(" 400 "), raw)
    }

    func testUnsupportedMethodIsRejected() async throws {
        let (_, response) = try await request(path: "v1/health", method: "PUT")
        XCTAssertEqual(response.statusCode, 405)
    }

    func testMissingJSONContentTypeIsRejected() throws {
        let raw = rawRequest(
            "POST /v1/health HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nAuthorization: Bearer test-token\r\nContent-Length: 2\r\n\r\n{}"
        )
        XCTAssertTrue(raw.contains(" 415 "), raw)
    }

    func testStopAllowsRestart() throws {
        let previous = port
        server.stop()
        let next = try server.start(preferredPort: 0)
        XCTAssertGreaterThan(next, 0)
        XCTAssertNotEqual(previous, next, "停止后应能重新绑定端口")
    }

    func testRateLimitIsEnforced() async throws {
        for _ in 0..<60 {
            _ = try await request(path: "v1/health")
        }
        let (_, response) = try await request(path: "v1/health")
        XCTAssertEqual(response.statusCode, 429, "超过 10 秒 60 次应被限流")
    }

    func testSecureCompare() {
        XCTAssertTrue(AgentHTTPServer.secureCompare("abc", "abc"))
        XCTAssertFalse(AgentHTTPServer.secureCompare("abc", "abd"))
        XCTAssertFalse(AgentHTTPServer.secureCompare("abc", "abcd"))
    }

    // MARK: - Helpers

    private func request(
        path: String,
        token: String? = "test-token",
        method: String = "GET"
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = 5
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    private func rawRequest(_ text: String) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "" }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return "" }

        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, bytes.count, 0) }
        shutdown(fd, SHUT_WR)

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return String(data: result, encoding: .utf8) ?? ""
    }
}
