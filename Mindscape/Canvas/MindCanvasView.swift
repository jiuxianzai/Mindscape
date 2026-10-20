import AppKit

struct CanvasCamera {
    var center: CGPoint = .zero
    var zoom: CGFloat = 1
    static let minZoom: CGFloat = 0.15
    static let maxZoom: CGFloat = 3.5
}

final class MindCanvasView: NSView, NSTextViewDelegate {
    weak var editor: MapEditor?

    private var theme: MapTheme = MapTheme.all[0]
    private var layoutResult: LayoutResult?
    private var layoutRevision: Int = -1
    private var layoutDocumentID: UUID?
    private var camera = CanvasCamera()
    private var lastFitToken: Int = -1
    private var lastZoomToken: Int = 0
    private var hasFitted = false
    private var fitBoundsSize: CGSize = .zero
    private var userHasInteracted = false

    private var drag: DragState?
    private var dragOffset: CGSize = .zero
    private var dropTargetID: UUID?
    private var editTextView: NSTextView?
    private var editingID: UUID?
    private var editingOriginalText = ""

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
            lastZoomToken = 0
            hasFitted = false
            fitBoundsSize = .zero
            userHasInteracted = false
            camera = CanvasCamera()
            cancelEditing()
        }
        self.theme = theme
        rebuildLayoutIfNeeded()
        if let activeEditor = self.editor, activeEditor.zoomToken != lastZoomToken {
            lastZoomToken = activeEditor.zoomToken
            zoom(by: activeEditor.zoomFactor, at: CGPoint(x: bounds.midX, y: bounds.midY))
        }
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
        guard bounds.width >= 320, bounds.height >= 240 else {
            hasFitted = false
            return
        }
        guard let layout = layoutResult, !layout.bounds.isEmpty else { return }
        let padding: CGFloat = 72
        let availableWidth = max(bounds.width - padding * 2, 100)
        let availableHeight = max(bounds.height - padding * 2, 100)
        let scale = min(availableWidth / max(layout.bounds.width, 1), availableHeight / max(layout.bounds.height, 1))
        camera.zoom = min(max(scale, CanvasCamera.minZoom), 1.35)
        camera.center = CGPoint(x: layout.bounds.midX, y: layout.bounds.midY)
        hasFitted = true
        fitBoundsSize = bounds.size
        updateEditorFrame()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if bounds.width > 40, bounds.height > 40 {
            if !hasFitted {
                rebuildLayoutIfNeeded(force: true)
                fitToContent()
            } else if !userHasInteracted,
                      fitBoundsSize.width > 0,
                      bounds.width > fitBoundsSize.width * 1.25 {
                rebuildLayoutIfNeeded(force: true)
                fitToContent()
            }
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
                dragOffset: dragOffset,
                dropTargetID: dropTargetID,
                editingNodeID: editingID
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
        userHasInteracted = true
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
        case .node(let id, let startPoint, _):
            dragOffset = CGSize(
                width: (point.x - startPoint.x) / camera.zoom,
                height: (point.y - startPoint.y) / camera.zoom
            )
            if editor?.map.layout != .free {
                let world = viewToWorld(point)
                let target = hitTest(worldPoint: world, excluding: id)
                dropTargetID = target.flatMap { canDrop(id, on: $0) ? $0 : nil }
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        defer {
            self.drag = nil
            dragOffset = .zero
            dropTargetID = nil
            needsDisplay = true
        }
        guard case .node(let id, _, let originalFrame) = drag else { return }

        if editor?.map.layout == .free {
            if abs(dragOffset.width) > 1 || abs(dragOffset.height) > 1 {
                let origin = CGPoint(x: originalFrame.minX + dragOffset.width, y: originalFrame.minY + dragOffset.height)
                editor?.moveFreeNode(id: id, to: origin)
            }
            return
        }

        guard let target = dropTargetID,
              let editor,
              let sourceNode = editor.map.node(id),
              let targetNode = editor.map.node(target) else { return }

        let point = convert(event.locationInWindow, from: nil)
        let world = viewToWorld(point)
        let targetFrame = layoutResult?.frames[target] ?? .zero
        let relativeY = targetFrame.height > 0
            ? (world.y - targetFrame.minY) / targetFrame.height
            : 0.5

        // 默认拖到节点上 = 挂到该节点下面；按住 ⌥ 再拖到同级节点 = 调整兄弟顺序
        if event.modifierFlags.contains(.option), sourceNode.parentID == targetNode.parentID {
            editor.reorder(id: id, relativeTo: target, after: relativeY > 0.5)
        } else if editor.canMove(id, to: target) {
            editor.move(id: id, to: target)
        }
    }

    private func canDrop(_ id: UUID, on target: UUID) -> Bool {
        guard let editor, id != target, id != editor.map.rootID else { return false }
        guard let source = editor.map.node(id), let targetNode = editor.map.node(target) else { return false }
        if source.parentID == targetNode.parentID { return true }
        return editor.canMove(id, to: target)
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
        focusNewNode(newID)
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
        userHasInteracted = true
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
        userHasInteracted = true
        if editingID != nil { commitEditing() }
        let point = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, at: point)
    }

    private func zoom(by factor: CGFloat, at viewPoint: CGPoint) {
        userHasInteracted = true
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

        if let action = ShortcutStore.shared.action(for: event, scope: .canvas) {
            perform(action, in: editor)
            return
        }

        switch event.keyCode {
        case 53: // Esc
            editor.clearSelection()
        case 123:
            navigate(dirX: -1, dirY: 0)
        case 124:
            navigate(dirX: 1, dirY: 0)
        case 125:
            navigate(dirX: 0, dirY: 1)
        case 126:
            navigate(dirX: 0, dirY: -1)
        default:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
               let characters = event.characters,
               let scalar = characters.unicodeScalars.first,
               scalar.value >= 32,
               let id = editor.selection.first {
                beginEditing(id, replacingWith: characters)
                return
            }
            super.keyDown(with: event)
        }
    }

    private func perform(_ action: ShortcutAction, in editor: MapEditor) {
        switch action {
        case .newChild:
            let target = editor.selection.first ?? editor.map.rootID
            if let newID = editor.addChild(to: target) {
                focusNewNode(newID)
            }
        case .newSibling:
            if let id = editor.selection.first, let newID = editor.addSibling(after: id) {
                focusNewNode(newID)
            } else if let newID = editor.addChild(to: editor.map.rootID) {
                focusNewNode(newID)
            }
        case .editNode:
            if let id = editor.selection.first {
                beginEditing(id)
            }
        case .deleteNode:
            editor.deleteSelection()
        case .toggleCollapse:
            if let id = editor.selection.first {
                editor.toggleCollapse(id)
            }
        default:
            break
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

    private func focusNewNode(_ id: UUID) {
        rebuildLayoutIfNeeded(force: true)
        ensureVisible(id)
        editor?.select(id)
        needsDisplay = true
    }

    private func ensureVisible(_ id: UUID) {
        guard let frame = layoutResult?.frames[id] else { return }
        if !visibleWorldRect.insetBy(dx: -20, dy: -20).contains(frame) {
            camera.center = CGPoint(x: frame.midX, y: frame.midY)
            needsDisplay = true
        }
    }

    // MARK: - Inline editing

    func beginEditing(_ id: UUID, replacingWith replacement: String? = nil) {
        guard let editor, let node = editor.map.node(id) else { return }
        commitEditing()
        editor.select(id)
        rebuildLayoutIfNeeded(force: true)
        guard let layout = layoutResult, let frame = layout.frames[id] else { return }
        if !visibleWorldRect.contains(frame) {
            camera.center = CGPoint(x: frame.midX, y: frame.midY)
            needsDisplay = true
        }

        let level = min(layout.depths[id] ?? 0, 2)
        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: level)
        let textRect = worldRectToView(textLayout.textRect)
        let font = NSFont(
            descriptor: textLayout.font.fontDescriptor,
            size: max(textLayout.font.pointSize * camera.zoom, 9)
        ) ?? textLayout.font

        let textView = NSTextView(frame: textRect)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = theme.accent
        textView.selectedTextAttributes = [
            .backgroundColor: theme.accent.withAlphaComponent(0.20),
            .foregroundColor: textColor(for: node, level: level)
        ]
        textView.delegate = self
        textView.string = replacement ?? node.text
        updateTextContainer(textView, width: textRect.width)
        applyTextAttributes(
            to: textView,
            node: node,
            level: level,
            font: font,
            alignment: textLayout.alignment
        )
        addSubview(textView)

        editTextView = textView
        editingID = id
        editingOriginalText = node.text
        needsDisplay = true

        window?.makeFirstResponder(textView)
        if let replacement {
            textView.setSelectedRange(NSRange(location: (replacement as NSString).length, length: 0))
            if node.text != replacement {
                editor.setText(replacement, for: id)
                rebuildLayoutIfNeeded(force: true)
                updateEditorFrame()
            }
        } else {
            textView.selectAll(nil)
        }
    }

    private func applyTextAttributes(
        to textView: NSTextView,
        node: MindNode,
        level: Int,
        font: NSFont,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        let color = textColor(for: node, level: level)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        textView.typingAttributes = attributes
        textView.textColor = color
        textView.alignment = alignment
        textView.font = font
    }

    private func updateTextContainer(_ textView: NSTextView, width: CGFloat) {
        textView.textContainer?.containerSize = NSSize(
            width: max(width, 10),
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
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
        guard let textView = editTextView, let id = editingID else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        editingID = nil
        editTextView = nil
        editingOriginalText = ""
        textView.delegate = nil
        textView.removeFromSuperview()

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
        guard let textView = editTextView, let id = editingID else { return }
        let original = editingOriginalText

        editingID = nil
        editTextView = nil
        editingOriginalText = ""
        textView.delegate = nil
        textView.removeFromSuperview()

        if let node = editor?.map.node(id), node.text != original {
            editor?.setText(original, for: id)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func updateEditorFrame() {
        guard let textView = editTextView, let id = editingID,
              let editor, let layout = layoutResult, let frame = layout.frames[id],
              let level = layout.depths[id],
              let node = editor.map.node(id) else { return }

        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: min(level, 2))
        ensureVisible(id)
        let textRect = worldRectToView(textLayout.textRect)
        let font = NSFont(
            descriptor: textLayout.font.fontDescriptor,
            size: max(textLayout.font.pointSize * camera.zoom, 9)
        ) ?? textLayout.font

        textView.frame = textRect
        applyTextAttributes(
            to: textView,
            node: node,
            level: min(level, 2),
            font: font,
            alignment: textLayout.alignment
        )
        updateTextContainer(textView, width: textRect.width)
        textView.needsDisplay = true
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let textView = editTextView, let id = editingID, let editor else { return }
        editor.setText(textView.string, for: id)
        rebuildLayoutIfNeeded(force: true)
        updateEditorFrame()
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                commitEditing()
            }
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

