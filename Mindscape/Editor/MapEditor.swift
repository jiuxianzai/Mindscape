import Foundation
import Observation

@MainActor
@Observable
final class MapEditor {
    private(set) var map: MindMap
    var selection: Set<UUID> = []
    private(set) var revision: Int = 0
    private(set) var fitToken: Int = 0
    private(set) var lastSavedAt: Date?
    private(set) var saveError: String?

    var onSaved: (() -> Void)?

    private let store: DocumentStore
    private var undoStack: [MindMap] = []
    private var redoStack: [MindMap] = []
    private var saveTask: Task<Void, Never>?
    private var lastAutoSnapshot = Date.distantPast
    private var lastTextEditID: UUID?
    private var lastTextEditAt = Date.distantPast

    var theme: MapTheme { MapTheme.byID(map.themeID) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    var redoCount: Int { redoStack.count }

    init(map: MindMap, store: DocumentStore) {
        self.map = map
        self.store = store
        self.selection = [map.rootID]
        self.lastAutoSnapshot = Date()
    }

    // MARK: - Selection

    func node(_ id: UUID) -> MindNode? { map.node(id) }

    func select(_ id: UUID, additive: Bool = false) {
        if additive, selection.contains(id) {
            selection.remove(id)
        } else if additive {
            selection.insert(id)
        } else {
            selection = [id]
        }
        revision += 1
    }

    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
        revision += 1
    }

    // MARK: - Structure

    @discardableResult
    func addChild(to parentID: UUID) -> UUID? {
        guard map.node(parentID) != nil else { return nil }
        var node = MindNode(parentID: parentID, text: "新主题", order: nextOrder(parentID))
        node.emoji = nil
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == parentID }) {
                map.nodes[index].collapsed = false
            }
            map.nodes.append(node)
        }
        selection = [node.id]
        return node.id
    }

    @discardableResult
    func addSibling(after id: UUID) -> UUID? {
        guard let current = map.node(id) else { return nil }
        guard let parentID = current.parentID else {
            return addChild(to: current.id)
        }
        let node = MindNode(parentID: parentID, text: "新主题", order: nextOrder(parentID))
        mutate { map in
            map.nodes.append(node)
        }
        selection = [node.id]
        return node.id
    }

    func deleteSelection() {
        delete(ids: selection)
    }

    func delete(id: UUID) {
        delete(ids: [id])
    }

    private func delete(ids: Set<UUID>) {
        var toRemove: Set<UUID> = []
        for id in ids where id != map.rootID {
            collectSubtree(id, into: &toRemove)
        }
        guard !toRemove.isEmpty else { return }

        let fallback = ids.compactMap { map.node($0)?.parentID }.first ?? map.rootID
        mutate { map in
            map.nodes.removeAll { toRemove.contains($0.id) }
        }
        selection = [fallback]
    }

    private func collectSubtree(_ id: UUID, into set: inout Set<UUID>) {
        guard !set.contains(id) else { return }
        set.insert(id)
        for child in map.children(of: id) {
            collectSubtree(child.id, into: &set)
        }
    }

    func toggleCollapse(_ id: UUID) {
        guard map.node(id) != nil, !map.children(of: id).isEmpty else { return }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].collapsed.toggle()
            }
        }
    }

    func canMove(_ id: UUID, to newParent: UUID) -> Bool {
        guard id != map.rootID, id != newParent else { return false }
        guard map.node(newParent) != nil else { return false }
        guard !map.isDescendant(newParent, of: id) else { return false }
        return map.node(id)?.parentID != newParent
    }

    func move(id: UUID, to newParent: UUID) {
        guard canMove(id, to: newParent) else { return }
        mutate { map in
            let newOrder = map.children(of: newParent).count
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].parentID = newParent
                map.nodes[index].order = newOrder
            }
            if let parentIndex = map.nodes.firstIndex(where: { $0.id == newParent }) {
                map.nodes[parentIndex].collapsed = false
            }
        }
    }

    func moveFreeNode(id: UUID, to origin: CGPoint) {
        guard map.node(id) != nil else { return }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].position = origin
            }
        }
    }

    // MARK: - Node content

    func setText(_ text: String, for id: UUID) {
        guard let node = map.node(id), node.text != text else { return }
        let now = Date()
        let coalesce = lastTextEditID == id && now.timeIntervalSince(lastTextEditAt) < 1.0
        mutate(undoable: !coalesce) { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].text = text
            }
        }
        lastTextEditID = id
        lastTextEditAt = now
    }

    func setNote(_ note: String, for id: UUID) {
        guard let node = map.node(id), node.note != note else { return }
        let now = Date()
        let coalesce = lastTextEditID == id && now.timeIntervalSince(lastTextEditAt) < 1.0
        mutate(undoable: !coalesce) { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].note = note
            }
        }
        lastTextEditID = id
        lastTextEditAt = now
    }

    func setEmoji(_ emoji: String?, for id: UUID) {
        guard let node = map.node(id), node.emoji != emoji else { return }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].emoji = emoji
            }
        }
    }

    func setColor(_ hex: String?, for id: UUID) {
        guard let node = map.node(id), node.colorHex != hex else { return }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].colorHex = hex
            }
        }
    }

    // MARK: - Document settings

    func setTitle(_ title: String) {
        guard map.title != title else { return }
        map.title = title
        map.updatedAt = Date()
        revision += 1
        scheduleSave()
    }

    func setLayout(_ layout: MapLayout) {
        guard map.layout != layout else { return }
        mutate { map in
            map.layout = layout
        }
        fitToken += 1
    }

    func setTheme(_ themeID: String) {
        guard map.themeID != themeID else { return }
        mutate { map in
            map.themeID = themeID
        }
    }

    func requestFit() {
        fitToken += 1
        revision += 1
    }

    // MARK: - Undo / redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(map)
        map = previous
        selection = selection.filter { map.node($0) != nil }
        revision += 1
        scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(map)
        map = next
        selection = selection.filter { map.node($0) != nil }
        revision += 1
        scheduleSave()
    }

    private func mutate(undoable: Bool = true, _ body: (inout MindMap) -> Void) {
        if undoable {
            undoStack.append(map)
            if undoStack.count > 150 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        body(&map)
        map.updatedAt = Date()
        revision += 1
        scheduleSave()
    }

    private func nextOrder(_ parentID: UUID) -> Int {
        (map.children(of: parentID).map(\.order).max() ?? -1) + 1
    }

    // MARK: - Saving

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try store.save(map)
            lastSavedAt = Date()
            saveError = nil
            maybeAutoSnapshot()
            onSaved?()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func maybeAutoSnapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastAutoSnapshot) > 600 else { return }
        lastAutoSnapshot = now
        try? store.addSnapshot(map, name: "自动快照", kind: "auto")
    }

    // MARK: - History

    func snapshots() -> [SnapshotRecord] {
        (try? store.snapshots(for: map.id)) ?? []
    }

    func createSnapshot(name: String = "手动快照") {
        try? store.addSnapshot(map, name: name, kind: "manual")
    }

    func restore(snapshot: SnapshotRecord) {
        guard let restored = try? store.loadSnapshot(snapshot.id) else { return }
        try? store.addSnapshot(map, name: "恢复前", kind: "manual")
        undoStack.append(map)
        if undoStack.count > 150 { undoStack.removeFirst() }
        redoStack.removeAll()

        var next = restored
        next.id = map.id
        next.updatedAt = Date()
        map = next
        selection = [map.rootID]
        revision += 1
        fitToken += 1
        saveNow()
    }
}
