import AppKit
import Dispatch
import Foundation
import Observation

/// AI 投递通道：监听 `<dataDir>/inbox/`，把请求交给 store，回写 ack。
///
/// 设计约束（见 AI-INTEGRATION.md）：
/// - 判定权在这里，不在工具侧。工具看不到编辑状态，所以忙判定只能由 app 做。
/// - 失败永不丢请求：原文件移进 `rejected/`，用户保存后重发即可。
/// - 不写库以外的任何外部状态；`outbox/state.json` 只读给 agent 看"用户在干什么"。
@MainActor
@Observable
final class AIInbox {
    static let shared = AIInbox()

    /// 非模态提示条的文案；nil 表示不显示
    private(set) var lastRejection: String?

    @ObservationIgnored private weak var store: DocumentStore?
    @ObservationIgnored private var editorProvider: (() -> MapEditor?)?
    @ObservationIgnored private var onImported: ((UUID) -> Void)?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var isEnabled = true

    private init() {}

    // MARK: - 生命周期

    func start(
        store: DocumentStore,
        editorProvider: @escaping () -> MapEditor?,
        onImported: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.editorProvider = editorProvider
        self.onImported = onImported
        isEnabled = UserDefaults.standard.object(forKey: "aiInboxEnabled") as? Bool ?? true

        ensureDirectories()
        startWatching()
        scanPending()
        publishContext()

        heartbeat?.invalidate()
        // 5 秒一次的心跳：既刷新 outbox 的 ts（工具据此判断 app 在不在），
        // 也顺手补扫一次 inbox——FSEvents 在休眠/合并时可能丢事件，扫目录很便宜。
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanPending()
                self?.publishContext()
            }
        }
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        source?.cancel()
        source = nil
        if watchedFD >= 0 {
            close(watchedFD)
            watchedFD = -1
        }
    }

    func dismissBanner() {
        lastRejection = nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            scanPending()
        }
    }

    // MARK: - 目录

    private var rootDirectory: URL? { store?.directoryURL }

    private var inboxDirectory: URL? {
        rootDirectory?.appendingPathComponent("inbox", isDirectory: true)
    }

    private var outboxDirectory: URL? {
        rootDirectory?.appendingPathComponent("outbox", isDirectory: true)
    }

    private func ensureDirectories() {
        guard let inbox = inboxDirectory, let outbox = outboxDirectory else { return }
        let fm = FileManager.default
        for directory in [inbox, inbox.appendingPathComponent("done"), inbox.appendingPathComponent("rejected"), outbox] {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func startWatching() {
        guard source == nil, let inbox = inboxDirectory else { return }
        let fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scanPending()
            }
        }
        source.resume()
        self.source = source
    }

    // MARK: - 消费

    func scanPending() {
        guard isEnabled, !isScanning, let inbox = inboxDirectory else { return }
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let requests = entries
            .filter { $0.lastPathComponent.hasPrefix("req-") && $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in requests {
            handle(url)
        }
        cleanupAcks(in: inbox)
    }

    private func handle(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let key = String(name.dropFirst("req-".count))

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw AIRequestError.invalid("拒绝符号链接")
            }
            if let size = values.fileSize, size > AILimits.fileBytes {
                throw AIRequestError.tooLarge("请求文件超过 2 MB")
            }
            let data = try Data(contentsOf: url)
            let request: AIRequest
            do {
                request = try JSONDecoder().decode(AIRequest.self, from: data)
            } catch {
                throw AIRequestError.invalid("请求 JSON 无法解析：\(error.localizedDescription)")
            }
            let ack = try apply(request)
            writeAck(ack, key: key)
            archive(url, success: true)
        } catch {
            let bridgeError = error as? AIRequestError
            let ack = AIAck(
                ok: false,
                reason: bridgeError?.reason ?? "invalid",
                message: error.localizedDescription,
                docID: nil,
                title: nil,
                action: nil,
                nodeCount: nil
            )
            writeAck(ack, key: key)
            archive(url, success: false)

            switch bridgeError {
            case .busy(let message)?, .stale(let message)?:
                lastRejection = message
            default:
                break
            }
        }
    }

    private func apply(_ request: AIRequest) throws -> AIAck {
        guard let store else {
            throw AIRequestError.unsupported("数据库不可用")
        }
        let icons = knownIcons

        switch request.op {
        case "create":
            var map = try AIInboxFormat.makeMap(from: request, knownIcons: icons)
            map.themeID = MapTheme.byID(map.themeID).id
            try store.save(map)
            publishContext()
            onImported?(map.id)
            return AIAck(
                ok: true,
                reason: nil,
                message: nil,
                docID: map.id.uuidString,
                title: map.title,
                action: "created",
                nodeCount: map.nodes.count
            )

        case "patch":
            guard let raw = request.doc, let docID = UUID(uuidString: raw) else {
                throw AIRequestError.invalid("doc 不是合法 UUID")
            }
            guard let edits = request.edits, !edits.isEmpty else {
                throw AIRequestError.invalid("edits 不能为空")
            }
            guard let existing = try store.load(id: docID) else {
                throw AIRequestError.notFound("找不到这张导图")
            }

            // 忙判定：只针对用户正打开的那张图
            let editor = editorProvider?()
            if let editor, editor.map.id == docID {
                if editor.hasPendingSave {
                    throw AIRequestError.busy("《\(existing.title)》还有未保存的改动，已拒绝写入")
                }
                if editor.editingNodeID != nil {
                    throw AIRequestError.busy("你正在编辑《\(existing.title)》里的节点，已拒绝写入")
                }
            }

            if let base = request.baseUpdatedAt,
               abs(base - existing.updatedAt.timeIntervalSince1970) > 0.001 {
                throw AIRequestError.stale(
                    "这张图在你读取之后被改过（updatedAt=\(existing.updatedAt.timeIntervalSince1970)），请重新读取"
                )
            }

            var updated = existing
            try AIInboxFormat.apply(edits, to: &updated, knownIcons: icons)
            updated.themeID = MapTheme.byID(updated.themeID).id
            updated.updatedAt = Date()

            try? store.addSnapshot(existing, name: String(localized: "AI 修改前"), kind: "ai")
            try store.save(updated)

            if let editor, editor.map.id == docID {
                editor.applyExternal(updated)
            }
            publishContext()
            return AIAck(
                ok: true,
                reason: nil,
                message: nil,
                docID: updated.id.uuidString,
                title: updated.title,
                action: "patched",
                nodeCount: updated.nodes.count
            )

        default:
            throw AIRequestError.invalid("未知 op \(request.op)")
        }
    }

    private var knownIcons: Set<String> {
        Set(IconCatalog.all.map(\.symbol))
    }

    // MARK: - 回执

    private func writeAck(_ ack: AIAck, key: String) {
        guard let inbox = inboxDirectory else { return }
        let url = inbox.appendingPathComponent("ack-\(key).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ack) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func archive(_ url: URL, success: Bool) {
        guard let inbox = inboxDirectory else { return }
        let folder = success ? "done" : "rejected"
        let destination = inbox
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: url, to: destination)
        } catch {
            try? fm.removeItem(at: url)
        }
    }

    /// 工具超时后不会再来读 ack，超过一分钟的清掉，避免目录长草
    private func cleanupAcks(in inbox: URL) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let now = Date()
        for url in entries where url.lastPathComponent.hasPrefix("ack-") {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > 60 else { continue }
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - 上下文（app -> agent）

    func publishContext() {
        guard isEnabled, let outbox = outboxDirectory else { return }
        let editor = editorProvider?()
        let state = AIContextState(
            ts: Date().timeIntervalSince1970,
            docID: editor?.map.id.uuidString,
            title: editor?.map.title,
            layout: editor?.map.layout.rawValue,
            theme: editor?.map.themeID,
            selection: (editor?.selectedNodes ?? []).prefix(20).map {
                AISelection(id: $0.id.uuidString, text: $0.text)
            },
            editingNode: editor?.editingNodeID?.uuidString,
            unsaved: editor?.hasPendingSave ?? false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: outbox.appendingPathComponent("state.json"), options: .atomic)
    }
}

// MARK: - 线格式

struct AISelection: Codable {
    var id: String
    var text: String
}

struct AIContextState: Codable {
    var ts: Double
    var docID: String?
    var title: String?
    var layout: String?
    var theme: String?
    var selection: [AISelection]
    var editingNode: String?
    var unsaved: Bool
}

struct AIAck: Codable {
    var ok: Bool
    var reason: String?
    var message: String?
    var docID: String?
    var title: String?
    var action: String?
    var nodeCount: Int?
}
