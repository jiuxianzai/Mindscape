import Foundation
import CoreGraphics

struct LayoutResult {
    var frames: [UUID: CGRect] = [:]
    var depths: [UUID: Int] = [:]
    var children: [UUID: [UUID]] = [:]
    var drawOrder: [UUID] = []
    var bounds: CGRect = .zero
    /// 所有头部节点，按顺序排列
    var rootIDs: [UUID] = []
}

enum LayoutEngine {
    /// 横向间距
    private static let hGap: CGFloat = 56
    /// 纵向间距
    private static let vGap: CGFloat = 16
    /// 根节点与一级分支的额外间距
    private static let rootGap: CGFloat = 78
    /// 组织架构 / 树形图上下层之间的间距。
    /// 原来沿用 vGap（16pt），父节点到子节点之间几乎只剩一条线，
    /// 折叠控件还会压在子节点上；这里单独给足走线和按钮的空间。
    private static let orgLevelGap: CGFloat = 54
    /// 多个头部节点时，每棵树（岛）之间的垂直间距
    private static let islandGap: CGFloat = 84

    static func layout(_ map: MindMap) -> LayoutResult {
        var result = LayoutResult()
        guard !map.nodes.isEmpty else { return result }

        // 不用 uniqueKeysWithValues：导入/损坏数据里若有重复 ID，那个构造器会直接崩溃
        var byID: [UUID: MindNode] = [:]
        byID.reserveCapacity(map.nodes.count)
        for node in map.nodes { byID[node.id] = node }
        var roots = map.rootIDs

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

        // 深度 + 绘制顺序（BFS，父节点先画）。所有头部节点都是第 0 层。
        var depths: [UUID: Int] = [:]
        var order: [UUID] = []
        var visited: Set<UUID> = []
        func walk(from start: UUID) {
            var queue: [UUID] = [start]
            depths[start] = 0
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard visited.insert(current).inserted else { continue }
                order.append(current)
                let depth = depths[current] ?? 0
                for child in childrenMap[current] ?? [] {
                    depths[child] = depth + 1
                    queue.append(child)
                }
            }
        }
        for root in roots { walk(from: root) }
        // 数据损坏 / 环：把没走到的节点也当成独立头部，保证所有节点都有坐标
        for node in map.nodes where !visited.contains(node.id) {
            roots.append(node.id)
            walk(from: node.id)
        }
        result.rootIDs = roots
        result.depths = depths
        result.drawOrder = order

        var sizes: [UUID: CGSize] = [:]
        for node in map.nodes {
            let level = min(depths[node.id] ?? 0, 2)
            sizes[node.id] = NodeMeasurer.size(for: node, level: level)
        }

        let context = Context(
            byID: byID,
            sizes: sizes,
            children: childrenMap,
            collapsed: Set(map.nodes.filter(\.collapsed).map(\.id)),
            frames: [:]
        )

        if roots.count <= 1, let rootID = roots.first {
            var single = context
            layoutIsland(rootID: rootID, style: map.layout, &single)
            result.frames = single.frames
        } else {
            result.frames = layoutForest(roots: roots, style: map.layout, base: context)
        }

