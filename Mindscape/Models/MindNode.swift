import Foundation

/// 一个思维导图节点。整张图用扁平数组存储，父子关系由 parentID 表达。
struct MindNode: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var parentID: UUID?
    var text: String = ""
    var note: String = ""
    var emoji: String?
    var collapsed: Bool = false
    var order: Int = 0
    var colorHex: String?
    /// 仅自由布局使用
    var position: CGPoint?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
