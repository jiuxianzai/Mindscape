import AppKit

struct CanvasCamera {
    var center: CGPoint = .zero
    var zoom: CGFloat = 1
    static let minZoom: CGFloat = 0.15
    static let maxZoom: CGFloat = 3.5
}

final class MindCanvasView: NSView, NSTextViewDelegate, NSUserInterfaceValidations {
    weak var editor: MapEditor?
    /// 相机缩放变化时回调，供底部缩放栏同步显示
    var onZoomChanged: ((CGFloat) -> Void)?
    var currentZoom: CGFloat { camera.zoom }

    /// 演示模式使用：不允许编辑、拖拽和框选，但保留缩放 / 平移
    var isReadOnly = false
    /// 专注 / 演示模式下焦点外节点的透明度
    var focusDimAlpha: CGFloat = 0.35

    private var theme: MapTheme = MapTheme.all[0]
    private var layoutResult: LayoutResult?
    private var layoutRevision: Int = -1
    private var layoutDocumentID: UUID?
    private var camera = CanvasCamera()
    private var displayFrames: [UUID: CGRect] = [:]
    private var frameAnimation: FrameAnimation?
    private var animationTimer: Timer?
    private var dashTimer: Timer?
    private var dashPhase: CGFloat = 0
    private var accessibilityObserver: NSObjectProtocol?
    private var nodeAccessibilityElements: [UUID: MindNodeAccessibilityElement] = [:]
    private var lastFitToken: Int = -1
    private var lastZoomToken: Int = 0
    private var lastBranchZoomToken: Int = -1
    private var lastCenterToken: Int = 0
    private var pendingBranchZoomID: UUID?
    private var pendingFitAll = false
    private var hasFitted = false
    private var fitBoundsSize: CGSize = .zero
    private var userHasInteracted = false
    private var searchMatches: Set<UUID> = []
    private var activeSearchID: UUID?
    private var marqueeRect: CGRect?
    private var snapGuides: [SnapGuide] = []
    private var hoveredControlID: UUID?
    private var trackingArea: NSTrackingArea?
    private var collapsedSnapshot: [UUID: Bool] = [:]
    private var collapseFade: CollapseFade?
    private var ghostAlpha: CGFloat = 0
    private var alphaOverrides: [UUID: CGFloat] = [:]

    private var drag: DragState?
    private var dragOffset: CGSize = .zero
    private var dropTargetID: UUID?
    private var editTextView: NSTextView?
    private var editingID: UUID?
    private var editingOriginalText = ""
    /// 当前就地编辑器已经应用过的字号，用于避免每次按键都重设整段属性
    private var appliedEditingFont: NSFont?
    /// 组字（marked text）不会触发 textDidChange，靠子类回调补上
    private final class EditingTextView: NSTextView {
        var onMarkedTextChange: (() -> Void)?

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onMarkedTextChange?()
        }

