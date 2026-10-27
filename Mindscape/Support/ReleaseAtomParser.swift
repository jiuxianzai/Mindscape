import Foundation

struct ReleaseAtomEntry {
    let tag: String
    let title: String
    let notes: String
    let updated: Date?
    let pageURL: URL?
}

/// GitHub Releases 的 Atom 源。没有 API 配额，用来在 403 / 限流时兜底拿版本号和更新说明。
enum ReleaseAtomParser {
    static func latestEntry(from data: Data) -> ReleaseAtomEntry? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.entries.first
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [ReleaseAtomEntry] = []

        private var isInsideEntry = false
        private var currentElement = ""
        private var buffer = ""
        private var linkHref: String?
        private var linkRel: String?
        private var title = ""
        private var content = ""
        private var updatedRaw = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "entry" {
                isInsideEntry = true
                linkHref = nil
                linkRel = nil
                title = ""
                content = ""
                updatedRaw = ""
                buffer = ""
                return
            }
            guard isInsideEntry else { return }

            if elementName == "link" {
                linkHref = attributeDict["href"]
                linkRel = attributeDict["rel"]
                return
            }

            currentElement = elementName
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard isInsideEntry, currentElement != "link" else { return }
            buffer += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard isInsideEntry, currentElement != "link" else { return }
            buffer += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "entry" {
                isInsideEntry = false
                appendEntryIfPossible()
                return
            }
            guard isInsideEntry else { return }

            switch elementName {
            case "title":
                title = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "content":
                content = buffer
            case "updated":
                updatedRaw = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                break
            }
            buffer = ""
        }

        private func appendEntryIfPossible() {
            let href = linkHref ?? ""
            guard linkRel == "alternate" || linkRel == nil else { return }
            guard let pageURL = URL(string: href) else { return }
            let tag = pageURL.lastPathComponent
            guard !tag.isEmpty,
                  let version = SemanticVersion(tag: tag) else { return }

            entries.append(ReleaseAtomEntry(
                tag: tag,
                title: title.isEmpty ? "Mindscape \(version.description)" : title,
                notes: ReleaseNotes.plainText(fromHTML: content),
                updated: ISO8601DateFormatter.parse(updatedRaw),
                pageURL: pageURL
            ))
        }
    }
}

enum ReleaseNotes {
    /// API 返回的是 Markdown；展示前转成保留换行的纯文本，避免 SwiftUI 的 Markdown
    /// 解析把单个换行折叠成空格，整段说明挤成一坨。
    static func plainText(fromMarkdown markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n").map { line -> String in
            var value = line
            value = value.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: "^>\\s?", with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "• ", options: .regularExpression)
            value = value.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            value = value.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            value = value.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
            value = value.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            return value
        }
        let text = lines.joined(separator: "\n")
        return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Atom 里给的是转义后的 HTML；转成可读纯文本，避免把标签直接显示给用户。
    static func plainText(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html
        text = text.replacingOccurrences(of: "\r\n", with: "\n")

        let breaks = [
            ("</p>", "\n\n"), ("</div>", "\n\n"), ("</h1>", "\n\n"), ("</h2>", "\n\n"),
            ("</h3>", "\n\n"), ("</ul>", "\n\n"), ("</ol>", "\n\n"), ("</blockquote>", "\n\n"),
            ("<br />", "\n"), ("<br/>", "\n"), ("<br>", "\n"),
            ("</li>", "\n"), ("<li>", "• ")
        ]
        for (needle, replacement) in breaks {
            text = text.replacingOccurrences(of: needle, with: replacement, options: .caseInsensitive)
        }

        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        text = decodeEntities(in: text)
        text = text.replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(in text: String) -> String {
        var value = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")

        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) {
            let matches = regex.matches(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: value),
                      let codeRange = Range(match.range(at: 1), in: value) else { continue }
                let raw = String(value[codeRange])
                let scalarValue: UInt32?
                if raw.hasPrefix("x") || raw.hasPrefix("X") {
                    scalarValue = UInt32(raw.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(raw, radix: 10)
                }
                if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                    value.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }

        return value.replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension ISO8601DateFormatter {
    /// GitHub 的 API 一般不带毫秒，Atom 有时带；两种都试一次。
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return internet.date(from: trimmed) ?? flexible.date(from: trimmed)
    }

    static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
