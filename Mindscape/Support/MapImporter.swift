import Foundation

enum ImportError: LocalizedError {
    case unreadable
    case empty
    case invalidOPML
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .unreadable: return String(localized: "无法读取文件内容")
        case .empty: return String(localized: "文件中没有可导入的内容")
        case .invalidOPML: return String(localized: "OPML 文件格式不正确")
        case .invalidJSON: return String(localized: "JSON 不是有效的 Mindscape 导图数据")
        }
    }
}

/// Markdown / OPML / JSON 导入。导入后总是生成新的文档 ID，避免覆盖已有导图。
enum MapImporter {
    static func load(url: URL, themeID: String, layout: MapLayout) throws -> MindMap {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw ImportError.unreadable
        }
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "opml", "xml":
            var map = try opml(data, themeID: themeID, layout: layout)
            map.id = UUID()
            return map
        case "json":
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard var map = try? decoder.decode(MindMap.self, from: data), !map.nodes.isEmpty else {
                throw ImportError.invalidJSON
            }
            map.id = UUID()
            map.updatedAt = Date()
            map.themeID = themeID
            return map
        default:
            guard let text = String(data: data, encoding: .utf8) else { throw ImportError.unreadable }
            return markdown(text, themeID: themeID, layout: layout)
        }
    }

    // MARK: - Markdown

    static func markdown(_ text: String, themeID: String, layout: MapLayout) -> MindMap {
        let rawLines = text.components(separatedBy: .newlines)
        let title = markdownTitle(from: rawLines)
        let rootID = UUID()
        var nodes: [MindNode] = [MindNode(id: rootID, text: title, order: 0)]
        var headingParents: [Int: UUID] = [:]
        var bulletStack: [(indent: Int, id: UUID)] = []
        var lastHeadingID: UUID?
        var lastNodeID: UUID? = rootID
        var consumedRootBullet = false
        var inCodeFence = false
        var titleNodeWasSet = false

        func nextOrder(for parentID: UUID) -> Int {
            (nodes.filter { $0.parentID == parentID }.map(\.order).max() ?? -1) + 1
        }

        @discardableResult
        func append(_ value: String, parentID: UUID, note: String = "") -> UUID {
            let clean = cleanInline(value)
            let node = MindNode(
                parentID: parentID,
                text: clean.isEmpty ? String(localized: "未命名") : clean,
                note: note,
                order: nextOrder(for: parentID)
            )
            nodes.append(node)
            return node.id
        }

        func appendNote(_ note: String) {
            guard let id = lastNodeID, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
            let clean = cleanInline(note)
            guard !clean.isEmpty else { return }
            if nodes[index].note.isEmpty {
                nodes[index].note = clean
            } else {
                nodes[index].note += "\n" + clean
            }
        }

        for rawLine in rawLines {
            let line = rawLine.replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeFence.toggle()
                continue
            }
            guard !inCodeFence else { continue }
            if trimmed.isEmpty { continue }

            // 标题
            if let heading = headingInfo(trimmed) {
                if heading.level == 1 {
                    // 第一个 H1 已经作为导图标题，不重复建节点
                    if titleNodeWasSet { continue }
                    titleNodeWasSet = true
                    continue
                }
                var level = heading.level
                var parent: UUID?
                while level > 1 {
                    level -= 1
                    if let candidate = headingParents[level] {
                        parent = candidate
                        break
                    }
                }
                let parentID = parent ?? rootID
                let id = append(heading.text, parentID: parentID)
                headingParents[heading.level] = id
                headingParents = headingParents.filter { $0.key <= heading.level }
                bulletStack = []
                lastHeadingID = id
                lastNodeID = id
                continue
            }

            // 引用行 → 上一节点的备注（与 Markdown 导出的备注格式一致）
            if trimmed.hasPrefix(">") {
                appendNote(String(trimmed.dropFirst()))
                continue
            }

            // 列表项
            if let bullet = bulletInfo(line) {
                let clean = cleanInline(bullet.text)
                if !consumedRootBullet, bullet.indent == 0, clean == title, !titleNodeWasSet || nodes.count == 1 {
                    consumedRootBullet = true
                    lastNodeID = rootID
                    bulletStack = [(0, rootID)]
                    continue
                }

                while let last = bulletStack.last, last.indent >= bullet.indent {
                    bulletStack.removeLast()
                }
                let parentID = bulletStack.last?.id ?? lastHeadingID ?? rootID
                let id = append(clean, parentID: parentID)
                bulletStack.append((bullet.indent, id))
                lastNodeID = id
                continue
            }

            // 普通段落：挂在最近标题下，保留内容而不是丢掉
            let id = append(trimmed, parentID: lastHeadingID ?? rootID)
            lastNodeID = id
        }

        var map = MindMap(
            id: UUID(),
            title: title,
            nodes: nodes,
            layout: layout,
            themeID: themeID
        )
        map.createdAt = Date()
        map.updatedAt = Date()
        return map
    }

    private struct HeadingInfo {
        var level: Int
        var text: String
    }

    private static func headingInfo(_ trimmed: String) -> HeadingInfo? {
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return HeadingInfo(level: hashes.count, text: String(rest).trimmingCharacters(in: .whitespaces))
    }

    private struct BulletInfo {
        var indent: Int
        var text: String
    }

    private static func bulletInfo(_ line: String) -> BulletInfo? {
        var indent = 0
        for character in line {
            if character == " " { indent += 1 }
            else if character == "\t" { indent += 2 }
            else { break }
        }
        let content = line.dropFirst(indent)
        guard let first = content.first else { return nil }
        if ["-", "*", "+"].contains(first) {
            let rest = content.dropFirst()
            guard rest.first == " " else { return nil }
            return BulletInfo(indent: indent, text: String(rest).trimmingCharacters(in: .whitespaces))
        }
        // 1. / 1)
        let digits = content.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let afterDigits = content.dropFirst(digits.count)
        guard let marker = afterDigits.first, marker == "." || marker == ")" else { return nil }
        let rest = afterDigits.dropFirst()
        guard rest.first == " " else { return nil }
        return BulletInfo(indent: indent, text: String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func markdownTitle(from lines: [String]) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let heading = headingInfo(trimmed), heading.level == 1 {
                let clean = cleanInline(heading.text)
                return clean.isEmpty ? String(localized: "未命名导图") : clean
            }
            if let bullet = bulletInfo(line) {
                let clean = cleanInline(bullet.text)
                if !clean.isEmpty { return clean }
            }
            return cleanInline(trimmed).isEmpty ? String(localized: "未命名导图") : cleanInline(trimmed)
        }
        return String(localized: "未命名导图")
    }

    static func cleanInline(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 任务列表标记
        if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = String(text.dropFirst(4))
        }
        let patterns: [(String, String)] = [
            ("\\[([^\\]]+)\\]\\([^\\)]*\\)", "$1"),
            ("\\*\\*(.+?)\\*\\*", "$1"),
            ("__(.+?)__", "$1"),
            ("~~(.+?)~~", "$1"),
            ("`(.+?)`", "$1"),
            ("\\*(.+?)\\*", "$1"),
            ("(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])", "$1"),
            ("<[^>]+>", "")
        ]
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OPML

    static func opml(_ data: Data, themeID: String, layout: MapLayout) throws -> MindMap {
        let parser = XMLParser(data: data)
        let delegate = OPMLDelegate()
        parser.delegate = delegate
        guard parser.parse(), !delegate.roots.isEmpty else {
            throw ImportError.invalidOPML
        }

        let roots = delegate.roots
        let title: String
        if roots.count == 1 {
            title = roots[0].text.isEmpty ? String(localized: "未命名导图") : roots[0].text
        } else {
            title = String(localized: "导入的导图")
        }

        let rootNode = MindNode(parentID: nil, text: title, order: 0)
        var nodes: [MindNode] = [rootNode]

        func append(_ item: OPMLDelegate.Item, parentID: UUID) {
            let node = MindNode(
                parentID: parentID,
                text: item.text.isEmpty ? String(localized: "未命名") : item.text,
                note: item.note,
                order: nodes.filter { $0.parentID == parentID }.count
            )
            nodes.append(node)
            for child in item.children {
                append(child, parentID: node.id)
            }
        }

        if roots.count == 1 {
            for child in roots[0].children {
                append(child, parentID: rootNode.id)
            }
            if !roots[0].note.isEmpty, let index = nodes.firstIndex(where: { $0.id == rootNode.id }) {
                nodes[index].note = roots[0].note
            }
        } else {
            for child in roots {
                append(child, parentID: rootNode.id)
            }
        }

        var map = MindMap(
            id: UUID(),
            title: title,
            nodes: nodes,
            layout: layout,
            themeID: themeID
        )
        map.createdAt = Date()
        map.updatedAt = Date()
        return map
    }
}

private final class OPMLDelegate: NSObject, XMLParserDelegate {
    struct Item {
        var text: String
        var note: String
        var children: [Item]
    }

    private(set) var roots: [Item] = []
    private var stack: [Item] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        let text = attributeDict["text"]
            ?? attributeDict["title"]
            ?? attributeDict["_text"]
            ?? ""
        let note = attributeDict["_note"] ?? attributeDict["note"] ?? ""
        stack.append(Item(text: text, note: note, children: []))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline", !stack.isEmpty else { return }
        let item = stack.removeLast()
        if stack.isEmpty {
            roots.append(item)
        } else {
            stack[stack.count - 1].children.append(item)
        }
    }
}
