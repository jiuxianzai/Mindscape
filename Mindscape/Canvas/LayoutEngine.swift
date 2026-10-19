import Foundation
import CoreGraphics

struct LayoutResult {
    var frames: [UUID: CGRect] = [:]
    var depths: [UUID: Int] = [:]
    var parents: [UUID: UUID] = [:]
    var children: [UUID: [UUID]] = [:]
    var drawOrder: [UUID] = []
    var bounds: CGRect = .zero
    var rootID: UUID?
}

enum LayoutEngine {
    /// 横向间距
    private static let hGap: CGFloat = 56
    /// 纵向间距
    private static let vGap: CGFloat = 16
    /// 根节点与一级分支的额外间距
    private static let rootGap: CGFloat = 78

    static func layout(_ map: MindMap) -> LayoutResult {
        var result = LayoutResult()
        guard !map.nodes.isEmpty else { return result }

        let byID = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
        let rootID = map.rootID
        result.rootID = rootID

        var childrenMap: [UUID: [UUID]] = [:]
        for node in map.nodes {
            if let parentID = node.parentID {
                childrenMap[parentID, default: []].append(node.id)
            }
        }
        // 保持节点顺序
        for (parent, ids) in childrenMap {
            childrenMap[parent] = ids.sorted { lhs, rhs in
                (byID[lhs]?.order ?? 0) < (byID[rhs]?.order ?? 0)
            }
        }
        result.children = childrenMap
        for node in map.nodes {
            if let parentID = node.parentID { result.parents[node.id] = parentID }
        }

        // 深度 + 绘制顺序（BFS，父节点先画）
        var depths: [UUID: Int] = [rootID: 0]
        var queue: [UUID] = [rootID]
        var order: [UUID] = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            order.append(current)
            let depth = depths[current] ?? 0
            for child in childrenMap[current] ?? [] {
                depths[child] = depth + 1
                queue.append(child)
            }
        }
        result.depths = depths
        result.drawOrder = order

        var sizes: [UUID: CGSize] = [:]
        for node in map.nodes {
            let level = min(depths[node.id] ?? 0, 2)
            sizes[node.id] = NodeMeasurer.size(for: node, level: level)
        }

        var context = Context(
            byID: byID,
            sizes: sizes,
            children: childrenMap,
            collapsed: Set(map.nodes.filter(\.collapsed).map(\.id)),
            frames: [:]
        )

        switch map.layout {
        case .mindMap:
            layoutMindMap(rootID: rootID, &context)
        case .logicRight:
            layoutLogic(rootID: rootID, direction: 1, &context)
        case .logicLeft:
            layoutLogic(rootID: rootID, direction: -1, &context)
        case .braceMap:
            layoutLogic(rootID: rootID, direction: 1, &context)
        case .orgChart, .tree:
            layoutOrg(rootID: rootID, &context)
        case .timeline:
            layoutTimeline(rootID: rootID, &context)
        case .free:
            layoutFree(rootID: rootID, &context)
        }

        result.frames = context.frames

