import Foundation

struct DocumentRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var layout: MapLayout
    var themeID: String
    var starred: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var nodeCount: Int
    var preview: String
}

struct SnapshotRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var documentID: UUID
    var name: String
    var kind: String
    var createdAt: Date
    var nodeCount: Int

    var isAuto: Bool { kind == "auto" }
}

@MainActor
final class DocumentStore {
    private let db: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    let databaseURL: URL?

    init(inMemory: Bool = false) throws {
        let path: String
        if inMemory {
            path = ":memory:"
            databaseURL = nil
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Mindscape", isDirectory: true)

            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let url = support.appendingPathComponent("mindscape.sqlite")
            path = url.path
            databaseURL = url
        }

        db = try SQLiteDatabase(path: path)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        try migrate()
    }

    private func migrate() throws {
        let version = try db.query("PRAGMA user_version;").first?.int("user_version") ?? 0
        if version < 1 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                layout TEXT NOT NULL,
                theme TEXT NOT NULL,
                starred INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                deleted_at REAL,
                node_count INTEGER NOT NULL DEFAULT 1,
                preview TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_documents_updated ON documents(updated_at DESC);
            CREATE TABLE IF NOT EXISTS snapshots (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                node_count INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_snapshots_document ON snapshots(document_id, created_at DESC);
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            PRAGMA user_version = 1;
            """)
        }
    }

    // MARK: - Documents

    func list(includeDeleted: Bool = false) throws -> [DocumentRecord] {
        let filter = includeDeleted ? "" : "WHERE deleted_at IS NULL"
        let rows = try db.query("""
        SELECT id, title, layout, theme, starred, created_at, updated_at, deleted_at, node_count, preview
        FROM documents
        \(filter)
        ORDER BY updated_at DESC
        """)
        return rows.compactMap(record(from:))
    }

    func load(id: UUID) throws -> MindMap? {
        guard let row = try db.query("SELECT content FROM documents WHERE id = ?", [.text(id.uuidString)]).first,
              let json = row.string("content"),
              let data = json.data(using: .utf8) else { return nil }
        return try decoder.decode(MindMap.self, from: data)
    }

    func save(_ map: MindMap) throws {
        let data = try encoder.encode(map)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let preview = map.nodes.prefix(24).map(\.text).joined(separator: " · ")

        try db.run("""
        INSERT INTO documents (id, title, content, layout, theme, starred, created_at, updated_at, deleted_at, node_count, preview)
        VALUES (?, ?, ?, ?, ?, 0, ?, ?, NULL, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            content = excluded.content,
            layout = excluded.layout,
            theme = excluded.theme,
            updated_at = excluded.updated_at,
            node_count = excluded.node_count,
            preview = excluded.preview
        """, [
            .text(map.id.uuidString),
            .text(map.title),
            .text(json),
            .text(map.layout.rawValue),
            .text(map.themeID),
            .double(map.createdAt.timeIntervalSince1970),
            .double(map.updatedAt.timeIntervalSince1970),
            .int(Int64(map.nodes.count)),
            .text(preview)
        ])
    }

    func setStarred(_ id: UUID, starred: Bool) throws {
        try db.run("UPDATE documents SET starred = ? WHERE id = ?", [.int(starred ? 1 : 0), .text(id.uuidString)])
    }

    func trash(_ id: UUID) throws {
        try db.run("UPDATE documents SET deleted_at = ? WHERE id = ?", [.double(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    func restore(_ id: UUID) throws {
        try db.run("UPDATE documents SET deleted_at = NULL WHERE id = ?", [.text(id.uuidString)])
    }

    func deletePermanently(_ id: UUID) throws {
        try db.run("DELETE FROM documents WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: - Snapshots

    func snapshots(for documentID: UUID) throws -> [SnapshotRecord] {
        let rows = try db.query("""
        SELECT id, document_id, name, kind, created_at, node_count
        FROM snapshots WHERE document_id = ?
        ORDER BY created_at DESC
        LIMIT 60
        """, [.text(documentID.uuidString)])
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let documentID = row.string("document_id").flatMap(UUID.init(uuidString:)) else { return nil }
            return SnapshotRecord(
                id: id,
                documentID: documentID,
                name: row.string("name") ?? "快照",
                kind: row.string("kind") ?? "manual",
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0),
                nodeCount: row.int("node_count") ?? 0
            )
        }
    }

    func addSnapshot(_ map: MindMap, name: String, kind: String) throws {
        let data = try encoder.encode(map)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try db.run("""
        INSERT INTO snapshots (id, document_id, name, kind, content, created_at, node_count)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(UUID().uuidString),
            .text(map.id.uuidString),
            .text(name),
            .text(kind),
            .text(json),
            .double(Date().timeIntervalSince1970),
            .int(Int64(map.nodes.count))
        ])

        if kind == "auto" {
            try db.run("""
            DELETE FROM snapshots
            WHERE document_id = ? AND kind = 'auto' AND id NOT IN (
                SELECT id FROM snapshots
                WHERE document_id = ? AND kind = 'auto'
                ORDER BY created_at DESC LIMIT 20
            )
            """, [.text(map.id.uuidString), .text(map.id.uuidString)])
        }
    }

    func loadSnapshot(_ id: UUID) throws -> MindMap? {
        guard let row = try db.query("SELECT content FROM snapshots WHERE id = ?", [.text(id.uuidString)]).first,
              let json = row.string("content"),
              let data = json.data(using: .utf8) else { return nil }
        return try decoder.decode(MindMap.self, from: data)
    }

    // MARK: - Helpers

    private func record(from row: SQLRow) -> DocumentRecord? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
        return DocumentRecord(
            id: id,
            title: row.string("title") ?? "未命名导图",
            layout: MapLayout(rawValue: row.string("layout") ?? "") ?? .mindMap,
            themeID: row.string("theme") ?? MapTheme.defaultThemeID,
            starred: row.bool("starred"),
            createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? 0),
            deletedAt: row.double("deleted_at").map(Date.init(timeIntervalSince1970:)),
            nodeCount: row.int("node_count") ?? 1,
            preview: row.string("preview") ?? ""
        )
    }
}
