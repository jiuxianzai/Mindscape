import AppKit
import XCTest
@testable import Mindscape

@MainActor
final class MindscapeCoreTests: XCTestCase {
    private func makeEditor() throws -> (MapEditor, DocumentStore) {
        let store = try DocumentStore(inMemory: true)
        let map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        return (MapEditor(map: map, store: store), store)
    }

    func testProjectTemplateAndLayout() throws {
        let map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        XCTAssertEqual(map.nodes.count, 14)
        XCTAssertNotNil(map.node(map.rootID))

        let layout = LayoutEngine.layout(map)
        XCTAssertEqual(layout.frames.count, map.nodes.count)
        XCTAssertFalse(layout.bounds.isEmpty)
        XCTAssertEqual(layout.children[map.rootID]?.count, 4)
    }

    func testAllLayoutsFrameEveryNode() throws {
        let map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        for style in MapLayout.allCases {
            var copy = map
            copy.layout = style
            let layout = LayoutEngine.layout(copy)
            XCTAssertEqual(layout.frames.count, copy.nodes.count, "layout \(style.rawValue)")
            XCTAssertFalse(layout.bounds.isEmpty, "bounds \(style.rawValue)")
        }
    }

    func testEditorAddEditUndoRedo() throws {
        let (editor, _) = try makeEditor()
        let root = editor.map.rootID
        guard let child = editor.addChild(to: root) else {
            return XCTFail("addChild returned nil")
        }
        editor.setText("自定义子主题", for: child)
        editor.setNote("一条备注", for: child)
        editor.setIcon("star.fill", for: child)
        editor.setColor("#E8836B", for: child)

        XCTAssertEqual(editor.map.node(child)?.text, "自定义子主题")
        XCTAssertEqual(editor.map.node(child)?.note, "一条备注")
        XCTAssertEqual(editor.map.node(child)?.icon, "star.fill")
        XCTAssertEqual(editor.map.node(child)?.colorHex, "#E8836B")

        editor.undo()
        XCTAssertNil(editor.map.node(child)?.colorHex)
        editor.redo()
        XCTAssertEqual(editor.map.node(child)?.colorHex, "#E8836B")
    }

    func testMoveAndReorder() throws {
        let (editor, _) = try makeEditor()
        guard let budget = editor.map.nodes.first(where: { $0.text == "预算" }),
              let risk = editor.map.nodes.first(where: { $0.text == "风险" }),
              let resource = editor.map.nodes.first(where: { $0.text == "资源" }) else {
            return XCTFail("fixture nodes missing")
        }
        XCTAssertEqual(budget.parentID, resource.id)
        editor.move(id: budget.id, to: risk.id)
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, risk.id)

