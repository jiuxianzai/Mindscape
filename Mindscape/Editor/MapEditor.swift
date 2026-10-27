import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MapEditor {
    private(set) var map: MindMap
    var selection: Set<UUID> = []
    private(set) var revision: Int = 0
    private(set) var fitToken: Int = 0
    /// 请求画布把整张导图居中（不改变缩放）
    private(set) var centerContentToken: Int = 0
    private(set) var zoomToken: Int = 0
    private(set) var zoomFactor: CGFloat = 1
    /// 专注模式聚焦的节点；nil 表示未开启
    private(set) var focusNodeID: UUID?
    /// 请求画布把某个分支缩放到合适大小
    private(set) var branchZoomToken: Int = 0
    private(set) var branchZoomNodeID: UUID?
    /// 请求画布把某个节点移到视口中心（新增节点 / 开始编辑时）
    private(set) var centerToken: Int = 0
    private(set) var centerNodeID: UUID?

    var onSaved: (() -> Void)?

    private let store: DocumentStore
    private var undoStack: [MindMap] = []
    private var redoStack: [MindMap] = []
    private var saveTask: Task<Void, Never>?
    private var lastAutoSnapshot = Date.distantPast
    private var lastTextEditID: UUID?
    private var lastTextEditAt = Date.distantPast

    var theme: MapTheme { MapTheme.byID(map.effectiveThemeID(isDark: NSApplication.shared.isDarkAppearance)) }
    var undoCount: Int { undoStack.count }

    init(map: MindMap, store: DocumentStore) {
        var normalized = map
        normalized.normalizeTheme(isDark: NSApplication.shared.isDarkAppearance)
        Self.assignMissingMindMapSides(in: &normalized)
        self.map = normalized
        self.store = store
        self.selection = normalized.root == nil ? [] : [normalized.rootID]
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

    /// 请求画布把节点居中；由画布在下次布局时消费。
    func requestCenter(_ id: UUID?) {
        markCenterRequest(id)
        revision += 1
    }

    private func markCenterRequest(_ id: UUID?) {
        centerNodeID = id
        centerToken &+= 1
    }

    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
        revision += 1
    }

    /// 框选、全选等批量选择入口
    func setSelection(_ ids: Set<UUID>) {
        let valid = ids.filter { map.node($0) != nil }
        guard valid != selection else { return }
        selection = valid
        revision += 1
    }

    func selectAll() {
        setSelection(Set(map.nodes.map(\.id)))
    }

    var selectedNodes: [MindNode] {
        map.nodes.filter { selection.contains($0.id) }
    }

    // MARK: - Structure

    @discardableResult
    func addChild(to parentID: UUID) -> UUID? {
        guard map.node(parentID) != nil else { return nil }
        var node = MindNode(parentID: parentID, text: String(localized: "新主题"), order: nextOrder(parentID))
        node.icon = nil
        if map.layout == .mindMap,
           map.resolvedMindMapLayoutMode == .remember,
           map.rootIDs.contains(parentID) {
            node.branchSide = preferredMindMapSide(for: parentID)
        }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == parentID }) {
                map.nodes[index].collapsed = false
            }
            map.nodes.append(node)
        }
        selection = [node.id]
        requestCenter(node.id)
        return node.id
    }

    /// 新建一个头部节点。`position` 只对自由布局生效，其它布局会按顺序堆叠。
    @discardableResult
    func addRoot(at position: CGPoint? = nil) -> UUID? {
        let wasFollowing = map.nodes.isEmpty || titleFollowsPrimaryHead
        var node = MindNode(
            parentID: nil,
            text: String(localized: "新主题"),
            order: nextRootOrder()
        )
        node.position = position
        mutate { map in
            map.nodes.append(node)
            refreshTitleIfFollowing(wasFollowing, in: &map)
        }
        selection = [node.id]
        requestCenter(node.id)
        return node.id
    }

    @discardableResult
    func addSibling(after id: UUID) -> UUID? {
        guard let current = map.node(id) else { return nil }
        guard let parentID = current.parentID else {
            return addRoot()
        }
        var node = MindNode(parentID: parentID, text: String(localized: "新主题"), order: nextOrder(parentID))
        if map.layout == .mindMap,
           map.resolvedMindMapLayoutMode == .remember,
           map.rootIDs.contains(parentID) {
            // 新同级默认跟当前分支同侧，插入后仍在同一列，不会跑到对面
            node.branchSide = current.branchSide
                ?? mindMapSide(of: id)
                ?? preferredMindMapSide(for: parentID)
        }
        mutate { map in
            map.nodes.append(node)
        }
        selection = [node.id]
        requestCenter(node.id)
        return node.id
    }

    func deleteSelection() {
        delete(ids: selection)
    }

    func delete(id: UUID) {
        delete(ids: [id])
    }

    func delete(ids: Set<UUID>) {
        let roots = map.rootIDs
        let rootSet = Set(roots)
        var rootsToDelete = roots.filter { ids.contains($0) }
        // 至少保留一个头部节点：批量删到只剩最后一个时把它留下
        if !roots.isEmpty, rootsToDelete.count == roots.count {
            rootsToDelete.removeAll { $0 == roots.last }
        }

        var toRemove: Set<UUID> = []
        for id in ids where !(rootSet.contains(id) && !rootsToDelete.contains(id)) {
            toRemove.formUnion(map.subtreeIDs(of: id))
        }
        guard !toRemove.isEmpty else { return }

        let fallback = ids.compactMap { map.node($0)?.parentID }.first(where: { !toRemove.contains($0) })
            ?? map.rootIDs.first(where: { !toRemove.contains($0) })
            ?? map.rootID
        let wasFollowing = titleFollowsPrimaryHead
        mutate { map in
            map.nodes.removeAll { toRemove.contains($0.id) }
            refreshTitleIfFollowing(wasFollowing, in: &map)
        }
        selection = [fallback]
        if let focusNodeID, toRemove.contains(focusNodeID) {
            self.focusNodeID = nil
        }
    }

    // MARK: - Copy / paste

    /// 复制选中分支（自动去掉被其它选中节点包含的子节点）
    @discardableResult
    func copySelection() -> Bool {
        guard let payload = clipboardPayload(for: selection) else { return false }
        NodeClipboard.write(payload, plainText: Self.plainTextOutline(for: payload))
        return true
    }

    @discardableResult
    func cutSelection() -> Bool {
        guard copySelection() else { return false }
        delete(ids: selection)
        return true
    }

    /// 把剪贴板里的分支粘贴到目标节点下面；默认粘贴到当前选中节点。
    /// 如果剪贴板里没有节点数据，就把纯文本按缩进 / 列表层级转成节点。
    @discardableResult
    func paste(into targetID: UUID? = nil) -> Bool {
        let target = targetID ?? selectedNodes.first?.id ?? map.rootID
        guard map.node(target) != nil else { return false }
        if let payload = NodeClipboard.read() {
            return pastePayload(payload, into: target)
        }
        if let text = NodeClipboard.readText() {
            return pasteText(text, into: target)
        }
        return false
    }

    private func pastePayload(_ payload: NodeClipboardPayload, into target: UUID) -> Bool {
        var newRoots: [UUID] = []
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == target }) {
                map.nodes[index].collapsed = false
            }
            newRoots = insert(payload: payload, into: &map) { _ in target }
        }
        guard !newRoots.isEmpty else { return false }
        selection = Set(newRoots)
        requestCenter(newRoots.first)
        return true
    }

    private struct OutlineLine {
        let indent: Int
        let text: String
    }

    /// 纯文本按缩进转成树：每行一个节点，缩进更深的行挂到上一行下面。
    private func pasteText(_ text: String, into target: UUID) -> Bool {
        let lines = Self.outlineLines(from: text)
        guard !lines.isEmpty else { return false }
        let minimumIndent = lines.map(\.indent).min() ?? 0
        var stack: [(indent: Int, id: UUID)] = []
        var newNodes: [MindNode] = []
        var newRoots: [UUID] = []
        var nextOrders: [UUID: Int] = [:]

        for line in lines {
            let indent = max(line.indent - minimumIndent, 0)
            while let last = stack.last, last.indent >= indent {
                stack.removeLast()
            }
            let parentID = stack.last?.id ?? target
            let order: Int
            if let next = nextOrders[parentID] {
                order = next
            } else {
                order = (map.children(of: parentID).map(\.order).max() ?? -1) + 1
            }
            nextOrders[parentID] = order + 1

            let node = MindNode(parentID: parentID, text: line.text, order: order)
            newNodes.append(node)
            if parentID == target {
                newRoots.append(node.id)
            }
            stack.append((indent, node.id))
        }

        guard !newNodes.isEmpty else { return false }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == target }) {
                map.nodes[index].collapsed = false
            }
            map.nodes.append(contentsOf: newNodes)
            Self.assignMissingMindMapSides(in: &map)
        }
        selection = Set(newRoots)
        requestCenter(newRoots.first)
        return true
    }

    private static func outlineLines(from text: String) -> [OutlineLine] {
        var result: [OutlineLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\r", with: "")
            let expanded = line.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = expanded.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let content = strippingListPrefix(trimmed)
            guard !content.isEmpty else { continue }
            let indent = expanded.prefix { $0 == " " }.count
            result.append(OutlineLine(indent: indent, text: content))
        }
        return result
    }

    /// 去掉 Markdown 列表 / 编号 / 标题前缀，保留节点文字本身。
    private static func strippingListPrefix(_ line: String) -> String {
        var content = line
        if content.hasPrefix("- ") || content.hasPrefix("* ")
            || content.hasPrefix("+ ") || content.hasPrefix("• ") {
            content.removeFirst(2)
        } else if let range = content.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            content.removeSubrange(range)
        } else if content.hasPrefix("#") {
            let hashes = content.prefix { $0 == "#" }
            let rest = content.dropFirst(hashes.count)
            if rest.first == " " {
                content = String(rest.dropFirst())
            }
        }
        return content.trimmingCharacters(in: .whitespaces)
    }

    /// 把复制的子树序列化成缩进 Markdown 列表，写入系统剪贴板，
    /// 这样节点也能直接粘贴到聊天、笔记等其它 App。
    private static func plainTextOutline(for payload: NodeClipboardPayload) -> String {
        var byID: [UUID: MindNode] = [:]
        for node in payload.nodes { byID[node.id] = node }
        var children: [UUID: [MindNode]] = [:]
        for node in payload.nodes {
            guard let parentID = node.parentID, byID[parentID] != nil else { continue }
            children[parentID, default: []].append(node)
        }
        for key in children.keys {
            children[key]?.sort { $0.order < $1.order }
        }

        var lines: [String] = []
        var stack: [(UUID, Int)] = payload.rootIDs.reversed().map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            guard let node = byID[id] else { continue }
            let text = node.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let content = text.isEmpty ? String(localized: "未命名") : text
            lines.append(String(repeating: "  ", count: depth) + "- " + content)
            for child in (children[id] ?? []).reversed() {
                stack.append((child.id, depth + 1))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 创建副本：复制选中分支，挂到原节点同一父级下面
    @discardableResult
    func duplicateSelection() -> Bool {
        guard let payload = clipboardPayload(for: selection) else { return false }
        var parents: [UUID: UUID] = [:]
        let payloadRoots = Set(payload.rootIDs)
        for node in payload.nodes where payloadRoots.contains(node.id) {
            if let parentID = map.node(node.id)?.parentID {
                parents[node.id] = parentID
            }
        }
        var newRoots: [UUID] = []
        mutate { map in
            // 顶层节点原本就是头部 → 复制成新头部；原本是某棵树的子节点 → 留在同一父级
            newRoots = insert(payload: payload, into: &map) { oldID in
                parents[oldID]
            }
        }
        guard !newRoots.isEmpty else { return false }
        selection = Set(newRoots)
        requestCenter(newRoots.first)
        return true
    }

    /// 去掉「父节点也在集合里」的项，只保留最上层节点。
    /// 批量移动/复制时以这些节点为单位，避免把同一棵子树搬两次。
    private func topmostIDs(in ids: Set<UUID>) -> Set<UUID> {
        Set(ids.filter { id in
            guard map.node(id) != nil else { return false }
            var parent = map.node(id)?.parentID
            var guardCount = 0
            while let current = parent, guardCount < map.nodes.count + 4 {
                if ids.contains(current) { return false }
                parent = map.node(current)?.parentID
                guardCount += 1
            }
            return true
        })
    }

    private func clipboardPayload(for ids: Set<UUID>) -> NodeClipboardPayload? {
        let roots = topmostIDs(in: ids).sorted { lhs, rhs in
            (map.nodes.firstIndex(where: { $0.id == lhs }) ?? 0) <
            (map.nodes.firstIndex(where: { $0.id == rhs }) ?? 0)
        }
        guard !roots.isEmpty else { return nil }

        var nodes: [MindNode] = []
        var visited: Set<UUID> = []
        func collect(_ id: UUID) {
            guard visited.insert(id).inserted, let node = map.node(id) else { return }
            nodes.append(node)
            for child in map.children(of: id) {
                collect(child.id)
            }
        }
        for root in roots {
            collect(root)
        }
        return NodeClipboardPayload(nodes: nodes, rootIDs: roots, sourceTitle: map.title)
    }

    /// 把 payload 里的节点用新 ID 插进 map，rootParent 决定每个顶层节点挂到哪里
    private func insert(
        payload: NodeClipboardPayload,
        into map: inout MindMap,
        rootParent: (UUID) -> UUID?
    ) -> [UUID] {
        var idMap: [UUID: UUID] = [:]
        for node in payload.nodes {
            idMap[node.id] = UUID()
        }

        var nextOrder: [UUID: Int] = [:]
        func order(for parent: UUID) -> Int {
            if let value = nextOrder[parent] { return value }
            let value = (map.children(of: parent).map(\.order).max() ?? -1) + 1
            nextOrder[parent] = value
            return value
        }

        var newRoots: [UUID] = []
        let roots = Set(payload.rootIDs)
        func nextRootOrder() -> Int {
            (map.rootIDs.compactMap { map.node($0)?.order }.max() ?? -1) + 1
        }
        for old in payload.nodes {
            guard let newID = idMap[old.id] else { continue }
            let isPayloadRoot = roots.contains(old.id)
            let parentID: UUID?
            if isPayloadRoot {
                parentID = rootParent(old.id)
            } else if let oldParent = old.parentID {
                parentID = idMap[oldParent]
            } else {
                parentID = rootParent(old.id)
            }
            if let parentID, map.node(parentID) == nil { continue }
            if parentID == nil, !isPayloadRoot { continue }

            var node = old
            node.id = newID
            node.parentID = parentID
            if let parentID {
                node.order = order(for: parentID)
                nextOrder[parentID, default: 0] += 1
            } else {
                node.order = nextRootOrder()
            }
            if let position = node.position {
                node.position = CGPoint(x: position.x + 24, y: position.y + 24)
            }
            map.nodes.append(node)
            if isPayloadRoot {
                newRoots.append(newID)
            }
        }
        Self.assignMissingMindMapSides(in: &map)
        return newRoots
    }

    // MARK: - Batch

    func setColor(_ hex: String?, for ids: Set<UUID>) {
        let targets = ids.filter { map.node($0) != nil }
        guard !targets.isEmpty else { return }
        guard targets.contains(where: { map.node($0)?.colorHex != hex }) else { return }
        mutate { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].colorHex = hex
            }
        }
    }

    func setIcon(_ icon: String?, for ids: Set<UUID>) {
        let targets = ids.filter { map.node($0) != nil }
        guard !targets.isEmpty else { return }
        guard targets.contains(where: { map.node($0)?.icon != icon }) else { return }
        mutate { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].icon = icon
            }
        }
    }

    func toggleCollapse(ids: Set<UUID>) {
        let targets = ids.filter { map.node($0) != nil && !map.children(of: $0).isEmpty }
        guard !targets.isEmpty else { return }
        let shouldCollapse = targets.contains { map.node($0)?.collapsed == false }
        mutate { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].collapsed = shouldCollapse
            }
        }
        guard shouldCollapse else { return }
        let hidden = targets.reduce(into: Set<UUID>()) { result, id in
            result.formUnion(map.subtreeIDs(of: id))
        }.subtracting(targets)
        if !selection.isDisjoint(with: hidden), let first = targets.first {
            selection = [first]
        }
    }

    // MARK: - Focus & collapse

    func setFocus(_ id: UUID?) {
        let next = id.flatMap { map.node($0) != nil ? $0 : nil }
        guard next != focusNodeID else { return }
        focusNodeID = next
        revision += 1
    }

    func toggleFocus(on id: UUID? = nil) {
        let target = id ?? selectedNodes.first?.id ?? map.rootID
        guard map.node(target) != nil else { return }
        // 只有一个头部节点时，聚焦它等同于显示整图，没有专注意义；
        // 多个头部节点时，聚焦某个头部可以只看它这一棵树。
        if map.rootIDs.count == 1, map.rootIDs.contains(target) {
            setFocus(nil)
            return
        }
        if focusNodeID == target {
            setFocus(nil)
        } else {
            setFocus(target)
            requestZoomToBranch(target)
        }
    }

    func requestZoomToBranch(_ id: UUID? = nil) {
        let target = id ?? selectedNodes.first?.id ?? map.rootID
        guard map.node(target) != nil else { return }
        branchZoomNodeID = target
        branchZoomToken += 1
        revision += 1
    }

    /// 一键折叠：保留根节点和一级分支，收起所有更深的子分支
    func collapseAll() {
        let roots = Set(map.rootIDs)
        let parents = Set(map.nodes.compactMap(\.parentID))
        let targets = Set(map.nodes.filter { node in
            !roots.contains(node.id)
                && parents.contains(node.id)
                && !node.collapsed
        }.map(\.id))
        guard !targets.isEmpty else { return }
        mutate { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].collapsed = true
            }
        }
    }

    func expandAll() {
        let targets = Set(map.nodes.filter { $0.collapsed }.map(\.id))
        guard !targets.isEmpty else { return }
        mutate { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].collapsed = false
            }
        }
    }

    /// 展开目标节点的所有折叠祖先，保证搜索结果 / 大纲定位时节点真实存在于布局中
    func expandAncestors(of id: UUID) {
        var targets: Set<UUID> = []
        var current = map.node(id)?.parentID
        var guardCount = 0
        while let parentID = current, guardCount < map.nodes.count + 4 {
            if map.node(parentID)?.collapsed == true {
                targets.insert(parentID)
            }
            current = map.node(parentID)?.parentID
            guardCount += 1
        }
        guard !targets.isEmpty else { return }
        mutate(undoable: false) { map in
            for index in map.nodes.indices where targets.contains(map.nodes[index].id) {
                map.nodes[index].collapsed = false
            }
        }
    }

    /// 仅用于导航 / 搜索定位的展开，不写入撤销栈
    func expandForNavigation(_ id: UUID) {
        guard map.node(id)?.collapsed == true else { return }
        mutate(undoable: false) { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].collapsed = false
            }
        }
    }

    // MARK: - Free layout arrangement

    enum FreeArrangement: String, CaseIterable, Identifiable {
        case alignLeft
        case alignCenterX
        case alignRight
        case alignTop
        case alignMiddleY
        case alignBottom
        case distributeHorizontally
        case distributeVertically

        var id: String { rawValue }

        var title: String {
            switch self {
            case .alignLeft: return String(localized: "左对齐")
            case .alignCenterX: return String(localized: "水平居中")
            case .alignRight: return String(localized: "右对齐")
            case .alignTop: return String(localized: "顶对齐")
            case .alignMiddleY: return String(localized: "垂直居中")
            case .alignBottom: return String(localized: "底对齐")
            case .distributeHorizontally: return String(localized: "水平等距")
            case .distributeVertically: return String(localized: "垂直等距")
            }
        }

        var symbol: String {
            switch self {
            case .alignLeft: return "align.horizontal.left"
            case .alignCenterX: return "align.horizontal.center"
            case .alignRight: return "align.horizontal.right"
            case .alignTop: return "align.vertical.top"
            case .alignMiddleY: return "align.vertical.center"
            case .alignBottom: return "align.vertical.bottom"
            case .distributeHorizontally: return "distribute.horizontal"
            case .distributeVertically: return "distribute.vertical"
            }
        }

        var needsThree: Bool {
            self == .distributeHorizontally || self == .distributeVertically
        }
    }

    @discardableResult
    func arrangeSelection(_ arrangement: FreeArrangement, frames: [UUID: CGRect]) -> Bool {
        let entries = selectedNodes.compactMap { node -> (UUID, CGRect)? in
            guard let frame = frames[node.id] else { return nil }
            return (node.id, frame)
        }
        guard entries.count >= (arrangement.needsThree ? 3 : 2) else { return false }

        var positions: [UUID: CGPoint] = [:]
        switch arrangement {
        case .alignLeft:
            let x = entries.map(\.1.minX).min() ?? 0
            for (id, frame) in entries { positions[id] = CGPoint(x: x, y: frame.minY) }
        case .alignCenterX:
            let center = (entries.map(\.1.minX).min() ?? 0) + ((entries.map(\.1.maxX).max() ?? 0) - (entries.map(\.1.minX).min() ?? 0)) / 2
            for (id, frame) in entries { positions[id] = CGPoint(x: center - frame.width / 2, y: frame.minY) }
        case .alignRight:
            let x = entries.map(\.1.maxX).max() ?? 0
            for (id, frame) in entries { positions[id] = CGPoint(x: x - frame.width, y: frame.minY) }
        case .alignTop:
            let y = entries.map(\.1.minY).min() ?? 0
            for (id, frame) in entries { positions[id] = CGPoint(x: frame.minX, y: y) }
        case .alignMiddleY:
            let center = (entries.map(\.1.minY).min() ?? 0) + ((entries.map(\.1.maxY).max() ?? 0) - (entries.map(\.1.minY).min() ?? 0)) / 2
            for (id, frame) in entries { positions[id] = CGPoint(x: frame.minX, y: center - frame.height / 2) }
        case .alignBottom:
            let y = entries.map(\.1.maxY).max() ?? 0
            for (id, frame) in entries { positions[id] = CGPoint(x: frame.minX, y: y - frame.height) }
        case .distributeHorizontally:
            let sorted = entries.sorted { $0.1.minX < $1.1.minX }
            guard let first = sorted.first, let last = sorted.last else { return false }
            let span = last.1.maxX - first.1.minX
            let widths = sorted.reduce(CGFloat(0)) { $0 + $1.1.width }
            let gap = (span - widths) / CGFloat(sorted.count - 1)
            var x = first.1.minX
            for (id, frame) in sorted {
                positions[id] = CGPoint(x: x, y: frame.minY)
                x += frame.width + gap
            }
        case .distributeVertically:
            let sorted = entries.sorted { $0.1.minY < $1.1.minY }
            guard let first = sorted.first, let last = sorted.last else { return false }
            let span = last.1.maxY - first.1.minY
            let heights = sorted.reduce(CGFloat(0)) { $0 + $1.1.height }
            let gap = (span - heights) / CGFloat(sorted.count - 1)
            var y = first.1.minY
            for (id, frame) in sorted {
                positions[id] = CGPoint(x: frame.minX, y: y)
                y += frame.height + gap
            }
        }

        guard !positions.isEmpty else { return false }
        mutate { map in
            for index in map.nodes.indices {
                if let position = positions[map.nodes[index].id] {
                    map.nodes[index].position = position
                }
            }
        }
        return true
    }

    // MARK: - Search

    /// 图内搜索：文字、备注、图标名称都参与匹配，结果按 BFS 顺序返回
    func searchMatches(_ query: String) -> [UUID] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        return map.breadthFirstIDs.filter { id in
            guard let node = map.node(id) else { return false }
            if node.text.localizedCaseInsensitiveContains(keyword) { return true }
            if node.note.localizedCaseInsensitiveContains(keyword) { return true }
            if let icon = node.icon {
                if icon.localizedCaseInsensitiveContains(keyword) { return true }
                if let name = IconCatalog.all.first(where: { $0.symbol == icon })?.name,
                   name.localizedCaseInsensitiveContains(keyword) {
                    return true
                }
            }
            return false
        }
    }

    func toggleCollapse(_ id: UUID) {
        guard map.node(id) != nil, !map.children(of: id).isEmpty else { return }
        let wasCollapsed = map.node(id)?.collapsed ?? false
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].collapsed.toggle()
            }
        }
        if !wasCollapsed {
            let hidden = map.subtreeIDs(of: id).subtracting([id])
            if !selection.isDisjoint(with: hidden) {
                selection = [id]
            }
        }
    }

    func canMove(_ id: UUID, to newParent: UUID) -> Bool {
        guard id != newParent else { return false }
        guard map.node(newParent) != nil else { return false }
        guard !map.isDescendant(newParent, of: id) else { return false }
        // 只有一个头部节点时不能把它拖成子节点，否则整张图就没有根了
        if map.rootIDs.count <= 1, map.rootIDs.contains(id) { return false }
        return map.node(id)?.parentID != newParent
    }

    func move(id: UUID, to newParent: UUID) {
        move(ids: [id], to: newParent)
    }

    /// 当前选中的节点里，至少有一个可以挂到 `newParent` 下面。
    /// 供画布在拖拽过程中决定是否显示落点。
    func canMoveSelection(to newParent: UUID) -> Bool {
        canMove(ids: selection, to: newParent)
    }

    func canMove(ids: Set<UUID>, to newParent: UUID) -> Bool {
        guard map.node(newParent) != nil else { return false }
        let moving = topmostIDs(in: ids)
        guard !moving.contains(newParent) else { return false }
        return moving.contains { canMove($0, to: newParent) }
    }

    /// 批量移动：把选中节点里最上层的几棵子树一起挂到目标节点下。
    /// 已经在目标节点下的节点会被跳过，避免重复搬运。
    @discardableResult
    func move(
        ids: Set<UUID>,
        to newParent: UUID,
        freeOrigins: [UUID: CGPoint] = [:],
        branchSide: MindMapSide? = nil
    ) -> Bool {
        guard map.node(newParent) != nil else { return false }
        let moving = topmostIDs(in: ids)
        guard !moving.contains(newParent) else { return false }

        let ordered = moving
            .filter { canMove($0, to: newParent) }
            .sorted { lhs, rhs in
                (map.nodes.firstIndex(where: { $0.id == lhs }) ?? 0) <
                (map.nodes.firstIndex(where: { $0.id == rhs }) ?? 0)
            }
        guard !ordered.isEmpty else { return false }

        let wasFollowing = titleFollowsPrimaryHead
        let targetsRoot = map.rootIDs.contains(newParent)
        let remembering = map.layout == .mindMap
            && map.resolvedMindMapLayoutMode == .remember
        mutate { map in
            var newOrder = (map.children(of: newParent).map(\.order).max() ?? -1) + 1
            for id in ordered {
                guard let index = map.nodes.firstIndex(where: { $0.id == id }) else { continue }
                map.nodes[index].parentID = newParent
                map.nodes[index].order = newOrder
                // 只有一级分支才有左右侧；显式拖到根节点左右半边时优先用拖拽方向
                if targetsRoot, remembering, ordered.count == 1, let branchSide {
                    map.nodes[index].branchSide = branchSide
                } else {
                    map.nodes[index].branchSide = nil
                }
                newOrder += 1
            }
            if targetsRoot, remembering {
                Self.assignMissingMindMapSides(in: &map)
            }
            if let parentIndex = map.nodes.firstIndex(where: { $0.id == newParent }) {
                map.nodes[parentIndex].collapsed = false
            }
            for (id, origin) in freeOrigins {
                if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                    map.nodes[index].position = origin
                }
            }
            refreshTitleIfFollowing(wasFollowing, in: &map)
        }
        return true
    }

    func moveFreeNode(id: UUID, to origin: CGPoint) {
        moveFreeNodes(origins: [id: origin])
    }

    /// 批量移动自由布局节点。一次 mutate = 一步撤销。
    func moveFreeNodes(origins: [UUID: CGPoint]) {
        guard !origins.isEmpty else { return }
        let changed = origins.contains { id, origin in
            guard let node = map.node(id) else { return false }
            return node.position != origin
        }
        guard changed else { return }
        mutate { map in
            for index in map.nodes.indices {
                if let origin = origins[map.nodes[index].id] {
                    map.nodes[index].position = origin
                }
            }
        }
    }

    func reorder(
        id: UUID,
        relativeTo targetID: UUID,
        after: Bool,
        branchSide: MindMapSide? = nil
    ) {
        guard id != targetID,
              let node = map.node(id),
              let target = map.node(targetID) else { return }

        // 头部节点之间也可以排序
        if node.parentID == nil, target.parentID == nil {
            let roots = map.rootIDs
            guard roots.contains(id), roots.contains(targetID) else { return }
            let wasFollowing = titleFollowsPrimaryHead
            mutate { map in
                var ids = roots.filter { $0 != id }
                guard let index = ids.firstIndex(of: targetID) else { return }
                ids.insert(id, at: after ? index + 1 : index)
                for (order, rootID) in ids.enumerated() {
                    if let nodeIndex = map.nodes.firstIndex(where: { $0.id == rootID }) {
                        map.nodes[nodeIndex].order = order
                    }
                }
                refreshTitleIfFollowing(wasFollowing, in: &map)
            }
            return
        }

        guard node.parentID == target.parentID,
              let parentID = node.parentID else { return }

        let siblings = map.children(of: parentID).map(\.id)
        guard siblings.contains(id), siblings.contains(targetID) else { return }

        mutate { map in
            var ids = siblings.filter { $0 != id }
            guard let index = ids.firstIndex(of: targetID) else { return }
            ids.insert(id, at: after ? index + 1 : index)
            for (order, siblingID) in ids.enumerated() {
                if let nodeIndex = map.nodes.firstIndex(where: { $0.id == siblingID }) {
                    map.nodes[nodeIndex].order = order
                }
            }
            if let branchSide,
               map.layout == .mindMap,
               map.resolvedMindMapLayoutMode == .remember,
               map.rootIDs.contains(parentID),
               let nodeIndex = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[nodeIndex].branchSide = branchSide
            }
        }
    }

    // MARK: - Node content

    func setText(_ text: String, for id: UUID) {
        guard let node = map.node(id), node.text != text else { return }
        let now = Date()
        let coalesce = lastTextEditID == id && now.timeIntervalSince(lastTextEditAt) < 1.0
        let primaryRoot = map.primaryRoot
        let wasFollowing = titleFollows(primaryRoot: primaryRoot)
        let isPrimaryHead = primaryRoot?.id == id
        mutate(undoable: !coalesce) { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].text = text
            }
            if isPrimaryHead, wasFollowing {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                map.title = trimmed.isEmpty ? String(localized: "新主题") : trimmed
            }
        }
        markCenterRequest(id)
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

    func setIcon(_ icon: String?, for id: UUID) {
        guard let node = map.node(id), node.icon != icon else { return }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].icon = icon
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
            Self.assignMissingMindMapSides(in: &map)
        }
        fitToken += 1
    }

    /// 切换思维导图一级分支的排列方式。
    /// 切到「记住布局」时先把当前视觉上的左右侧固化下来；
    /// 切到「平衡布局」时清掉记录，之后每次布局都会自动平衡。
    func setMindMapLayoutMode(_ mode: MindMapLayoutMode) {
        guard map.resolvedMindMapLayoutMode != mode else { return }
        let sides = mindMapSideSnapshot()
        mutate { map in
            map.mindMapLayoutMode = mode
            if mode == .remember {
                for index in map.nodes.indices {
                    if let side = sides[map.nodes[index].id] {
                        map.nodes[index].branchSide = side
                    }
                }
            } else {
                for index in map.nodes.indices {
                    map.nodes[index].branchSide = nil
                }
            }
        }
    }

    /// 只改一级分支的左右侧，保留它当前在同侧里的竖向顺序。
    @discardableResult
    func setMindMapBranchSide(id: UUID, side: MindMapSide) -> Bool {
        guard map.layout == .mindMap,
              map.resolvedMindMapLayoutMode == .remember,
              let node = map.node(id),
              let parentID = node.parentID,
              map.rootIDs.contains(parentID),
              node.branchSide != side else { return false }
        mutate { map in
            if let index = map.nodes.firstIndex(where: { $0.id == id }) {
                map.nodes[index].branchSide = side
            }
        }
        return true
    }

    // MARK: - Mind map branch helpers

    /// 记住布局下，把还没有显式左右侧的一级分支按当前视觉位置补记录。
    /// 旧数据、导入的数据、粘贴进来的分支都靠这一步保持「看起来没变」。
    private static func assignMissingMindMapSides(in map: inout MindMap) {
        guard map.layout == .mindMap,
              map.resolvedMindMapLayoutMode == .remember,
              !map.nodes.isEmpty else { return }
        let layout = LayoutEngine.layout(map)
        for rootID in map.rootIDs {
            guard let rootFrame = layout.frames[rootID] else { continue }
            for child in map.children(of: rootID) where child.branchSide == nil {
                guard let frame = layout.frames[child.id],
                      let index = map.nodes.firstIndex(where: { $0.id == child.id }) else { continue }
                map.nodes[index].branchSide = frame.midX < rootFrame.midX ? .left : .right
            }
        }
    }

    /// 一级分支当前实际在哪一侧（优先用记住的值，旧数据回退到布局坐标）。
    private func mindMapSide(of id: UUID) -> MindMapSide? {
        guard map.layout == .mindMap, let node = map.node(id) else { return nil }
        if let side = node.branchSide { return side }
        guard let parentID = node.parentID, map.rootIDs.contains(parentID) else { return nil }
        let layout = LayoutEngine.layout(map)
        guard let rootFrame = layout.frames[parentID],
              let frame = layout.frames[id] else { return nil }
        return frame.midX < rootFrame.midX ? .left : .right
    }

    /// 新建一级分支时，放到当前总高度更小的一侧。
    private func preferredMindMapSide(for rootID: UUID) -> MindMapSide {
        guard map.rootIDs.contains(rootID) else { return .right }
        let layout = LayoutEngine.layout(map)
        guard let rootFrame = layout.frames[rootID] else { return .right }
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        for child in map.children(of: rootID) {
            var union = CGRect.null
            for id in map.subtreeIDs(of: child.id) {
                if let frame = layout.frames[id] { union = union.union(frame) }
            }
            guard !union.isNull else { continue }
            if union.midX < rootFrame.midX {
                leftHeight += union.height
            } else {
                rightHeight += union.height
            }
        }
        return rightHeight <= leftHeight ? .right : .left
    }

    /// 非破坏性模拟一次思维导图落点，返回被拖节点在结果布局里的位置。
    /// 只用于拖动时的虚线预览，不写入模型，也不进入撤销栈。
    func previewMindMapDropFrame(
        sourceID: UUID,
        targetID: UUID,
        after: Bool,
        side: MindMapSide?
    ) -> CGRect? {
        guard let source = map.node(sourceID),
              source.parentID != nil,
              map.node(targetID) != nil else { return nil }

        var preview = map
        guard let sourceIndex = preview.nodes.firstIndex(where: { $0.id == sourceID }),
              let targetNode = preview.node(targetID) else { return nil }
        let roots = preview.rootIDs
        let remembering = preview.layout == .mindMap
            && preview.resolvedMindMapLayoutMode == .remember

        if roots.contains(targetID) {
            if source.parentID == targetID {
                guard remembering, let side else { return nil }
                preview.nodes[sourceIndex].branchSide = side
            } else {
                let order = (preview.rootIDs.compactMap { preview.node($0)?.order }.max() ?? -1) + 1
                preview.nodes[sourceIndex].parentID = targetID
                preview.nodes[sourceIndex].order = order
                preview.nodes[sourceIndex].branchSide = remembering ? side : nil
                if let targetIndex = preview.nodes.firstIndex(where: { $0.id == targetID }) {
                    preview.nodes[targetIndex].collapsed = false
                }
            }
        } else if source.parentID == targetNode.parentID {
            guard let parentID = source.parentID else { return nil }
            var siblings = preview.children(of: parentID).map(\.id)
            guard let sourceSiblingIndex = siblings.firstIndex(of: sourceID) else { return nil }
            siblings.remove(at: sourceSiblingIndex)
            guard let targetSiblingIndex = siblings.firstIndex(of: targetID) else { return nil }
            siblings.insert(sourceID, at: after ? targetSiblingIndex + 1 : targetSiblingIndex)
            for (order, id) in siblings.enumerated() {
                if let index = preview.nodes.firstIndex(where: { $0.id == id }) {
                    preview.nodes[index].order = order
                }
            }
            if remembering, let side, roots.contains(parentID) {
                preview.nodes[sourceIndex].branchSide = side
            }
        } else {
            let order = (preview.children(of: targetID).map(\.order).max() ?? -1) + 1
            preview.nodes[sourceIndex].parentID = targetID
            preview.nodes[sourceIndex].order = order
            preview.nodes[sourceIndex].branchSide = nil
            if let targetIndex = preview.nodes.firstIndex(where: { $0.id == targetID }) {
                preview.nodes[targetIndex].collapsed = false
            }
        }

        return LayoutEngine.layout(preview).frames[sourceID]
    }

    private func mindMapSideSnapshot() -> [UUID: MindMapSide] {
        guard map.layout == .mindMap else { return [:] }
        let layout = LayoutEngine.layout(map)
        var sides: [UUID: MindMapSide] = [:]
        for rootID in map.rootIDs {
            guard let rootFrame = layout.frames[rootID] else { continue }
            for child in map.children(of: rootID) {
                guard let frame = layout.frames[child.id] else { continue }
                sides[child.id] = frame.midX < rootFrame.midX ? .left : .right
            }
        }
        return sides
    }

    func setTheme(_ themeID: String) {
        let isDark = NSApplication.shared.isDarkAppearance
        let adjusted = ThemePolicy.adjusted(themeID, isDark: isDark)
        let stored = isDark ? map.darkThemeID : map.lightThemeID
        guard map.themeID != adjusted || stored != adjusted else { return }
        mutate { map in
            map.rememberTheme(adjusted, isDark: isDark)
        }
    }

    /// 外观切换后，把当前文件切换到对应的浅色/深色主题。
    func syncThemeForAppearance() {
        var updated = map
        updated.normalizeTheme(isDark: NSApplication.shared.isDarkAppearance)
        guard updated != map else { return }
        mutate(undoable: false) { $0 = updated }
    }

    func requestFit() {
        fitToken += 1
        revision += 1
    }

    /// 请求画布把整张导图水平、垂直居中到视口中央。
    func requestCenterContent() {
        centerContentToken += 1
        revision += 1
    }

    func requestZoom(_ factor: CGFloat) {
        zoomFactor = factor
        zoomToken += 1
        revision += 1
    }

    // MARK: - Undo / redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(map)
        trim(&redoStack)
        map = previous
        selection = selection.filter { map.node($0) != nil }
        sanitizeFocus()
        revision += 1
        scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(map)
        trim(&undoStack)
        map = next
        selection = selection.filter { map.node($0) != nil }
        sanitizeFocus()
        revision += 1
        scheduleSave()
    }

    private func sanitizeFocus() {
        if let focusNodeID, map.node(focusNodeID) == nil {
            self.focusNodeID = nil
        }
        if let branchZoomNodeID, map.node(branchZoomNodeID) == nil {
            self.branchZoomNodeID = nil
        }
    }

    private func mutate(undoable: Bool = true, _ body: (inout MindMap) -> Void) {
        if undoable {
            undoStack.append(map)
            trim(&undoStack)
            redoStack.removeAll()
        }
        body(&map)
        map.updatedAt = Date()
        revision += 1
        scheduleSave()
    }

    /// 标题是否还在跟随第一个头部节点（用户手动改名后就不再跟随）
    private var titleFollowsPrimaryHead: Bool {
        titleFollows(primaryRoot: map.primaryRoot)
    }

    private func titleFollows(primaryRoot: MindNode?) -> Bool {
        let trimmed = map.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == String(localized: "未命名导图") {
            return true
        }
        let headText = primaryRoot?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return map.title == (headText.isEmpty ? String(localized: "新主题") : headText)
    }

    private func refreshTitleIfFollowing(_ wasFollowing: Bool, in map: inout MindMap) {
        guard wasFollowing else { return }
        map.title = map.primaryHeadText
    }

    /// 撤销栈同时按「步数」和「节点总数」限制：大图连续编辑时，
    /// 150 份完整快照可能占掉几百 MB；节点总数超预算就先丢最旧的快照。
    private func trim(_ stack: inout [MindMap]) {
        let maxSteps = 150
        let maxNodes = 40_000
        var totalNodes = stack.reduce(0) { $0 + $1.nodes.count }
        while stack.count > maxSteps || (totalNodes > maxNodes && stack.count > 1) {
            totalNodes -= stack.removeFirst().nodes.count
        }
    }

    private func nextOrder(_ parentID: UUID) -> Int {
        (map.children(of: parentID).map(\.order).max() ?? -1) + 1
    }

    private func nextRootOrder() -> Int {
        (map.rootIDs.compactMap { map.node($0)?.order }.max() ?? -1) + 1
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
            maybeAutoSnapshot()
            onSaved?()
        } catch {
            // 自动保存失败时不打断编辑；下一次编辑会再次尝试。
        }
    }

    private func maybeAutoSnapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastAutoSnapshot) > 600 else { return }
        lastAutoSnapshot = now
        try? store.addSnapshot(map, name: String(localized: "自动快照"), kind: "auto")
    }

    // MARK: - History

    func snapshots() -> [SnapshotRecord] {
        (try? store.snapshots(for: map.id)) ?? []
    }

    @discardableResult
    func createSnapshot(name: String = String(localized: "手动快照")) -> Bool {
        do {
            try store.addSnapshot(map, name: name, kind: "manual")
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func renameSnapshot(id: UUID, name: String) -> Bool {
        do {
            try store.renameSnapshot(id: id, name: name)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func deleteSnapshot(id: UUID) -> Bool {
        do {
            try store.deleteSnapshot(id: id)
            return true
        } catch {
            return false
        }
    }

    func restore(snapshot: SnapshotRecord) {
        guard let restored = try? store.loadSnapshot(snapshot.id) else { return }
        try? store.addSnapshot(map, name: String(localized: "恢复前"), kind: "manual")
        undoStack.append(map)
        trim(&undoStack)
        redoStack.removeAll()

        var next = restored
        next.id = map.id
        next.updatedAt = Date()
        map = next
        selection = map.root == nil ? [] : [map.rootID]
        focusNodeID = nil
        revision += 1
        fitToken += 1
        saveNow()
    }
}
