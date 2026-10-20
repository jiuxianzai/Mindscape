import AppKit

struct RenderSelection {
    var ids: Set<UUID> = []
    var dragNodeID: UUID?
    var dragOffset: CGSize = .zero
    var dimmed: Set<UUID> = []
    var dropTargetID: UUID?
    /// 正在内联编辑的节点：画布不再绘制它的文字和图标，避免与输入框重影
    var editingNodeID: UUID?
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
        in context: CGContext
    ) {
        drawConnectors(map: map, layout: layout, theme: theme)
        drawNodes(map: map, layout: layout, theme: theme, selection: selection)
    }

    // MARK: - Connectors

    private static func drawConnectors(map: MindMap, layout: LayoutResult, theme: MapTheme) {
        theme.connector.withAlphaComponent(0.95).setStroke()

        if map.layout == .timeline {
            drawTimelineAxis(layout: layout, theme: theme)
        }

        for node in map.nodes {
            guard let parentID = node.parentID,
                  let parentRect = layout.frames[parentID],
                  let childRect = layout.frames[node.id] else { continue }

            if map.layout == .braceMap {
                continue
            }

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
            drawBraceConnectors(map: map, layout: layout, theme: theme)
        }
    }

    private static func drawBraceConnectors(map: MindMap, layout: LayoutResult, theme: MapTheme) {
        let color = theme.connector.withAlphaComponent(0.95)
        color.setStroke()
        for node in map.nodes {
            guard let parentID = node.parentID,
                  let parentRect = layout.frames[parentID] else { continue }
            let children = (layout.children[node.id] ?? []).compactMap { layout.frames[$0] }
            guard !children.isEmpty else { continue }

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

    private static func drawTimelineAxis(layout: LayoutResult, theme: MapTheme) {
        guard let rootID = layout.rootID, let rootRect = layout.frames[rootID] else { return }
        let milestones = (layout.children[rootID] ?? []).compactMap { layout.frames[$0] }
        guard let last = milestones.max(by: { $0.maxX < $1.maxX }) else { return }

        let path = NSBezierPath()
        path.move(to: CGPoint(x: rootRect.maxX, y: rootRect.midY))
        path.line(to: CGPoint(x: last.maxX, y: rootRect.midY))
        path.lineWidth = 1.4
        theme.connector.withAlphaComponent(0.55).setStroke()
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

    private static func drawNodes(map: MindMap, layout: LayoutResult, theme: MapTheme, selection: RenderSelection) {
        for id in layout.drawOrder {
            guard let node = map.node(id), let originalRect = layout.frames[id] else { continue }
            var rect = originalRect
            if selection.dragNodeID == id {
                rect.origin.x += selection.dragOffset.width
                rect.origin.y += selection.dragOffset.height
            }
            let level = min(layout.depths[id] ?? 0, 2)
            drawNode(
                node: node,
                rect: rect,
                level: level,
                theme: theme,
                selected: selection.ids.contains(id),
                dimmed: selection.dimmed.contains(id),
                dropTarget: selection.dropTargetID == id,
                editing: selection.editingNodeID == id,
                layout: layout
            )
        }
    }

    private static func drawNode(
        node: MindNode,
        rect: CGRect,
        level: Int,
        theme: MapTheme,
        selected: Bool,
        dimmed: Bool,
        dropTarget: Bool,
        editing: Bool,
        layout: LayoutResult
    ) {
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

        let alpha: CGFloat = dimmed ? 0.35 : 1
        let radius: CGFloat = level == 0 ? 15 : (level == 1 ? 12 : 11)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        if level == 0 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.35 : 0.12)
            shadow.shadowBlurRadius = 14
            shadow.shadowOffset = CGSize(width: 0, height: 4)
            shadow.set()
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
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), xRadius: radius + 2, yRadius: radius + 2)
            theme.accent.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }

        if dropTarget {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: -5), xRadius: radius + 4, yRadius: radius + 4)
            theme.accent.withAlphaComponent(0.85).setStroke()
            ring.lineWidth = 2
            ring.setLineDash([5, 3], count: 2, phase: 0)
            ring.stroke()
        }

        // 文字布局与就地编辑器共用，保证位置一致
        let textLayout = NodeMeasurer.textLayout(for: node, in: rect, level: level)
        if let iconName = node.icon,
           let iconRect = textLayout.iconRect,
           let image = symbolImage(name: iconName, size: textLayout.iconSize, color: textColor, alpha: alpha) {
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        // 编辑中由输入控件负责文字，画布只保留图标、背景和边框
        if editing { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = textLayout.alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textLayout.font,
            .foregroundColor: textColor.withAlphaComponent(alpha),
            .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: NodeMeasurer.displayText(node), attributes: attributes)
        string.draw(with: textLayout.textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        // 笔记标记
        if !node.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let dot = NSBezierPath(ovalIn: CGRect(x: rect.maxX - 9, y: rect.minY + 6, width: 4, height: 4))
            theme.accent.withAlphaComponent(0.8 * alpha).setFill()
            dot.fill()
        }

        // 折叠提示
        let kids = layout.children[node.id] ?? []
        if node.collapsed, !kids.isEmpty {
            let hidden = descendantCount(of: node.id, layout: layout)
            let outward: CGFloat = (layout.depths[node.id] ?? 0) == 0 ? 0 : (rect.midX >= (layout.frames[layout.rootID ?? node.id]?.midX ?? 0) ? 1 : -1)
            let center = CGPoint(x: rect.midX + outward * (rect.width / 2 + 11), y: rect.midY)
            let badgeRect = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            theme.accent.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let badgeString = NSAttributedString(string: "\(hidden)", attributes: badgeAttributes)
            let size = badgeString.size()
            badgeString.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        }
    }

    private static func symbolImage(name: String, size: CGFloat, color: NSColor, alpha: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color.withAlphaComponent(alpha)]))
        return base.withSymbolConfiguration(configuration)
    }

    private static func descendantCount(of id: UUID, layout: LayoutResult) -> Int {
        var count = 0
        var stack = layout.children[id] ?? []
        while let current = stack.popLast() {
            count += 1
            stack.append(contentsOf: layout.children[current] ?? [])
        }
        return count
    }
}

private extension NSColor {
    var isLight: Bool {
        guard let color = usingColorSpace(.sRGB) else { return true }
        let luminance = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return luminance > 0.62
    }
}