        editor.undo()
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, resource.id)

        guard let first = editor.map.nodes.first(where: { $0.text == "要解决的问题" }),
              let second = editor.map.nodes.first(where: { $0.text == "成功标准" }) else {
            return XCTFail("reorder nodes missing")
        }
        editor.reorder(id: first.id, relativeTo: second.id, after: true)
        XCTAssertGreaterThan(editor.map.node(first.id)?.order ?? 0, editor.map.node(second.id)?.order ?? 0)
    }

    func testCollapseAndDelete() throws {
        let (editor, _) = try makeEditor()
        guard let branch = editor.map.nodes.first(where: { $0.text == "里程碑" }) else {
            return XCTFail("branch missing")
        }
        editor.toggleCollapse(branch.id)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true)

        let before = editor.map.nodes.count
        editor.delete(id: branch.id)
        XCTAssertLessThan(editor.map.nodes.count, before)
        XCTAssertNil(editor.map.node(branch.id))
    }

    func testExportFormats() throws {
        let (editor, _) = try makeEditor()
        editor.setText("导出测试", for: editor.map.rootID)
        let layout = LayoutEngine.layout(editor.map)

        for format in ExportFormat.allCases {
            let data = try ExportService.makeData(map: editor.map, layout: layout, format: format)
            XCTAssertGreaterThan(data.count, 20, "\(format.rawValue)")

            switch format {
            case .png:
                XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            case .pdf:
                XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
            case .markdown:
                let text = String(data: data, encoding: .utf8) ?? ""
                XCTAssertTrue(text.contains("# 项目规划"))
                XCTAssertTrue(text.contains("导出测试"))
            case .opml:
                let text = String(data: data, encoding: .utf8) ?? ""
                XCTAssertTrue(text.contains("<opml"))
            case .json:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                XCTAssertNoThrow(try decoder.decode(MindMap.self, from: data))
            }
        }
    }

    func testDocumentStoreTrashRestore() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MapTemplate.blank.makeMap(themeID: "paper", layout: .mindMap)
        map.title = "存储测试"
        try store.save(map)

        let loaded = try store.load(id: map.id)
        XCTAssertEqual(loaded?.title, "存储测试")

        try store.trash(map.id)
        let trashed = try store.list(includeDeleted: true).first(where: { $0.id == map.id })
        XCTAssertNotNil(trashed?.deletedAt)

        try store.restore(map.id)
        XCTAssertNotNil(try store.load(id: map.id))

        try store.deletePermanently(map.id)
        XCTAssertNil(try store.load(id: map.id))
    }

    func testCollapsingParentMovesHiddenSelectionToParent() {
        var map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        map.layout = .mindMap
        let store = try! DocumentStore(inMemory: true)
        let editor = MapEditor(map: map, store: store)
        guard let branch = editor.map.nodes.first(where: { editor.map.children(of: $0.id).count > 0 }),
              let child = editor.map.children(of: branch.id).first else {
            return XCTFail("fixture missing")
        }
        editor.select(child.id)
        editor.toggleCollapse(branch.id)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true)
        XCTAssertEqual(editor.selection, [branch.id])
    }

    func testCollapseControlGeometry() {
        let map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        let layout = LayoutEngine.layout(map)
        guard let branch = map.nodes.first(where: { map.children(of: $0.id).count > 1 }),
              let leaf = map.nodes.first(where: { map.children(of: $0.id).isEmpty }) else {
            return XCTFail("fixture missing")
        }
        guard let center = NodeControlGeometry.collapseControlCenter(for: branch.id, in: map, layout: layout),
              let rect = layout.frames[branch.id] else {
            return XCTFail("control center missing")
        }
        XCTAssertFalse(rect.insetBy(dx: -1, dy: -1).contains(center))
        XCTAssertNil(NodeControlGeometry.collapseControlCenter(for: leaf.id, in: map, layout: layout))
        XCTAssertTrue(NodeControlGeometry.hitTest(center, for: branch.id, in: map, layout: layout))

        var collapsed = map
        if let index = collapsed.nodes.firstIndex(where: { $0.id == branch.id }) {
            collapsed.nodes[index].collapsed = true
        }
        let collapsedLayout = LayoutEngine.layout(collapsed)
        XCTAssertNotNil(NodeControlGeometry.collapseControlCenter(for: branch.id, in: collapsed, layout: collapsedLayout))

        var vertical = map
        vertical.layout = .orgChart
        let verticalLayout = LayoutEngine.layout(vertical)
        guard let verticalCenter = NodeControlGeometry.collapseControlCenter(for: branch.id, in: vertical, layout: verticalLayout),
              let verticalRect = verticalLayout.frames[branch.id] else {
            return XCTFail("vertical control missing")
        }
        XCTAssertGreaterThan(verticalCenter.y, verticalRect.midY)
    }

    func testShortcutCategoriesAreNotLost() {
        var seen = Set<String>()
        let categories = ShortcutAction.allCases.map(\.category).filter { seen.insert($0).inserted }
        XCTAssertFalse(categories.isEmpty)
        for category in categories {
            XCTAssertFalse(ShortcutAction.allCases.filter { $0.category == category }.isEmpty, category)
        }
    }

    func testCanvasMotionPolicy() {
        let previous = CanvasMotion.reduceMotionOverride
        defer { CanvasMotion.reduceMotionOverride = previous }

        CanvasMotion.reduceMotionOverride = false
        XCTAssertTrue(CanvasMotion.allowsAnimation(nodeCount: 10))
        XCTAssertTrue(CanvasMotion.allowsAnimation(nodeCount: CanvasMotion.maxAnimatedNodes))
        XCTAssertFalse(CanvasMotion.allowsAnimation(nodeCount: CanvasMotion.maxAnimatedNodes + 1))

        CanvasMotion.reduceMotionOverride = true
        XCTAssertFalse(CanvasMotion.allowsAnimation(nodeCount: 10))

        XCTAssertEqual(CanvasMotion.frameInterval(nodeCount: 100), 1.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.frameInterval(nodeCount: CanvasMotion.reducedFrameRateNodes), 1.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.frameInterval(nodeCount: CanvasMotion.reducedFrameRateNodes + 1), 1.0 / 30, accuracy: 0.0001)
    }

    func testEnglishLocalizationBundled() throws {
        let app = Bundle.main
        XCTAssertTrue(app.localizations.contains("en"), "localizations: \(app.localizations)")
        guard let path = app.path(forResource: "en", ofType: "lproj"),
              let english = Bundle(path: path) else {
            return XCTFail("en.lproj missing")
        }
        XCTAssertEqual(english.localizedString(forKey: "属性", value: nil, table: nil), "Properties")
        XCTAssertEqual(english.localizedString(forKey: "节点文字", value: nil, table: nil), "Node Text")
        XCTAssertEqual(english.localizedString(forKey: "新建导图", value: nil, table: nil), "New Map")
        XCTAssertEqual(english.localizedString(forKey: "自由布局", value: nil, table: nil), "Freeform")
        XCTAssertEqual(english.localizedString(forKey: "格式", value: nil, table: nil), "Format")
        XCTAssertEqual(english.localizedString(forKey: "导出「%@」", value: nil, table: nil), "Export “%@”")
        XCTAssertEqual(english.localizedString(forKey: "空白导图", value: nil, table: nil), "Blank Map")
        XCTAssertEqual(english.localizedString(forKey: "里程碑", value: nil, table: nil), "Milestones")
        XCTAssertNotNil(english.url(forResource: "Localizable", withExtension: "stringsdict"))

        guard let stringsURL = english.url(forResource: "Localizable", withExtension: "strings") else {
            return XCTFail("Localizable.strings missing")
        }
        let data = try Data(contentsOf: stringsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let catalog = plist as? [String: String] else {
            return XCTFail("catalog not a dictionary")
        }
        XCTAssertGreaterThan(catalog.count, 200)
        XCTAssertFalse(catalog.values.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
    }

    func testIconCatalogSearch() {
        XCTAssertFalse(IconCatalog.all.isEmpty)
        XCTAssertTrue(IconCatalog.search("目标").contains { $0.symbol == "target" })
        XCTAssertTrue(IconCatalog.search("star").contains { $0.symbol == "star.fill" })
    }

    func testCanvasAccessibilityTree() throws {
        let (editor, _) = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))

        let children = canvas.accessibilityChildren() as? [MindNodeAccessibilityElement]
        XCTAssertEqual(children?.count, editor.map.nodes.count)
        XCTAssertTrue(children?.contains(where: { ($0.accessibilityLabel() ?? "").contains("项目规划") }) == true)
        XCTAssertTrue(children?.allSatisfy { $0.accessibilityRole() == .button } == true)
    }
}

