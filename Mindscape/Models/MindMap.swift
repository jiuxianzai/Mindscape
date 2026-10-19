import Foundation

struct MindMap: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = "未命名导图"
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

    var previewText: String {
        nodes.prefix(40).map(\.text).joined(separator: " ")
    }

    // MARK: - Factories

    static func blank(title: String = "未命名导图", themeID: String = MapTheme.defaultThemeID, layout: MapLayout = .mindMap) -> MindMap {
        let root = MindNode(parentID: nil, text: "中心主题", order: 0)
        return MindMap(title: title, nodes: [root], layout: layout, themeID: themeID)
    }
}
