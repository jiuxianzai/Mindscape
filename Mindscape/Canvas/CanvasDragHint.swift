import Foundation

/// 拖动结束后的操作提示。
///
/// 括号图、逻辑图、组织架构图、树形图、时间轴都不是「拖动即换位」：
/// 拖到空白处会直接弹回原位，普通拖到节点上也只是挂到它下面，不会调整同级顺序。
/// 用户第一次遇到这种情况几乎都会以为拖动坏了，所以这里给一次明确提示。
enum CanvasDragHint {
    /// 这次拖动要不要提示「按住 ⌥ 拖到同级节点上才能换序」。
    ///
    /// - 只有真的拖动了、结果又什么都没变时才提示；
    /// - 已经按着 ⌥ 说明用户知道这个操作，不用再提示；
    /// - 自由布局拖动就是移动，思维导图普通拖动本来就能换序，都不提示。
    static func shouldRemindSiblingReorder(
        layout: MapLayout,
        optionHeld: Bool,
        selectionCount: Int,
        moved: Bool,
        didChange: Bool
    ) -> Bool {
        guard moved, !didChange, !optionHeld else { return false }
        guard selectionCount == 1 else { return false }
        switch layout {
        case .free, .mindMap:
            return false
        case .logicRight, .logicLeft, .orgChart, .tree, .timeline, .braceMap:
            return true
        }
    }

    /// 每次启动只提示一次：第一次够用，反复弹就变成打扰了。
    @MainActor
    private static var reminded = false

    @MainActor
    static func consumeReminder() -> Bool {
        guard !reminded else { return false }
        reminded = true
        return true
    }

    /// 测试用：把「已提示过」的状态复位。
    @MainActor
    static func resetReminderForTesting() {
        reminded = false
    }
}