// MARK: - New feature tests

@MainActor
final class MindscapeFeatureTests: XCTestCase {
    private func makeEditor(layout: MapLayout = .mindMap) throws -> MapEditor {
        let store = try DocumentStore(inMemory: true)
        let map = MapTemplate.project.makeMap(themeID: "paper", layout: layout)
        return MapEditor(map: map, store: store)
    }

    private func node(_ editor: MapEditor, _ text: String) -> MindNode? {
        editor.map.nodes.first(where: { $0.text == text })
    }

    func testCopyPasteSubtree() throws {
        let editor = try makeEditor()
        guard let branch = node(editor, "里程碑"), let root = editor.map.node(editor.map.rootID) else {
            return XCTFail("fixture missing")
        }
        let subtreeCount = editor.map.subtreeIDs(of: branch.id).count
        let before = editor.map.nodes.count

        editor.select(branch.id)
        XCTAssertTrue(editor.copySelection())
        editor.select(root.id)
        XCTAssertTrue(editor.paste())

        XCTAssertEqual(editor.map.nodes.count, before + subtreeCount)
        guard let pasted = editor.selectedNodes.first else { return XCTFail("nothing pasted") }
        XCTAssertEqual(pasted.text, "里程碑")
        XCTAssertEqual(pasted.parentID, root.id)
        XCTAssertEqual(editor.map.children(of: pasted.id).count, editor.map.children(of: branch.id).count)

        editor.undo()
        XCTAssertEqual(editor.map.nodes.count, before)
    }

    func testDuplicateSelection() throws {
        let editor = try makeEditor()
        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        let subtreeCount = editor.map.subtreeIDs(of: branch.id).count
        let before = editor.map.nodes.count

        editor.select(branch.id)
        XCTAssertTrue(editor.duplicateSelection())
        XCTAssertEqual(editor.map.nodes.count, before + subtreeCount)
        guard let copy = editor.selectedNodes.first else { return XCTFail("nothing duplicated") }
        XCTAssertEqual(copy.text, "里程碑")
        XCTAssertEqual(copy.parentID, branch.parentID)
        XCTAssertNotEqual(copy.id, branch.id)
    }

    func testBatchOperations() throws {
        let editor = try makeEditor()
        guard let target = node(editor, "目标"), let milestone = node(editor, "里程碑") else {
            return XCTFail("fixture missing")
        }
        editor.setSelection([target.id, milestone.id])
        editor.setColor("#E8836B", for: editor.selection)
        editor.setIcon("star.fill", for: editor.selection)
        XCTAssertEqual(editor.map.node(target.id)?.colorHex, "#E8836B")
        XCTAssertEqual(editor.map.node(milestone.id)?.icon, "star.fill")

        editor.undo()
        XCTAssertNil(editor.map.node(milestone.id)?.icon)
        editor.undo()
        XCTAssertNil(editor.map.node(target.id)?.colorHex)
    }

    func testFocusCollapseAndExpand() throws {
        let editor = try makeEditor()
        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.setFocus(branch.id)
        XCTAssertEqual(editor.focusNodeID, branch.id)
        editor.setFocus(nil)
        XCTAssertNil(editor.focusNodeID)

        editor.collapseAll()
        XCTAssertTrue(editor.map.nodes.filter { $0.id != editor.map.rootID && !editor.map.children(of: $0.id).isEmpty }.allSatisfy { $0.collapsed })
        XCTAssertFalse(editor.map.node(editor.map.rootID)?.collapsed ?? true)

        editor.expandAll()
        XCTAssertTrue(editor.map.nodes.allSatisfy { !$0.collapsed })
    }

