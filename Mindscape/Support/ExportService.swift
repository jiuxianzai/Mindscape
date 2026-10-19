import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case pdf
    case markdown
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG 图片"
        case .pdf: return "PDF 文档"
        case .markdown: return "Markdown 大纲"
        case .json: return "JSON 数据"
        }
    }

    var symbol: String {
        switch self {
        case .png: return "photo"
        case .pdf: return "doc.richtext"
        case .markdown: return "text.alignleft"
        case .json: return "curlybraces"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .json: return "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .json: return .json
        }
    }
}

@MainActor
enum ExportService {
    static func export(map: MindMap, layout: LayoutResult, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.title = "导出 \(format.title)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(safeFileName(map.title)).\(format.fileExtension)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                do {
                    try write(map: map, layout: layout, format: format, to: url)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    private static func write(map: MindMap, layout: LayoutResult, format: ExportFormat, to url: URL) throws {
        switch format {
        case .png:
            let data = try pngData(map: map, layout: layout)
            try data.write(to: url, options: .atomic)
        case .pdf:
            let data = try pdfData(map: map, layout: layout)
            try data.write(to: url, options: .atomic)
        case .markdown:
            let text = markdown(map: map)
            try text.write(to: url, atomically: true, encoding: .utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(map)
            try data.write(to: url, options: .atomic)
        }
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

    private static func pngData(map: MindMap, layout: LayoutResult) throws -> Data {
        let view = makeExportView(map: map, layout: layout)
        let pdf = view.dataWithPDF(inside: view.bounds)
        guard let image = NSImage(data: pdf) else {
            throw ExportError.renderFailed
        }

        let scale: CGFloat = 2
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

    // MARK: - Markdown

    static func markdown(map: MindMap) -> String {
        var lines: [String] = ["# \(map.title)", ""]
        let rootID = map.rootID

        func walk(_ id: UUID, depth: Int) {
            guard let node = map.node(id) else { return }
            let indent = String(repeating: "  ", count: depth)
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = "\(indent)- \(text.isEmpty ? "未命名" : text)"
            if let emoji = node.emoji, !emoji.isEmpty {
                line = "\(indent)- \(emoji) \(text)"
            }
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

    private static func safeFileName(_ name: String) -> String {
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
