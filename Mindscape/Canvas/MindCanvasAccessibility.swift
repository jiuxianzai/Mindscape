import AppKit

/// 画布节点的 VoiceOver 元素
final class MindNodeAccessibilityElement: NSAccessibilityElement {
    weak var canvas: MindCanvasView?
    var nodeID: UUID?
}