    func testSearchMatchesTextNoteAndIcon() throws {
        let editor = try makeEditor()
        guard let budget = node(editor, "预算"), let target = node(editor, "目标") else {
            return XCTFail("fixture missing")
        }
        editor.setNote("这是一个关键预算备注", for: budget.id)
        editor.setIcon("target", for: target.id)

        XCTAssertTrue(editor.searchMatches("预算").contains(budget.id))
        XCTAssertTrue(editor.searchMatches("关键预算").contains(budget.id))
        XCTAssertTrue(editor.searchMatches("target").contains(target.id))
        XCTAssertTrue(editor.searchMatches("目标").contains(target.id))
        XCTAssertTrue(editor.searchMatches("不存在的关键词").isEmpty)
        XCTAssertTrue(editor.searchMatches("   ").isEmpty)
    }

    func testFreeLayoutArrangement() throws {
        let editor = try makeEditor(layout: .free)
        guard let target = node(editor, "目标"),
              let milestone = node(editor, "里程碑"),
              let resource = node(editor, "资源") else {
            return XCTFail("fixture missing")
        }
        editor.setSelection([target.id, milestone.id, resource.id])
        let frames = LayoutEngine.layout(editor.map).frames
        XCTAssertTrue(editor.arrangeSelection(.alignLeft, frames: frames))

        let arranged = LayoutEngine.layout(editor.map).frames
        let xs = [target.id, milestone.id, resource.id].compactMap { arranged[$0]?.minX }
        XCTAssertEqual(xs.count, 3)
        XCTAssertEqual(Set(xs.map { ($0 * 1000).rounded() }).count, 1)

        let frames2 = LayoutEngine.layout(editor.map).frames
        XCTAssertTrue(editor.arrangeSelection(.distributeVertically, frames: frames2))
        let arranged2 = LayoutEngine.layout(editor.map).frames
        let sorted = [target.id, milestone.id, resource.id]
            .compactMap { arranged2[$0] }
            .sorted { $0.minY < $1.minY }
        XCTAssertEqual(sorted.count, 3)
        if sorted.count == 3 {
            let gap1 = sorted[1].minY - sorted[0].maxY
            let gap2 = sorted[2].minY - sorted[1].maxY
            XCTAssertEqual(gap1, gap2, accuracy: 0.5)
        }
    }

    func testMarkdownImportRoundTrip() throws {
        let editor = try makeEditor()
        editor.setNote("里程碑备注", for: node(editor, "里程碑")!.id)
        let markdown = ExportService.markdown(map: editor.map)
        let imported = MapImporter.markdown(markdown, themeID: "paper", layout: .mindMap)

        XCTAssertEqual(imported.nodes.count, editor.map.nodes.count)
        XCTAssertEqual(imported.title, editor.map.title)
        XCTAssertEqual(imported.root?.text, editor.map.root?.text)
        guard let importedMilestone = imported.nodes.first(where: { $0.text == "里程碑" }) else {
            return XCTFail("milestone missing")
        }
        XCTAssertEqual(importedMilestone.note, "里程碑备注")
        XCTAssertEqual(imported.children(of: importedMilestone.id).count, 3)
    }

    func testMarkdownHeadingsAndNotes() {
        let text = """
        # 产品规划

        ## 目标
        - 要解决的问题
          > 来自用户访谈
        - 成功标准

        ### 深层
        - 另一个节点

        ## 风险
        1. 已知风险
        """
        let map = MapImporter.markdown(text, themeID: "paper", layout: .mindMap)
        XCTAssertEqual(map.title, "产品规划")
        XCTAssertEqual(map.nodes.count, 8)
        guard let goal = map.nodes.first(where: { $0.text == "目标" }),
              let problem = map.nodes.first(where: { $0.text == "要解决的问题" }),
              let deep = map.nodes.first(where: { $0.text == "深层" }),
              let another = map.nodes.first(where: { $0.text == "另一个节点" }) else {
            return XCTFail("headings missing: \(map.nodes.map(\.text))")
        }
        XCTAssertEqual(goal.parentID, map.rootID)
        XCTAssertEqual(problem.parentID, goal.id)
        XCTAssertEqual(problem.note, "来自用户访谈")
        XCTAssertEqual(deep.parentID, goal.id)
        XCTAssertEqual(another.parentID, deep.id)
    }

    func testMarkdownNestedIndentation() {
        let text = """
        # 项目
        - 一级 A
            - 二级 B
                - 三级 C
        - 一级 D
        """
        let map = MapImporter.markdown(text, themeID: "paper", layout: .mindMap)
        guard let a = map.nodes.first(where: { $0.text == "一级 A" }),
              let b = map.nodes.first(where: { $0.text == "二级 B" }),
              let c = map.nodes.first(where: { $0.text == "三级 C" }),
              let d = map.nodes.first(where: { $0.text == "一级 D" }) else {
            return XCTFail("nodes missing: \(map.nodes.map(\.text))")
        }
        XCTAssertEqual(a.parentID, map.rootID)
        XCTAssertEqual(b.parentID, a.id)
        XCTAssertEqual(c.parentID, b.id)
        XCTAssertEqual(d.parentID, map.rootID)
    }

    func testOPMLImportRoundTrip() throws {
        let editor = try makeEditor()
        let xml = ExportService.opml(map: editor.map)
        let imported = try MapImporter.opml(Data(xml.utf8), themeID: "paper", layout: .mindMap)
        XCTAssertEqual(imported.nodes.count, editor.map.nodes.count)
        XCTAssertEqual(imported.title, editor.map.title)
        guard let milestone = imported.nodes.first(where: { $0.text == "里程碑" }) else {
            return XCTFail("milestone missing")
        }
        XCTAssertEqual(imported.children(of: milestone.id).count, 3)
    }

