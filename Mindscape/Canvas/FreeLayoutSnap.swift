import CoreGraphics

/// 自由布局拖动时显示的对齐辅助线（世界坐标）
struct SnapGuide: Equatable, Sendable {
    enum Axis: Equatable, Sendable {
        case vertical
        case horizontal
    }

    var axis: Axis
    /// 竖线的 x，或横线的 y
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
}

struct SnapResult: Equatable, Sendable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var guides: [SnapGuide] = []
}

/// 自由布局吸附：把拖动节点的左 / 中 / 右、上 / 中 / 下与其它节点的对应边比较，
/// 在阈值内取最近的一条进行吸附，并返回需要绘制的辅助线。
enum FreeLayoutSnap {
    static func snap(movingFrame: CGRect, otherFrames: [CGRect], threshold: CGFloat) -> SnapResult {
        let limit = max(threshold, 0)
        guard limit > 0, !otherFrames.isEmpty else { return SnapResult() }

        let xEdges = [movingFrame.minX, movingFrame.midX, movingFrame.maxX]
        let yEdges = [movingFrame.minY, movingFrame.midY, movingFrame.maxY]

        var bestX: (delta: CGFloat, target: CGFloat)?
        var bestY: (delta: CGFloat, target: CGFloat)?

        for other in otherFrames {
            for target in [other.minX, other.midX, other.maxX] {
                for own in xEdges {
                    let delta = target - own
                    guard abs(delta) <= limit else { continue }
                    if bestX == nil || abs(delta) < abs(bestX!.delta) {
                        bestX = (delta, target)
                    }
                }
            }
            for target in [other.minY, other.midY, other.maxY] {
                for own in yEdges {
                    let delta = target - own
                    guard abs(delta) <= limit else { continue }
                    if bestY == nil || abs(delta) < abs(bestY!.delta) {
                        bestY = (delta, target)
                    }
                }
            }
        }

        var result = SnapResult()
        result.dx = bestX?.delta ?? 0
        result.dy = bestY?.delta ?? 0

        let snapped = movingFrame.offsetBy(dx: result.dx, dy: result.dy)

        if let bestX {
            let matches = otherFrames.filter { frame in
                abs(frame.minX - bestX.target) < 0.5
                    || abs(frame.midX - bestX.target) < 0.5
                    || abs(frame.maxX - bestX.target) < 0.5
            }
            let minY = (matches.map(\.minY) + [snapped.minY]).min() ?? snapped.minY
            let maxY = (matches.map(\.maxY) + [snapped.maxY]).max() ?? snapped.maxY
            result.guides.append(SnapGuide(axis: .vertical, position: bestX.target, start: minY, end: maxY))
        }

        if let bestY {
            let matches = otherFrames.filter { frame in
                abs(frame.minY - bestY.target) < 0.5
                    || abs(frame.midY - bestY.target) < 0.5
                    || abs(frame.maxY - bestY.target) < 0.5
            }
            let minX = (matches.map(\.minX) + [snapped.minX]).min() ?? snapped.minX
            let maxX = (matches.map(\.maxX) + [snapped.maxX]).max() ?? snapped.maxX
            result.guides.append(SnapGuide(axis: .horizontal, position: bestY.target, start: minX, end: maxX))
        }

        return result
    }
}
