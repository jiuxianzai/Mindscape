import AppKit

struct CanvasCamera {
    var center: CGPoint = .zero
    var zoom: CGFloat = 1
    static let minZoom: CGFloat = 0.15
    static let maxZoom: CGFloat = 3.5
}

final class MindCanvasView: NSView, NSTextFieldDelegate {
    weak var editor: MapEditor?

    private var theme: MapTheme = MapTheme.all[0]
    private var layoutResult: LayoutResult?
    private var layoutRevision: Int = -1
    private var layoutDocumentID: UUID?
    private var camera = CanvasCamera()
    private var lastFitToken: Int = -1
    private var hasFitted = false

    private var drag: DragState?
    private var dragOffset: CGSize = .zero
    private var editField: NSTextField?
    private var editingID: UUID?

    private enum DragState {
        case pan(startPoint: CGPoint, startCenter: CGPoint)
        case node(id: UUID, startPoint: CGPoint, originalFrame: CGRect)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Attach

    func attach(editor: MapEditor, theme: MapTheme) {
        if self.editor !== editor {
            self.editor = editor
            layoutResult = nil
            layoutRevision = -1
            layoutDocumentID = nil
            lastFitToken = -1
            hasFitted = false
            camera = CanvasCamera()
            cancelEditing()
        }
        self.theme = theme
        rebuildLayoutIfNeeded()
        needsDisplay = true
    }

    // MARK: - Layout cache

    private func rebuildLayoutIfNeeded(force: Bool = false) {
        guard let editor else { return }
        if force || layoutResult == nil || layoutRevision != editor.revision || layoutDocumentID != editor.map.id {
            layoutResult = LayoutEngine.layout(editor.map)
            layoutRevision = editor.revision
            layoutDocumentID = editor.map.id
        }
        if editor.fitToken != lastFitToken {
            lastFitToken = editor.fitToken
            if bounds.width > 40, bounds.height > 40 {
                fitToContent()
            } else {
                hasFitted = false
            }
        }
    }

