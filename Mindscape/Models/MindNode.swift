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
    /// 仅思维导图布局的一级分支使用：显式记住分支在根节点的左侧还是右侧。
    /// 其它节点 / 其它布局忽略这个值。
    var branchSide: MindMapSide?
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
        branchSide: MindMapSide? = nil,
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
        self.branchSide = branchSide
        self.colorHex = colorHex
        self.position = position
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 兼容旧版本用 emoji 字段存图标的数据
    enum CodingKeys: String, CodingKey {
        case id, parentID, text, note, icon, emoji, collapsed, order, branchSide, colorHex, position
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
        branchSide = try container.decodeIfPresent(MindMapSide.self, forKey: .branchSide)
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
        try container.encodeIfPresent(branchSide, forKey: .branchSide)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(position, forKey: .position)
    }
}

/// 思维导图一级分支的相对根节点方向。
enum MindMapSide: String, Codable, Equatable, Sendable {
    case left
    case right
}