        var union: CGRect = .null
        for rect in result.frames.values {
            union = union.union(rect)
        }
        result.bounds = union.isNull ? .zero : union.insetBy(dx: -60, dy: -50)
        return result
    }

    private static func layoutIsland(rootID: UUID, style: MapLayout, _ ctx: inout Context) {
        switch style {
        case .mindMap:
            layoutMindMap(rootID: rootID, &ctx)
        case .logicRight:
            layoutLogic(rootID: rootID, direction: 1, &ctx)
        case .logicLeft:
            layoutLogic(rootID: rootID, direction: -1, &ctx)
        case .braceMap:
            layoutLogic(rootID: rootID, direction: 1, &ctx)
        case .orgChart, .tree:
            layoutOrg(rootID: rootID, &ctx)
        case .timeline:
            layoutTimeline(rootID: rootID, &ctx)
        case .free:
            layoutFree(rootID: rootID, &ctx)
        }
    }

    /// 多个头部节点：每棵树独立布局，然后按顺序垂直堆叠，水平居中对齐。
    private static func layoutForest(roots: [UUID], style: MapLayout, base: Context) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var cursorY: CGFloat = 0

        for root in roots {
            var island = Context(
                byID: base.byID,
                sizes: base.sizes,
                children: base.children,
                collapsed: base.collapsed,
                frames: [:]
            )
            layoutIsland(rootID: root, style: style, &island)
            guard let bounds = union(of: island.frames.values) else { continue }

            let dx = -bounds.midX
            let dy = cursorY - bounds.minY
            for (id, rect) in island.frames {
                // 自由布局里用户摆好的位置是绝对坐标，不能被堆叠偏移改掉
                if style == .free, let position = base.byID[id]?.position {
                    frames[id] = CGRect(origin: position, size: rect.size)
                } else {
                    frames[id] = rect.offsetBy(dx: dx, dy: dy)
                }
            }
            cursorY += bounds.height + islandGap
        }
        return frames
    }

    private static func union(of rects: Dictionary<UUID, CGRect>.Values) -> CGRect? {
        var union: CGRect = .null
        for rect in rects { union = union.union(rect) }
        return union.isNull ? nil : union
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

    private static func subtreeHeight(_ id: UUID, _ ctx: inout Context, depth: Int = 0) -> CGFloat {
        let own = nodeHeight(id, &ctx)
        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id), depth < 256 else { return own }
        let total = kids.reduce(CGFloat(0)) {
            $0 + subtreeHeight($1, &ctx, depth: depth + 1)
        } + vGap * CGFloat(kids.count - 1)
        return max(own, total)
    }

    /// 忽略折叠状态的高度：只用于给一级分支分左右侧，保证结构稳定
    private static func expandedSubtreeHeight(_ id: UUID, _ ctx: inout Context, depth: Int = 0) -> CGFloat {
        let own = nodeHeight(id, &ctx)
        let kids = ctx.kids(id)
        guard !kids.isEmpty, depth < 256 else { return own }
        let total = kids.reduce(CGFloat(0)) {
            $0 + expandedSubtreeHeight($1, &ctx, depth: depth + 1)
        } + vGap * CGFloat(kids.count - 1)
        return max(own, total)
    }

    private static func subtreeWidth(_ id: UUID, _ ctx: inout Context, depth: Int = 0) -> CGFloat {
        let own = ctx.size(id).width
        let kids = ctx.kids(id)
        guard !kids.isEmpty, !ctx.isCollapsed(id), depth < 256 else { return own }
        let total = kids.reduce(CGFloat(0)) {
            $0 + subtreeWidth($1, &ctx, depth: depth + 1)
        } + hGap * CGFloat(kids.count - 1)
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
            // 用“完全展开时”的高度分侧：折叠 / 展开不应让一级分支换边，
            // 否则转场时整个分支会横穿根节点，看起来像糊成一团。
            let height = expandedSubtreeHeight(kid, &ctx)
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
        guard ctx.frames[id] == nil else { return }
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
        guard ctx.frames[id] == nil else { return }
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
        if let existing = ctx.frames[id] { return existing.maxY }
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
            let childMaxY = placeOrg(id: kid, centerX: left + width / 2, top: rect.maxY + orgLevelGap, &ctx)
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
            var seen: Set<UUID> = [milestone, rootID]
            var index = 0
            while index < descendants.count {
                let (child, depth) = descendants[index]
                index += 1
                guard seen.insert(child).inserted else { continue }
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
        for id in subtreeIDs(of: rootID, in: ctx) {
            guard let position = ctx.byID[id]?.position else { continue }
            let size = ctx.size(id)
            ctx.frames[id] = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
        }
    }

    private static func subtreeIDs(of id: UUID, in ctx: Context) -> Set<UUID> {
        var result: Set<UUID> = []
        var stack: [UUID] = [id]
        while let current = stack.popLast() {
            guard result.insert(current).inserted else { continue }
            stack.append(contentsOf: ctx.kids(current))
        }
        return result
    }
}
