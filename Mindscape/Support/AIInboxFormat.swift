import Foundation

/// AI 投递请求的解析、校验与转换。
///
/// 这个文件只 import Foundation，不依赖 SwiftUI：可以脱离完整 Xcode 用 `swiftc` 单独编译。
/// （模型层的 `MindMap` 会引到 `MapTheme`，所以测试链接里带上了 AppKit——但仍不需要窗口、
/// 不需要 Xcode 工程，见 `scripts/test-aibridge.sh`。）
/// 需要 AppKit 的信息（图标白名单、主题表）由调用方以参数注入。

enum AILimits {
    static let nodes = 2_000
    static let depth = 12
    static let textLength = 500
    static let noteLength = 4_000
    static let titleLength = 120
    static let edits = 500
    static let fileBytes = 2 * 1024 * 1024
}

enum AIRequestError: LocalizedError, Equatable {
    case invalid(String)
    case tooLarge(String)
    case notFound(String)
    case unsupported(String)
    /// 文档正被编辑 / 有未落盘改动，拒绝写入
    case busy(String)
    /// 文档在读取之后被改过
    case stale(String)

    var reason: String {
        switch self {
        case .invalid: return "invalid"
        case .tooLarge: return "too_large"
        case .notFound: return "not_found"
        case .unsupported: return "unsupported"
        case .busy: return "busy"
        case .stale: return "stale"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .tooLarge(let message), .notFound(let message),
             .unsupported(let message), .busy(let message), .stale(let message):
            return message
        }
    }
}

// MARK: - 线上格式

struct AITreeNode: Decodable {
    var text: String
    var note: String?
    var icon: String?
    var color: String?
    var children: [AITreeNode]?
}

enum AITarget: Decodable, Equatable {
    case id(String)
    case path([String])

    private enum CodingKeys: String, CodingKey {
        case id, path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .id), !id.isEmpty {
            self = .id(id)
            return
        }
        if let path = try container.decodeIfPresent([String].self, forKey: .path), !path.isEmpty {
            self = .path(path)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "target 需要 id 或 path")
        )
    }
}

struct AIEdit: Decodable {
    enum Kind: String, Decodable {
        case setText, setNote, setColor, setIcon, addChildren, remove, move
        case setLayout, setTheme, setTitle
    }

    var kind: Kind
    var target: AITarget?
    var text: String?
    var note: String?
    var color: String?
    var icon: String?
    var nodes: [AITreeNode]?
    var newParent: AITarget?
    /// setLayout / setTheme / setTitle 的值
    var value: String?

    private enum CodingKeys: String, CodingKey {
        case kind, target, text, note, color, icon, nodes, newParent, layout, theme, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        target = try container.decodeIfPresent(AITarget.self, forKey: .target)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        nodes = try container.decodeIfPresent([AITreeNode].self, forKey: .nodes)
        newParent = try container.decodeIfPresent(AITarget.self, forKey: .newParent)
        switch kind {
        case .setLayout: value = try container.decodeIfPresent(String.self, forKey: .layout)
        case .setTheme: value = try container.decodeIfPresent(String.self, forKey: .theme)
        case .setTitle: value = try container.decodeIfPresent(String.self, forKey: .title)
        default: value = nil
        }
    }
}

struct AIRequest: Decodable {
    var op: String
    var title: String?
    var layout: String?
    var theme: String?
    var tree: AITreeNode?
    var doc: String?
    var baseUpdatedAt: Double?
    var edits: [AIEdit]?
}

// MARK: - 转换

enum AIInboxFormat {
    // MARK: create

