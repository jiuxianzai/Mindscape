import Foundation

struct MindMap: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = String(localized: "未命名导图")
    var nodes: [MindNode] = []
    var layout: MapLayout = .mindMap
    var themeID: String = MapTheme.defaultThemeID
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Lookup

    var rootID: UUID {
        nodes.first(where: { $0.parentID == nil })?.id ?? nodes.first?.id ?? UUID()
    }

    var root: MindNode? { node(rootID) }

    func node(_ id: UUID) -> MindNode? {
        nodes.first(where: { $0.id == id })
    }

    func children(of id: UUID) -> [MindNode] {
        nodes.filter { $0.parentID == id }.sorted { $0.order < $1.order }
    }

    func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        var current = node(candidate)
        var guardCount = 0
        while let parentID = current?.parentID, guardCount < nodes.count + 4 {
            if parentID == ancestor { return true }
            current = node(parentID)
            guardCount += 1
        }
        return false
    }

    var nodeCount: Int { nodes.count }

    /// 从根节点开始的广度优先遍历顺序；用于搜索、演示和大纲
    var breadthFirstIDs: [UUID] {
        guard nodes.contains(where: { $0.id == rootID }) else { return [] }
        var result: [UUID] = []
        var queue: [UUID] = [rootID]
        var visited: Set<UUID> = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            result.append(current)
            queue.append(contentsOf: children(of: current).map(\.id))
        }
        // 兜底：把因为数据损坏而脱离根节点的节点也放进来
        for node in nodes where !visited.contains(node.id) {
            result.append(node.id)
        }
        return result
    }

    func subtreeIDs(of id: UUID) -> Set<UUID> {
        guard node(id) != nil else { return [] }
        var result: Set<UUID> = []
        var stack: [UUID] = [id]
        while let current = stack.popLast() {
            guard result.insert(current).inserted else { continue }
            stack.append(contentsOf: children(of: current).map(\.id))
        }
        return result
    }

    var previewText: String {
        nodes.prefix(40).map(\.text).joined(separator: " ")
    }

    // MARK: - Factories

    static func blank(title: String = String(localized: "未命名导图"), themeID: String = MapTheme.defaultThemeID, layout: MapLayout = .mindMap) -> MindMap {
        let root = MindNode(parentID: nil, text: String(localized: "中心主题"), order: 0)
        return MindMap(title: title, nodes: [root], layout: layout, themeID: themeID)
    }
}
