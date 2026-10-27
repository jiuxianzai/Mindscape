import Foundation

/// 串行化首启弹窗：自动更新 -> AI Agent Skill -> 画布操作提示。
/// 画布提示必须等前面所有 sheet 真正关闭后再展开，避免被 sheet 顶掉后状态残留。
@MainActor
final class FirstRunPromptCoordinator {
    static let shared = FirstRunPromptCoordinator()

    private(set) var isRunning = false
    private var didPrepare = false

    func prepareForLaunch() {
        guard !didPrepare else { return }
        didPrepare = true
        isRunning = true
        NotificationCenter.default.post(name: .mindscapeFirstRunPromptsWillPresent, object: nil)
    }

    func finish() {
        guard isRunning else { return }
        isRunning = false
        NotificationCenter.default.post(name: .mindscapeFirstRunPromptsDidFinish, object: nil)
    }
}

extension Notification.Name {
    static let mindscapeFirstRunPromptsWillPresent = Notification.Name("com.youyanping.mindscape.firstRunPromptsWillPresent")
    static let mindscapeFirstRunPromptsDidFinish = Notification.Name("com.youyanping.mindscape.firstRunPromptsDidFinish")
}
