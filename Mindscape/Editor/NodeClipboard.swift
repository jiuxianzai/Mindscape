import AppKit

/// 子树复制时写入剪贴板的数据。节点保留原始 ID，粘贴时再统一换成新 ID。
struct NodeClipboardPayload: Codable, Sendable {
    var nodes: [MindNode]
    var rootIDs: [UUID]
    var sourceTitle: String

    var rootCount: Int { rootIDs.count }
    var nodeCount: Int { nodes.count }
}

/// 应用内的分支剪贴板：内存缓存 + 自定义 NSPasteboard 类型，
/// 这样同一份数据在多个窗口 / 多次启动之间也能粘贴。
@MainActor
enum NodeClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("com.youyanping.mindscape.nodes")

    private static var cached: NodeClipboardPayload?
    private static var cachedChangeCount: Int = -1

    static func write(_ payload: NodeClipboardPayload) {
        cached = payload
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
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

    static var hasContent: Bool {
        read() != nil
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
