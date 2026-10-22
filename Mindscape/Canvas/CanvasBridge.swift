import AppKit
import Observation

/// SwiftUI 与 `MindCanvasView` 之间的轻量桥接：
/// 把画布的实时缩放暴露给底部操作栏，并把操作栏的指令转发回画布。
@MainActor
@Observable
final class CanvasBridge {
    var zoom: CGFloat = 1
    weak var canvas: MindCanvasView?

    /// 画布还没创建时先记下请求，等 `wire` 建立连接后补发
    private var pendingFocus: (id: UUID?, fit: Bool)?
    private var pendingReveal: UUID?

    func setZoomPercent(_ percent: Double) {
        let clamped = min(max(CGFloat(percent) / 100, CanvasCamera.minZoom), CanvasCamera.maxZoom)
        zoom = clamped
        canvas?.setZoom(clamped)
    }

    func stepZoom(byPercentPoints points: CGFloat) {
        let base = canvas?.currentZoom ?? zoom
        let percent = (base * 100).rounded() + points
        setZoomPercent(Double(percent))
    }

    func resetZoom() {
        setZoomPercent(100)
    }

    func centerContent() {
        canvas?.centerContent()
    }

    func fitCanvas() {
        canvas?.fitToContent()
    }

    func revealNode(_ id: UUID) {
        guard let canvas else {
            pendingReveal = id
            return
        }
        canvas.revealNode(id)
    }

    func focusSubtree(_ id: UUID?, fit: Bool = true) {
        guard let canvas else {
            pendingFocus = (id, fit)
            return
        }
        canvas.focusSubtree(id, fit: fit)
    }

    /// 由 `MapCanvasRepresentable` 在画布创建后调用，补发挂起请求
    func attachCanvas(_ view: MindCanvasView) {
        canvas = view
        if let pendingFocus {
            self.pendingFocus = nil
            view.focusSubtree(pendingFocus.id, fit: pendingFocus.fit)
        }
        if let pendingReveal {
            self.pendingReveal = nil
            view.revealNode(pendingReveal)
        }
    }
}
