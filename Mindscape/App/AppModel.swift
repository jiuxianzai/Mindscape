import AppKit
import Observation

enum LibraryScope: String, CaseIterable, Identifiable {
    case all
    case starred

    var id: String { rawValue }
    var title: String { self == .all ? "全部" : "收藏" }
}

@MainActor
@Observable
final class AppModel {
    let store: DocumentStore
    var documents: [DocumentRecord] = []
    var selectedDocumentID: UUID?
    var editor: MapEditor?
    var searchText: String = ""
    var scope: LibraryScope = .all
    var showInspector: Bool = true
    var startupError: String?

    private var observers: [NSObjectProtocol] = []

    init() {
        let resolved: DocumentStore
        var errorMessage: String?
        do {
            resolved = try DocumentStore()
        } catch {
            resolved = try! DocumentStore(inMemory: true)
            errorMessage = "本地数据库打开失败，本次修改不会保存：\(error.localizedDescription)"
        }
        store = resolved
        startupError = errorMessage

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

    var selectedRecord: DocumentRecord? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    func reload() {
        documents = (try? store.list(includeDeleted: true)) ?? []
    }

    private func refreshQuietly() {
        let previousSelection = selectedDocumentID
        documents = (try? store.list(includeDeleted: true)) ?? []
        selectedDocumentID = previousSelection
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
        map.title = uniqueTitle(for: template.title)
        map.createdAt = Date()
        map.updatedAt = Date()
        do {
            try store.save(map)
        } catch {
            startupError = error.localizedDescription
            return
        }
        reload()
        selectDocument(map.id)
    }

    func createBlank() {
        createDocument(template: .blank)
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
        selectedDocumentID = id
    }

    func trashDocument(_ id: UUID) {
        if selectedDocumentID == id {
            editor?.saveNow()
            editor = nil
            selectedDocumentID = nil
        }
        try? store.trash(id)
        reload()
    }

    func restoreDocument(_ id: UUID) {
        try? store.restore(id)
        reload()
    }

    func deletePermanently(_ id: UUID) {
        try? store.deletePermanently(id)
        reload()
        if selectedDocumentID == id {
            selectedDocumentID = nil
            editor = nil
        }
    }

    // MARK: - Export

    func export(_ format: ExportFormat) {
        guard let editor else { return }
        ExportService.export(map: editor.map, layout: LayoutEngine.layout(editor.map), format: format)
    }
}
