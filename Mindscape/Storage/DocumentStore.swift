import Foundation

struct FolderRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var createdAt: Date
}

struct DocumentRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var layout: MapLayout
    var themeID: String
    var starred: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var folderID: UUID?
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

enum DataDirectoryError: LocalizedError {
    case destinationExists
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .destinationExists: return "目标目录中已经存在 Mindscape 数据，请选择空目录，或切换为使用该目录。"
        case .copyFailed: return "复制数据库失败。"
        }
    }
}

@MainActor
final class DocumentStore {
    private let db: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    let directoryURL: URL?
    var databaseURL: URL? {
        directoryURL?.appendingPathComponent("mindscape.sqlite")
    }

    static var defaultDirectory: URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Mindscape", isDirectory: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mindscape", isDirectory: true)
    }

    static var configuredDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "dataDirectory"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultDirectory
    }

    init(directory: URL? = nil, inMemory: Bool = false) throws {
        let path: String
        if inMemory {
            path = ":memory:"
            directoryURL = nil
        } else {
            let dir = directory ?? Self.configuredDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("mindscape.sqlite").path
            directoryURL = dir
        }

        db = try SQLiteDatabase(path: path)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        try migrate()
    }

    // MARK: - Migration

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

        if version < 2 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS folders (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                parent_id TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id, sort_order);
            """)

            let columns = try db.query("PRAGMA table_info(documents);").compactMap { $0.string("name") }
            if !columns.contains("folder_id") {
                try db.execute("ALTER TABLE documents ADD COLUMN folder_id TEXT;")
            }
            try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_documents_folder ON documents(folder_id);
            PRAGMA user_version = 2;
            """)
        }
    }

    // MARK: - Documents

    func list(includeDeleted: Bool = false) throws -> [DocumentRecord] {
        let filter = includeDeleted ? "" : "WHERE deleted_at IS NULL"
        let rows = try db.query("""
        SELECT id, title, layout, theme, starred, created_at, updated_at, deleted_at, folder_id, node_count, preview
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

    func save(_ map: MindMap, folderID: UUID? = nil) throws {
        let data = try encoder.encode(map)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let preview = map.nodes.prefix(24).map(\.text).joined(separator: " · ")

        try db.run("""
        INSERT INTO documents
            (id, title, content, layout, theme, starred, created_at, updated_at, deleted_at, node_count, preview, folder_id)
        VALUES (?, ?, ?, ?, ?, 0, ?, ?, NULL, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            content = excluded.content,
            layout = excluded.layout,
            theme = excluded.theme,
            updated_at = excluded.updated_at,
            node_count = excluded.node_count,
            preview = excluded.preview,
            folder_id = COALESCE(documents.folder_id, excluded.folder_id)
        """, [
            .text(map.id.uuidString),
            .text(map.title),
            .text(json),
            .text(map.layout.rawValue),
            .text(map.themeID),
            .double(map.createdAt.timeIntervalSince1970),
            .double(map.updatedAt.timeIntervalSince1970),
            .int(Int64(map.nodes.count)),
            .text(preview),
            folderID.map { .text($0.uuidString) } ?? .null
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

    func setFolder(documentID: UUID, folderID: UUID?) throws {
        try db.run(
            "UPDATE documents SET folder_id = ?, updated_at = ? WHERE id = ?",
            [
                folderID.map { .text($0.uuidString) } ?? .null,
                .double(Date().timeIntervalSince1970),
                .text(documentID.uuidString)
            ]
        )
    }

    // MARK: - Folders

    func folders() throws -> [FolderRecord] {
        let rows = try db.query("""
        SELECT id, name, parent_id, sort_order, created_at
        FROM folders
        ORDER BY sort_order ASC, created_at ASC
        """)
        return rows.compactMap { row in
            guard let idString = row.string("id"), let id = UUID(uuidString: idString) else { return nil }
            return FolderRecord(
                id: id,
                name: row.string("name") ?? "新建目录",
                parentID: row.string("parent_id").flatMap(UUID.init(uuidString:)),
                sortOrder: row.int("sort_order") ?? 0,
                createdAt: Date(timeIntervalSince1970: row.double("created_at") ?? 0)
            )
        }
    }

    @discardableResult
    func createFolder(name: String, parentID: UUID?) throws -> FolderRecord {
        let siblings = try folders().filter { $0.parentID == parentID }
        let order = (siblings.map(\.sortOrder).max() ?? -1) + 1
        let folder = FolderRecord(id: UUID(), name: name, parentID: parentID, sortOrder: order, createdAt: Date())
        try db.run(
            "INSERT INTO folders (id, name, parent_id, sort_order, created_at) VALUES (?, ?, ?, ?, ?)",
            [
                .text(folder.id.uuidString),
                .text(folder.name),
                parentID.map { .text($0.uuidString) } ?? .null,
                .int(Int64(folder.sortOrder)),
                .double(folder.createdAt.timeIntervalSince1970)
            ]
        )
        return folder
    }

    func renameFolder(_ id: UUID, name: String) throws {
        try db.run("UPDATE folders SET name = ? WHERE id = ?", [.text(name), .text(id.uuidString)])
    }

    /// 删除目录：其中的导图和子目录会移动到上一级，不会丢数据。
    func deleteFolder(_ id: UUID) throws -> UUID? {
        guard let folder = try folders().first(where: { $0.id == id }) else { return nil }
        let parentValue: SQLValue = folder.parentID.map { .text($0.uuidString) } ?? .null

        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.run("UPDATE documents SET folder_id = ? WHERE folder_id = ?", [parentValue, .text(id.uuidString)])
            try db.run("UPDATE folders SET parent_id = ? WHERE parent_id = ?", [parentValue, .text(id.uuidString)])
            try db.run("DELETE FROM folders WHERE id = ?", [.text(id.uuidString)])
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
        return folder.parentID
    }

    // MARK: - Data directory

    /// 用 SQLite 的 VACUUM INTO 生成一份一致的数据库副本。
    func exportDatabase(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("mindscape.sqlite")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DataDirectoryError.destinationExists
        }
        let escaped = destination.path.replacingOccurrences(of: "'", with: "''")
        try db.execute("PRAGMA wal_checkpoint(FULL);")
        try db.execute("VACUUM INTO '\(escaped)';")
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

    func renameSnapshot(id: UUID, name: String) throws {
        try db.run("UPDATE snapshots SET name = ? WHERE id = ?", [.text(name), .text(id.uuidString)])
    }

    func deleteSnapshot(id: UUID) throws {
        try db.run("DELETE FROM snapshots WHERE id = ?", [.text(id.uuidString)])
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
            deletedAt: row.double("deleted_at").map { Date(timeIntervalSince1970: $0) },
            folderID: row.string("folder_id").flatMap(UUID.init(uuidString:)),
            nodeCount: row.int("node_count") ?? 1,
            preview: row.string("preview") ?? ""
        )
    }
}