    func testSnapAlignmentGuides() {
        let moving = CGRect(x: 100, y: 100, width: 50, height: 20)
        let other = CGRect(x: 150, y: 180, width: 80, height: 30)
        let result = FreeLayoutSnap.snap(movingFrame: moving, otherFrames: [other], threshold: 2)
        XCTAssertEqual(result.guides.count, 1)
        XCTAssertEqual(result.guides.first?.axis, .vertical)
        XCTAssertEqual(result.guides.first?.position, 150)

        let far = CGRect(x: 400, y: 400, width: 30, height: 20)
        let none = FreeLayoutSnap.snap(movingFrame: moving, otherFrames: [far], threshold: 4)
        XCTAssertTrue(none.guides.isEmpty)
        XCTAssertEqual(none.dx, 0)
        XCTAssertEqual(none.dy, 0)
    }

    func testPresentationSlides() throws {
        let editor = try makeEditor()
        let store = try DocumentStore(inMemory: true)
        let model = PresentationModel(map: editor.map, store: store)
        XCTAssertGreaterThan(model.slides.count, 1)
        XCTAssertNil(model.slides[0].nodeID)
        model.next()
        XCTAssertEqual(model.index, 1)
        XCTAssertNotNil(model.slides[1].nodeID)
        XCTAssertEqual(model.editor.focusNodeID, model.slides[1].nodeID)
        model.previous()
        XCTAssertEqual(model.index, 0)
        XCTAssertNil(model.editor.focusNodeID)
    }
}

extension MindscapeFeatureTests {
    func testCanvasCopyPasteResponder() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        guard let branch = editor.map.nodes.first(where: { $0.text == "里程碑" }) else {
            return XCTFail("fixture missing")
        }
        let subtreeCount = editor.map.subtreeIDs(of: branch.id).count
        let before = editor.map.nodes.count

        editor.select(branch.id)
        canvas.copy(nil)
        editor.select(editor.map.rootID)
        canvas.paste(nil)
        XCTAssertEqual(editor.map.nodes.count, before + subtreeCount)
        XCTAssertEqual(editor.selectedNodes.first?.text, "里程碑")
    }

    func testCanvasZoomResetBridge() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let bridge = CanvasBridge()
        bridge.attachCanvas(canvas)
        canvas.setZoom(1.6)
        XCTAssertEqual(canvas.currentZoom, 1.6, accuracy: 0.001)
        bridge.resetZoom()
        XCTAssertEqual(canvas.currentZoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(bridge.zoom, 1.0, accuracy: 0.001)
    }

    /// 回归：折叠控件是开关，系统会把连续快速点击的 clickCount 累加成 2/3/4，
    /// 每一次点击都必须翻转一次，不能被丢弃。
    func testRapidCollapseClicksAllTakeEffect() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.select(branch.id)

        let window = canvas.attachToTestWindow()
        let layout = LayoutEngine.layout(editor.map)
        guard let center = NodeControlGeometry.collapseControlCenter(for: branch.id, in: editor.map, layout: layout) else {
            return XCTFail("collapse control missing")
        }
        let windowPoint = canvas.convert(canvas.worldToView(center), to: nil)

        for count in 1...4 {
            guard let event = mouseEvent(.leftMouseDown, at: windowPoint, in: window, clickCount: count) else {
                return XCTFail("无法构造鼠标事件")
            }
            canvas.mouseDown(with: event)
            XCTAssertEqual(
                editor.map.node(branch.id)?.collapsed,
                count % 2 == 1,
                "第 \(count) 次点击被丢弃"
            )
        }
    }

    /// 悬停到有子节点的节点上就应该出现折叠控件，不需要先点选。
    func testHoveringNodeRevealsCollapseControl() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.clearSelection()

        let window = canvas.attachToTestWindow()
        let layout = LayoutEngine.layout(editor.map)
        guard let nodeFrame = layout.frames[branch.id],
              let controlCenter = NodeControlGeometry.collapseControlCenter(for: branch.id, in: editor.map, layout: layout) else {
            return XCTFail("fixture layout missing")
        }

        let nodePoint = canvas.convert(canvas.worldToView(CGPoint(x: nodeFrame.midX, y: nodeFrame.midY)), to: nil)
        guard let move = mouseEvent(.mouseMoved, at: nodePoint, in: window) else {
            return XCTFail("无法构造鼠标移动事件")
        }
        canvas.mouseMoved(with: move)
        XCTAssertTrue(editor.selection.isEmpty, "悬停不应改变选择")

        // 没有选中节点，直接点控件也应该生效
        let controlPoint = canvas.convert(canvas.worldToView(controlCenter), to: nil)
        guard let click = mouseEvent(.leftMouseDown, at: controlPoint, in: window) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true, "悬停后控件不可点")
    }

    /// 从节点移向 +/- 控件途中会离开节点矩形，控件不能在这一小段空隙里消失
    func testCollapseControlSurvivesGapWhileHovering() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.clearSelection()

        let window = canvas.attachToTestWindow()
        canvas.setZoom(2)

        let layout = LayoutEngine.layout(editor.map)
        guard let frame = layout.frames[branch.id],
              let control = NodeControlGeometry.collapseControlCenter(for: branch.id, in: editor.map, layout: layout) else {
            return XCTFail("fixture layout missing")
        }

        // 控件在哪一侧，就从哪一侧离开节点，并竖直偏离 7pt：
        // 已经离开节点矩形、也超过连接线的悬停容差（zoom 2 时为 5pt），正是移向控件的必经空隙
        let gapX = control.x > frame.midX ? frame.maxX + 11 : frame.minX - 11
        let gapWorld = CGPoint(x: gapX, y: frame.midY + 7)
        XCTAssertFalse(frame.contains(gapWorld), "测试点必须在节点外")

        let nodePoint = canvas.convert(canvas.worldToView(CGPoint(x: frame.midX, y: frame.midY)), to: nil)
        let gapPoint = canvas.convert(canvas.worldToView(gapWorld), to: nil)
        let controlPoint = canvas.convert(canvas.worldToView(control), to: nil)

        guard let moveToNode = mouseEvent(.mouseMoved, at: nodePoint, in: window),
              let moveToGap = mouseEvent(.mouseMoved, at: gapPoint, in: window),
              let click = mouseEvent(.leftMouseDown, at: controlPoint, in: window) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseMoved(with: moveToNode)
        canvas.mouseMoved(with: moveToGap)
        canvas.mouseDown(with: click)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true, "移向控件途中控件消失了")
    }

    /// 就地编辑的字号必须和画布上一致（pointSize × zoom），打字过程中也不能变
    func testInlineEditorFontMatchesCanvas() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        let expectedPointSize = NodeMeasurer.font(level: 1).pointSize

        for zoom in [0.5, 0.8, 1.0, 1.6] {
            canvas.setZoom(CGFloat(zoom))
            canvas.beginEditing(branch.id)
            guard let textView = canvas.subviews.compactMap({ $0 as? NSTextView }).last else {
                return XCTFail("编辑器没有创建")
            }
            XCTAssertEqual(
                textView.font?.pointSize ?? -1,
                expectedPointSize * canvas.currentZoom,
                accuracy: 0.01,
                "zoom \(zoom) 时编辑字号与画布不一致"
            )

            textView.insertText("测试", replacementRange: NSRange(location: textView.string.count, length: 0))
            XCTAssertEqual(
                textView.font?.pointSize ?? -1,
                expectedPointSize * canvas.currentZoom,
                accuracy: 0.01,
                "zoom \(zoom) 时打字改变了编辑字号"
            )
            canvas.commitEditing()
        }
    }
}