    func fitToContent() {
        guard let layout = layoutResult, !layout.bounds.isEmpty else { return }
        let padding: CGFloat = 72
        let availableWidth = max(bounds.width - padding * 2, 100)
        let availableHeight = max(bounds.height - padding * 2, 100)
        let scale = min(availableWidth / max(layout.bounds.width, 1), availableHeight / max(layout.bounds.height, 1))
        camera.zoom = min(max(scale, CanvasCamera.minZoom), 1.35)
        camera.center = CGPoint(x: layout.bounds.midX, y: layout.bounds.midY)
        hasFitted = true
        updateEditorFrame()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if bounds.width > 40, bounds.height > 40, !hasFitted {
            rebuildLayoutIfNeeded(force: true)
            fitToContent()
        }
        updateEditorFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Coordinate conversion

    func worldToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - camera.center.x) * camera.zoom + bounds.midX,
            y: (point.y - camera.center.y) * camera.zoom + bounds.midY
        )
    }

    func viewToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - bounds.midX) / camera.zoom + camera.center.x,
            y: (point.y - bounds.midY) / camera.zoom + camera.center.y
        )
    }

    private func worldRectToView(_ rect: CGRect) -> CGRect {
        let origin = worldToView(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * camera.zoom, height: rect.height * camera.zoom)
    }

    private var visibleWorldRect: CGRect {
        let width = bounds.width / camera.zoom
        let height = bounds.height / camera.zoom
        return CGRect(x: camera.center.x - width / 2, y: camera.center.y - height / 2, width: width, height: height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let editor else {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            return
        }
        rebuildLayoutIfNeeded()

        MapRenderer.drawBackground(theme: theme, in: bounds)
        guard let layout = layoutResult, let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: camera.zoom, y: camera.zoom)
        context.translateBy(x: -camera.center.x, y: -camera.center.y)

        drawGrid(in: context)
        MapRenderer.draw(
            map: editor.map,
            layout: layout,
            theme: theme,
            selection: RenderSelection(
                ids: editor.selection,
                dragNodeID: dragNodeID,
                dragOffset: dragOffset
            ),
            in: context
        )
        context.restoreGState()
    }

    private var dragNodeID: UUID? {
        if case .node(let id, _, _)? = drag { return id }
        return nil
    }

    private func drawGrid(in context: CGContext) {
        guard theme.showsGrid, camera.zoom > 0.4 else { return }
        let step = 26 / camera.zoom
        let rect = visibleWorldRect
        let startX = floor(rect.minX / step) * step
        let startY = floor(rect.minY / step) * step
        let radius = 0.9 / camera.zoom
        theme.grid.withAlphaComponent(0.85).setFill()

        var x = startX
        var count = 0
        while x <= rect.maxX {
            var y = startY
            while y <= rect.maxY {
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                y += step
                count += 1
                if count > 5000 { return }
            }
            x += step
        }
    }

    // MARK: - Hit testing

    private func hitTest(worldPoint: CGPoint, excluding: UUID? = nil) -> UUID? {
        guard let layout = layoutResult else { return nil }
        for id in layout.drawOrder.reversed() {
            if id == excluding { continue }
            if layout.frames[id]?.contains(worldPoint) == true { return id }
        }
        return nil
    }

    private func hitTest(viewPoint: CGPoint, excluding: UUID? = nil) -> UUID? {
        hitTest(worldPoint: viewToWorld(viewPoint), excluding: excluding)
    }

    private func badgeRect(for id: UUID) -> CGRect? {
        guard let editor,
              let layout = layoutResult,
              let node = editor.map.node(id),
              node.collapsed,
              let rules = layout.children[id], !rules.isEmpty,
              let rect = layout.frames[id] else { return nil }
        let rootMidX = layout.frames[layout.rootID ?? id]?.midX ?? 0
        let outward: CGFloat = rect.midX >= rootMidX ? 1 : -1
        let center = CGPoint(x: rect.midX + outward * (rect.width / 2 + 11), y: rect.midY)
        return CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if editingID != nil { commitEditing() }

        let point = convert(event.locationInWindow, from: nil)
        let worldPoint = viewToWorld(point)

        if event.clickCount == 2, let id = hitTest(worldPoint: worldPoint) {
            beginEditing(id)
            return
        }

        if let layout = layoutResult {
            for (id, _) in layout.frames {
                if badgeRect(for: id)?.contains(worldPoint) == true {
                    editor?.toggleCollapse(id)
                    needsDisplay = true
                    return
                }
            }
        }

        if let id = hitTest(worldPoint: worldPoint) {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            editor?.select(id, additive: additive)
            if let frame = layoutResult?.frames[id] {
                drag = .node(id: id, startPoint: point, originalFrame: frame)
                dragOffset = .zero
            }
            needsDisplay = true
        } else {
            if !event.modifierFlags.contains(.shift) { editor?.clearSelection() }
            drag = .pan(startPoint: point, startCenter: camera.center)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .pan(let startPoint, let startCenter):
            camera.center.x = startCenter.x - (point.x - startPoint.x) / camera.zoom
            camera.center.y = startCenter.y - (point.y - startPoint.y) / camera.zoom
            updateEditorFrame()
            needsDisplay = true
        case .node(_, _, _):
            dragOffset = CGSize(
                width: (point.x - dragStartPoint(drag).x) / camera.zoom,
                height: (point.y - dragStartPoint(drag).y) / camera.zoom
            )
            needsDisplay = true
        }
    }

    private func dragStartPoint(_ drag: DragState) -> CGPoint {
        switch drag {
        case .pan(let point, _): return point
        case .node(_, let point, _): return point
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        defer {
            self.drag = nil
            dragOffset = .zero
            needsDisplay = true
        }
        guard case .node(let id, _, let originalFrame) = drag else { return }

        if editor?.map.layout == .free {
            if abs(dragOffset.width) > 1 || abs(dragOffset.height) > 1 {
                let origin = CGPoint(x: originalFrame.minX + dragOffset.width, y: originalFrame.minY + dragOffset.height)
                editor?.moveFreeNode(id: id, to: origin)
            }
        } else {
            let point = convert(event.locationInWindow, from: nil)
            if let target = hitTest(viewPoint: point, excluding: id), let editor, editor.canMove(id, to: target) {
                editor.move(id: id, to: target)
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = hitTest(viewPoint: point) else { return }
        editor?.select(id)
        needsDisplay = true
        NSMenu.popUpContextMenu(contextMenu(for: id), with: event, for: self)
    }

    private func contextMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "添加子主题", action: #selector(menuAddChild), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let edit = NSMenuItem(title: "编辑文字", action: #selector(menuEdit), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        if let editor, !editor.map.children(of: id).isEmpty {
            let collapsed = editor.map.node(id)?.collapsed == true
            let toggle = NSMenuItem(title: collapsed ? "展开分支" : "折叠分支", action: #selector(menuToggleCollapse), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
        }

        menu.addItem(.separator())
        let delete = NSMenuItem(title: "删除", action: #selector(menuDelete), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = id != editor?.map.rootID
        menu.addItem(delete)

        menu.addItem(.separator())
        let colorMenu = NSMenu()
        let colors: [(String, String)] = [
            ("无", ""), ("珊瑚", "#E8836B"), ("琥珀", "#E6B450"), ("薄荷", "#7FB89A"),
            ("天蓝", "#7BA7D9"), ("紫罗兰", "#A28BC9"), ("石墨", "#4A4A52")
        ]
        for (name, hex) in colors {
            let item = NSMenuItem(title: name, action: #selector(menuSetColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hex
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "节点颜色", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        return menu
    }

    @objc private func menuAddChild() {
        guard let id = editor?.selection.first, let newID = editor?.addChild(to: id) else { return }
        beginEditing(newID)
    }

    @objc private func menuEdit() {
        guard let id = editor?.selection.first else { return }
        beginEditing(id)
    }

    @objc private func menuToggleCollapse() {
        guard let id = editor?.selection.first else { return }
        editor?.toggleCollapse(id)
    }

    @objc private func menuDelete() {
        editor?.deleteSelection()
    }

    @objc private func menuSetColor(_ sender: NSMenuItem) {
        guard let id = editor?.selection.first else { return }
        let hex = sender.representedObject as? String
        editor?.setColor(hex?.isEmpty == true ? nil : hex, for: id)
    }

    // MARK: - Scrolling & zoom

    override func scrollWheel(with event: NSEvent) {
        if editingID != nil { commitEditing() }
        let point = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) {
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
            let factor = 1 + event.scrollingDeltaY * sensitivity
            zoom(by: factor, at: point)
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            camera.center.x -= event.scrollingDeltaX * multiplier / camera.zoom
            camera.center.y -= event.scrollingDeltaY * multiplier / camera.zoom
            updateEditorFrame()
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        if editingID != nil { commitEditing() }
        let point = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, at: point)
    }

    private func zoom(by factor: CGFloat, at viewPoint: CGPoint) {
        let before = viewToWorld(viewPoint)
        let next = min(max(camera.zoom * factor, CanvasCamera.minZoom), CanvasCamera.maxZoom)
        guard next != camera.zoom else { return }
        camera.zoom = next
        let after = viewToWorld(viewPoint)
        camera.center.x += before.x - after.x
        camera.center.y += before.y - after.y
        updateEditorFrame()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard editingID == nil, let editor else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "=", "+":
                zoom(by: 1.2, at: CGPoint(x: bounds.midX, y: bounds.midY))
                return
            case "-", "_":
                zoom(by: 0.83, at: CGPoint(x: bounds.midX, y: bounds.midY))
                return
            case "0":
                fitToContent()
                return
            default:
                super.keyDown(with: event)
                return
            }
        }

        switch event.keyCode {
        case 48: // Tab
            if let id = editor.selection.first, let newID = editor.addChild(to: id) {
                focusAndEdit(newID)
            }
        case 36, 76: // Return
            if let id = editor.selection.first, let newID = editor.addSibling(after: id) {
                focusAndEdit(newID)
            }
        case 51, 117: // Delete
            editor.deleteSelection()
        case 53: // Esc
            editor.clearSelection()
        case 49: // Space
            if let id = editor.selection.first { editor.toggleCollapse(id) }
        case 120: // F2
            if let id = editor.selection.first { beginEditing(id) }
        case 123:
            navigate(dirX: -1, dirY: 0)
        case 124:
            navigate(dirX: 1, dirY: 0)
        case 125:
            navigate(dirX: 0, dirY: 1)
        case 126:
            navigate(dirX: 0, dirY: -1)
        default:
            super.keyDown(with: event)
        }
    }

    private func navigate(dirX: CGFloat, dirY: CGFloat) {
        guard let editor,
              let layout = layoutResult,
              let currentID = editor.selection.first,
              let current = layout.frames[currentID] else { return }

        var best: (id: UUID, score: CGFloat)?
        for (id, frame) in layout.frames where id != currentID {
            let dx = frame.midX - current.midX
            let dy = frame.midY - current.midY
            let forward = dx * dirX + dy * dirY
            guard forward > 6 else { continue }
            let lateral = abs(dx * dirY) + abs(dy * dirX)
            let score = forward + lateral * 2.4
            if best == nil || score < best!.score {
                best = (id, score)
            }
        }
        if let best {
            editor.select(best.id)
            if let frame = layout.frames[best.id], !visibleWorldRect.insetBy(dx: 20, dy: 20).contains(frame) {
                camera.center = CGPoint(x: frame.midX, y: frame.midY)
                needsDisplay = true
            }
        }
    }

    private func focusAndEdit(_ id: UUID) {
        rebuildLayoutIfNeeded(force: true)
        ensureVisible(id)
        beginEditing(id)
    }

    private func ensureVisible(_ id: UUID) {
        guard let frame = layoutResult?.frames[id] else { return }
        if !visibleWorldRect.insetBy(dx: -20, dy: -20).contains(frame) {
            camera.center = CGPoint(x: frame.midX, y: frame.midY)
            needsDisplay = true
        }
    }

    // MARK: - Inline editing

    func beginEditing(_ id: UUID) {
        guard let editor, let node = editor.map.node(id) else { return }
        commitEditing()
        rebuildLayoutIfNeeded(force: true)
        guard let layout = layoutResult, let frame = layout.frames[id] else { return }
        if !visibleWorldRect.contains(frame) {
            camera.center = CGPoint(x: frame.midX, y: frame.midY)
            needsDisplay = true
        }

        let level = min(layout.depths[id] ?? 0, 2)
        let rect = worldRectToView(frame)
        let font = NodeMeasurer.font(level: level)
        let screenFont = NSFont(descriptor: font.fontDescriptor, size: max(font.pointSize * camera.zoom, 9)) ?? font
        let height = max(24, screenFont.pointSize * 1.55)

        let field = NSTextField(frame: CGRect(
            x: rect.minX + 5,
            y: rect.midY - height / 2,
            width: max(rect.width - 10, 30),
            height: height
        ))
        field.stringValue = node.text
        field.placeholderString = "输入主题"
        field.font = screenFont
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = fillColor(for: node, level: level)
        field.textColor = textColor(for: node, level: level)
        field.focusRingType = .none
        field.alignment = level == 0 ? .center : .left
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        addSubview(field)

        editField = field
        editingID = id
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func fillColor(for node: MindNode, level: Int) -> NSColor {
        if let hex = node.colorHex { return NSColor(hex: hex) }
        switch level {
        case 0: return theme.rootFill
        case 1: return theme.branchFill
        default: return theme.nodeFill
        }
    }

    private func textColor(for node: MindNode, level: Int) -> NSColor {
        if let hex = node.colorHex {
            let fill = NSColor(hex: hex)
            return fill.luminance > 0.62 ? NSColor.black : NSColor.white
        }
        switch level {
        case 0: return theme.rootText
        case 1: return theme.branchText
        default: return theme.nodeText
        }
    }

    func commitEditing() {
        guard let field = editField, let id = editingID else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        editingID = nil
        editField = nil
        field.delegate = nil
        field.removeFromSuperview()

        if text.isEmpty {
            if editor?.map.node(id)?.parentID == nil {
                editor?.setText("中心主题", for: id)
            } else {
                editor?.delete(id: id)
            }
        } else if let node = editor?.map.node(id), node.text != text {
            editor?.setText(text, for: id)
        }

        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func cancelEditing() {
        guard let field = editField else { return }
        editingID = nil
        editField = nil
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func updateEditorFrame() {
        guard let field = editField, let id = editingID,
              let layout = layoutResult, let frame = layout.frames[id],
              let level = layout.depths[id] else { return }

        let rect = worldRectToView(frame)
        let baseFont = NodeMeasurer.font(level: min(level, 2))
        let font = NSFont(descriptor: baseFont.fontDescriptor, size: max(baseFont.pointSize * camera.zoom, 9)) ?? baseFont
        field.font = font
        let height = max(24, font.pointSize * 1.55)
        field.frame = CGRect(
            x: rect.minX + 5,
            y: rect.midY - height / 2,
            width: max(rect.width - 10, 30),
            height: height
        )
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        if editingID != nil { commitEditing() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }
}

private extension NSColor {
    var luminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 1 }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }
}