    static func makeMap(from request: AIRequest, knownIcons: Set<String>) throws -> MindMap {
        guard let tree = request.tree else {
            throw AIRequestError.invalid("缺少 tree")
        }

        let layoutID = request.layout ?? "mindMap"
        guard let layout = MapLayout(rawValue: layoutID) else {
            throw AIRequestError.invalid("未知布局 \(layoutID)")
        }

        var map = MindMap()
        map.layout = layout
        map.themeID = request.theme ?? "paper"
        map.createdAt = Date()
        map.updatedAt = Date()

        var counter = 0
        var nodes: [MindNode] = []
        try build(tree, parentID: nil, order: 0, depth: 0, counter: &counter, knownIcons: knownIcons, into: &nodes)
        map.nodes = nodes

        let rootText = nodes.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            map.title = String(title.prefix(AILimits.titleLength))
        } else if !rootText.isEmpty {
            map.title = String(rootText.prefix(AILimits.titleLength))
        } else {
            map.title = String(localized: "未命名导图")
        }
        return map
    }

    private static func build(
        _ tree: AITreeNode,
        parentID: UUID?,
        order: Int,
        depth: Int,
        counter: inout Int,
        knownIcons: Set<String>,
        into nodes: inout [MindNode]
    ) throws {
        if depth > AILimits.depth {
            throw AIRequestError.tooLarge("层级超过 \(AILimits.depth) 层")
        }
        counter += 1
        if counter > AILimits.nodes {
            throw AIRequestError.tooLarge("节点数超过 \(AILimits.nodes)")
        }

        let text = tree.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIRequestError.invalid("节点缺少非空的 text")
        }

        let id = UUID()
        var node = MindNode(
            id: id,
            parentID: parentID,
            text: String(text.prefix(AILimits.textLength)),
            order: order
        )
        if let note = tree.note, !note.isEmpty {
            node.note = String(note.prefix(AILimits.noteLength))
        }
        if let icon = tree.icon, knownIcons.contains(icon) {
            node.icon = icon
        }
        if let color = tree.color, let normalized = normalizeColor(color) {
            node.colorHex = normalized
        }
        nodes.append(node)

        for (index, child) in (tree.children ?? []).enumerated() {
            try build(
                child,
                parentID: id,
                order: index,
                depth: depth + 1,
                counter: &counter,
                knownIcons: knownIcons,
                into: &nodes
            )
        }
    }

    // MARK: patch

    static func apply(_ edits: [AIEdit], to map: inout MindMap, knownIcons: Set<String>) throws {
        guard edits.count <= AILimits.edits else {
            throw AIRequestError.tooLarge("edits 超过 \(AILimits.edits)")
        }

        // 先把所有 target 按**改动前**的状态解析成 UUID。
        // 否则同一批里先 setText 改了父节点文字，后面的 {"path": ["旧名字", …]} 就会解析失败，
        // 结果取决于 edits 的书写顺序——对模型来说太脆。
        var targets: [UUID?] = []
        var newParents: [UUID?] = []
        targets.reserveCapacity(edits.count)
        newParents.reserveCapacity(edits.count)

        for edit in edits {
            switch edit.kind {
            case .setLayout, .setTheme, .setTitle:
                targets.append(nil)
                newParents.append(nil)
            case .move:
                guard let target = edit.target else { throw AIRequestError.invalid("edit 缺少 target") }
                guard let parent = edit.newParent else { throw AIRequestError.invalid("move 缺少 newParent") }
                targets.append(try resolve(target, in: map))
                newParents.append(try resolve(parent, in: map))
            case .setText, .setNote, .setColor, .setIcon, .addChildren, .remove:
                targets.append(try resolve(edit.target, in: map))
                newParents.append(nil)
            }
        }

        // 在副本上做完整批，任何一条失败都不落盘
        var working = map
        for (index, edit) in edits.enumerated() {
            try apply(edit, target: targets[index], newParent: newParents[index], to: &working, knownIcons: knownIcons)
            guard working.nodes.count <= AILimits.nodes else {
                throw AIRequestError.tooLarge("节点数超过 \(AILimits.nodes)")
            }
        }
        map = working
    }

    private static func apply(
        _ edit: AIEdit,
        target: UUID?,
        newParent: UUID?,
        to map: inout MindMap,
        knownIcons: Set<String>
    ) throws {
        switch edit.kind {
        case .setLayout:
            guard let value = edit.value, let layout = MapLayout(rawValue: value) else {
                throw AIRequestError.invalid("未知布局 \(edit.value ?? "")")
            }
            map.layout = layout

        case .setTheme:
            guard let value = edit.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                throw AIRequestError.invalid("setTheme 缺少 theme")
            }
            map.themeID = value

        case .setTitle:
            guard let value = edit.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                throw AIRequestError.invalid("setTitle 缺少 title")
            }
            map.title = String(value.prefix(AILimits.titleLength))

        case .setText, .setNote, .setColor, .setIcon, .addChildren, .remove, .move:
            guard let id = target, let index = map.nodes.firstIndex(where: { $0.id == id }) else {
                throw AIRequestError.notFound("找不到目标节点")
            }
            try applyNodeEdit(
                edit,
                at: index,
                id: id,
                newParent: newParent,
                to: &map,
                knownIcons: knownIcons
            )
        }
    }

    private static func applyNodeEdit(
        _ edit: AIEdit,
        at index: Int,
        id: UUID,
        newParent: UUID?,
        to map: inout MindMap,
        knownIcons: Set<String>
    ) throws {
        switch edit.kind {
        case .setText:
            let text = (edit.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIRequestError.invalid("setText 缺少 text") }
            map.nodes[index].text = String(text.prefix(AILimits.textLength))

        case .setNote:
            map.nodes[index].note = String((edit.note ?? "").prefix(AILimits.noteLength))

        case .setColor:
            guard let color = edit.color, let normalized = normalizeColor(color) else {
                throw AIRequestError.invalid("setColor 需要 #RRGGBB")
            }
            map.nodes[index].colorHex = normalized

        case .setIcon:
            guard let icon = edit.icon?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw AIRequestError.invalid("setIcon 缺少 icon")
            }
            // 不认识的图标静默丢弃，不打断整批
            map.nodes[index].icon = knownIcons.contains(icon) ? icon : nil

        case .addChildren:
            guard let trees = edit.nodes, !trees.isEmpty else {
                throw AIRequestError.invalid("addChildren 缺少 nodes")
            }
            var order = (map.children(of: id).map(\.order).max() ?? -1) + 1
            var counter = 0
            var created: [MindNode] = []
            for tree in trees {
                try build(
                    tree,
                    parentID: id,
                    order: order,
                    depth: 1,
                    counter: &counter,
                    knownIcons: knownIcons,
                    into: &created
                )
                order += 1
            }
            guard map.nodes.count + created.count <= AILimits.nodes else {
                throw AIRequestError.tooLarge("节点数超过 \(AILimits.nodes)")
            }
            map.nodes.append(contentsOf: created)

        case .remove:
            guard map.node(id)?.parentID != nil else {
                throw AIRequestError.invalid("不能删除根节点")
            }
            let doomed = subtree(of: id, in: map)
            map.nodes.removeAll { doomed.contains($0.id) }

        case .move:
            guard let parentID = newParent else {
                throw AIRequestError.invalid("move 缺少 newParent")
            }
            guard parentID != id, !map.isDescendant(parentID, of: id) else {
                throw AIRequestError.invalid("不能移动到自己的子树里")
            }
            let nextOrder = (map.children(of: parentID).filter { $0.id != id }.map(\.order).max() ?? -1) + 1
            map.nodes[index].parentID = parentID
            map.nodes[index].order = nextOrder

        case .setLayout, .setTheme, .setTitle:
            break
        }
    }

    // MARK: 目标解析

    static func resolve(_ target: AITarget?, in map: MindMap) throws -> UUID {
        guard let target else {
            throw AIRequestError.invalid("edit 缺少 target")
        }
        switch target {
        case .id(let raw):
            guard let uuid = UUID(uuidString: raw) else {
                throw AIRequestError.invalid("target.id 不是合法 UUID：\(raw)")
            }
            guard map.node(uuid) != nil else {
                throw AIRequestError.notFound("找不到节点 \(raw)")
            }
            return uuid

        case .path(let titles):
            var current: UUID?
            for (index, title) in titles.enumerated() {
                let candidates: [UUID]
                if index == 0 {
                    candidates = map.rootIDs
                } else if let current {
                    candidates = map.children(of: current).map(\.id)
                } else {
                    candidates = []
                }
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let found = candidates.first(where: {
                    (map.node($0)?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                }) else {
                    throw AIRequestError.notFound("路径找不到：\(titles.joined(separator: " / "))")
                }
                current = found
            }
            guard let current else {
                throw AIRequestError.invalid("target.path 不能为空")
            }
            return current
        }
    }

    static func subtree(of id: UUID, in map: MindMap) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var stack = map.children(of: id).map(\.id)
        while let next = stack.popLast() {
            guard result.insert(next).inserted else { continue }
            stack.append(contentsOf: map.children(of: next).map(\.id))
        }
        return result
    }

    static func normalizeColor(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + digits.lowercased()
    }
}