private extension MindCanvasView {
    func attachToTestWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = self
        layout()
        return window
    }
}

private func mouseEvent(
    _ type: NSEvent.EventType,
    at windowPoint: NSPoint,
    in window: NSWindow,
    clickCount: Int = 1
) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type,
        location: windowPoint,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    )
}

extension MindscapeFeatureTests {
    /// 根节点的编辑容器宽度必须和画布的换行宽度一致，否则一进入编辑就被挤成两行、
    /// 多出来的一行还会被节点高度裁掉（看起来就像字号变小）
    func testRootEditorWrapsLikeCanvas() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.35)

        let rootID = editor.map.rootID
        guard let root = editor.map.node(rootID) else { return XCTFail("fixture missing") }
        canvas.beginEditing(rootID)
        guard let textView = canvas.subviews.compactMap({ $0 as? NSTextView }).last,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return XCTFail("编辑器没有创建")
        }

        let layout = LayoutEngine.layout(editor.map)
        guard let frame = layout.frames[rootID] else { return XCTFail("fixture layout missing") }
        let textLayout = NodeMeasurer.textLayout(for: root, in: frame, level: 0)
        XCTAssertEqual(
            container.containerSize.width,
            textLayout.contentWidth * canvas.currentZoom,
            accuracy: 0.5,
            "编辑容器宽度没有跟着画布的换行宽度走"
        )

        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        let oneLineHeight = (textView.font?.pointSize ?? 19) * 1.4
        XCTAssertLessThan(usedHeight, oneLineHeight, "根节点文字在编辑态被挤成了多行")
        canvas.commitEditing()
    }
}

extension MindscapeFeatureTests {
    /// 缩到 20% 时控件只有 2pt 大，命中范围必须按屏幕尺寸兜底，否则点不中
    func testCollapseControlHitAreaStaysClickableWhenZoomedOut() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.select(branch.id)

        let window = canvas.attachToTestWindow()
        canvas.setZoom(0.2)

        let layout = LayoutEngine.layout(editor.map)
        guard let center = NodeControlGeometry.collapseControlCenter(for: branch.id, in: editor.map, layout: layout) else {
            return XCTFail("collapse control missing")
        }
        // 点在控件中心往下 8pt（屏幕）处：远大于世界坐标的 13pt 命中半径
        var viewPoint = canvas.worldToView(center)
        viewPoint.y += 8
        let windowPoint = canvas.convert(viewPoint, to: nil)

