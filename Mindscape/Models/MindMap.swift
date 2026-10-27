import Foundation

struct MindMap: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = String(localized: "未命名导图")
    var nodes: [MindNode] = []
    var layout: MapLayout = .mindMap
    var themeID: String = MapTheme.defaultThemeID
    /// 浅色/深色外观下分别使用的主题；nil 表示旧数据尚未记录。
    var lightThemeID: String?
    var darkThemeID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()


    // MARK: - Theme pair

    /// 当前外观应使用的主题。旧数据只有 themeID 时，优先保留它原本的明暗属性；
    /// 另一种外观落到纸白/深空默认值。
    func effectiveThemeID(isDark: Bool) -> String {
        let stored = isDark ? darkThemeID : lightThemeID
        if let stored, ThemePolicy.allows(stored, isDark: isDark) {
            return stored
        }
        let legacy = MapTheme.byID(themeID)
        if legacy.isDark == isDark, ThemePolicy.allows(themeID, isDark: isDark) {
            return themeID
        }
        return ThemePolicy.defaultID(isDark: isDark)
    }

    /// 把旧数据的 themeID 物化成一对主题，并切换到当前外观对应的那一套。
    mutating func normalizeTheme(isDark: Bool) {
        let legacy = MapTheme.byID(themeID)
        if lightThemeID == nil {
            lightThemeID = legacy.isDark ? ThemePolicy.lightFallbackID : themeID
        }
        if darkThemeID == nil {
            darkThemeID = legacy.isDark ? themeID : ThemePolicy.darkFallbackID
        }
        lightThemeID = ThemePolicy.adjusted(lightThemeID ?? ThemePolicy.lightFallbackID, isDark: false)
        darkThemeID = ThemePolicy.adjusted(darkThemeID ?? ThemePolicy.darkFallbackID, isDark: true)
        themeID = effectiveThemeID(isDark: isDark)
    }

    /// 用户在当前外观下选主题时，只更新对应的那一套。
    mutating func rememberTheme(_ id: String, isDark: Bool) {
        let adjusted = ThemePolicy.adjusted(id, isDark: isDark)
        if isDark {
            darkThemeID = adjusted
        } else {
            lightThemeID = adjusted
        }
        themeID = adjusted
    }

    // MARK: - Lookup

    /// 所有头部节点（没有父节点，或父节点已丢失的节点），按同级顺序排列。
    /// 一张导图允许有多个头部节点；第一个就是主头部节点。
    var rootIDs: [UUID] {
        let existing = Set(nodes.map(\.id))
        let roots = nodes.enumerated()
            .filter { _, node in
                guard let parentID = node.parentID else { return true }
                return !existing.contains(parentID)
            }
            .sorted { lhs, rhs in
                if lhs.element.order != rhs.element.order {
                    return lhs.element.order < rhs.element.order
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element.id)
        if roots.isEmpty, let first = nodes.first {
            return [first.id]
        }
        // 防御重复 ID 的损坏数据：同一个头部只返回一次
        var seen: Set<UUID> = []
        return roots.filter { seen.insert($0).inserted }
    }

    /// 主头部节点：按 order 最小的根节点。这里不排序整个 rootIDs，
    /// 因为标题跟随检查会在每次输入时调用，避免 O(n log n) 的临时数组。
    var primaryRoot: MindNode? {
        let existing = Set(nodes.map(\.id))
        var best: MindNode?
        for node in nodes {
            let isRoot: Bool
            if let parentID = node.parentID {
                isRoot = !existing.contains(parentID)
            } else {
                isRoot = true
            }
            guard isRoot else { continue }
            if let current = best {
                if node.order < current.order { best = node }
            } else {
                best = node
            }
        }
        return best
    }

    /// 主头部节点，保留给单根布局和旧代码使用。
    var rootID: UUID {
        primaryRoot?.id ?? nodes.first?.id ?? UUID()
    }

    var root: MindNode? { primaryRoot }

    /// 第一个头部节点的显示文字，用作导图默认标题。
    var primaryHeadText: String {
        let text = primaryRoot?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? String(localized: "新主题") : text
    }

    func node(_ id: UUID) -> MindNode? {
        nodes.first(where: { $0.id == id })
    }

    func children(of id: UUID) -> [MindNode] {
        nodes.filter { $0.parentID == id }.sorted { $0.order < $1.order }
    }

    /// 一次性建立父子索引，供 BFS / 子树遍历使用，避免对每个节点都做一次
    /// `nodes.filter` 的 O(n²) 扫描。
    private var childrenByParent: [UUID: [MindNode]] {
        var result: [UUID: [MindNode]] = [:]
        for node in nodes {
            if let parentID = node.parentID {
                result[parentID, default: []].append(node)
            }
        }
        for key in Array(result.keys) {
            result[key]?.sort { $0.order < $1.order }
        }
        return result
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

    /// 从所有头部节点开始的广度优先遍历顺序；用于搜索、演示和大纲
    var breadthFirstIDs: [UUID] {
        let roots = rootIDs
        guard !roots.isEmpty else { return [] }
        let childrenMap = childrenByParent
        var result: [UUID] = []
        var queue: [UUID] = roots
        var visited: Set<UUID> = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            result.append(current)
            queue.append(contentsOf: (childrenMap[current] ?? []).map(\.id))
        }
        // 兜底：把因为数据损坏而脱离根节点的节点也放进来
        for node in nodes where !visited.contains(node.id) {
            result.append(node.id)
        }
        return result
    }

    func subtreeIDs(of id: UUID) -> Set<UUID> {
        guard node(id) != nil else { return [] }
        let childrenMap = childrenByParent
        var result: Set<UUID> = []
        var stack: [UUID] = [id]
        while let current = stack.popLast() {
            guard result.insert(current).inserted else { continue }
            stack.append(contentsOf: (childrenMap[current] ?? []).map(\.id))
        }
        return result
    }

    // MARK: - Factories

    static func blank(title: String = String(localized: "未命名导图"), themeID: String = MapTheme.defaultThemeID, layout: MapLayout = .mindMap) -> MindMap {
        let root = MindNode(parentID: nil, text: String(localized: "中心主题"), order: 0)
        return MindMap(title: title, nodes: [root], layout: layout, themeID: themeID)
    }
}
