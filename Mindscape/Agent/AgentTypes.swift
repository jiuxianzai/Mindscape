import Foundation

// MARK: - HTTP transport

struct AgentHTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct AgentHTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> AgentHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(value)) ?? Data(#"{"ok":false}"#.utf8)
        return AgentHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }
}

// MARK: - Errors

struct AgentAPIError: Error {
    let status: Int
    let code: String
    let message: String

    static func badRequest(_ message: String, code: String = "bad_request") -> AgentAPIError {
        AgentAPIError(status: 400, code: code, message: message)
    }

    static func notFound(_ message: String = "资源不存在") -> AgentAPIError {
        AgentAPIError(status: 404, code: "not_found", message: message)
    }

    static func conflict(_ message: String) -> AgentAPIError {
        AgentAPIError(status: 409, code: "conflict", message: message)
    }

    static func unauthorized(_ message: String = "缺少或无效的访问令牌") -> AgentAPIError {
        AgentAPIError(status: 401, code: "unauthorized", message: message)
    }

    static func forbidden(_ message: String) -> AgentAPIError {
        AgentAPIError(status: 403, code: "forbidden", message: message)
    }
}

// MARK: - JSON envelopes

struct AgentSuccessEnvelope<Value: Encodable>: Encodable {
    let ok = true
    let data: Value
}

struct AgentErrorInfo: Encodable {
    let code: String
    let message: String
}

struct AgentErrorEnvelope: Encodable {
    let ok = false
    let error: AgentErrorInfo
}

// MARK: - DTOs

struct AgentNodeDTO: Encodable {
    let id: String
    let parentId: String?
    let text: String
    let note: String
    let icon: String?
    let collapsed: Bool
    let order: Int
    let colorHex: String?

    init(_ node: MindNode) {
        id = node.id.uuidString
        parentId = node.parentID?.uuidString
        text = node.text
        note = node.note
        icon = node.icon
        collapsed = node.collapsed
        order = node.order
        colorHex = node.colorHex
    }
}

struct AgentMapDTO: Encodable {
    let id: String
    let title: String
    let layout: String
    let theme: String
    let folderId: String?
    let createdAt: Date
    let updatedAt: Date
    let rootIds: [String]
    let nodes: [AgentNodeDTO]

    init(map: MindMap, folderID: UUID?) {
        id = map.id.uuidString
        title = map.title
        layout = map.layout.rawValue
        theme = map.themeID
        folderId = folderID?.uuidString
        createdAt = map.createdAt
        updatedAt = map.updatedAt
        rootIds = map.rootIDs.map(\.uuidString)
        nodes = map.nodes.map(AgentNodeDTO.init)
    }
}

struct AgentMapSummary: Encodable {
    let id: String
    let title: String
    let layout: String
    let theme: String
    let folderId: String?
    let updatedAt: Date
    let nodeCount: Int

    init(_ record: DocumentRecord) {
        id = record.id.uuidString
        title = record.title
        layout = record.layout.rawValue
        theme = record.themeID
        folderId = record.folderID?.uuidString
        updatedAt = record.updatedAt
        nodeCount = record.nodeCount
    }
}

struct AgentFolderDTO: Encodable {
    let id: String
    let name: String
    let parentId: String?
    let sortOrder: Int

    init(_ record: FolderRecord) {
        id = record.id.uuidString
        name = record.name
        parentId = record.parentID?.uuidString
        sortOrder = record.sortOrder
    }
}

struct AgentHealth: Encodable {
    let status: String
    let version: String
    let apiVersion: Int
}

// MARK: - Request bodies

struct AgentCreateFolderBody: Decodable {
    let name: String
    let parentId: String?
}

struct AgentRenameFolderBody: Decodable {
    let name: String
}

struct AgentCreateMapBody: Decodable {
    let title: String?
    let rootText: String?
    let folderId: String?
    let layout: String?
    let theme: String?
    let template: String?
}

struct AgentUpdateMapBody: Decodable {
    let title: String?
    let folderId: String?
    let layout: String?
    let theme: String?
}

struct AgentAddNodeBody: Decodable {
    let parentId: String?
    let text: String?
    let note: String?
    let icon: String?
    let color: String?
    let collapsed: Bool?
    let index: Int?
}

struct AgentUpdateNodeBody: Decodable {
    let text: String?
    let note: String?
    let icon: String?
    let color: String?
    let collapsed: Bool?
}

struct AgentMoveNodeBody: Decodable {
    let parentId: String?
    let index: Int?
}

struct AgentExportBody: Decodable {
    let format: String
    let path: String
    let scale: Int?
}

struct AgentImportBody: Decodable {
    let path: String
    let folderId: String?
    let layout: String?
    let theme: String?
}

struct AgentSkillInstallBody: Decodable {
    let target: String
}

struct AgentExportResult: Encodable {
    let path: String
    let format: String
    let bytes: Int
}

struct AgentImportResult: Encodable {
    let map: AgentMapSummary
}

struct AgentSkillInstallResult: Encodable {
    let target: String
    let path: String
    let version: String
}

// MARK: - Path helpers

enum AgentPath {
    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func uuid(_ raw: String, name: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else {
            throw AgentAPIError.badRequest("\(name) 不是有效 UUID", code: "invalid_uuid")
        }
        return id
    }
}
