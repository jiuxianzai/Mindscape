import Foundation

/// 计算节点折叠 / 展开控件在连接线上的位置。
/// 控件只在节点有子主题时存在，坐标使用画布世界坐标。
enum NodeControlGeometry {
    static let radius: CGFloat = 9
    static let hitRadius: CGFloat = 13

    static func collapseControlCenter(for id: UUID, in map: MindMap, layout: LayoutResult) -> CGPoint? {
        guard let node = map.node(id), let rect = layout.frames[id] else { return nil }
        guard !map.children(of: id).isEmpty else { return nil }

        let childFrames = map.children(of: id).compactMap { layout.frames[$0.id] }
        let parentRect = node.parentID.flatMap { layout.frames[$0] }
        let direction = direction(
            for: node,
            rect: rect,
            parentRect: parentRect,
            childFrames: childFrames,
            style: map.layout
        )

        if direction == .free {
            if let child = childFrames.min(by: {
                distance(from: $0, to: rect) < distance(from: $1, to: rect)
            }) {
                let dx = child.midX - rect.midX
                let dy = child.midY - rect.midY
                if abs(dx) >= abs(dy) {
                    return CGPoint(x: dx >= 0 ? rect.maxX + 18 : rect.minX - 18, y: rect.midY)
                }
                return CGPoint(x: rect.midX, y: dy >= 0 ? rect.maxY + 18 : rect.minY - 18)
            }
            return CGPoint(x: rect.maxX + 18, y: rect.midY)
        }

        if direction == .down || direction == .up {
            return CGPoint(
                x: rect.midX,
                y: direction == .down ? rect.maxY + 18 : rect.minY - 18
            )
        }

        return CGPoint(
            x: direction == .right ? rect.maxX + 18 : rect.minX - 18,
            y: rect.midY
        )
    }

    static func hitTest(_ point: CGPoint, for id: UUID, in map: MindMap, layout: LayoutResult) -> Bool {
        guard let center = collapseControlCenter(for: id, in: map, layout: layout) else { return false }
        return hypot(point.x - center.x, point.y - center.y) <= hitRadius
    }

    private enum Direction {
        case right
        case left
        case down
        case up
        case free
    }

    private static func direction(
        for node: MindNode,
        rect: CGRect,
        parentRect: CGRect?,
        childFrames: [CGRect],
        style: MapLayout
    ) -> Direction {
        switch style {
        case .logicRight, .tree, .braceMap:
            return .right
        case .logicLeft:
            return .left
        case .orgChart, .timeline:
            return .down
        case .free:
            return .free
        case .mindMap:
            if let parentRect {
                return rect.midX >= parentRect.midX ? .right : .left
            }
            if childFrames.contains(where: { $0.midX >= rect.midX }) { return .right }
            if childFrames.contains(where: { $0.midX < rect.midX }) { return .left }
            return .right
        }
    }

    private static func distance(from rect: CGRect, to other: CGRect) -> CGFloat {
        hypot(rect.midX - other.midX, rect.midY - other.midY)
    }
}