        override func unmarkText() {
            super.unmarkText()
            onMarkedTextChange?()
        }
    }

    private enum DragState {
        case pan(startPoint: CGPoint, startCenter: CGPoint)
        case node(id: UUID, startPoint: CGPoint, originalFrame: CGRect)
        case marquee(startPoint: CGPoint, base: Set<UUID>)
    }

    private struct FrameAnimation {
        let from: [UUID: CGRect]
        let to: [UUID: CGRect]
        let startTime: TimeInterval
        let duration: TimeInterval
        /// 每个节点自己的起步延迟（按层级错峰）
        let delays: [UUID: TimeInterval]
        let maxDelay: TimeInterval
    }

    private struct CollapseFade {
        let startTime: TimeInterval
        let duration: TimeInterval
        let ghostFrames: [UUID: CGRect]
        let ghostLevels: [UUID: Int]
        let fadeIn: Set<UUID>
        /// 新出现节点的淡入延迟，跟落位动画保持同一套层级错峰
        let delays: [UUID: TimeInterval]
        let maxDelay: TimeInterval
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(loc("思维导图画布"))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Attach

    func attach(editor: MapEditor, theme: MapTheme) {
        if self.editor !== editor {
            self.editor = editor
            layoutResult = nil
            layoutRevision = -1
            layoutDocumentID = nil
            lastFitToken = -1
            lastZoomToken = 0
            lastBranchZoomToken = -1
            lastCenterToken = editor.centerToken
            pendingBranchZoomID = nil
            pendingFitAll = false
            hasFitted = false
            fitBoundsSize = .zero
            userHasInteracted = false
            camera = CanvasCamera()
            stopFrameAnimation()
            displayFrames = [:]
            collapsedSnapshot = [:]
            stopDashTimer()
            cancelEditing()
            searchMatches = []
            activeSearchID = nil
            marqueeRect = nil
            snapGuides = []
            notifyZoomChanged()
        }
        self.theme = theme
        rebuildLayoutIfNeeded()
        syncEditorWithModel(editor)
        if let activeEditor = self.editor, activeEditor.zoomToken != lastZoomToken {
            lastZoomToken = activeEditor.zoomToken
            zoom(by: activeEditor.zoomFactor, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
        applyPendingBranchZoomIfPossible()
        applyPendingCenterIfPossible()
        needsDisplay = true
    }

    /// 撤销 / 重做 / 删除之后，编辑器要和模型对齐：
    /// 节点没了就收起编辑器（否则会留下一段漂浮的文字），内容变了就同步文字。
    private func syncEditorWithModel(_ editor: MapEditor) {
        guard let id = editingID else { return }
        guard let node = editor.map.node(id), layoutResult?.frames[id] != nil else {
            cancelEditing()
            return
        }
        guard let textView = editTextView, textView.string != node.text else { return }
        textView.string = node.text
        appliedEditingFont = nil
        updateEditorFrame()
    }

    // MARK: - Layout cache

    private func rebuildLayoutIfNeeded(force: Bool = false) {
        guard let editor else { return }
        if layoutDocumentID != editor.map.id {
            collapsedSnapshot = [:]
        }
        let previousLayout = layoutResult
        let previousCollapsed = collapsedSnapshot

        if force || layoutResult == nil || layoutRevision != editor.revision || layoutDocumentID != editor.map.id {
            let newLayout = LayoutEngine.layout(editor.map)
            var newSnapshot: [UUID: Bool] = [:]
            newSnapshot.reserveCapacity(editor.map.nodes.count)
            for node in editor.map.nodes { newSnapshot[node.id] = node.collapsed }
            layoutResult = newLayout
            layoutRevision = editor.revision
            layoutDocumentID = editor.map.id

            let toggled = previousCollapsed.compactMap { id, old -> UUID? in
                guard let new = newSnapshot[id], new != old else { return nil }
                return id
            }

            if !toggled.isEmpty, let previousLayout, animationsAllowed, drag == nil {
                beginCollapseTransition(
                    from: previousLayout,
                    to: newLayout,
                    toggled: toggled,
                    newSnapshot: newSnapshot,
                    editor: editor
                )
            } else if frameAnimation == nil && collapseFade == nil && drag == nil {
                displayFrames = newLayout.frames
            }
            collapsedSnapshot = newSnapshot
        }
        if editor.fitToken != lastFitToken {
            lastFitToken = editor.fitToken
            if bounds.width > 40, bounds.height > 40 {
                fitToContent()
            } else {
                hasFitted = false
            }
        }
        if editor.branchZoomToken != lastBranchZoomToken {
            lastBranchZoomToken = editor.branchZoomToken
            pendingBranchZoomID = editor.branchZoomNodeID ?? nil
            applyPendingBranchZoomIfPossible()
        }
    }

    private func beginCollapseTransition(
        from oldLayout: LayoutResult,
        to newLayout: LayoutResult,
        toggled: [UUID],
        newSnapshot: [UUID: Bool],
        editor: MapEditor
    ) {
        var ghostFrames: [UUID: CGRect] = [:]
        var ghostLevels: [UUID: Int] = [:]
        var fadeIn: Set<UUID> = []

        // 从屏幕当前可见的位置续接，而不是上一段动画的终点：
        // 连点时画面不会先跳回终点再重新插值
        var startFrames = displayFrames
        if startFrames.isEmpty {
            startFrames = oldLayout.frames
        } else {
            for (id, rect) in oldLayout.frames where startFrames[id] == nil {
                startFrames[id] = rect
            }
        }

        for id in toggled {
            let descendants = descendantIDs(of: id, in: editor.map)
            if newSnapshot[id] == true {
                for child in descendants {
                    if let frame = startFrames[child] ?? oldLayout.frames[child] {
                        ghostFrames[child] = frame
                        ghostLevels[child] = oldLayout.depths[child] ?? 2
                    }
                }
            } else {
                for child in descendants where oldLayout.frames[child] == nil && newLayout.frames[child] != nil {
                    fadeIn.insert(child)
                }
            }
        }

        // 重新开始一段转场，避免叠加旧动画
        frameAnimation = nil
        stopAnimationTimer()
        displayFrames = startFrames

        if ghostFrames.isEmpty && fadeIn.isEmpty {
            collapseFade = nil
            ghostAlpha = 0
            alphaOverrides = [:]
        } else {
            // 新出现的节点等邻居先落位再淡入，避免刚亮起来就被别的节点压住
            var fadeDelays: [UUID: TimeInterval] = [:]
            for id in fadeIn {
                fadeDelays[id] = CanvasMotion.delay(forDepth: newLayout.depths[id] ?? 0) + 0.02
            }
            collapseFade = CollapseFade(
                startTime: ProcessInfo.processInfo.systemUptime,
                duration: 0.18,
                ghostFrames: ghostFrames,
                ghostLevels: ghostLevels,
                fadeIn: fadeIn,
                delays: fadeDelays,
                maxDelay: fadeDelays.values.max() ?? 0
            )
            ghostAlpha = ghostFrames.isEmpty ? 0 : 1
            alphaOverrides = Dictionary(uniqueKeysWithValues: fadeIn.map { ($0, 0) })
        }

        animateFrames(from: startFrames, to: newLayout.frames, duration: 0.24)
        if collapseFade != nil && animationTimer == nil {
            startAnimationTimer()
        }
    }

    private func descendantIDs(of id: UUID, in map: MindMap) -> [UUID] {
        var result: [UUID] = []
        var stack = map.children(of: id).map(\.id)
        while let current = stack.popLast(), result.count < 5000 {
            result.append(current)
            stack.append(contentsOf: map.children(of: current).map(\.id))
        }
        return result
    }

    private func applyPendingBranchZoomIfPossible() {
        guard bounds.width >= 320, bounds.height >= 240 else { return }
        if pendingFitAll {
            pendingFitAll = false
            fitSubtree(nil)
            return
        }
        guard let id = pendingBranchZoomID else { return }
        pendingBranchZoomID = nil
        fitSubtree(id)
    }

    /// 只把某个分支缩放到画布合适大小；id 为 nil 时适配整图
    func fitSubtree(_ id: UUID?) {
        rebuildLayoutIfNeeded(force: true)
        guard bounds.width >= 320, bounds.height >= 240 else {
            if let id {
                pendingBranchZoomID = id
            } else {
                pendingFitAll = true
            }
            return
        }
        guard let editor, let layout = layoutResult else { return }
        let ids = id.map { editor.map.subtreeIDs(of: $0) } ?? Set(layout.frames.keys)
        guard !ids.isEmpty else { return }
        var union: CGRect = .null
        for nodeID in ids {
            if let frame = layout.frames[nodeID] {
                union = union.union(frame)
            }
        }
        guard !union.isNull, union.width > 0, union.height > 0 else { return }
        let padding: CGFloat = 96
        let availableWidth = max(bounds.width - padding * 2, 100)
        let availableHeight = max(bounds.height - padding * 2, 100)
        let scale = min(availableWidth / union.width, availableHeight / union.height)
        camera.zoom = min(max(scale, CanvasCamera.minZoom), min(CanvasCamera.maxZoom, 1.8))
        camera.center = CGPoint(x: union.midX, y: union.midY)
        userHasInteracted = true
        hasFitted = true
        fitBoundsSize = bounds.size
        updateEditorFrame()
        needsDisplay = true
        notifyZoomChanged()
    }

    /// 专注模式 / 演示模式：设置焦点并（可选）把分支缩放适配
    func focusSubtree(_ id: UUID?, fit: Bool = true) {
        guard let editor else { return }
        editor.setFocus(id)
        if fit {
            fitSubtree(id)
        } else {
            needsDisplay = true
        }
    }

    /// 搜索定位：先展开折叠的祖先，再把节点放进可视区域
    func revealNode(_ id: UUID) {
        guard let editor, editor.map.node(id) != nil else { return }
        editor.expandAncestors(of: id)
        rebuildLayoutIfNeeded(force: true)
        ensureVisible(id)
        needsDisplay = true
    }

    func setSearchResults(_ ids: Set<UUID>, active: UUID?) {
        guard ids != searchMatches || active != activeSearchID else { return }
        searchMatches = ids
        activeSearchID = active
        needsDisplay = true
    }

    func fitToContent() {
        guard bounds.width >= 320, bounds.height >= 240 else {
            hasFitted = false
            return
        }
        guard let layout = layoutResult, !layout.bounds.isEmpty else { return }
        let padding: CGFloat = 72
        let availableWidth = max(bounds.width - padding * 2, 100)
        let availableHeight = max(bounds.height - padding * 2, 100)
        let scale = min(availableWidth / max(layout.bounds.width, 1), availableHeight / max(layout.bounds.height, 1))
        camera.zoom = min(max(scale, CanvasCamera.minZoom), 1.35)
        camera.center = CGPoint(x: layout.bounds.midX, y: layout.bounds.midY)
        hasFitted = true
        fitBoundsSize = bounds.size
        updateEditorFrame()
        needsDisplay = true
        notifyZoomChanged()
    }

    /// 直接设置缩放（以视图中心为锚点，中心指向的世界坐标保持不变）
    func setZoom(_ value: CGFloat) {
        userHasInteracted = true
        if editingID != nil { commitEditing() }
        let clamped = min(max(value, CanvasCamera.minZoom), CanvasCamera.maxZoom)
        guard abs(clamped - camera.zoom) > 0.0005 else { return }
        camera.zoom = clamped
        updateEditorFrame()
        needsDisplay = true
        notifyZoomChanged()
    }

    /// 把整张导图水平、垂直居中到画布
    func centerContent() {
        rebuildLayoutIfNeeded()
        guard let layout = layoutResult, !layout.bounds.isEmpty else { return }
        userHasInteracted = true
        camera.center = CGPoint(x: layout.bounds.midX, y: layout.bounds.midY)
        updateEditorFrame()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // 模型可能刚发生变化（例如从属性面板新增节点），layout 阶段先把布局跑出来，
        // 后面的 fit / 居中请求才能拿到新节点坐标。
        rebuildLayoutIfNeeded()
        if bounds.width > 40, bounds.height > 40 {
            if !hasFitted {
                rebuildLayoutIfNeeded(force: true)
                fitToContent()
            } else if !userHasInteracted,
                      fitBoundsSize.width > 0,
                      abs(bounds.width - fitBoundsSize.width) > 4
                        || abs(bounds.height - fitBoundsSize.height) > 4 {
                // 用户还没动过画布时，「适配」是一种持续状态：
                // 启动阶段画布会先按较窄的宽度适配一次，等侧栏 / 属性面板就位后宽度还会变，
                // 原来只在「变宽超过 25%」时重算，21% 的变化就被漏掉了，整张图一直偏小。
                rebuildLayoutIfNeeded(force: true)
                fitToContent()
            }
            applyPendingBranchZoomIfPossible()
            applyPendingCenterIfPossible()
        }
        updateEditorFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
        observeAccessibilityDisplayOptions()
    }

    private func observeAccessibilityDisplayOptions() {
        guard accessibilityObserver == nil else { return }
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accessibilityDisplayOptionsDidChange()
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            // Timer 会强引用 target；视图离开窗口时不停掉，拖拽 / 动画中的
            // timer 会一直把画布留在内存里。
            stopAnimationTimer()
            stopDashTimer()
            if let observer = accessibilityObserver {
                NotificationCenter.default.removeObserver(observer)
                accessibilityObserver = nil
            }
        }
    }

    // MARK: - Accessibility

    override func accessibilityChildren() -> [Any]? {
        guard let editor, let layout = layoutResult else {
            return super.accessibilityChildren()
        }
        let validIDs = Set(layout.drawOrder)
        nodeAccessibilityElements = nodeAccessibilityElements.filter { validIDs.contains($0.key) }

        var nodesByID: [UUID: MindNode] = [:]
        nodesByID.reserveCapacity(editor.map.nodes.count)
        for node in editor.map.nodes { nodesByID[node.id] = node }

        var elements: [MindNodeAccessibilityElement] = []
        for id in layout.drawOrder {
            guard let node = nodesByID[id], let frame = layout.frames[id] else { continue }
            let element = nodeAccessibilityElements[id] ?? makeAccessibilityElement(for: id)
            let children = layout.children[id]?.count ?? 0
            var label = NodeMeasurer.displayText(node)
            label += String(format: loc("，%lld 个子主题"), children)
            if node.collapsed, children > 0 { label += loc("，已折叠") }
            if !node.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { label += loc("，有备注") }
            if let icon = node.icon, let name = IconCatalog.all.first(where: { $0.symbol == icon })?.name {
                label += String(format: loc("，图标 %@"), name)
            }
            element.setAccessibilityLabel(label)
            element.setAccessibilityFrame(screenRect(for: frame))
            element.setAccessibilitySelected(editor.selection.contains(id))
            elements.append(element)
        }
        return elements
    }

    private func makeAccessibilityElement(for id: UUID) -> MindNodeAccessibilityElement {
        let element = MindNodeAccessibilityElement()
        element.canvas = self
        element.nodeID = id
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(.button)
        element.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: loc("选中节点")) { [weak self] in
                self?.selectNodeForAccessibility(id)
                return true
            },
            NSAccessibilityCustomAction(name: loc("折叠 / 展开")) { [weak self] in
                guard let self, let editor = self.editor else { return false }
                editor.toggleCollapse(id)
                self.needsDisplay = true
                return true
            }
        ])
        nodeAccessibilityElements[id] = element
        return element
    }

    private func selectNodeForAccessibility(_ id: UUID) {
        guard let editor, editor.map.node(id) != nil else { return }
        editor.select(id)
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
    }

    private func screenRect(for worldFrame: CGRect) -> NSRect {
        let viewRect = worldRectToView(worldFrame)
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? .zero
    }

    private func accessibilityDisplayOptionsDidChange() {
        guard !animationsAllowed else { return }
        stopFrameAnimation()
        stopDashTimer()
        displayFrames = layoutResult?.frames ?? [:]
        needsDisplay = true
    }

    private var animationsAllowed: Bool {
        CanvasMotion.allowsAnimation(nodeCount: layoutResult?.frames.count ?? 0)
    }

    // MARK: - Coordinate conversion

    func worldToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - camera.center.x) * camera.zoom + bounds.midX,
            y: (point.y - camera.center.y) * camera.zoom + bounds.midY
        )
    }

    func viewToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - bounds.midX) / camera.zoom + camera.center.x,
            y: (point.y - bounds.midY) / camera.zoom + camera.center.y
        )
    }

    private func worldRectToView(_ rect: CGRect) -> CGRect {
        let origin = worldToView(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * camera.zoom, height: rect.height * camera.zoom)
    }

    private var visibleWorldRect: CGRect {
        let width = bounds.width / camera.zoom
        let height = bounds.height / camera.zoom
        return CGRect(x: camera.center.x - width / 2, y: camera.center.y - height / 2, width: width, height: height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let editor else {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            return
        }
        rebuildLayoutIfNeeded()
        applyPendingCenterIfPossible()

        MapRenderer.drawBackground(theme: theme, in: bounds)
        guard let layout = layoutResult, let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: camera.zoom, y: camera.zoom)
        context.translateBy(x: -camera.center.x, y: -camera.center.y)

        drawGrid(in: context)

        var renderLayout = layout
        if !displayFrames.isEmpty {
            // 动画帧里可能还没有刚新建的节点，补上终态坐标，避免新节点“只有文字没有框”
            var frames = displayFrames
            for (id, rect) in layout.frames where frames[id] == nil {
                frames[id] = rect
            }
            renderLayout.frames = frames
        }
        MapRenderer.draw(
            map: editor.map,
            layout: renderLayout,
            theme: theme,
            selection: RenderSelection(
                ids: editor.selection,
                dragNodeID: dragNodeID,
                dragOffset: dragOffset,
                dimmed: dimmedNodeIDs(),
                dimAlpha: focusDimAlpha,
                dropTargetID: dropTargetID,
                dashPhase: dashPhase,
                editingNodeID: editingID,
                searchMatches: searchMatches,
                activeSearchID: activeSearchID,
                collapseControlIDs: collapseControlIDs,
                activeCollapseControlID: activeCollapseControlID,
                ghostFrames: collapseFade?.ghostFrames ?? [:],
                ghostLevels: collapseFade?.ghostLevels ?? [:],
                ghostAlpha: ghostAlpha,
                alphaOverrides: alphaOverrides
            ),
            visibleRect: visibleWorldRect.insetBy(dx: -120, dy: -120),
            in: context
        )
        drawSnapGuides(in: context)
        context.restoreGState()
        drawMarquee()
    }

    private func dimmedNodeIDs() -> Set<UUID> {
        guard let editor, let focusID = editor.focusNodeID else { return [] }
        let focusIDs = editor.map.subtreeIDs(of: focusID)
        guard !focusIDs.isEmpty else { return [] }
        return Set(editor.map.nodes.map(\.id)).subtracting(focusIDs)
    }

    private func drawSnapGuides(in context: CGContext) {
        guard !snapGuides.isEmpty else { return }
        let width = 1 / max(camera.zoom, 0.1)
        context.setLineWidth(width)
        context.setStrokeColor(theme.accent.withAlphaComponent(0.75).cgColor)
        context.setLineDash(phase: 0, lengths: [5 / max(camera.zoom, 0.1), 4 / max(camera.zoom, 0.1)])
        for guide in snapGuides {
            switch guide.axis {
            case .vertical:
                context.move(to: CGPoint(x: guide.position, y: guide.start))
                context.addLine(to: CGPoint(x: guide.position, y: guide.end))
            case .horizontal:
                context.move(to: CGPoint(x: guide.start, y: guide.position))
                context.addLine(to: CGPoint(x: guide.end, y: guide.position))
            }
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawMarquee() {
        guard let rect = marqueeRect else { return }
        theme.accent.withAlphaComponent(0.10).setFill()
        rect.fill()
        theme.accent.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
    }

    private var dragNodeID: UUID? {
        if case .node(let id, _, _)? = drag { return id }
        return nil
    }

    private func drawGrid(in context: CGContext) {
        guard theme.showsGrid, camera.zoom > 0.4 else { return }
        let step = 26 / camera.zoom
        let rect = visibleWorldRect
        let startX = floor(rect.minX / step) * step
        let startY = floor(rect.minY / step) * step
        let radius = 0.9 / camera.zoom
        theme.grid.withAlphaComponent(0.85).setFill()

        var x = startX
        var count = 0
        while x <= rect.maxX {
            var y = startY
            while y <= rect.maxY {
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                y += step
                count += 1
                if count > 5000 { return }
            }
            x += step
        }
    }

    // MARK: - Hit testing

    /// 命中测试用的布局：落位动画期间节点在屏幕上处于插值位置，
    /// 这时必须按可见位置判断，否则连点会点在“上一帧看到、但已经不是终态”的地方。
    private var hitTestLayout: LayoutResult? {
        guard var layout = layoutResult else { return nil }
        if frameAnimation != nil, !displayFrames.isEmpty {
            layout.frames = displayFrames
        }
        return layout
    }

    private func hitTest(worldPoint: CGPoint, excluding: UUID? = nil) -> UUID? {
        guard let layout = hitTestLayout else { return nil }
        for id in layout.drawOrder.reversed() {
            if id == excluding { continue }
            if layout.frames[id]?.contains(worldPoint) == true { return id }
        }
        return nil
    }

    private func hitTest(viewPoint: CGPoint, excluding: UUID? = nil) -> UUID? {
        hitTest(worldPoint: viewToWorld(viewPoint), excluding: excluding)
    }

    private var hoveredConnectorParentID: UUID?
    /// 鼠标当前所在节点：悬停即可显示折叠控件，不必先点选
    private var hoveredNodeID: UUID?
    private var cursorIsPointing = false

    private func hasChildren(_ id: UUID) -> Bool {
        layoutResult?.children[id]?.isEmpty == false
    }

    private var collapseControlIDs: Set<UUID> {
        guard !isReadOnly, drag == nil, editingID == nil, let editor else { return [] }
        var ids = Set<UUID>()
        if editor.selection.count == 1,
           let id = editor.selection.first,
           hasChildren(id) {
            ids.insert(id)
        }
        if let hoveredNodeID, hasChildren(hoveredNodeID) {
            ids.insert(hoveredNodeID)
        }
        if let hoveredConnectorParentID, hasChildren(hoveredConnectorParentID) {
            ids.insert(hoveredConnectorParentID)
        }
        // 已折叠的分支常驻显示（+ 和隐藏数量），不用悬停也能一眼看出来哪里收起了
        for node in editor.map.nodes where node.collapsed && hasChildren(node.id) {
            ids.insert(node.id)
        }
        return ids
    }

    private var activeCollapseControlID: UUID? {
        let visible = collapseControlIDs
        if let hoveredControlID, visible.contains(hoveredControlID) { return hoveredControlID }
        if let hoveredConnectorParentID, visible.contains(hoveredConnectorParentID) { return hoveredConnectorParentID }
        if let hoveredNodeID, visible.contains(hoveredNodeID) { return hoveredNodeID }
        guard editor?.selection.count == 1,
              let id = editor?.selection.first,
              visible.contains(id) else { return nil }
        return id
    }

    private func collapseControlID(at worldPoint: CGPoint) -> UUID? {
        guard let editor, let layout = hitTestLayout else { return nil }
        let nodeUnderPoint = hitTest(worldPoint: worldPoint)
        var best: (id: UUID, distance: CGFloat, onVisibleCircle: Bool)?
        for id in collapseControlIDs {
            guard let center = NodeControlGeometry.collapseControlCenter(for: id, in: editor.map, layout: layout) else { continue }
            let distance = hypot(worldPoint.x - center.x, worldPoint.y - center.y)
            // 圆本身画在节点之上，点中看得见的圆就优先当作点控件；
            // 小缩放下额外放大的命中区不能抢走节点点击（节点命中时只认可见圆）。
            let onVisibleCircle = distance <= NodeControlGeometry.radius
            if !onVisibleCircle {
                guard nodeUnderPoint == nil, distance <= controlHitRadius else { continue }
            }
            if best == nil
                || (onVisibleCircle && !best!.onVisibleCircle)
                || (onVisibleCircle == best!.onVisibleCircle && distance < best!.distance) {
                best = (id, distance, onVisibleCircle)
            }
        }
        return best?.id
    }

    /// 控件命中半径：等于「看得见的圆」，并保证至少 12pt 的屏幕面积。
    /// 放大的上限由可见半径决定，免得高缩放下一大圈看不见的命中区误伤附近的点击。
    private var controlHitRadius: CGFloat {
        max(NodeControlGeometry.radius, 12 / max(camera.zoom, CanvasCamera.minZoom))
    }

    /// 节点边缘到折叠控件圆心之间的走廊：鼠标经过这里时保持控件可见
    private func isOnControlBridge(
        _ point: CGPoint,
        for id: UUID,
        in map: MindMap,
        layout: LayoutResult
    ) -> Bool {
        guard let frame = layout.frames[id],
              let center = NodeControlGeometry.collapseControlCenter(for: id, in: map, layout: layout) else {
            return false
        }
        let anchor = CGPoint(
            x: min(max(center.x, frame.minX), frame.maxX),
            y: min(max(center.y, frame.minY), frame.maxY)
        )
        let dx = center.x - anchor.x
        let dy = center.y - anchor.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.01 else { return false }
        let t = min(max(((point.x - anchor.x) * dx + (point.y - anchor.y) * dy) / lengthSquared, 0), 1)
        let nearest = CGPoint(x: anchor.x + dx * t, y: anchor.y + dy * t)
        return hypot(point.x - nearest.x, point.y - nearest.y) <= controlHitRadius
    }

    private func updateHoveredControl(at worldPoint: CGPoint) {
        guard !isReadOnly, drag == nil, let editor, let layout = hitTestLayout else { return }

        // 节点与 +/- 控件之间有 9pt 空隙，只按节点矩形判定的话，
        // 鼠标一离开节点控件就会消失，所以把这段走廊也算进悬停区域。
        let nodeUnderCursor = hitTest(worldPoint: worldPoint)
        let nextHovered: UUID?
        if let nodeUnderCursor {
            nextHovered = nodeUnderCursor
        } else if let current = hoveredNodeID,
                  isOnControlBridge(worldPoint, for: current, in: editor.map, layout: layout) {
            nextHovered = current
        } else {
            nextHovered = nil
        }
        if nextHovered != hoveredNodeID {
            hoveredNodeID = nextHovered
            needsDisplay = true
        }

        if let hit = collapseControlID(at: worldPoint) {
            let changed = hoveredControlID != hit
            hoveredControlID = hit
            let selectedID = editor.selection.count == 1 ? editor.selection.first : nil
            if hit != hoveredConnectorParentID, hit != selectedID {
                hoveredConnectorParentID = nil
            }
            setPointingCursor(true)
            if changed { needsDisplay = true }
            return
        }

        setPointingCursor(false)
        let tolerance = 10 / max(camera.zoom, 0.2)
        let parent = MapRenderer.connectorParent(
            at: worldPoint,
            map: editor.map,
            layout: layout,
            tolerance: tolerance
        )
        let changed = parent != hoveredConnectorParentID || hoveredControlID != nil
        hoveredControlID = nil
        hoveredConnectorParentID = parent
        if changed { needsDisplay = true }
    }

    /// 悬停在 +/− 上换成手型指针：画布整体是箭头，不给反馈很难发现这里可点
    private func setPointingCursor(_ pointing: Bool) {
        guard cursorIsPointing != pointing else { return }
        cursorIsPointing = pointing
        (pointing ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoveredControl(at: viewToWorld(point))
    }

    override func mouseExited(with event: NSEvent) {
        setPointingCursor(false)
        guard hoveredControlID != nil || hoveredConnectorParentID != nil || hoveredNodeID != nil else { return }
        hoveredControlID = nil
        hoveredConnectorParentID = nil
        hoveredNodeID = nil
        needsDisplay = true
    }

    // MARK: - Mouse

    /// 双击空白：新建一个头部节点并直接进入编辑。
    /// 自由布局会把头部放在双击位置，其它布局按顺序追加到头部列表末尾。
    private func addHeadAtEmptySpace(at worldPoint: CGPoint) {
        guard let editor else { return }
        let position = editor.map.layout == .free ? worldPoint : nil
        guard let newID = editor.addRoot(at: position) else { return }
        rebuildLayoutIfNeeded(force: true)
        centerOnNode(newID)
        needsDisplay = true
        beginEditing(newID)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        userHasInteracted = true
        if editingID != nil { commitEditing() }

        let point = convert(event.locationInWindow, from: nil)
        let worldPoint = viewToWorld(point)

        if isReadOnly {
            drag = .pan(startPoint: point, startCenter: camera.center)
            return
        }

        // 折叠控件是开关：每次按下都应该翻转，不能因为系统把连续点击合并成
        // clickCount 2/3/4 就丢弃中间那些点击。这里也不提前中断落位动画，
        // 交给新的转场从当前可见位置续接，连点才会跟手。
        if let editor, let controlID = collapseControlID(at: worldPoint) {
            editor.toggleCollapse(controlID)
            needsDisplay = true
            return
        }

        // 这里不再 stopFrameAnimation()：点在节点/空白处只是选择，不该让整张图瞬间落位。
        // 真正开始拖拽时才会收口（见 mouseDragged）。
        if event.clickCount == 2 {
            if let id = hitTest(worldPoint: worldPoint) {
                beginEditing(id)
            } else {
                addHeadAtEmptySpace(at: worldPoint)
            }
            return
        }

        if let id = hitTest(worldPoint: worldPoint) {
            hoveredConnectorParentID = nil
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            editor?.select(id, additive: additive)
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
            if let frame = currentVisualFrames()[id] ?? layoutResult?.frames[id] {
                drag = .node(id: id, startPoint: point, originalFrame: frame)
                dragOffset = .zero
                snapGuides = []
                startDashTimer()
            }
            needsDisplay = true
        } else {
            if event.modifierFlags.contains(.shift) {
                let base = editor?.selection ?? []
                drag = .marquee(startPoint: point, base: base)
                marqueeRect = CGRect(origin: point, size: .zero)
            } else {
                editor?.clearSelection()
                hoveredControlID = nil
                hoveredConnectorParentID = nil
                NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
                drag = .pan(startPoint: point, startCenter: camera.center)
            }
            stopDashTimer()
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .pan(let startPoint, let startCenter):
            camera.center.x = startCenter.x - (point.x - startPoint.x) / camera.zoom
            camera.center.y = startCenter.y - (point.y - startPoint.y) / camera.zoom
            updateEditorFrame()
            needsDisplay = true
        case .node(let id, let startPoint, let originalFrame):
            // 真正开始拖拽才让落位动画收口，选择/双击都不打断它
            if frameAnimation != nil || collapseFade != nil { stopFrameAnimation() }
            var offset = CGSize(
                width: (point.x - startPoint.x) / camera.zoom,
                height: (point.y - startPoint.y) / camera.zoom
            )
            if editor?.map.layout == .free {
                snapGuides = []
                if !event.modifierFlags.contains(.command), let layout = layoutResult {
                    let moving = originalFrame.offsetBy(dx: offset.width, dy: offset.height)
                    let others = layout.frames
                        .filter { $0.key != id }
                        .map(\.value)
                    let result = FreeLayoutSnap.snap(
                        movingFrame: moving,
                        otherFrames: others,
                        threshold: 7 / max(camera.zoom, 0.1)
                    )
                    offset.width += result.dx
                    offset.height += result.dy
                    snapGuides = result.guides
                }
                dropTargetID = nil
            } else {
                let world = viewToWorld(point)
                let target = hitTest(worldPoint: world, excluding: id)
                dropTargetID = target.flatMap { canDrop(id, on: $0) ? $0 : nil }
            }
            dragOffset = offset
            needsDisplay = true
        case .marquee(let startPoint, let base):
            let rect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
            marqueeRect = rect
            if let layout = layoutResult {
                let worldRect = CGRect(
                    x: viewToWorld(CGPoint(x: rect.minX, y: rect.minY)).x,
                    y: viewToWorld(CGPoint(x: rect.minX, y: rect.minY)).y,
                    width: rect.width / camera.zoom,
                    height: rect.height / camera.zoom
                )
                let hits = layout.frames.filter { $0.value.intersects(worldRect) }.map(\.key)
                editor?.setSelection(base.union(hits))
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        switch drag {
        case .pan:
            self.drag = nil
            needsDisplay = true
        case .node(let id, _, let originalFrame):
            finishNodeDrag(id: id, originalFrame: originalFrame, event: event)
        case .marquee:
            self.drag = nil
            marqueeRect = nil
            needsDisplay = true
        }
    }

    private func finishNodeDrag(id: UUID, originalFrame: CGRect, event: NSEvent) {
        let startFrames = currentVisualFrames()
        let offset = dragOffset
        let target = dropTargetID
        dropTargetID = nil
        stopDashTimer()

        // 自由布局：直接按拖动位移落位
        if editor?.map.layout == .free {
            if abs(offset.width) > 1 || abs(offset.height) > 1 {
                let origin = CGPoint(x: originalFrame.minX + offset.width, y: originalFrame.minY + offset.height)
                editor?.moveFreeNode(id: id, to: origin)
                rebuildLayoutIfNeeded(force: true)
                endNodeDrag()
                animateFrames(from: startFrames, to: layoutResult?.frames ?? [:], duration: 0.2)
            } else {
                endNodeDrag()
            }
            return
        }

        guard let target,
              let editor,
              let sourceNode = editor.map.node(id),
              let targetNode = editor.map.node(target) else {
            snapBack(from: startFrames)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let world = viewToWorld(point)
        let targetFrame = layoutResult?.frames[target] ?? .zero
        let relativeY = targetFrame.height > 0
            ? (world.y - targetFrame.minY) / targetFrame.height
            : 0.5
        var didChange = false

        // 默认拖到节点上 = 挂到该节点下面；按住 ⌥ 再拖到同级节点 = 调整兄弟顺序
        if event.modifierFlags.contains(.option), sourceNode.parentID == targetNode.parentID {
            editor.reorder(id: id, relativeTo: target, after: relativeY > 0.5)
            didChange = true
        } else if editor.canMove(id, to: target) {
            editor.move(id: id, to: target)
            didChange = true
        }

        if didChange {
            rebuildLayoutIfNeeded(force: true)
            endNodeDrag()
            animateFrames(from: startFrames, to: layoutResult?.frames ?? [:], duration: 0.24)
        } else {
            snapBack(from: startFrames)
        }
    }

    private func snapBack(from frames: [UUID: CGRect]) {
        endNodeDrag()
        guard let target = layoutResult?.frames else { return }
        animateFrames(from: frames, to: target, duration: 0.18)
    }

    private func endNodeDrag() {
        drag = nil
        dragOffset = .zero
        dropTargetID = nil
        snapGuides = []
        stopDashTimer()
        needsDisplay = true
    }

    /// 当前屏幕上看到的节点位置（含正在拖动的偏移），用于作为落位动画的起点
    private func currentVisualFrames() -> [UUID: CGRect] {
        var frames = displayFrames
        if frames.isEmpty { frames = layoutResult?.frames ?? [:] }
        if case .node(let id, _, _)? = drag, let base = frames[id] {
            frames[id] = base.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
        }
        return frames
    }

    private func animateFrames(from: [UUID: CGRect], to: [UUID: CGRect], duration: TimeInterval) {
        guard !to.isEmpty else {
            displayFrames = to
            return
        }
        guard animationsAllowed else {
            displayFrames = to
            frameAnimation = nil
            collapseFade = nil
            ghostAlpha = 0
            alphaOverrides = [:]
            stopAnimationTimer()
            needsDisplay = true
            return
        }
        var start = from
        for (id, rect) in to where start[id] == nil {
            start[id] = rect
        }
        guard hasMovement(from: start, to: to) else {
            displayFrames = to
            frameAnimation = nil
            stopAnimationTimer()
            needsDisplay = true
            return
        }

        displayFrames = start
        var delays: [UUID: TimeInterval] = [:]
        delays.reserveCapacity(to.count)
        for id in to.keys {
            delays[id] = CanvasMotion.delay(forDepth: layoutResult?.depths[id] ?? 0)
        }
        frameAnimation = FrameAnimation(
            from: start,
            to: to,
            startTime: ProcessInfo.processInfo.systemUptime,
            duration: max(duration, 0.01),
            delays: delays,
            maxDelay: delays.values.max() ?? 0
        )
        startAnimationTimer()
        needsDisplay = true
    }

    private func hasMovement(from: [UUID: CGRect], to: [UUID: CGRect]) -> Bool {
        for (id, target) in to {
            let start = from[id] ?? target
            if abs(start.minX - target.minX) > 0.5
                || abs(start.minY - target.minY) > 0.5
                || abs(start.width - target.width) > 0.5
                || abs(start.height - target.height) > 0.5 {
                return true
            }
        }
        return false
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: CanvasMotion.frameInterval(nodeCount: layoutResult?.frames.count ?? 0),
            target: self,
            selector: #selector(animationTick(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func animationTick(_ timer: Timer) {
        let now = ProcessInfo.processInfo.systemUptime

        if let animation = frameAnimation {
            let elapsed = now - animation.startTime

            var frames: [UUID: CGRect] = [:]
            frames.reserveCapacity(animation.to.count)
            for (id, target) in animation.to {
                let start = animation.from[id] ?? target
                let delay = animation.delays[id] ?? 0
                let eased = CanvasMotion.easeOutCubic((elapsed - delay) / animation.duration)
                frames[id] = CGRect(
                    x: start.minX + (target.minX - start.minX) * eased,
                    y: start.minY + (target.minY - start.minY) * eased,
                    width: start.width + (target.width - start.width) * eased,
                    height: start.height + (target.height - start.height) * eased
                )
            }
            displayFrames = frames

            if elapsed >= animation.duration + animation.maxDelay {
                displayFrames = animation.to
                frameAnimation = nil
            }
        }

        if let fade = collapseFade {
            let elapsed = now - fade.startTime
            let progress = min(max(elapsed / fade.duration, 0), 1)
            // 淡出用线性：缓出会让残影在前 1/3 就几乎消失，看起来像“闪一下”
            ghostAlpha = fade.ghostFrames.isEmpty ? 0 : CGFloat(1 - progress)

            var overrides: [UUID: CGFloat] = [:]
            var allFadedIn = true
            for id in fade.fadeIn {
                let delay = fade.delays[id] ?? 0
                let alpha = CanvasMotion.easeOutCubic((elapsed - delay) / fade.duration)
                overrides[id] = alpha
                if alpha < 0.999 { allFadedIn = false }
            }
            alphaOverrides = overrides

            if progress >= 1, allFadedIn {
                ghostAlpha = 0
                alphaOverrides = [:]
                collapseFade = nil
            }
        }

        needsDisplay = true

        if frameAnimation == nil && collapseFade == nil {
            timer.invalidate()
            animationTimer = nil
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func stopFrameAnimation() {
        if let animation = frameAnimation {
            displayFrames = animation.to
        }
        frameAnimation = nil
        collapseFade = nil
        ghostAlpha = 0
        alphaOverrides = [:]
        stopAnimationTimer()
    }

    private func startDashTimer() {
        guard animationsAllowed, dashTimer == nil else { return }
        dashPhase = 0
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(dashTick(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        dashTimer = timer
    }

    @objc private func dashTick(_ timer: Timer) {
        dashPhase -= 0.9
        needsDisplay = true
    }

    private func stopDashTimer() {
        dashTimer?.invalidate()
        dashTimer = nil
    }

    private func canDrop(_ id: UUID, on target: UUID) -> Bool {
        guard let editor, id != target else { return false }
        guard let source = editor.map.node(id), let targetNode = editor.map.node(target) else { return false }
        if source.parentID == targetNode.parentID { return true }
        return editor.canMove(id, to: target)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isReadOnly else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let id = hitTest(viewPoint: point) else {
            if let editor, !editor.selection.isEmpty { editor.clearSelection() }
            needsDisplay = true
            NSMenu.popUpContextMenu(canvasContextMenu(), with: event, for: self)
            return
        }
        if editor?.selection.contains(id) != true {
            editor?.select(id)
        }
        needsDisplay = true
        let menu = (editor?.selection.count ?? 0) > 1
            ? batchContextMenu()
            : contextMenu(for: id)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func loc(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func canDeleteNode(_ id: UUID) -> Bool {
        guard let editor else { return false }
        return !editor.map.rootIDs.contains(id) || editor.map.rootIDs.count > 1
    }

    private func contextMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(loc("添加子主题"), #selector(menuAddChild)))
        menu.addItem(menuItem(loc("编辑文字"), #selector(menuEdit)))

        if let editor, !editor.map.children(of: id).isEmpty {
            let collapsed = editor.map.node(id)?.collapsed == true
            menu.addItem(menuItem(
                collapsed ? loc("展开分支") : loc("折叠分支"),
                #selector(menuToggleCollapse)
            ))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(loc("复制子树"), #selector(menuCopy)))
        menu.addItem(menuItem(loc("创建副本"), #selector(menuDuplicate)))
        menu.addItem(menuItem(loc("粘贴为子主题"), #selector(menuPaste), enabled: NodeClipboard.hasContent))

        menu.addItem(.separator())
        menu.addItem(menuItem(loc("专注此分支"), #selector(menuFocusBranch)))
        menu.addItem(menuItem(loc("缩放到分支"), #selector(menuZoomBranch)))

        menu.addItem(.separator())
        let colorMenu = NSMenu()
        for (name, hex) in colorChoices {
            let item = NSMenuItem(title: loc(name), action: #selector(menuSetColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hex
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: loc("节点颜色"), action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        if let editor, editor.map.layout == .free {
            menu.addItem(arrangeMenu())
        }

        menu.addItem(.separator())
        let delete = menuItem(loc("删除"), #selector(menuDelete), enabled: canDeleteNode(id))
        menu.addItem(delete)
        return menu
    }

    private func batchContextMenu() -> NSMenu {
        let menu = NSMenu()
        let count = editor?.selection.count ?? 0
        menu.addItem(menuItem(String(format: loc("复制 %lld 个分支"), count), #selector(menuCopy)))
        menu.addItem(menuItem(String(format: loc("创建 %lld 个副本"), count), #selector(menuDuplicate)))
        menu.addItem(menuItem(loc("粘贴为子主题"), #selector(menuPaste), enabled: NodeClipboard.hasContent))

        menu.addItem(.separator())
        let colorMenu = NSMenu()
        for (name, hex) in colorChoices {
            let item = NSMenuItem(title: loc(name), action: #selector(menuSetBatchColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hex
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: loc("批量颜色"), action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(menuItem(loc("清除图标"), #selector(menuClearIcons)))

        if editor?.map.layout == .free {
            menu.addItem(arrangeMenu())
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(loc("删除所选"), #selector(menuDelete)))
        return menu
    }

    private var colorChoices: [(String, String)] {
        [
            ("无", ""), ("珊瑚", "#E8836B"), ("琥珀", "#E6B450"), ("薄荷", "#7FB89A"),
            ("天蓝", "#7BA7D9"), ("紫罗兰", "#A28BC9"), ("石墨", "#4A4A52")
        ]
    }

    private func arrangeMenu() -> NSMenuItem {
        let submenu = NSMenu()
        for option in MapEditor.FreeArrangement.allCases {
            let item = NSMenuItem(title: loc(option.title), action: #selector(menuArrange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.isEnabled = (editor?.selection.count ?? 0) >= (option.needsThree ? 3 : 2)
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: loc("对齐与等距"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func canvasContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(loc("粘贴到根主题"), #selector(menuPaste), enabled: NodeClipboard.hasContent))
        menu.addItem(menuItem(loc("全选"), #selector(menuSelectAll)))
        menu.addItem(.separator())
        menu.addItem(menuItem(loc("适配画布"), #selector(menuFit)))
        menu.addItem(menuItem(loc("水平 + 垂直居中"), #selector(menuCenter)))
        if editor?.focusNodeID != nil {
            menu.addItem(.separator())
            menu.addItem(menuItem(loc("退出专注模式"), #selector(menuExitFocus)))
        }
        return menu
    }

    @objc private func menuAddChild() {
        guard let id = editor?.selection.first, let newID = editor?.addChild(to: id) else { return }
        focusNewNode(newID)
    }

    @objc private func menuEdit() {
        guard let id = editor?.selection.first else { return }
        beginEditing(id)
    }

    @objc private func menuToggleCollapse() {
        guard let id = editor?.selection.first else { return }
        editor?.toggleCollapse(id)
    }

    @objc private func menuDelete() {
        editor?.deleteSelection()
        rebuildLayoutIfNeeded(force: true)
        needsDisplay = true
    }

    @objc private func menuSetColor(_ sender: NSMenuItem) {
        guard let id = editor?.selection.first else { return }
        let hex = sender.representedObject as? String
        editor?.setColor(hex?.isEmpty == true ? nil : hex, for: id)
    }

    @objc private func menuSetBatchColor(_ sender: NSMenuItem) {
        guard let ids = editor?.selection else { return }
        let hex = sender.representedObject as? String
        editor?.setColor(hex?.isEmpty == true ? nil : hex, for: ids)
    }

    @objc private func menuClearIcons() {
        guard let ids = editor?.selection else { return }
        editor?.setIcon(nil, for: ids)
    }

    @objc private func menuCopy() {
        editor?.copySelection()
    }

    @objc private func menuDuplicate() {
        performStructuralEdit { editor?.duplicateSelection() }
    }

    @objc private func menuPaste() {
        performStructuralEdit { editor?.paste() }
    }

    @objc private func menuFocusBranch() {
        guard let id = editor?.selection.first else { return }
        editor?.toggleFocus(on: id)
    }

    @objc private func menuZoomBranch() {
        editor?.requestZoomToBranch()
    }

    @objc private func menuArrange(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let arrangement = MapEditor.FreeArrangement(rawValue: raw),
              let frames = layoutResult?.frames else { return }
        editor?.arrangeSelection(arrangement, frames: frames)
        rebuildLayoutIfNeeded(force: true)
        needsDisplay = true
    }

    @objc private func menuSelectAll() {
        editor?.selectAll()
        needsDisplay = true
    }

    @objc private func menuFit() {
        editor?.requestFit()
    }

    @objc private func menuCenter() {
        centerContent()
    }

    @objc private func menuExitFocus() {
        editor?.setFocus(nil)
        needsDisplay = true
    }

    // MARK: - Scrolling & zoom

    override func scrollWheel(with event: NSEvent) {
        userHasInteracted = true
        if editingID != nil { commitEditing() }
        let point = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) {
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
            let factor = 1 + event.scrollingDeltaY * sensitivity
            zoom(by: factor, at: point)
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            camera.center.x -= event.scrollingDeltaX * multiplier / camera.zoom
            camera.center.y -= event.scrollingDeltaY * multiplier / camera.zoom
            updateEditorFrame()
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        userHasInteracted = true
        if editingID != nil { commitEditing() }
        let point = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, at: point)
    }

    private func zoom(by factor: CGFloat, at viewPoint: CGPoint) {
        userHasInteracted = true
        let before = viewToWorld(viewPoint)
        let next = min(max(camera.zoom * factor, CanvasCamera.minZoom), CanvasCamera.maxZoom)
        guard next != camera.zoom else { return }
        camera.zoom = next
        let after = viewToWorld(viewPoint)
        camera.center.x += before.x - after.x
        camera.center.y += before.y - after.y
        updateEditorFrame()
        needsDisplay = true
        notifyZoomChanged()
    }

    private var zoomNotifyToken: Int = 0

    /// SwiftUI 的缩放栏在布局/更新阶段也可能被回调，异步发一次避免在视图更新中改状态
    private func notifyZoomChanged() {
        guard onZoomChanged != nil else { return }
        zoomNotifyToken &+= 1
        let token = zoomNotifyToken
        let zoom = camera.zoom
        DispatchQueue.main.async { [weak self] in
            guard let self, self.zoomNotifyToken == token else { return }
            self.onZoomChanged?(zoom)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard !isReadOnly, editingID == nil, let editor else {
            super.keyDown(with: event)
            return
        }

        if let action = ShortcutStore.shared.action(for: event, scope: .canvas) {
            perform(action, in: editor)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.keyCode {
            case 0: // ⌘A
                editor.selectAll()
                needsDisplay = true
                return
            case 8: // ⌘C
                editor.copySelection()
                return
            case 7: // ⌘X
                performStructuralEdit { editor.cutSelection() }
                return
            case 9: // ⌘V
                performStructuralEdit { editor.paste() }
                return
            case 2: // ⌘D
                performStructuralEdit { editor.duplicateSelection() }
                return
            case 123:
                navigateStructural(.previousSibling)
                return
            case 124:
                navigateStructural(.nextSibling)
                return
            case 125:
                navigateStructural(.firstChild)
                return
            case 126:
                navigateStructural(.parent)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 53: // Esc
            if editor.focusNodeID != nil {
                editor.setFocus(nil)
            } else {
                editor.clearSelection()
            }
            needsDisplay = true
        case 123:
            navigate(dirX: -1, dirY: 0)
        case 124:
            navigate(dirX: 1, dirY: 0)
        case 125:
            navigate(dirX: 0, dirY: 1)
        case 126:
            navigate(dirX: 0, dirY: -1)
        default:
            if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
               let characters = event.characters,
               let scalar = characters.unicodeScalars.first,
               scalar.value >= 32,
               let id = editor.selection.first {
                // 不要预先把 event.characters 写进节点：中文输入法下第一个按键
                // 只是拼音字母（如 n / z），提前写入会把英文留在节点里，
                // 输入法反而收不到这次按键。先进入编辑，再把事件原样交给输入框，
                // 由 NSTextView 的输入上下文决定是插入字符还是开始组字。
                beginEditing(id)
                if let textView = editTextView {
                    textView.interpretKeyEvents([event])
                    return
                }
            }
            super.keyDown(with: event)
        }
    }

    private enum StructuralDirection {
        case parent
        case firstChild
        case previousSibling
        case nextSibling
    }

    private func navigateStructural(_ direction: StructuralDirection) {
        guard let editor, let currentID = editor.selection.first, let node = editor.map.node(currentID) else { return }
        var target: UUID?
        switch direction {
        case .parent:
            target = node.parentID
        case .firstChild:
            guard let child = editor.map.children(of: currentID).first else { return }
            if node.collapsed {
                editor.expandForNavigation(currentID)
            }
            target = child.id
        case .previousSibling, .nextSibling:
            let siblings: [UUID]
            if let parentID = node.parentID {
                siblings = editor.map.children(of: parentID).map(\.id)
            } else {
                siblings = editor.map.rootIDs
            }
            guard let index = siblings.firstIndex(of: currentID) else { return }
            let offset = direction == .previousSibling ? -1 : 1
            let nextIndex = index + offset
            guard siblings.indices.contains(nextIndex) else { return }
            target = siblings[nextIndex]
        }
        guard let target else { return }
        editor.select(target)
        rebuildLayoutIfNeeded(force: true)
        ensureVisible(target)
        needsDisplay = true
    }

    /// 结构变化（粘贴 / 副本 / 剪切）后统一刷新布局并做落位动画
    private func performStructuralEdit(_ body: () -> Void) {
        guard let editor else { return }
        let startFrames = currentVisualFrames()
        let before = editor.revision
        body()
        guard editor.revision != before else { return }
        rebuildLayoutIfNeeded(force: true)
        if let id = editor.selection.first {
            centerOnNode(id)
        }
        animateFrames(from: startFrames, to: layoutResult?.frames ?? [:], duration: 0.22)
    }

    // MARK: - Copy / paste responder

    @objc func copy(_ sender: Any?) {
        guard !isReadOnly else { return }
        editor?.copySelection()
    }

    @objc func cut(_ sender: Any?) {
        guard !isReadOnly else { return }
        performStructuralEdit { editor?.cutSelection() }
    }

    @objc func paste(_ sender: Any?) {
        guard !isReadOnly else { return }
        performStructuralEdit { editor?.paste() }
    }

    @objc func duplicate(_ sender: Any?) {
        guard !isReadOnly else { return }
        performStructuralEdit { editor?.duplicateSelection() }
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard !isReadOnly else { return false }
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(duplicate(_:)):
            return !(editor?.selection.isEmpty ?? true)
        case #selector(paste(_:)):
            return NodeClipboard.hasContent
        default:
            return true
        }
    }

    private func perform(_ action: ShortcutAction, in editor: MapEditor) {
        switch action {
        case .newChild:
            let target = editor.selection.first ?? editor.map.rootID
            if let newID = editor.addChild(to: target) {
                focusNewNode(newID)
            }
        case .newSibling:
            if let id = editor.selection.first, let newID = editor.addSibling(after: id) {
                focusNewNode(newID)
            } else if let newID = editor.addRoot() {
                focusNewNode(newID)
            }
        case .editNode:
            if let id = editor.selection.first {
                beginEditing(id)
            } else {
                beginEditing(editor.map.rootID)
            }
        case .deleteNode:
            editor.deleteSelection()
        case .toggleCollapse:
            if let id = editor.selection.first {
                editor.toggleCollapse(id)
            }
        default:
            break
        }
    }

    private func navigate(dirX: CGFloat, dirY: CGFloat) {
        guard let editor,
              let layout = layoutResult,
              let currentID = editor.selection.first,
              let current = layout.frames[currentID] else { return }

        var best: (id: UUID, score: CGFloat)?
        for (id, frame) in layout.frames where id != currentID {
            let dx = frame.midX - current.midX
            let dy = frame.midY - current.midY
            let forward = dx * dirX + dy * dirY
            guard forward > 6 else { continue }
            let lateral = abs(dx * dirY) + abs(dy * dirX)
            let score = forward + lateral * 2.4
            if best == nil || score < best!.score {
                best = (id, score)
            }
        }
        if let best {
            editor.select(best.id)
            if let frame = layout.frames[best.id] {
                panToReveal(frame, margin: 40)
            }
        }
    }

    private func focusNewNode(_ id: UUID) {
        rebuildLayoutIfNeeded(force: true)
        centerOnNode(id)
        editor?.select(id)
        needsDisplay = true
    }

    private func ensureVisible(_ id: UUID) {
        guard let frame = layoutResult?.frames[id] else { return }
        panToReveal(frame, margin: 24)
    }

    /// 把节点放到视口正中心，缩放不变。新增 / 编辑节点时使用。
    func centerOnNode(_ id: UUID) {
        guard let frame = currentVisualFrames()[id] ?? layoutResult?.frames[id] else { return }
        userHasInteracted = true
        let target = CGPoint(x: frame.midX, y: frame.midY)
        if abs(camera.center.x - target.x) > 0.5 || abs(camera.center.y - target.y) > 0.5 {
            camera.center = target
            needsDisplay = true
        }
        updateEditorFrame()
    }

    /// 消费 MapEditor 的居中请求。放在 fit / 分支缩放之后调用，
    /// 避免初次布局的 fitToContent 把刚算好的中心覆盖掉。
    private func applyPendingCenterIfPossible() {
        guard let editor, editor.centerToken != lastCenterToken else { return }
        guard let id = editor.centerNodeID, layoutResult?.frames[id] != nil else { return }
        lastCenterToken = editor.centerToken
        centerOnNode(id)
    }

    /// 只把差的那一点平移进视野。用于搜索定位、大纲跳转等临时操作；
    /// 编辑 / 新增节点走 centerOnNode，会按当前缩放居中。
    private func panToReveal(_ rect: CGRect, margin: CGFloat) {
        let visible = visibleWorldRect
        guard visible.width > margin * 2, visible.height > margin * 2 else { return }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if rect.minX < visible.minX + margin { dx = rect.minX - (visible.minX + margin) }
        if rect.maxX > visible.maxX - margin { dx = rect.maxX - (visible.maxX - margin) }
        if rect.minY < visible.minY + margin { dy = rect.minY - (visible.minY + margin) }
        if rect.maxY > visible.maxY - margin { dy = rect.maxY - (visible.maxY - margin) }
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        camera.center.x += dx
        camera.center.y += dy
        needsDisplay = true
    }

    // MARK: - Inline editing

    func beginEditing(_ id: UUID) {
        guard let editor, let node = editor.map.node(id) else { return }
        stopFrameAnimation()
        commitEditing()
        editor.select(id)
        rebuildLayoutIfNeeded(force: true)
        guard let layout = layoutResult, let frame = layout.frames[id] else { return }
        centerOnNode(id)

        let level = min(layout.depths[id] ?? 0, 2)
        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: level)
        let font = editingFont(for: textLayout)
        let textRect = editingRect(
            editingRect(for: textLayout),
            fitting: node.text,
            font: font,
            level: level,
            node: node
        )

        let textView = EditingTextView(frame: textRect)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = theme.accent
        textView.selectedTextAttributes = [
            .backgroundColor: theme.accent.withAlphaComponent(0.35),
            .foregroundColor: textColor(for: node, level: level)
        ]
        textView.delegate = self
        textView.string = node.text
        updateTextContainer(textView, width: textRect.width)
        applyTextAttributes(
            to: textView,
            node: node,
            level: level,
            font: font,
            alignment: textLayout.alignment
        )
        fitEditorHeight(textView)
        addSubview(textView)

        editTextView = textView
        editingID = id
        editor.editingNodeID = id
        editingOriginalText = node.text
        appliedEditingFont = font
        textView.onMarkedTextChange = { [weak self] in
            // 组字不进 textDidChange：先把容器撑开（纯几何），模型更新延后一拍
            self?.refreshEditingWidth()
            DispatchQueue.main.async { self?.syncEditingText() }
        }
        needsDisplay = true

        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    /// 编辑器字号必须与画布完全一致（pointSize × zoom）。这里不设最小字号，
    /// 否则缩得比较小的时候，一进入编辑文字就会比画布上大一圈。
    private func editingFont(for textLayout: NodeMeasurer.NodeTextLayout) -> NSFont {
        let target = max(textLayout.font.pointSize * camera.zoom, 1)
        let descriptor = textLayout.font.fontDescriptor
        if let font = NSFont(descriptor: descriptor, size: target), abs(font.pointSize - target) < 0.05 {
            return font
        }
        if let font = NSFont(descriptor: descriptor.withSize(target), size: target), abs(font.pointSize - target) < 0.05 {
            return font
        }
        return NSFontManager.shared.convert(textLayout.font, toSize: target)
    }

    /// 编辑器在视图坐标里的位置和宽度。
    ///
    /// 换行宽度必须和画布一致（`contentWidth`），否则同一个节点一进入编辑就可能
    /// 被挤成两行，多出来的那行又被节点高度裁掉，看起来就像字号突然变小了。
    /// 文字在节点里居中后，编辑容器也要以文字块中心对齐，输入时文字才不会左右跳。
    private func editingRect(
        for textLayout: NodeMeasurer.NodeTextLayout
    ) -> CGRect {
        let width = max(textLayout.contentWidth * camera.zoom, 10)
        var rect = worldRectToView(textLayout.textRect)
        rect.origin.x = rect.midX - width / 2
        rect.size.width = width
        rect.size.height += 4
        return rect
    }

    /// 编辑期间容器要能装下当前输入（含输入法组字）：否则会先按旧宽度折行、
    /// 下一拍节点变宽再弹回第一行，看起来就是闪一下。
    private func editingRect(
        _ rect: CGRect,
        fitting string: String,
        font: NSFont,
        level: Int,
        node: MindNode
    ) -> CGRect {
        let maxContent: CGFloat = (level == 0 ? 226 : 192) - (node.icon == nil ? 0 : 20)
        let maxWidth = max(maxContent * camera.zoom, rect.width)
        let measured = (string as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).width
        let fitted = min(max(rect.width, ceil(measured) + 2), maxWidth)
        guard fitted > rect.width + 0.5 else { return rect }
        var out = rect
        out.origin.x -= (fitted - rect.width) / 2   // 始终围绕文字块中心扩宽
        out.size.width = fitted
        return out
    }

    /// 兜底：如果排版出来的高度超过节点，扩高而不是裁掉最后一行
    private func fitEditorHeight(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let needed = layoutManager.usedRect(for: container).height + 4
        if needed > textView.frame.height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: needed))
        }
    }

    private func applyTextAttributes(
        to textView: NSTextView,
        node: MindNode,
        level: Int,
        font: NSFont,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        let color = textColor(for: node, level: level)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        textView.typingAttributes = attributes
        textView.textColor = color
        textView.alignment = alignment
        textView.font = font
    }

    private func updateTextContainer(_ textView: NSTextView, width: CGFloat) {
        textView.textContainer?.containerSize = NSSize(
            width: max(width, 10),
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
    }

    private func textColor(for node: MindNode, level: Int) -> NSColor {
        if let hex = node.colorHex {
            let fill = NSColor(hex: hex)
            return fill.luminance > 0.62 ? NSColor.black : NSColor.white
        }
        switch level {
        case 0: return theme.rootText
        case 1: return theme.branchText
        default: return theme.nodeText
        }
    }

    func commitEditing() {
        guard let textView = editTextView, let id = editingID else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        editingID = nil
        editor?.editingNodeID = nil
        editTextView = nil
        editingOriginalText = ""
        appliedEditingFont = nil
        textView.delegate = nil
        textView.removeFromSuperview()

        if text.isEmpty {
            if editor?.map.node(id)?.parentID == nil {
                editor?.setText("中心主题", for: id)
            } else {
                editor?.delete(id: id)
            }
        } else if let node = editor?.map.node(id), node.text != text {
            editor?.setText(text, for: id)
        }

        if editor?.map.node(id) != nil {
            rebuildLayoutIfNeeded(force: true)
            centerOnNode(id)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func cancelEditing() {
        guard let textView = editTextView, let id = editingID else { return }
        let original = editingOriginalText

        editingID = nil
        editor?.editingNodeID = nil
        editTextView = nil
        editingOriginalText = ""
        appliedEditingFont = nil
        textView.delegate = nil
        textView.removeFromSuperview()

        if let node = editor?.map.node(id), node.text != original {
            editor?.setText(original, for: id)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func updateEditorFrame() {
        guard let textView = editTextView, let id = editingID,
              let editor, let layout = layoutResult, let frame = layout.frames[id],
              let level = layout.depths[id],
              let node = editor.map.node(id) else { return }

        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: min(level, 2))
        // 正常打字由 syncEditingText 把节点居中；这里只兜底外部变化导致节点完全跑出视野
        if !visibleWorldRect.intersects(frame) {
            panToReveal(frame, margin: 32)
        }
        let font = editingFont(for: textLayout)
        let textRect = editingRect(
            editingRect(for: textLayout),
            fitting: textView.string,
            font: font,
            level: min(level, 2),
            node: node
        )

        textView.frame = textRect
        // 打字过程中字号并不会变，只在缩放变化时才需要重设属性；
        // 每次按键都写一遍 textStorage 会打断中文输入法的组字。
        if appliedEditingFont?.pointSize != font.pointSize || appliedEditingFont?.fontName != font.fontName {
            applyTextAttributes(
                to: textView,
                node: node,
                level: min(level, 2),
                font: font,
                alignment: textLayout.alignment
            )
            appliedEditingFont = font
        }
        updateTextContainer(textView, width: textRect.width)
        fitEditorHeight(textView)
        textView.needsDisplay = true
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        syncEditingText()
    }

    /// 只调整编辑框几何（不碰模型）：组字变长时先把容器撑开，避免这一帧折行
    private func refreshEditingWidth() {
        guard let textView = editTextView, let id = editingID, let editor,
              let layout = layoutResult, let frame = layout.frames[id],
              let level = layout.depths[id], let node = editor.map.node(id) else { return }
        let lvl = min(level, 2)
        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: lvl)
        let font = editingFont(for: textLayout)
        let rect = editingRect(
            editingRect(for: textLayout),
            fitting: textView.string,
            font: font,
            level: lvl,
            node: node
        )
        guard abs(rect.width - textView.frame.width) > 0.5 else { return }
        textView.frame = rect
        updateTextContainer(textView, width: rect.width)
    }

    /// 把输入框里的文字（含输入法组字）同步回模型，让节点跟着变宽，
    /// 组字就不会提前折行、候选框也不会飘到节点外面。
    private func syncEditingText() {
        guard let textView = editTextView, let id = editingID, let editor,
              let node = editor.map.node(id), node.text != textView.string else { return }
        editor.setText(textView.string, for: id)
        rebuildLayoutIfNeeded(force: true)
        centerOnNode(id)
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                commitEditing()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }

}

private extension NSColor {
    var luminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 1 }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }
}