        guard let click = mouseEvent(.leftMouseDown, at: windowPoint, in: window) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true, "小缩放下控件点不中")
    }

    /// 分层错峰：父节点先走，子节点按层级依次跟上
    func testDepthStaggeredAnimationDelays() {
        XCTAssertEqual(CanvasMotion.delay(forDepth: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.delay(forDepth: 1), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(CanvasMotion.delay(forDepth: 2), 0)
        XCTAssertGreaterThan(CanvasMotion.delay(forDepth: 3), CanvasMotion.delay(forDepth: 2))
        XCTAssertEqual(
            CanvasMotion.delay(forDepth: 8),
            CanvasMotion.delay(forDepth: 2 + CanvasMotion.maxDelayedDepth),
            accuracy: 0.0001,
            "延迟应当封顶，避免长链拖太久"
        )
        XCTAssertEqual(CanvasMotion.easeOutCubic(0), 0, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.easeOutCubic(1), 1, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.easeOutCubic(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(CanvasMotion.easeOutCubic(2), 1, accuracy: 0.0001)
    }
}

extension MindscapeFeatureTests {
    /// 小缩放下控件命中区被放大，但不能把「点节点」抢走
    func testEnlargedControlHitAreaDoesNotStealNodeClicks() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.select(branch.id)

        let window = canvas.attachToTestWindow()
        canvas.setZoom(0.2)

        let layout = LayoutEngine.layout(editor.map)
        guard let frame = layout.frames[branch.id] else { return XCTFail("fixture layout missing") }
        let nodePoint = canvas.convert(canvas.worldToView(CGPoint(x: frame.midX, y: frame.midY)), to: nil)

        guard let click = mouseEvent(.leftMouseDown, at: nodePoint, in: window) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, false, "点节点被当成了点控件")
        XCTAssertEqual(editor.selection, [branch.id])
    }
}

extension MindscapeFeatureTests {
    /// 折叠时要知道被藏了多少个节点
    func testHiddenDescendantCount() throws {
        let editor = try makeEditor()
        let layout = LayoutEngine.layout(editor.map)
        guard let milestone = node(editor, "里程碑"), let risk = node(editor, "风险") else {
            return XCTFail("fixture missing")
        }
        XCTAssertEqual(MapRenderer.hiddenDescendantCount(of: milestone.id, layout: layout), 3)
        XCTAssertEqual(MapRenderer.hiddenDescendantCount(of: risk.id, layout: layout), 2)
        XCTAssertEqual(
            MapRenderer.hiddenDescendantCount(of: editor.map.rootID, layout: layout),
            editor.map.nodes.count - 1
        )
    }

    /// 双击空白画布：在根主题下新建一个子主题并直接进入编辑
    func testDoubleClickEmptySpaceCreatesNode() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        editor.clearSelection()

        let before = Set(editor.map.nodes.map(\.id))
        // 画布左上角，fitToContent 之后一定是空白
        let emptyPoint = canvas.convert(NSPoint(x: 12, y: 12), to: nil)
        guard let click = mouseEvent(.leftMouseDown, at: emptyPoint, in: window, clickCount: 2) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)

        let created = editor.map.nodes.filter { !before.contains($0.id) }
        XCTAssertEqual(created.count, 1, "双击空白没有新建节点")
        XCTAssertEqual(created.first?.parentID, editor.map.rootID)
        XCTAssertNotNil(canvas.subviews.compactMap { $0 as? NSTextView }.last, "新建后应直接进入编辑")
        canvas.commitEditing()
    }
}

extension MindscapeFeatureTests {
    /// 折叠标记常驻：没有悬停、也没有选中时，也应该能直接点开
    func testCollapsedControlIsAlwaysClickable() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        canvas.setZoom(1)

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        editor.toggleCollapse(branch.id)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, true)
        // 选中另一个节点，保证折叠节点既不是选中态也没有悬停
        editor.select(editor.map.rootID)

        let layout = LayoutEngine.layout(editor.map)
        guard let center = NodeControlGeometry.collapseControlCenter(for: branch.id, in: editor.map, layout: layout) else {
            return XCTFail("collapse control missing")
        }
        let windowPoint = canvas.convert(canvas.worldToView(center), to: nil)
        guard let click = mouseEvent(.leftMouseDown, at: windowPoint, in: window) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)
        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, false, "常驻的折叠标记点不开")
    }
}

