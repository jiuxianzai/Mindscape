import AppKit

/// 画布动效策略：尊重系统「减弱动态效果」，并在大图上关闭逐帧动画，避免整图 60fps 重绘。
enum CanvasMotion {
    /// 超过这个节点数就不再对落位做逐帧插值
    static let maxAnimatedNodes = 800

    /// 超过这个节点数降到 30fps：大图上整屏重绘更贵，降帧比直接关掉动画观感好
    static let reducedFrameRateNodes = 300

    /// 测试 / 调试时强制开启或关闭；nil 表示跟随系统
    static var reduceMotionOverride: Bool?

    static var reduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func allowsAnimation(nodeCount: Int) -> Bool {
        !reduceMotion && nodeCount <= maxAnimatedNodes
    }

    static func frameInterval(nodeCount: Int) -> TimeInterval {
        nodeCount > reducedFrameRateNodes ? 1.0 / 30.0 : 1.0 / 60.0
    }

    /// 每深一层延后一点：父节点先走、子分支跟随，
    /// 避免整张图所有节点同时挤在中途、互相穿过。
    static let depthDelay: TimeInterval = 0.02

    /// 最多累计多少层延迟（再深就同速了，避免长链拖太久）
    static let maxDelayedDepth = 2

    static func delay(forDepth depth: Int) -> TimeInterval {
        TimeInterval(min(max(depth - 1, 0), maxDelayedDepth)) * depthDelay
    }

    /// 落位用缓出：起步快、收尾稳
    static func easeOutCubic(_ progress: Double) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - p, 3))
    }
}
