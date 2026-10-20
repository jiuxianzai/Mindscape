import Foundation

/// 一个思维导图节点。整张图用扁平数组存储，父子关系由 parentID 表达。
struct MindNode: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var parentID: UUID?
    var text: String
    var note: String
    /// SF Symbols 名称，例如 "lightbulb"
    var icon: String?
    var collapsed: Bool
    var order: Int
    var colorHex: String?
    /// 仅自由布局使用
    var position: CGPoint?

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        text: String = "",
        note: String = "",
        icon: String? = nil,
        collapsed: Bool = false,
        order: Int = 0,
        colorHex: String? = nil,
        position: CGPoint? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.text = text
        self.note = note
        self.icon = icon
        self.collapsed = collapsed
        self.order = order
        self.colorHex = colorHex
        self.position = position
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 兼容旧版本用 emoji 字段存图标的数据
    enum CodingKeys: String, CodingKey {
        case id, parentID, text, note, icon, emoji, collapsed, order, colorHex, position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
            ?? container.decodeIfPresent(String.self, forKey: .emoji)
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(text, forKey: .text)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(collapsed, forKey: .collapsed)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(position, forKey: .position)
    }
}