        var union: CGRect = .null
        for rect in context.frames.values {
            union = union.union(rect)
        }
        result.bounds = union.isNull ? .zero : union.insetBy(dx: -60, dy: -50)
        return result
    }

    // MARK: - Context

    private struct Context {
        let byID: [UUID: MindNode]
        let sizes: [UUID: CGSize]
        let children: [UUID: [UUID]]
        let collapsed: Set<UUID>
        var frames: [UUID: CGRect]

        func size(_ id: UUID) -> CGSize { sizes[id] ?? CGSize(width: 100, height: 40) }
        func kids(_ id: UUID) -> [UUID] { children[id] ?? [] }
        func isCollapsed(_ id: UUID) -> Bool { collapsed.contains(id) }
    }

    private static func nodeHeight(_ id: UUID, _ ctx: inout Context) -> CGFloat {
        ctx.size(id).height
    }

    private static func subtreeHeight(_ id: UUID, _ ctx: inout Context) -> CGFloat {
        let own = nodeHeight(id, &ctx)
        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id) else { return own }
        let total = kids.reduce(CGFloat(0)) { $0 + subtreeHeight($1, &ctx) } + vGap * CGFloat(kids.count - 1)
        return max(own, total)
    }

    private static func subtreeWidth(_ id: UUID, _ ctx: inout Context) -> CGFloat {
        let own = ctx.size(id).width
        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id) else { return own }
        let total = kids.reduce(CGFloat(0)) { $0 + subtreeWidth($1, &ctx) } + hGap * CGFloat(kids.count - 1)
        return max(own, total)
    }

    // MARK: - Mind map

    private static func layoutMindMap(rootID: UUID, _ ctx: inout Context) {
        let rootSize = ctx.size(rootID)
        let rootRect = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)
        ctx.frames[rootID] = rootRect

        let kids = ctx.kids(rootID)
        guard !kids.isEmpty, !ctx.isCollapsed(rootID) else { return }

        var right: [UUID] = []
        var left: [UUID] = []
        var rightHeight: CGFloat = 0
        var leftHeight: CGFloat = 0
        for kid in kids {
            let height = subtreeHeight(kid, &ctx)
            if rightHeight <= leftHeight {
                right.append(kid)
                rightHeight += height + vGap
            } else {
                left.append(kid)
                leftHeight += height + vGap
            }
        }

        placeColumn(right, x: rootRect.maxX + rootGap, direction: 1, centerY: 0, &ctx)
        placeColumn(left, x: rootRect.minX - rootGap, direction: -1, centerY: 0, &ctx)
    }

    private static func placeColumn(_ ids: [UUID], x: CGFloat, direction: CGFloat, centerY: CGFloat, _ ctx: inout Context) {
        guard !ids.isEmpty else { return }
        let heights = ids.map { subtreeHeight($0, &ctx) }
        let total = heights.reduce(0, +) + vGap * CGFloat(ids.count - 1)
        var top = centerY - total / 2
        for (index, id) in ids.enumerated() {
            let height = heights[index]
            let childCenter = top + height / 2
            if direction > 0 {
                placeRight(id: id, x: x, centerY: childCenter, &ctx)
            } else {
                placeLeft(id: id, x: x, centerY: childCenter, &ctx)
            }
            top += height + vGap
        }
    }

    private static func placeRight(id: UUID, x: CGFloat, centerY: CGFloat, _ ctx: inout Context) {
        let size = ctx.size(id)
        let rect = CGRect(x: x, y: centerY - size.height / 2, width: size.width, height: size.height)
        ctx.frames[id] = rect

        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id) else { return }

        let heights = kids.map { subtreeHeight($0, &ctx) }
        let total = heights.reduce(0, +) + vGap * CGFloat(kids.count - 1)
        var top = centerY - total / 2
        for (index, kid) in kids.enumerated() {
            let height = heights[index]
            placeRight(id: kid, x: rect.maxX + hGap, centerY: top + height / 2, &ctx)
            top += height + vGap
        }
    }

    private static func placeLeft(id: UUID, x: CGFloat, centerY: CGFloat, _ ctx: inout Context) {
        let size = ctx.size(id)
        let rect = CGRect(x: x - size.width, y: centerY - size.height / 2, width: size.width, height: size.height)
        ctx.frames[id] = rect

        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id) else { return }

        let heights = kids.map { subtreeHeight($0, &ctx) }
        let total = heights.reduce(0, +) + vGap * CGFloat(kids.count - 1)
        var top = centerY - total / 2
        for (index, kid) in kids.enumerated() {
            let height = heights[index]
            placeLeft(id: kid, x: rect.minX - hGap, centerY: top + height / 2, &ctx)
            top += height + vGap
        }
    }

    // MARK: - Logic / brace

    private static func layoutLogic(rootID: UUID, direction: CGFloat, _ ctx: inout Context) {
        let rootSize = ctx.size(rootID)
        let rootX = direction > 0 ? 0 : -rootSize.width
        let rootRect = CGRect(x: rootX, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)
        ctx.frames[rootID] = rootRect
        guard !ctx.isCollapsed(rootID) else { return }

        let kids = ctx.kids(rootID)
        let total = kids.reduce(CGFloat(0)) { $0 + subtreeHeight($1, &ctx) } + vGap * CGFloat(max(kids.count - 1, 0))
        var top = -total / 2
        for kid in kids {
            let height = subtreeHeight(kid, &ctx)
            let center = top + height / 2
            if direction > 0 {
                placeRight(id: kid, x: rootRect.maxX + rootGap, centerY: center, &ctx)
            } else {
                placeLeft(id: kid, x: rootRect.minX - rootGap, centerY: center, &ctx)
            }
            top += height + vGap
        }
    }

    // MARK: - Org / tree

    private static func layoutOrg(rootID: UUID, _ ctx: inout Context) {
        let width = subtreeWidth(rootID, &ctx)
        placeOrg(id: rootID, centerX: width / 2, top: 0, &ctx)
    }

    @discardableResult
    private static func placeOrg(id: UUID, centerX: CGFloat, top: CGFloat, _ ctx: inout Context) -> CGFloat {
        let size = ctx.size(id)
        let rect = CGRect(x: centerX - size.width / 2, y: top, width: size.width, height: size.height)
        ctx.frames[id] = rect

        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id) else { return rect.maxY }

        let widths = kids.map { subtreeWidth($0, &ctx) }
        let total = widths.reduce(0, +) + hGap * CGFloat(kids.count - 1)
        var left = centerX - total / 2
        var maxY = rect.maxY
        for (index, kid) in kids.enumerated() {
            let width = widths[index]
            let childMaxY = placeOrg(id: kid, centerX: left + width / 2, top: rect.maxY + vGap, &ctx)
            maxY = max(maxY, childMaxY)
            left += width + hGap
        }
        return maxY
    }

    // MARK: - Timeline

    private static func layoutTimeline(rootID: UUID, _ ctx: inout Context) {
        let rootSize = ctx.size(rootID)
        let rootRect = CGRect(x: 0, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)
        ctx.frames[rootID] = rootRect

        let milestones = ctx.kids(rootID)
        guard !milestones.isEmpty, !ctx.isCollapsed(rootID) else { return }

        var x = rootRect.maxX + 64
        for milestone in milestones {
            let size = ctx.size(milestone)
            let rect = CGRect(x: x, y: -size.height / 2, width: size.width, height: size.height)
            ctx.frames[milestone] = rect

            var columnWidth = size.width
            var descendants: [(UUID, Int)] = ctx.isCollapsed(milestone) ? [] : ctx.kids(milestone).map { ($0, 1) }
            var index = 0
            while index < descendants.count {
                let (child, depth) = descendants[index]
                index += 1
                columnWidth = max(columnWidth, ctx.size(child).width + CGFloat(depth) * 14)
                if !ctx.isCollapsed(child) {
                    for grandchild in ctx.kids(child) {
                        descendants.append((grandchild, depth + 1))
                    }
                }
            }

            var childTop = rect.maxY + 30
            for (child, depth) in descendants {
                let childSize = ctx.size(child)
                let childX = rect.minX + CGFloat(depth) * 14
                let childRect = CGRect(x: childX, y: childTop, width: childSize.width, height: childSize.height)
                ctx.frames[child] = childRect
                childTop = childRect.maxY + 10
            }

            x += columnWidth + 60
        }
    }

    // MARK: - Free

    private static func layoutFree(rootID: UUID, _ ctx: inout Context) {
        // 先用逻辑图给出默认位置，用户拖动后再覆盖
        layoutLogic(rootID: rootID, direction: 1, &ctx)
        for (id, node) in Array(ctx.byID) {
            if let position = node.position {
                let size = ctx.size(id)
                ctx.frames[id] = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
            }
        }
    }
}
