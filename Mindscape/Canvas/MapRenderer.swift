import AppKit

struct RenderSelection {
    var ids: Set<UUID> = []
    var dragNodeID: UUID?
    var dragOffset: CGSize = .zero
    var dimmed: Set<UUID> = []
    /// 专注 / 演示模式下被弱化节点的透明度
    var dimAlpha: CGFloat = 0.35
    var dropTargetID: UUID?
    /// 拖拽落点虚线的动画相位
    var dashPhase: CGFloat = 0
    /// 正在内联编辑的节点：画布不再绘制它的文字和图标，避免与输入框重影
    var editingNodeID: UUID?
    /// 图内搜索命中的节点；activeSearchID 是当前定位到的那一个
    var searchMatches: Set<UUID> = []
    var activeSearchID: UUID?
    /// 所有需要显示折叠 / 展开控件的父节点
    var collapseControlIDs: Set<UUID> = []
    var activeCollapseControlID: UUID?
    /// 折叠/展开时淡出的旧节点与淡入的新节点
    var ghostFrames: [UUID: CGRect] = [:]
    var ghostLevels: [UUID: Int] = [:]
    var ghostAlpha: CGFloat = 0
    var alphaOverrides: [UUID: CGFloat] = [:]
}

enum MapRenderer {
    static let cornerRadius: CGFloat = 12

    // MARK: - Background

