import Foundation
import XCTest
@testable import Mindscape

@MainActor
final class AgentServiceTests: XCTestCase {
    private var directory: URL!
    private var store: DocumentStore!
    private var service: AgentService!
    private var changes: [UUID?] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeAgentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try DocumentStore(directory: directory)
        changes = []
        service = AgentService(
            store: store,
            appVersion: "test",
            skillInstaller: nil,
            openAPIData: Data("{}".utf8),
            skillData: Data("# skill".utf8)
        ) { [weak self] id in
            self?.changes.append(id)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testHealth() throws {
        let response = service.handle(request("GET", "/v1/health"))
        XCTAssertEqual(response.status, 200)
        let body = try object(response)
        XCTAssertEqual((body["data"] as? [String: Any])?["status"] as? String, "ok")
    }

    func testOpenAPIIsServed() throws {
        let response = service.handle(request("GET", "/v1/openapi.json"))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "{}")
    }

    func testFolderLifecycle() throws {
        let created = try object(service.handle(request("POST", "/v1/folders", ["name": "项目"])))
        let folder = created["data"] as? [String: Any]
        let id = try XCTUnwrap(folder?["id"] as? String)

        let list = try object(service.handle(request("GET", "/v1/folders")))
        XCTAssertEqual((list["data"] as? [[String: Any]])?.count, 1)

        let renamed = service.handle(request("PATCH", "/v1/folders/\(id)", ["name": "改名"]))
        XCTAssertEqual(renamed.status, 200)

        let deleted = service.handle(request("DELETE", "/v1/folders/\(id)"))
        XCTAssertEqual(deleted.status, 200)
        let after = try object(service.handle(request("GET", "/v1/folders")))
        XCTAssertEqual((after["data"] as? [[String: Any]])?.count, 0)
    }

    func testMapAndNodeLifecycle() throws {
        let created = try object(service.handle(request("POST", "/v1/maps", ["title": "测试导图"])))
        let map = try XCTUnwrap(created["data"] as? [String: Any])
        let mapID = try XCTUnwrap(map["id"] as? String)
        let rootID = try XCTUnwrap((map["rootIds"] as? [String])?.first)

        let added = try object(service.handle(request(
            "POST", "/v1/maps/\(mapID)/nodes",
            ["parentId": rootID, "text": "子节点", "note": "备注"]
        )))
        let node = try XCTUnwrap(added["data"] as? [String: Any])
        let nodeID = try XCTUnwrap(node["id"] as? String)

        let updated = try object(service.handle(request(
            "PATCH", "/v1/maps/\(mapID)/nodes/\(nodeID)",
            ["text": "改名节点", "color": "#C26A4A"]
        )))
        let updatedNode = try XCTUnwrap(updated["data"] as? [String: Any])
        XCTAssertEqual(updatedNode["text"] as? String, "改名节点")
        XCTAssertEqual(updatedNode["colorHex"] as? String, "#C26A4A")

        let full = try object(service.handle(request("GET", "/v1/maps/\(mapID)")))
        let fullMap = try XCTUnwrap(full["data"] as? [String: Any])
        XCTAssertEqual((fullMap["nodes"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(changes.count, 3, "创建、加节点、改节点各触发一次界面刷新")

        let deleted = service.handle(request("DELETE", "/v1/maps/\(mapID)/nodes/\(nodeID)"))
        XCTAssertEqual(deleted.status, 200)
    }

    func testDeleteLastNodeIsRejected() throws {
        let created = try object(service.handle(request("POST", "/v1/maps", ["title": "只有一个节点"])))
        let map = try XCTUnwrap(created["data"] as? [String: Any])
        let mapID = try XCTUnwrap(map["id"] as? String)
        let rootID = try XCTUnwrap((map["rootIds"] as? [String])?.first)

        let response = service.handle(request("DELETE", "/v1/maps/\(mapID)/nodes/\(rootID)"))
        XCTAssertEqual(response.status, 409)
    }

    func testMoveRejectsCycle() throws {
        let created = try object(service.handle(request("POST", "/v1/maps", ["title": "循环测试"])))
        let map = try XCTUnwrap(created["data"] as? [String: Any])
        let mapID = try XCTUnwrap(map["id"] as? String)
        let rootID = try XCTUnwrap((map["rootIds"] as? [String])?.first)

        let child = try object(service.handle(request(
            "POST", "/v1/maps/\(mapID)/nodes", ["parentId": rootID, "text": "子节点"]
        )))
        let childID = try XCTUnwrap((child["data"] as? [String: Any])?["id"] as? String)

        let response = service.handle(request(
            "POST", "/v1/maps/\(mapID)/nodes/\(rootID)/move", ["parentId": childID]
        ))
        XCTAssertEqual(response.status, 409)
    }

    func testBatchAndExport() throws {
        let created = try object(service.handle(request("POST", "/v1/maps", ["title": "批量"])))
        let map = try XCTUnwrap(created["data"] as? [String: Any])
        let mapID = try XCTUnwrap(map["id"] as? String)
        let rootID = try XCTUnwrap((map["rootIds"] as? [String])?.first)

        let start = Date()
        for offset in stride(from: 0, to: 1000, by: 500) {
            let operations = (offset..<(offset + 500)).map { index -> [String: Any] in
                ["op": "addNode", "parentId": rootID, "text": "节点 \(index)"]
            }
            let batched = service.handle(request("POST", "/v1/maps/\(mapID)/batch", ["operations": operations]))
            XCTAssertEqual(batched.status, 200)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "1000 个节点应在 2 秒内完成")

        let body = try object(service.handle(request("GET", "/v1/maps/\(mapID)")))
        let batchData = body["data"] as? [String: Any]
        XCTAssertEqual((batchData?["nodes"] as? [[String: Any]])?.count, 1001)

        let path = "/tmp/mindscape-agent-\(UUID().uuidString).md"
        let exported = service.handle(request(
            "POST", "/v1/maps/\(mapID)/export", ["format": "markdown", "path": path]
        ))
        XCTAssertEqual(exported.status, 200)
        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# 批量"))
        XCTAssertTrue(markdown.contains("节点 999"))
        try? FileManager.default.removeItem(atPath: path)
    }

    func testExportOutsideAllowedRootsIsForbidden() throws {
        let created = try object(service.handle(request("POST", "/v1/maps", ["title": "越界"])))
        let mapID = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        let response = service.handle(request(
            "POST", "/v1/maps/\(mapID)/export", ["format": "markdown", "path": "/etc/evil.md"]
        ))
        XCTAssertEqual(response.status, 403)
    }

    func testInvalidUUIDReturnsBadRequest() throws {
        let response = service.handle(request("GET", "/v1/maps/nope"))
        XCTAssertEqual(response.status, 400)
    }

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil) -> AgentHTTPRequest {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return AgentHTTPRequest(
            method: method,
            path: path,
            query: [:],
            headers: [:],
            body: data
        )
    }

    private func object(_ response: AgentHTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }
}