extension MindscapeFeatureTests {
    /// 128% 缩放下点进编辑不应该把节点“搬”到屏幕中央
    func testEditingDoesNotRecenterCanvas() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.28)
        canvas.centerContent()

        let layout = LayoutEngine.layout(editor.map)
        // 找一个已经跑出右边界（或贴边）的节点
        let outside = layout.frames.first { _, frame in
            let origin = canvas.worldToView(frame.origin)
            return origin.x + frame.width * canvas.currentZoom > canvas.bounds.width - 8
        }
        guard let (id, frame) = outside else { return XCTFail("测试需要一张超出视口的节点") }
        let before = canvas.worldToView(frame.origin)

        canvas.beginEditing(id)
        let after = canvas.worldToView(frame.origin)

        XCTAssertGreaterThan(after.x, canvas.bounds.width * 0.45, "编辑时节点被搬到了屏幕中间")
        XCTAssertLessThan(abs(after.x - before.x), canvas.bounds.width * 0.4, "镜头移动幅度过大")
        canvas.commitEditing()
    }

    /// 打字过程中画布不应该移动
    func testTypingDoesNotMoveCamera() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.28)
        canvas.centerContent()

        guard let branch = node(editor, "里程碑") else { return XCTFail("fixture missing") }
        canvas.beginEditing(branch.id)
        guard let tv = canvas.subviews.compactMap({ $0 as? NSTextView }).last else {
            return XCTFail("编辑器没有创建")
        }
        let cameraProbeBefore = canvas.worldToView(.zero)
        tv.insertText("追加一小段文字看看画布会不会动", replacementRange: NSRange(location: tv.string.count, length: 0))
        let cameraProbeAfter = canvas.worldToView(.zero)
        XCTAssertEqual(cameraProbeAfter.x, cameraProbeBefore.x, accuracy: 0.5)
        XCTAssertEqual(cameraProbeAfter.y, cameraProbeBefore.y, accuracy: 0.5)
        canvas.commitEditing()
    }
}

extension MindscapeFeatureTests {
    /// 中文输入法组字时，节点要跟着变宽，组字不能提前折行到节点外面
    func testMarkedTextKeepsNodeInSync() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MindMap.blank(title: "t", themeID: "paper", layout: .logicRight)
        let child = MindNode(parentID: map.rootID, text: "services.msx", order: 0)
        map.nodes.append(child)
        let editor = MapEditor(map: map, store: store)

        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        _ = window
        canvas.setZoom(1.5)
        canvas.centerContent()

        let widthBefore = LayoutEngine.layout(editor.map).frames[child.id]!.width
        canvas.beginEditing(child.id)
        guard let textView = canvas.subviews.compactMap({ $0 as? NSTextView }).last,
              let manager = textView.layoutManager,
              let container = textView.textContainer else {
            return XCTFail("编辑器没有创建")
        }
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.setMarkedText(
            "zc",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        // 同步是延后一拍的
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(editor.map.node(child.id)?.text.contains("zc") == true, "组字没有同步回模型")
        let widthAfter = LayoutEngine.layout(editor.map).frames[child.id]!.width
        XCTAssertGreaterThan(widthAfter, widthBefore, "组字时节点没有变宽")

        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let lineHeight = (textView.font?.pointSize ?? 13) * 1.6
        XCTAssertLessThan(used.height, lineHeight, "组字仍然折行到第二行")
        canvas.commitEditing()
    }
}

extension MindscapeFeatureTests {
    /// 组字不能先折行再弹回第一行（闪烁）
    func testComposingTextDoesNotWrapAndBounce() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MindMap.blank(title: "t", themeID: "paper", layout: .logicRight)
        let child = MindNode(parentID: map.rootID, text: "ftp 192.168.1.1", order: 0)
        map.nodes.append(child)
        let editor = MapEditor(map: map, store: store)

        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.28)
        canvas.centerContent()

        canvas.beginEditing(child.id)
        guard let tv = canvas.subviews.compactMap({ $0 as? NSTextView }).last,
              let manager = tv.layoutManager,
              let container = tv.textContainer else {
            return XCTFail("编辑器没有创建")
        }
        tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
        let composing = "zhongwen"
        tv.setMarkedText(composing, selectedRange: NSRange(location: composing.count, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))

        // 组字发生的第一帧就不该折行（这一帧模型还没更新，全靠容器先撑开）
        manager.ensureLayout(for: container)
        var used = manager.usedRect(for: container)
        let lineHeight = (tv.font?.pointSize ?? 13) * 1.6
        XCTAssertLessThan(used.height, lineHeight, "组字时这一帧就折行了")
        XCTAssertGreaterThanOrEqual(container.containerSize.width, used.width, "容器宽度没跟上组字")

        // 模型同步是延后一拍的
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        manager.ensureLayout(for: container)
        used = manager.usedRect(for: container)
        XCTAssertLessThan(used.height, lineHeight, "组字同步后又折行了")
        XCTAssertTrue(editor.map.node(child.id)?.text.contains(composing) == true, "组字没同步到模型")
        canvas.commitEditing()
    }
}

extension MindscapeFeatureTests {
    /// 双击空白建节点后 ⌘Z：节点没了，编辑器也必须收起，不能留下一段漂浮文字
    func testUndoWhileEditingRemovesEditor() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        editor.clearSelection()

        let emptyPoint = canvas.convert(NSPoint(x: 12, y: 12), to: nil)
        guard let click = mouseEvent(.leftMouseDown, at: emptyPoint, in: window, clickCount: 2) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)
        XCTAssertEqual(canvas.subviews.compactMap { $0 as? NSTextView }.count, 1, "双击后应进入编辑")

        editor.undo()
        // 模拟 SwiftUI 在 revision 变化后刷新画布
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))

        XCTAssertTrue(
            canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty,
            "撤销后编辑框还留在画布上"
        )
    }
}