    static func drawBackground(theme: MapTheme, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            theme.background.setFill()
            rect.fill()
            return
        }
        let colors = [theme.background.cgColor, theme.backgroundBottom.cgColor] as CFArray
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
            context.restoreGState()
        } else {
            theme.background.setFill()
            rect.fill()
        }
    }

    // MARK: - Full content

    static func draw(
        map: MindMap,
        layout: LayoutResult,
        theme: MapTheme,
        selection: RenderSelection,
        visibleRect: CGRect = .infinite,
        in context: CGContext
    ) {
        drawConnectors(
            map: map,
            layout: layout,
            theme: theme,
            dimmed: selection.dimmed,
            dimAlpha: selection.dimAlpha,
            alphaOverrides: selection.alphaOverrides,
            visibleRect: visibleRect
        )
        drawNodes(map: map, layout: layout, theme: theme, selection: selection, visibleRect: visibleRect)
    }

    // MARK: - Connectors

    private static func drawConnectors(
        map: MindMap,
        layout: LayoutResult,
        theme: MapTheme,
        dimmed: Set<UUID>,
        dimAlpha: CGFloat,
        alphaOverrides: [UUID: CGFloat],
        visibleRect: CGRect
    ) {
        if map.layout == .timeline {
            drawTimelineAxis(layout: layout, theme: theme, dimmed: dimmed, dimAlpha: dimAlpha)
        }

        for node in map.nodes {
            guard let parentID = node.parentID,
                  let parentRect = layout.frames[parentID],
                  let childRect = layout.frames[node.id],
                  parentRect.union(childRect).intersects(visibleRect) else { continue }

            if map.layout == .braceMap {
                continue
            }

            let baseAlpha = dimmed.contains(node.id) ? max(0.06, dimAlpha * 0.7) : 0.95
            let alpha = baseAlpha * (alphaOverrides[node.id] ?? 1)
            theme.connector.withAlphaComponent(alpha).setStroke()

            let path: NSBezierPath
            switch map.layout {
            case .orgChart, .tree:
                path = orthogonalPath(from: parentRect, to: childRect)
            case .timeline:
                path = timelinePath(from: parentRect, to: childRect)
            case .free:
                path = beamPath(from: parentRect, to: childRect)
            default:
                path = beamPath(from: parentRect, to: childRect)
            }
            path.lineWidth = node.parentID == layout.rootID ? 2.2 : 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        if map.layout == .braceMap {
            drawBraceConnectors(
                map: map, layout: layout, theme: theme,
                dimmed: dimmed, dimAlpha: dimAlpha, alphaOverrides: alphaOverrides
            )
        }
    }

    /// 命中父节点到子节点的连线；返回连线所属的父节点
    static func connectorParent(
        at point: CGPoint,
        map: MindMap,
        layout: LayoutResult,
        tolerance: CGFloat
    ) -> UUID? {
        guard tolerance > 0 else { return nil }
        for node in map.nodes {
            guard let parentID = node.parentID,
                  let parentRect = layout.frames[parentID],
                  let childRect = layout.frames[node.id] else { continue }
            let hitBounds = parentRect.union(childRect).insetBy(dx: -tolerance, dy: -tolerance)
            guard hitBounds.contains(point) else { continue }

            let path: NSBezierPath
            if map.layout == .braceMap {
                let barX = parentRect.maxX + 28
                let childMids = (layout.children[parentID] ?? []).compactMap { layout.frames[$0]?.midY }
                let minY = childMids.min() ?? childRect.midY
                let maxY = childMids.max() ?? childRect.midY
                path = NSBezierPath()
                path.move(to: CGPoint(x: parentRect.maxX, y: parentRect.midY))
                path.line(to: CGPoint(x: barX, y: parentRect.midY))
                path.move(to: CGPoint(x: barX, y: minY))
                path.line(to: CGPoint(x: barX, y: maxY))
                path.move(to: CGPoint(x: barX, y: childRect.midY))
                path.line(to: CGPoint(x: childRect.minX, y: childRect.midY))
            } else {
                switch map.layout {
                case .orgChart, .tree:
                    path = orthogonalPath(from: parentRect, to: childRect)
                case .timeline:
                    path = timelinePath(from: parentRect, to: childRect)
                default:
                    path = beamPath(from: parentRect, to: childRect)
                }
            }

            let stroked = path.cgPath.copy(
                strokingWithWidth: max(2, tolerance * 2),
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            if stroked.contains(point) { return parentID }
        }
        return nil
    }

    private static func drawBraceConnectors(
        map: MindMap,
        layout: LayoutResult,
        theme: MapTheme,
        dimmed: Set<UUID>,
        dimAlpha: CGFloat,
        alphaOverrides: [UUID: CGFloat]
    ) {
        for node in map.nodes {
            guard let parentID = node.parentID,
                  let parentRect = layout.frames[parentID] else { continue }
            let children = (layout.children[node.id] ?? []).compactMap { layout.frames[$0] }
            guard !children.isEmpty else { continue }

            let baseAlpha = dimmed.contains(node.id) ? max(0.06, dimAlpha * 0.7) : 0.95
            let alpha = baseAlpha * (alphaOverrides[node.id] ?? 1)
            theme.connector.withAlphaComponent(alpha).setStroke()

            let barX = parentRect.maxX + 28
            let minY = children.map(\.midY).min() ?? parentRect.midY
            let maxY = children.map(\.midY).max() ?? parentRect.midY

            let path = NSBezierPath()
            path.move(to: CGPoint(x: parentRect.maxX, y: parentRect.midY))
            path.line(to: CGPoint(x: barX, y: parentRect.midY))
            path.move(to: CGPoint(x: barX, y: minY))
            path.line(to: CGPoint(x: barX, y: maxY))
            for child in children {
                path.move(to: CGPoint(x: barX, y: child.midY))
                path.line(to: CGPoint(x: child.minX, y: child.midY))
            }
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func drawTimelineAxis(
        layout: LayoutResult,
        theme: MapTheme,
        dimmed: Set<UUID>,
        dimAlpha: CGFloat
    ) {
        guard let rootID = layout.rootID, let rootRect = layout.frames[rootID] else { return }
        let milestones = (layout.children[rootID] ?? []).compactMap { layout.frames[$0] }
        guard let last = milestones.max(by: { $0.maxX < $1.maxX }) else { return }

        let alpha = dimmed.contains(rootID) ? max(0.06, dimAlpha * 0.7) : 0.55
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rootRect.maxX, y: rootRect.midY))
        path.line(to: CGPoint(x: last.maxX, y: rootRect.midY))
        path.lineWidth = 1.4
        theme.connector.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private static func beamPath(from parent: CGRect, to child: CGRect) -> NSBezierPath {
        let toRight = child.midX >= parent.midX
        let start = CGPoint(x: toRight ? parent.maxX : parent.minX, y: parent.midY)
        let end = CGPoint(x: toRight ? child.minX : child.maxX, y: child.midY)
        let distance = max(abs(end.x - start.x) * 0.45, 22)
        let direction: CGFloat = toRight ? 1 : -1

        let path = NSBezierPath()
        path.move(to: start)
        path.curve(
            to: end,
            controlPoint1: CGPoint(x: start.x + distance * direction, y: start.y),
            controlPoint2: CGPoint(x: end.x - distance * direction, y: end.y)
        )
        return path
    }

    private static func orthogonalPath(from parent: CGRect, to child: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let start = CGPoint(x: parent.midX, y: parent.maxY)
        let end = CGPoint(x: child.midX, y: child.minY)

        if abs(start.x - end.x) < 1 {
            path.move(to: start)
            path.line(to: end)
            return path
        }

        let midY = start.y + max((end.y - start.y) * 0.5, 14)
        path.move(to: start)
        path.line(to: CGPoint(x: start.x, y: midY))
        path.line(to: CGPoint(x: end.x, y: midY))
        path.line(to: end)
        return path
    }

    private static func timelinePath(from parent: CGRect, to child: CGRect) -> NSBezierPath {
        if child.minY >= parent.maxY - 2 {
            return orthogonalPath(from: parent, to: child)
        }
        return beamPath(from: parent, to: child)
    }

    // MARK: - Nodes

    private static func drawNodes(
        map: MindMap,
        layout: LayoutResult,
        theme: MapTheme,
        selection: RenderSelection,
        visibleRect: CGRect
    ) {
        let draggedID = selection.dragNodeID

        // 拖动时在原位置留一个虚线占位，明确节点是从哪里被拿起的
        if let draggedID,
           let original = layout.frames[draggedID],
           original.intersects(visibleRect),
           abs(selection.dragOffset.width) + abs(selection.dragOffset.height) > 2 {
            let level = min(layout.depths[draggedID] ?? 0, 2)
            let radius: CGFloat = level == 0 ? 15 : (level == 1 ? 12 : 11)
            let placeholder = NSBezierPath(roundedRect: original, xRadius: radius, yRadius: radius)
            theme.accent.withAlphaComponent(0.28).setStroke()
            placeholder.lineWidth = 1.5
            placeholder.setLineDash([4, 4], count: 2, phase: selection.dashPhase)
            placeholder.stroke()
        }

        // 残影先画：折叠过程中它们是“退场”的一方，要压在下面，
        // 否则会盖住正在移动的真实节点，观感像糊在一起
        for (id, frame) in selection.ghostFrames where map.node(id) != nil {
            drawNodeIfPresent(
                id, map: map, layout: layout, theme: theme, selection: selection,
                dragging: false, frameOverride: frame,
                levelOverride: selection.ghostLevels[id],
                alphaScale: selection.ghostAlpha,
                visibleRect: visibleRect
            )
        }

        // 被拖动的节点最后画，保证浮在其它节点之上
        for id in layout.drawOrder where id != draggedID {
            drawNodeIfPresent(
                id, map: map, layout: layout, theme: theme, selection: selection,
                dragging: false, alphaScale: selection.alphaOverrides[id] ?? 1,
                visibleRect: visibleRect
            )
        }
        if let draggedID {
            drawNodeIfPresent(
                draggedID, map: map, layout: layout, theme: theme, selection: selection,
                dragging: true, alphaScale: selection.alphaOverrides[draggedID] ?? 1,
                visibleRect: visibleRect
            )
        }

        // 所有有子节点的父节点都有自己的 +/− 控件，当前悬停/选中的那个高亮
        for controlID in selection.collapseControlIDs where controlID != selection.activeCollapseControlID {
            guard let node = map.node(controlID),
                  let frame = layout.frames[controlID], frame.intersects(visibleRect),
                  let center = NodeControlGeometry.collapseControlCenter(for: controlID, in: map, layout: layout) else { continue }
            drawCollapseControl(
                center: center,
                nodeFrame: frame,
                collapsed: node.collapsed,
                hiddenCount: node.collapsed ? hiddenDescendantCount(of: controlID, layout: layout) : 0,
                theme: theme,
                active: false,
                alpha: controlAlpha(controlID, selection: selection)
            )
        }
        if let active = selection.activeCollapseControlID,
           selection.collapseControlIDs.contains(active),
           let node = map.node(active),
           let frame = layout.frames[active], frame.intersects(visibleRect),
           let center = NodeControlGeometry.collapseControlCenter(for: active, in: map, layout: layout) {
            drawCollapseControl(
                center: center,
                nodeFrame: frame,
                collapsed: node.collapsed,
                hiddenCount: node.collapsed ? hiddenDescendantCount(of: active, layout: layout) : 0,
                theme: theme,
                active: true,
                alpha: controlAlpha(active, selection: selection)
            )
        }
    }

    /// 专注模式下，落在焦点之外的控件也要跟着变淡，否则会从灰掉的节点上“跳出来”
    private static func controlAlpha(_ id: UUID, selection: RenderSelection) -> CGFloat {
        selection.dimmed.contains(id) ? selection.dimAlpha : 1
    }

    /// 折叠后被藏起来的节点数量（含更深层级），用于在控件旁给出提示
    static func hiddenDescendantCount(of id: UUID, layout: LayoutResult) -> Int {
        var count = 0
        var stack = layout.children[id] ?? []
        while let current = stack.popLast() {
            count += 1
            stack.append(contentsOf: layout.children[current] ?? [])
        }
        return count
    }

    private static func drawCollapseControl(
        center: CGPoint,
        nodeFrame: CGRect,
        collapsed: Bool,
        hiddenCount: Int,
        theme: MapTheme,
        active: Bool,
        alpha: CGFloat
    ) {
        let radius = NodeControlGeometry.radius
        let circle = NSBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent((theme.isDark ? 0.45 : 0.18) * alpha)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        shadow.set()
        (active ? theme.accent : theme.background).withAlphaComponent(0.98 * alpha).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        theme.accent.withAlphaComponent(0.9 * alpha).setStroke()
        circle.lineWidth = 1.2
        circle.stroke()

        // 折叠状态只显示一个数字：这个圆本身就是「展开」按钮，不用再并一个 +
        if collapsed, hiddenCount > 0 {
            var countText = "\(hiddenCount)" as NSString
            var fontSize: CGFloat = 9
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NodeMeasurer.rounded(size: fontSize, weight: .semibold),
                .foregroundColor: (active ? NSColor.white : theme.accent).withAlphaComponent(alpha)
            ]
            while countText.size(withAttributes: attributes).width > radius * 2 - 5, fontSize > 5.5 {
                fontSize -= 0.5
                attributes[.font] = NodeMeasurer.rounded(size: fontSize, weight: .semibold)
            }
            if countText.size(withAttributes: attributes).width > radius * 2 - 5 {
                countText = "99+" as NSString
            }
            let textSize = countText.size(withAttributes: attributes)
            countText.draw(
                at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                withAttributes: attributes
            )
            return
        }

        (active ? NSColor.white : theme.accent).withAlphaComponent(alpha).setStroke()
        let glyph = NSBezierPath()
        glyph.move(to: CGPoint(x: center.x - 4, y: center.y))
        glyph.line(to: CGPoint(x: center.x + 4, y: center.y))
        glyph.lineWidth = 1.5
        glyph.lineCapStyle = .round
        glyph.stroke()
    }

    private static func drawNodeIfPresent(
        _ id: UUID,
        map: MindMap,
        layout: LayoutResult,
        theme: MapTheme,
        selection: RenderSelection,
        dragging: Bool,
        frameOverride: CGRect? = nil,
        levelOverride: Int? = nil,
        alphaScale: CGFloat = 1,
        visibleRect: CGRect
    ) {
        guard let node = map.node(id) else { return }
        guard var rect = frameOverride ?? layout.frames[id] else { return }
        if dragging {
            rect.origin.x += selection.dragOffset.width
            rect.origin.y += selection.dragOffset.height
        }
        if !rect.intersects(visibleRect) { return }
        let level = levelOverride ?? min(layout.depths[id] ?? 0, 2)
        drawNode(
            node: node,
            rect: rect,
            level: level,
            theme: theme,
            selected: selection.ids.contains(id),
            dimmed: selection.dimmed.contains(id),
            dimAlpha: selection.dimAlpha,
            dropTarget: selection.dropTargetID == id,
            dragPhase: selection.dashPhase,
            dragging: dragging,
            editing: selection.editingNodeID == id,
            searchMatch: selection.searchMatches.contains(id),
            activeSearch: selection.activeSearchID == id,
            alphaScale: alphaScale,
            layout: layout
        )
    }

    private static func drawNode(
        node: MindNode,
        rect: CGRect,
        level: Int,
        theme: MapTheme,
        selected: Bool,
        dimmed: Bool,
        dimAlpha: CGFloat,
        dropTarget: Bool,
        dragPhase: CGFloat,
        dragging: Bool,
        editing: Bool,
        searchMatch: Bool,
        activeSearch: Bool,
        alphaScale: CGFloat = 1,
        layout: LayoutResult
    ) {
        if dragging {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.scale(by: 1.035)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
        }
        defer {
            if dragging { NSGraphicsContext.restoreGraphicsState() }
        }
        var fill: NSColor
        var textColor: NSColor
        if let hex = node.colorHex {
            fill = NSColor(hex: hex)
            textColor = fill.isLight ? NSColor(hex: "#1E1E1E") : .white
        } else {
            switch level {
            case 0:
                fill = theme.rootFill
                textColor = theme.rootText
            case 1:
                fill = theme.branchFill
                textColor = theme.branchText
            default:
                fill = theme.nodeFill
                textColor = theme.nodeText
            }
        }

        let alpha: CGFloat = (dimmed ? dimAlpha : 1) * alphaScale
        let radius: CGFloat = level == 0 ? 15 : (level == 1 ? 12 : 11)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        if dragging {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.5 : 0.24)
            shadow.shadowBlurRadius = 20
            shadow.shadowOffset = CGSize(width: 0, height: 7)
            shadow.set()
            fill.withAlphaComponent(alpha).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if level == 0 {
            NSGraphicsContext.saveGraphicsState()
            if !dragging {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.35 : 0.12)
                shadow.shadowBlurRadius = 14
                shadow.shadowOffset = CGSize(width: 0, height: 4)
                shadow.set()
            }
            fill.withAlphaComponent(alpha).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            fill.withAlphaComponent(alpha).setFill()
            path.fill()
        }

        if level != 0 || node.colorHex != nil {
            theme.border.withAlphaComponent(alpha).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if selected {
            // 描边压在节点边界内侧：选中 / 编辑不会让节点看起来“变大一圈”，
            // 文字相对位置也就不会跟着跳。
            let ring = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: max(radius - 1, 2),
                yRadius: max(radius - 1, 2)
            )
            theme.accent.withAlphaComponent(alpha).setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }

        if searchMatch {
            let inset: CGFloat = activeSearch ? -5.5 : -3.5
            let ring = NSBezierPath(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                xRadius: radius + abs(inset),
                yRadius: radius + abs(inset)
            )
            theme.accent.withAlphaComponent(activeSearch ? 1 : 0.5).setStroke()
            ring.lineWidth = activeSearch ? 2.6 : 1.4
            if activeSearch {
                ring.setLineDash([6, 3], count: 2, phase: dragPhase)
            }
            ring.stroke()
        }

        if dropTarget {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: -5), xRadius: radius + 4, yRadius: radius + 4)
            theme.accent.withAlphaComponent(0.85).setStroke()
            ring.lineWidth = 2
            ring.setLineDash([5, 3], count: 2, phase: dragPhase)
            ring.stroke()
        }

        // 文字布局与就地编辑器共用，保证位置一致
        let textLayout = NodeMeasurer.textLayout(for: node, in: rect, level: level)
        if let iconName = node.icon,
           let iconRect = textLayout.iconRect,
           let image = symbolImage(name: iconName, size: textLayout.iconSize, color: textColor, alpha: alpha) {
            NSGraphicsContext.saveGraphicsState()
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: iconRect.midY * 2)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }

        // 编辑中由输入控件负责文字，画布只保留图标、背景和边框
        if editing { return }

        let string: NSAttributedString
        if alpha == 1 {
            string = cachedText(
                NodeMeasurer.displayText(node),
                font: textLayout.font,
                color: textColor,
                alignment: textLayout.alignment
            )
        } else {
            string = makeText(
                NodeMeasurer.displayText(node),
                font: textLayout.font,
                color: textColor.withAlphaComponent(alpha),
                alignment: textLayout.alignment
            )
        }
        string.draw(with: textLayout.textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        // 笔记标记：贴在文字后面、与文字垂直居中，比角落里的点更容易被看到
        if NodeMeasurer.hasNote(node) {
            let diameter = NodeMeasurer.noteDotDiameter
            let gap = NodeMeasurer.noteDotGap
            let dotRect = CGRect(
                x: textLayout.textRect.minX + textLayout.measuredSize.width + gap,
                y: textLayout.textRect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            theme.accent.withAlphaComponent(0.95 * alpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private struct TextCacheKey: Hashable {
        let text: String
        let fontName: String
        let pointSize: CGFloat
        let traits: UInt32
        let colorHex: String
        let alignment: Int
    }

    private static var textCache: [TextCacheKey: NSAttributedString] = [:]

    private static func cachedText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let key = TextCacheKey(
            text: text,
            fontName: font.fontName,
            pointSize: font.pointSize,
            traits: font.fontDescriptor.symbolicTraits.rawValue,
            colorHex: color.hexString,
            alignment: alignment.rawValue
        )
        if let cached = textCache[key] { return cached }
        let string = makeText(text, font: font, color: color, alignment: alignment)
        if textCache.count > 600 { textCache.removeAll(keepingCapacity: true) }
        textCache[key] = string
        return string
    }

    private static func makeText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(name: String, size: CGFloat, color: NSColor, alpha: CGFloat) -> NSImage? {
        let cacheKey = "\(name)|\(size)|\(color.hexString)|\(alpha)"
        if let cached = symbolCache[cacheKey] { return cached }

        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        // 这里只能用单色配置：paletteColors 会把 xmark.circle.fill 等符号的
        // 负空间（圆里的 X / 对勾）当成第二层填成同色，渲染出来就是一个实心黑圆。
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let symbol = base.withSymbolConfiguration(configuration) else { return nil }

        // SF Symbol 在 PDF / 翻转视图中直接绘制会丢失字形或上下颠倒；
        // 先栅格化成高分辨率位图，再由渲染器按需翻转，保证画布和导出一致。
        let pixelSize = 128
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        symbol.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        // 保留单色渲染出的镂空，再按节点文字色整体着色（sourceIn 只影响已有像素）
        color.withAlphaComponent(alpha).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(representation)
        symbolCache[cacheKey] = image
        if symbolCache.count > 300 { symbolCache.removeAll() }
        return image
    }

}

private extension NSColor {
    var isLight: Bool {
        guard let color = usingColorSpace(.sRGB) else { return true }
        let luminance = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return luminance > 0.62
    }
}
