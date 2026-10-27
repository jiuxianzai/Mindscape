import AppKit

/// 子树复制时写入剪贴板的数据。节点保留原始 ID，粘贴时再统一换成新 ID。
struct NodeClipboardPayload: Codable, Sendable {
    var nodes: [MindNode]
    var rootIDs: [UUID]
    var sourceTitle: String
}

/// 应用内的分支剪贴板：内存缓存 + 自定义 NSPasteboard 类型，
/// 这样同一份数据在多个窗口 / 多次启动之间也能粘贴。
@MainActor
enum NodeClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("com.youyanping.mindscape.nodes")

    private static var cached: NodeClipboardPayload?
    private static var cachedChangeCount: Int = -1

    /// 同时写入自定义节点数据和纯文本大纲，方便粘贴到其它 App。
    static func write(_ payload: NodeClipboardPayload, plainText: String? = nil) {
        cached = payload
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
        if let plainText, !plainText.isEmpty {
            pasteboard.setString(plainText, forType: .string)
        }
        cachedChangeCount = pasteboard.changeCount
    }

    static func read() -> NodeClipboardPayload? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: pasteboardType),
           let payload = try? JSONDecoder().decode(NodeClipboardPayload.self, from: data),
           !payload.nodes.isEmpty {
            cached = payload
            cachedChangeCount = pasteboard.changeCount
            return payload
        }
        // 剪贴板被其它 App 覆盖后，不再返回旧的缓存
        if let cached, pasteboard.changeCount == cachedChangeCount {
            return cached
        }
        cached = nil
        return nil
    }

    /// 剪贴板里没有节点数据时，退回系统纯文本（支持从大纲 / 聊天记录粘贴）。
    static func readText() -> String? {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static var hasContent: Bool {
        read() != nil || readText() != nil
    }

    static func clear() {
        cached = nil
        cachedChangeCount = -1
        let pasteboard = NSPasteboard.general
        if pasteboard.data(forType: pasteboardType) != nil {
            pasteboard.clearContents()
        }
    }
}
