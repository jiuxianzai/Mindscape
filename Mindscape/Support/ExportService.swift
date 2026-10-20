import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case pdf
    case markdown
    case opml
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG 图片"
        case .pdf: return "PDF 文档"
        case .markdown: return "Markdown 大纲"
        case .opml: return "OPML 大纲"
        case .json: return "JSON 数据"
        }
    }

    var detail: String {
        switch self {
        case .png: return "高清图片，适合发微信、文档、演示"
        case .pdf: return "矢量文档，适合打印和正式分享"
        case .markdown: return "层级大纲，可导入笔记 / 大纲工具"
        case .opml: return "通用大纲格式，可导入 XMind、OmniOutliner 等"
        case .json: return "完整数据结构，适合备份和迁移"
        }
    }

    var symbol: String {
        switch self {
        case .png: return "photo"
        case .pdf: return "doc.richtext"
        case .markdown: return "text.alignleft"
        case .opml: return "list.bullet.rectangle"
        case .json: return "curlybraces"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .opml: return "opml"
        case .json: return "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .opml: return UTType(filenameExtension: "opml") ?? .xml
        case .json: return .json
        }
    }

    var supportsScale: Bool { self == .png }
}

@MainActor
enum ExportService {
    private static var sharingPicker: NSSharingServicePicker?

    /// 弹出保存面板并写入文件，返回是否成功保存。
    static func save(
        map: MindMap,
        layout: LayoutResult,
        format: ExportFormat,
        scale: CGFloat = 2
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = "导出 \(format.title)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(safeFileName(map.title)).\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try makeData(map: map, layout: layout, format: format, scale: scale)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    static func makeData(
        map: MindMap,
        layout: LayoutResult,
        format: ExportFormat,
        scale: CGFloat = 2
    ) throws -> Data {
        switch format {
        case .png:
            return try pngData(map: map, layout: layout, scale: scale)
        case .pdf:
            return try pdfData(map: map, layout: layout)
        case .markdown:
            return Data(markdown(map: map).utf8)
        case .opml:
            return Data(opml(map: map).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(map)
        }
    }

    /// 生成用于系统分享的临时文件。
    static func temporaryURL(
        map: MindMap,
        layout: LayoutResult,
        format: ExportFormat,
        scale: CGFloat = 2
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeShare", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent(
            "\(safeFileName(map.title))-\(stamp).\(format.fileExtension)"
        )
        let data = try makeData(map: map, layout: layout, format: format, scale: scale)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func share(_ url: URL) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        sharingPicker = picker
        picker.show(
            relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
            of: view,
            preferredEdge: .minY
        )
    }

    // MARK: - Rendering

    private static func makeExportView(map: MindMap, layout: LayoutResult) -> ExportCanvasView {
        let theme = MapTheme.byID(map.themeID)
        let size = CGSize(
            width: max(layout.bounds.width, 420),
            height: max(layout.bounds.height, 320)
        )
        let view = ExportCanvasView(map: map, layout: layout, theme: theme)
        view.frame = CGRect(origin: .zero, size: size)
        return view
    }

    private static func pdfData(map: MindMap, layout: LayoutResult) throws -> Data {
        let view = makeExportView(map: map, layout: layout)
        return view.dataWithPDF(inside: view.bounds)
    }

    private static func pngData(map: MindMap, layout: LayoutResult, scale: CGFloat) throws -> Data {
        let view = makeExportView(map: map, layout: layout)
        let pdf = view.dataWithPDF(inside: view.bounds)
        guard let image = NSImage(data: pdf) else {
            throw ExportError.renderFailed
        }

        let width = Int(ceil(view.bounds.width * scale))
        let height = Int(ceil(view.bounds.height * scale))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.renderFailed
        }
        representation.size = view.bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let rect = NSRect(origin: .zero, size: view.bounds.size)
        NSColor.clear.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ExportError.renderFailed
        }
        return data
    }

    // MARK: - Text formats

    static func markdown(map: MindMap) -> String {
        var lines: [String] = ["# \(map.title)", ""]
        let rootID = map.rootID

        func walk(_ id: UUID, depth: Int) {
            guard let node = map.node(id) else { return }
            let indent = String(repeating: "  ", count: depth)
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = "\(indent)- \(text.isEmpty ? "未命名" : text)"
            lines.append(line)
            let note = node.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                for noteLine in note.split(separator: "\n") {
                    lines.append("\(indent)  > \(noteLine)")
                }
            }
            for child in map.children(of: id) {
                walk(child.id, depth: depth + 1)
            }
        }

        walk(rootID, depth: 0)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func opml(map: MindMap) -> String {
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<opml version=\"2.0\">",
            "<head><title>\(escapeXML(map.title))</title></head>",
            "<body>"
        ]

        func walk(_ id: UUID, depth: Int) {
            guard let node = map.node(id) else { return }
            let indent = String(repeating: "  ", count: depth)
            var attributes = "text=\"\(escapeXML(node.text.isEmpty ? "未命名" : node.text))\""
            let note = node.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                attributes += " _note=\"\(escapeXML(note))\""
            }
            let children = map.children(of: id)
            if children.isEmpty {
                lines.append("\(indent)<outline \(attributes)/>")
            } else {
                lines.append("\(indent)<outline \(attributes)>")
                for child in children {
                    walk(child.id, depth: depth + 1)
                }
                lines.append("\(indent)</outline>")
            }
        }

        walk(map.rootID, depth: 1)
        lines.append("</body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n")
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "未命名导图" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|")
        return base.components(separatedBy: invalid).joined(separator: "-")
    }
}

enum ExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? { "生成导出文件失败" }
}

final class ExportCanvasView: NSView {
    private let map: MindMap
    private let layout: LayoutResult
    private let theme: MapTheme

    init(map: MindMap, layout: LayoutResult, theme: MapTheme) {
        self.map = map
        self.layout = layout
        self.theme = theme
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        MapRenderer.drawBackground(theme: theme, in: bounds)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let offsetX = -layout.bounds.minX
        let offsetY = -layout.bounds.minY
        context.saveGState()
        context.translateBy(x: offsetX, y: offsetY)
        MapRenderer.draw(
            map: map,
            layout: layout,
            theme: theme,
            selection: RenderSelection(),
            in: context
        )
        context.restoreGState()
    }
}
