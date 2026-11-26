import Foundation

extension Notification.Name {
    static let mindscapeSnapshotCreated = Notification.Name("com.youyanping.mindscape.snapshotCreated")
}
extension Notification.Name {
    /// 普通拖动没能改变任何东西：提示用户同级换序要按住 ⌥
    static let mindscapeReorderHint = Notification.Name("com.youyanping.mindscape.reorderHint")
}
