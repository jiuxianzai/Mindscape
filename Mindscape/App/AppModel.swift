import AppKit
import Observation
import UniformTypeIdentifiers

enum LibraryScope: String, CaseIterable, Identifiable {
    case all
    case starred

    var id: String { rawValue }
    var title: String { self == .all ? String(localized: "全部") : String(localized: "收藏") }
}

@MainActor
@Observable
final class AppModel {
    private(set) var store: DocumentStore
    var documents: [DocumentRecord] = []
    var folders: [FolderRecord] = []
    var selectedDocumentID: UUID?
    var selectedFolderID: UUID?
    var expandedFolders: Set<UUID> = []
    var editor: MapEditor?
    var searchText: String = ""
    var scope: LibraryScope = .all
    var startupError: String?

    let shortcuts = ShortcutStore.shared

    private var didExpandInitialFolders = false
    private var observers: [NSObjectProtocol] = []
    private static let recentDirectoriesKey = "recentDataDirectories"

    init() {
        let resolved: DocumentStore
        var errorMessage: String?

        do {
            resolved = try DocumentStore()
        } catch {
            let configured = DocumentStore.configuredDirectory
            if configured != DocumentStore.defaultDirectory,
               let fallback = try? DocumentStore(directory: DocumentStore.defaultDirectory) {
                resolved = fallback
                UserDefaults.standard.removeObject(forKey: "dataDirectory")
                errorMessage = "自定义数据目录无法打开，已切换到默认目录。\n\(error.localizedDescription)"
            } else {
                resolved = try! DocumentStore(inMemory: true)
                errorMessage = "本地数据库打开失败，本次修改不会保存：\(error.localizedDescription)"
            }
        }

        store = resolved
        startupError = errorMessage
        rememberDirectory(resolved.directoryURL)

        reload()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.editor?.saveNow()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.editor?.saveNow()
            }
        })

        if let first = documents.first {
            selectDocument(first.id)
        }
    }

    // MARK: - Lists

    var visibleDocuments: [DocumentRecord] {
        let base = documents.filter { $0.deletedAt == nil }
        let filtered: [DocumentRecord]
        switch scope {
        case .all:
            filtered = base
        case .starred:
            filtered = base.filter(\.starred)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filtered }
        return filtered.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    var trashDocuments: [DocumentRecord] {
        documents.filter { $0.deletedAt != nil }
    }

    var recentDocuments: [DocumentRecord] {
        documents
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedRecord: DocumentRecord? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Folder tree

    var rootFolders: [FolderRecord] {
        folders
            .filter { $0.parentID == nil }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func childFolders(of id: UUID) -> [FolderRecord] {
        folders
            .filter { $0.parentID == id }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func documents(in folderID: UUID?) -> [DocumentRecord] {
        documents
            .filter { $0.deletedAt == nil && $0.folderID == folderID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var rootDocuments: [DocumentRecord] {
        let known = Set(folders.map(\.id))
        return documents
            .filter { $0.deletedAt == nil && ($0.folderID == nil || !known.contains($0.folderID!)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func documentCount(in folderID: UUID) -> Int {
        var total = documents(in: folderID).count
        for child in childFolders(of: folderID) {
            total += documentCount(in: child.id)
        }
        return total
    }

    func folderPath(for id: UUID) -> String {
        var parts: [String] = []
        var current = folders.first(where: { $0.id == id })
        var guardCount = 0
        while let folder = current, guardCount < 64 {
            parts.insert(folder.name, at: 0)
            current = folder.parentID.flatMap { parentID in folders.first(where: { $0.id == parentID }) }
            guardCount += 1
        }
        return parts.joined(separator: " / ")
    }

    func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }
        selectedFolderID = id
    }

    func expandFolder(_ id: UUID) {
        expandedFolders.insert(id)
    }

    func expandAncestors(of id: UUID?) {
        guard let id else { return }
        expandedFolders.insert(id)
        var current = folders.first(where: { $0.id == id })
        var guardCount = 0
        while let parentID = current?.parentID, guardCount < 64 {
            expandedFolders.insert(parentID)
            current = folders.first(where: { $0.id == parentID })
            guardCount += 1
        }
    }

    // MARK: - Reload

    func reload() {
        folders = (try? store.folders()) ?? []
        documents = (try? store.list(includeDeleted: true)) ?? []

        if !didExpandInitialFolders {
            expandedFolders.formUnion(folders.map(\.id))
            didExpandInitialFolders = true
        }
        if let selectedFolderID, !folders.contains(where: { $0.id == selectedFolderID }) {
            self.selectedFolderID = nil
        }
    }

    private func refreshQuietly() {
        let document = selectedDocumentID
        let folder = selectedFolderID
        reload()
        selectedDocumentID = document
        selectedFolderID = folder
    }

    // MARK: - Opening

    func selectDocument(_ id: UUID?) {
        if id == selectedDocumentID, editor != nil { return }
        editor?.saveNow()
        selectedDocumentID = id

        guard let id, let map = try? store.load(id: id) else {
            editor = nil
            return
        }

        let record = documents.first(where: { $0.id == id })
        if let folderID = record?.folderID {
            selectedFolderID = folderID
            expandAncestors(of: folderID)
        }

        let newEditor = MapEditor(map: map, store: store)
        newEditor.onSaved = { [weak self] in
            self?.refreshQuietly()
        }
        editor = newEditor
    }

    // MARK: - Create

    func createDocument(template: MapTemplate) {
        let layout = defaultLayout
        let themeID = defaultThemeID
        var map = template.makeMap(themeID: themeID, layout: layout)
        // 标题默认跟随第一个头部节点；用户之后手动改名才会脱离跟随
        map.title = map.primaryHeadText
        map.createdAt = Date()
        map.updatedAt = Date()

        do {
            try store.save(map, folderID: selectedFolderID)
        } catch {
            startupError = error.localizedDescription
            return
        }

        reload()
        if let folderID = selectedFolderID {
            expandAncestors(of: folderID)
        }
        selectDocument(map.id)
    }

    func createBlank() {
        createDocument(template: .blank)
    }

    @discardableResult
    func createFolder(parentID: UUID?) -> UUID? {
        guard let folder = try? store.createFolder(name: String(localized: "新建目录"), parentID: parentID) else {
            return nil
        }
        if let parentID {
            expandedFolders.insert(parentID)
        }
        expandedFolders.insert(folder.id)
        selectedFolderID = folder.id
        reload()
        selectedFolderID = folder.id
        return folder.id
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.renameFolder(id, name: trimmed)
        reload()
    }

    func deleteFolder(_ id: UUID) {
        do {
            let parent = try store.deleteFolder(id)
            expandedFolders.remove(id)
            selectedFolderID = parent
            reload()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func moveDocument(_ id: UUID, to folderID: UUID?) {
        do {
            try store.setFolder(documentID: id, folderID: folderID)
            reload()
            if let folderID {
                expandAncestors(of: folderID)
            }
            if selectedDocumentID == id {
                selectedFolderID = folderID
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func uniqueTitle(for base: String) -> String {
        let existing = Set(documents.map(\.title))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private var defaultThemeID: String {
        UserDefaults.standard.string(forKey: "defaultThemeID") ?? MapTheme.defaultThemeID
    }

    private var defaultLayout: MapLayout {
        MapLayout(rawValue: UserDefaults.standard.string(forKey: "defaultLayout") ?? "") ?? .mindMap
    }

    // MARK: - Document actions

    func toggleStar(_ id: UUID) {
        guard let record = documents.first(where: { $0.id == id }) else { return }
        try? store.setStarred(id, starred: !record.starred)
        reload()
    }

    func trashDocument(_ id: UUID) {
        let wasSelected = selectedDocumentID == id
        if wasSelected {
            editor?.saveNow()
            editor = nil
            selectedDocumentID = nil
        }
        try? store.trash(id)
        reload()
        if wasSelected, let next = documents.first(where: { $0.deletedAt == nil }) {
            selectDocument(next.id)
        }
    }

    func restoreDocument(_ id: UUID) {
        try? store.restore(id)
        reload()
    }

    func deletePermanently(_ id: UUID) {
        let wasSelected = selectedDocumentID == id
        if wasSelected {
            editor?.saveNow()
            editor = nil
            selectedDocumentID = nil
        }
        try? store.deletePermanently(id)
        reload()
        if wasSelected, let next = documents.first(where: { $0.deletedAt == nil }) {
            selectDocument(next.id)
        }
    }

    func emptyTrash() {
        for record in trashDocuments {
            try? store.deletePermanently(record.id)
        }
        reload()
    }

    // MARK: - Data directory

    func switchDataDirectory(to directory: URL, useExisting: Bool) -> String? {
        let oldStore = store
        editor?.saveNow()
        editor = nil

        do {
            if !useExisting {
                try oldStore.exportDatabase(to: directory)
            }
            let newStore = try DocumentStore(directory: directory)
            rememberDirectory(oldStore.directoryURL)
            UserDefaults.standard.set(directory.path, forKey: "dataDirectory")
            rememberDirectory(directory)
            store = newStore
            selectedDocumentID = nil
            selectedFolderID = nil
            expandedFolders = []
            didExpandInitialFolders = false
            reload()
            if let first = documents.first {
                selectDocument(first.id)
            }
            return nil
        } catch {
            if let first = documents.first {
                selectDocument(first.id)
            }
            return error.localizedDescription
        }
    }

    func resetDataDirectory() -> String? {
        let defaultDirectory = DocumentStore.defaultDirectory
        let hasExisting = FileManager.default.fileExists(
            atPath: defaultDirectory.appendingPathComponent("mindscape.sqlite").path
        )
        return switchDataDirectory(to: defaultDirectory, useExisting: hasExisting)
    }

    // MARK: - Recent data directories

    var recentDataDirectories: [URL] {
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentDirectoriesKey) ?? []
        if let current = store.directoryURL?.path {
            paths.insert(current, at: 0)
        }
        paths.append(DocumentStore.defaultDirectory.path)

        var seen = Set<String>()
        return paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            let database = url.appendingPathComponent("mindscape.sqlite")
            guard FileManager.default.fileExists(atPath: database.path) else { return nil }
            return url
        }
    }

    private func rememberDirectory(_ url: URL?) {
        guard let url else { return }
        let normalized = url.standardizedFileURL
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentDirectoriesKey) ?? []
        paths.removeAll { URL(fileURLWithPath: $0).standardizedFileURL.path == normalized.path }
        paths.insert(normalized.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(6)), forKey: Self.recentDirectoriesKey)
    }

    // MARK: - Import

    func importDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "导入")
        panel.message = String(localized: "选择 Markdown、OPML 或 JSON 文件")
        var types: [UTType] = [.plainText, .json, .xml]
        for ext in ["md", "markdown", "opml"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var map = try MapImporter.load(
                url: url,
                themeID: defaultThemeID,
                layout: defaultLayout
            )
            map.title = uniqueTitle(for: map.title)
            try store.save(map, folderID: selectedFolderID)
            reload()
            if let folderID = selectedFolderID {
                expandAncestors(of: folderID)
            }
            selectDocument(map.id)
        } catch {
            startupError = error.localizedDescription
        }
    }

    // MARK: - Export

    func export(document id: UUID, format: ExportFormat) {
        guard let map = try? store.load(id: id) else { return }
        let layout = LayoutEngine.layout(map)
        _ = ExportService.save(map: map, layout: layout, format: format)
    }
}
