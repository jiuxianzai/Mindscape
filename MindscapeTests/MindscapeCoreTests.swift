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
                XCTAssertTrue(text.contains("# 导出测试"), "Markdown 标题应跟随第一个头部节点")
                XCTAssertTrue(text.contains("- 导出测试"))
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

    func testSnapshotCreateRenameDelete() throws {
        let editor = try makeEditor()
        editor.saveNow()
        XCTAssertTrue(editor.createSnapshot(name: "提交前"))
        let snapshots = editor.snapshots()
        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.name, "提交前")
        XCTAssertFalse(snapshot.isAuto)

        XCTAssertTrue(editor.renameSnapshot(id: snapshot.id, name: "发布前"))
        XCTAssertEqual(editor.snapshots().first?.name, "发布前")

        XCTAssertTrue(editor.deleteSnapshot(id: snapshot.id))
        XCTAssertTrue(editor.snapshots().isEmpty)
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
    clickCount: Int = 1,
    modifiers: NSEvent.ModifierFlags = []
) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type,
        location: windowPoint,
        modifierFlags: modifiers,
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
    func testDoubleClickEmptySpaceCreatesHeadNode() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        editor.clearSelection()

        let before = Set(editor.map.nodes.map(\.id))
        let rootsBefore = editor.map.rootIDs
        // 画布左上角，fitToContent 之后一定是空白
        let emptyPoint = canvas.convert(NSPoint(x: 12, y: 12), to: nil)
        guard let click = mouseEvent(.leftMouseDown, at: emptyPoint, in: window, clickCount: 2) else {
            return XCTFail("无法构造鼠标事件")
        }
        canvas.mouseDown(with: click)

        let created = editor.map.nodes.filter { !before.contains($0.id) }
        XCTAssertEqual(created.count, 1, "双击空白没有新建节点")
        XCTAssertNil(created.first?.parentID, "双击空白新建的应该是头部节点，不是子节点")
        XCTAssertEqual(editor.map.rootIDs.count, rootsBefore.count + 1, "头部节点数量没有增加")
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
    /// 进入编辑时节点要按当前缩放居中，而不是只做最小幅度平移
    func testEditingCentersNodeInViewport() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.28)
        canvas.centerContent()

        let layout = LayoutEngine.layout(editor.map)
        guard let (id, frame) = layout.frames.first else { return XCTFail("fixture missing") }
        canvas.beginEditing(id)

        let center = canvas.worldToView(CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(center.x, canvas.bounds.midX, accuracy: 1, "编辑时节点没有水平居中")
        XCTAssertEqual(center.y, canvas.bounds.midY, accuracy: 1, "编辑时节点没有垂直居中")
        XCTAssertEqual(canvas.currentZoom, 1.28, accuracy: 0.001, "居中不能改变缩放")
        canvas.commitEditing()
    }

    /// 打字导致节点变宽时，节点中心仍保持在视口中心
    func testTypingKeepsNodeCentered() throws {
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
        tv.insertText("追加一小段文字看看节点会不会跑出屏幕", replacementRange: NSRange(location: tv.string.count, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let layout = LayoutEngine.layout(editor.map)
        guard let frame = layout.frames[branch.id] else { return XCTFail("fixture missing") }
        let center = canvas.worldToView(CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(center.x, canvas.bounds.midX, accuracy: 1, "打字后节点没有水平居中")
        XCTAssertEqual(center.y, canvas.bounds.midY, accuracy: 1, "打字后节点没有垂直居中")
        canvas.commitEditing()
    }

    /// 从 Inspector 等非画布入口新增节点，也要把新节点居中
    func testNewChildCentersViewport() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        _ = canvas.attachToTestWindow()
        canvas.setZoom(1.28)
        canvas.centerContent()

        let newID = try XCTUnwrap(editor.addChild(to: editor.map.rootID))
        canvas.layout()

        let layout = LayoutEngine.layout(editor.map)
        guard let frame = layout.frames[newID] else { return XCTFail("new node missing") }
        let center = canvas.worldToView(CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(center.x, canvas.bounds.midX, accuracy: 1, "新增节点没有水平居中")
        XCTAssertEqual(center.y, canvas.bounds.midY, accuracy: 1, "新增节点没有垂直居中")
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

extension MindscapeFeatureTests {
    /// 图标高度必须统一、宽度跟随符号自身比例：
    /// SF Symbols 的宽高比在 0.64~1.78 之间，统一塞进正方形会被拉扁或挤瘦
    func testIconKeepsNativeAspectRatio() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MindMap.blank(title: "t", themeID: "paper", layout: .logicRight)
        let icons = ["key.fill", "star.fill", "person.3.fill"]   // 窄 / 方 / 宽
        for (index, icon) in icons.enumerated() {
            var node = MindNode(parentID: map.rootID, text: "图标", order: index)
            node.icon = icon
            map.nodes.append(node)
        }
        let editor = MapEditor(map: map, store: store)
        let layout = LayoutEngine.layout(editor.map)
        let level = 1
        let expectedHeight = NodeMeasurer.iconSize(level: level)

        var widths: [String: CGFloat] = [:]
        for node in editor.map.nodes where node.icon != nil {
            guard let frame = layout.frames[node.id], let icon = node.icon else { continue }
            let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: level)
            guard let box = textLayout.iconRect?.size else { return XCTFail("\(icon) 没有图标占位") }

            XCTAssertEqual(box.height, expectedHeight, accuracy: 0.01, "\(icon) 高度没有统一")
            widths[icon] = box.width

            let natural = try XCTUnwrap(
                NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: expectedHeight, weight: .medium))?
                    .size
            )
            XCTAssertEqual(
                box.width / box.height,
                natural.width / natural.height,
                accuracy: 0.02,
                "\(icon) 的占位比例被改掉了"
            )
        }

        XCTAssertLessThan(try XCTUnwrap(widths["key.fill"]), try XCTUnwrap(widths["star.fill"]), "窄符号被拉宽了")
        XCTAssertLessThan(try XCTUnwrap(widths["star.fill"]), try XCTUnwrap(widths["person.3.fill"]), "宽符号被挤窄了")
    }

    /// 图标宽度要参与节点尺寸计算，否则宽图标会压到文字
    func testIconWidthAffectsNodeWidth() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MindMap.blank(title: "t", themeID: "paper", layout: .logicRight)
        for (index, icon) in ["key.fill", "person.3.fill"].enumerated() {
            var node = MindNode(parentID: map.rootID, text: "同样长度的文字", order: index)
            node.icon = icon
            map.nodes.append(node)
        }
        let editor = MapEditor(map: map, store: store)
        let layout = LayoutEngine.layout(editor.map)
        let keyNode = try XCTUnwrap(editor.map.nodes.first { $0.icon == "key.fill" })
        let wideNode = try XCTUnwrap(editor.map.nodes.first { $0.icon == "person.3.fill" })
        let keyWidth = try XCTUnwrap(layout.frames[keyNode.id]).width
        let wideWidth = try XCTUnwrap(layout.frames[wideNode.id]).width
        XCTAssertGreaterThan(wideWidth, keyWidth + 5, "宽图标的节点没有跟着变宽")
    }
}

extension MindscapeFeatureTests {
    /// 启动时画布宽度会变化（侧栏、属性面板先后就位），「适配」要跟着重算，
    /// 否则打开后整张图偏小，必须按一次 ⌘0 才正常
    func testFitFollowsCanvasResizeBeforeInteraction() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 720, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        canvas.layout()
        let narrowWidth = canvas.bounds.width
        let narrowZoom = canvas.currentZoom

        // 属性面板就位后画布变宽 20%（低于原来 25% 的阈值）
        let wideWidth = narrowWidth * 1.2
        window.setContentSize(NSSize(width: wideWidth, height: 700))
        canvas.setFrameSize(NSSize(width: wideWidth, height: 700))
        canvas.layout()

        XCTAssertEqual(
            canvas.currentZoom / narrowZoom,
            1.2,
            accuracy: 0.08,
            "画布变宽后没有按新宽度重新适配"
        )
    }
}

extension MindscapeFeatureTests {
    /// 三个等宽一级分支：中间那个正好落在根节点中线正下方，
    /// 折叠控件以前固定放在 +18，圆心会落进子节点矩形里，点击被当成选中子节点。
    private func makeThreeBranchOrgMap() -> MindMap {
        var map = MindMap.blank(title: "招聘流程", themeID: "paper", layout: .orgChart)
        let root = map.rootID
        for (index, title) in ["设计", "工程", "运营"].enumerated() {
            let branch = MindNode(parentID: root, text: title, order: index)
            map.nodes.append(branch)
            map.nodes.append(MindNode(parentID: branch.id, text: "\(title)子项", order: 0))
        }
        return map
    }

    /// 组织架构图上下层之间要有足够走线的空间，折叠控件必须整个落在空隙里
    func testOrgChartConnectorGapFitsCollapseControl() throws {
        let map = makeThreeBranchOrgMap()
        let layout = LayoutEngine.layout(map)
        let rootRect = try XCTUnwrap(layout.frames[map.rootID])
        let childFrames = map.children(of: map.rootID).compactMap { layout.frames[$0.id] }
        let childTop = try XCTUnwrap(childFrames.map(\.minY).min())

        XCTAssertGreaterThanOrEqual(
            childTop - rootRect.maxY,
            48,
            "组织架构图上下层间距太小，连接线会贴在一起"
        )

        let center = try XCTUnwrap(
            NodeControlGeometry.collapseControlCenter(for: map.rootID, in: map, layout: layout)
        )
        XCTAssertGreaterThan(
            center.y - NodeControlGeometry.radius,
            rootRect.maxY,
            "折叠控件没有落在父节点下方的空隙里"
        )
        XCTAssertLessThan(
            center.y + NodeControlGeometry.radius,
            childTop,
            "折叠控件压到了子节点上"
        )
        for frame in childFrames {
            XCTAssertFalse(frame.insetBy(dx: -1, dy: -1).contains(center))
        }
    }

    /// 招聘流程这类三列组织架构图，点根节点的折叠按钮必须真的折叠
    func testOrgChartCollapseControlClickToggles() throws {
        let store = try DocumentStore(inMemory: true)
        let editor = MapEditor(map: makeThreeBranchOrgMap(), store: store)
        editor.select(editor.map.rootID)

        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let layout = LayoutEngine.layout(editor.map)
        let center = try XCTUnwrap(
            NodeControlGeometry.collapseControlCenter(for: editor.map.rootID, in: editor.map, layout: layout)
        )
        let windowPoint = canvas.convert(canvas.worldToView(center), to: nil)
        let click = try XCTUnwrap(mouseEvent(.leftMouseDown, at: windowPoint, in: window))
        canvas.mouseDown(with: click)

        XCTAssertEqual(editor.map.node(editor.map.rootID)?.collapsed, true, "组织架构图折叠按钮点不动")
    }

    /// 短文字节点（被最小宽度撑开）文字块必须水平居中，而不是贴着左边
    func testShortNodeTextIsHorizontallyCentered() throws {
        let editor = try makeEditor()
        let layout = LayoutEngine.layout(editor.map)
        let budget = try XCTUnwrap(node(editor, "预算"))
        let frame = try XCTUnwrap(layout.frames[budget.id])
        let textLayout = NodeMeasurer.textLayout(for: budget, in: frame, level: 2)

        let textCenter = textLayout.textRect.minX + textLayout.measuredSize.width / 2
        XCTAssertEqual(textCenter, frame.midX, accuracy: 0.5, "短文字没有水平居中")
        XCTAssertEqual(textLayout.textRect.midY, frame.midY, accuracy: 0.5, "文字块没有垂直居中")
    }

    /// 有图标的节点：文字本身仍居中，图标放在左侧并保留内边距
    func testIconNodeTextIsCenteredWithIconPadding() throws {
        var map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        guard let index = map.nodes.firstIndex(where: { $0.text == "目标" }) else {
            return XCTFail("fixture missing")
        }
        map.nodes[index].icon = "target"
        map.nodes[index].note = "备注"
        let layout = LayoutEngine.layout(map)
        let node = map.nodes[index]
        let frame = try XCTUnwrap(layout.frames[node.id])
        let textLayout = NodeMeasurer.textLayout(for: node, in: frame, level: 1)
        let iconRect = try XCTUnwrap(textLayout.iconRect)

        let textCenter = textLayout.textRect.minX + textLayout.measuredSize.width / 2
        XCTAssertEqual(textCenter, frame.midX, accuracy: 0.5, "有图标时文字没有居中")
        XCTAssertEqual(textLayout.textRect.midY, frame.midY, accuracy: 0.5, "有图标时文字没有垂直居中")
        XCTAssertEqual(iconRect.midY, frame.midY, accuracy: 0.5, "图标没有和文字垂直对齐")
        XCTAssertGreaterThanOrEqual(iconRect.minX, frame.minX + 8, "图标贴到节点左边框")
        let groupRight = textLayout.textRect.minX + textLayout.measuredSize.width + NodeMeasurer.noteWidth(for: node)
        XCTAssertLessThanOrEqual(groupRight, frame.maxX - 8, "备注点贴到节点右边框")
    }
}

private func keyEvent(
    _ characters: String,
    keyCode: UInt16,
    in window: NSWindow
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )
}

extension MindscapeFeatureTests {
    private func makeTwoHeadMap() -> (MindMap, UUID, MindNode, MindNode) {
        var map = MapTemplate.project.makeMap(themeID: "paper", layout: .mindMap)
        let first = map.rootID
        let second = MindNode(parentID: nil, text: "第二头部", order: 1)
        let secondChild = MindNode(parentID: second.id, text: "第二子项", order: 0)
        map.nodes.append(second)
        map.nodes.append(secondChild)
        return (map, first, second, secondChild)
    }

    /// 多个头部节点：每棵树都要有坐标，头部都在第 0 层
    func testMultipleHeadsAcrossLayouts() throws {
        let (map, first, second, secondChild) = makeTwoHeadMap()
        for style in MapLayout.allCases {
            var copy = map
            copy.layout = style
            let layout = LayoutEngine.layout(copy)
            XCTAssertEqual(layout.rootIDs, [first, second.id], "layout \(style.rawValue)")
            XCTAssertEqual(layout.frames.count, copy.nodes.count, "layout \(style.rawValue)")
            XCTAssertEqual(layout.depths[first], 0, "layout \(style.rawValue)")
            XCTAssertEqual(layout.depths[second.id], 0, "layout \(style.rawValue)")
            XCTAssertEqual(layout.depths[secondChild.id], 1, "layout \(style.rawValue)")
            XCTAssertNotNil(layout.frames[first], "layout \(style.rawValue)")
            XCTAssertNotNil(layout.frames[second.id], "layout \(style.rawValue)")
        }
    }

    /// 回车在头部节点上是新增头部，不是新增子节点
    func testEnterOnHeadAddsAnotherHead() throws {
        let editor = try makeEditor()
        let first = editor.map.rootID
        let newID = try XCTUnwrap(editor.addSibling(after: first))
        XCTAssertNil(editor.map.node(newID)?.parentID, "头部节点的同级节点应该还是头部")
        XCTAssertEqual(editor.map.rootIDs.count, 2)
        XCTAssertEqual(editor.map.rootIDs.first, first, "新头部应该排在原来的头部后面")
    }

    /// 标题默认跟随第一个头部；手动改名后不再被覆盖；删除第一个头部后跟随新的第一个
    func testTitleFollowsFirstHead() throws {
        let editor = try makeEditor()
        let first = editor.map.rootID
        XCTAssertEqual(editor.map.title, "项目规划")
        editor.setText("招聘流程", for: first)
        XCTAssertEqual(editor.map.title, "招聘流程", "标题没有跟随第一个头部")

        editor.setTitle("我的导图")
        editor.setText("另一个名字", for: first)
        XCTAssertEqual(editor.map.title, "我的导图", "手动改过的标题被头部文字覆盖了")

        let (map, firstHead, secondHead, _) = makeTwoHeadMap()
        let store = try DocumentStore(inMemory: true)
        let twoHeads = MapEditor(map: map, store: store)
        XCTAssertEqual(twoHeads.map.title, "项目规划")
        twoHeads.setText("第一头部", for: firstHead)
        XCTAssertEqual(twoHeads.map.title, "第一头部")
        twoHeads.delete(id: firstHead)
        XCTAssertEqual(twoHeads.map.rootIDs, [secondHead.id])
        XCTAssertEqual(twoHeads.map.title, "第二头部", "删除第一个头部后标题没有跟随新的第一个头部")

        // 旧空白导图的「未命名导图」占位标题也应视为自动标题
        let blankStore = try DocumentStore(inMemory: true)
        let blankEditor = MapEditor(map: MindMap.blank(), store: blankStore)
        blankEditor.setText("新头部", for: blankEditor.map.rootID)
        XCTAssertEqual(blankEditor.map.title, "新头部")
    }

    /// 至少保留一个头部节点，不能把整张图删空
    func testCannotDeleteLastHead() throws {
        let editor = try makeEditor()
        let first = editor.map.rootID
        let before = editor.map.nodes.count
        editor.delete(id: first)
        XCTAssertEqual(editor.map.nodes.count, before, "最后一个头部节点被删掉了")
        XCTAssertEqual(editor.map.rootIDs, [first])
    }

    /// 空格进入编辑，不再触发折叠
    func testSpaceStartsEditingInsteadOfCollapse() throws {
        let shortcuts = ShortcutStore.shared
        let oldEdit = shortcuts.combo(for: .editNode)
        let oldCollapse = shortcuts.combo(for: .toggleCollapse)
        shortcuts.set(KeyCombo(key: "space"), for: .editNode)
        shortcuts.set(KeyCombo(key: "f3"), for: .toggleCollapse)
        defer {
            shortcuts.set(oldEdit, for: .editNode)
            shortcuts.set(oldCollapse, for: .toggleCollapse)
        }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        let branch = try XCTUnwrap(node(editor, "里程碑"))
        editor.select(branch.id)

        let event = try XCTUnwrap(keyEvent(" ", keyCode: 49, in: window))
        canvas.keyDown(with: event)

        XCTAssertEqual(editor.map.node(branch.id)?.collapsed, false, "空格把节点折叠了")
        let editorView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.last, "空格没有进入编辑")
        XCTAssertEqual(editorView.string, branch.text, "空格把节点原文字替换掉了")

        // 编辑中点击画布：提交编辑，不能因为文字被空格清空而删除节点
        let emptyPoint = canvas.convert(CGPoint(x: 20, y: 20), to: nil)
        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: emptyPoint, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: emptyPoint, in: window)))

        XCTAssertNotNil(editor.map.node(branch.id), "点击画布后编辑中的节点消失了")
        XCTAssertEqual(editor.map.node(branch.id)?.text, branch.text)
    }

    /// 空格编辑一个本来没有文字的节点，点到画布上不能连子树一起删掉；
    /// 没有输入时用「新主题」占位。
    func testSpaceEditingEmptyNodeKeepsSubtreeAndFillsPlaceholder() throws {
        let shortcuts = ShortcutStore.shared
        let oldEdit = shortcuts.combo(for: .editNode)
        shortcuts.set(KeyCombo(key: "space"), for: .editNode)
        defer { shortcuts.set(oldEdit, for: .editNode) }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let branch = try XCTUnwrap(node(editor, "里程碑"))
        let child = try XCTUnwrap(editor.addChild(to: branch.id))
        editor.setText("", for: branch.id)
        editor.select(branch.id)

        let event = try XCTUnwrap(keyEvent(" ", keyCode: 49, in: window))
        canvas.keyDown(with: event)

        let editorView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.last)
        XCTAssertEqual(editorView.string, "", "空格不应写入空节点")

        let emptyPoint = canvas.convert(CGPoint(x: 20, y: 20), to: nil)
        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: emptyPoint, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: emptyPoint, in: window)))

        XCTAssertNotNil(editor.map.node(branch.id), "空编辑提交后节点被删除了")
        XCTAssertNotNil(editor.map.node(child), "空编辑提交后子节点被删除了")
        XCTAssertEqual(editor.map.node(branch.id)?.text, String(localized: "新主题"), "空编辑没有回填占位文字")
    }

    /// 中心节点空编辑回填「中心主题」，与其它节点的「新主题」区分。
    func testEmptyCenterNodeFallsBackToCenterTopic() throws {
        let shortcuts = ShortcutStore.shared
        let oldEdit = shortcuts.combo(for: .editNode)
        shortcuts.set(KeyCombo(key: "space"), for: .editNode)
        defer { shortcuts.set(oldEdit, for: .editNode) }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let root = editor.map.rootID
        let child = try XCTUnwrap(editor.addChild(to: root))
        editor.setText("", for: root)
        editor.select(root)

        let event = try XCTUnwrap(keyEvent(" ", keyCode: 49, in: window))
        canvas.keyDown(with: event)

        let emptyPoint = canvas.convert(CGPoint(x: 20, y: 20), to: nil)
        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: emptyPoint, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: emptyPoint, in: window)))

        XCTAssertNotNil(editor.map.node(root), "中心节点空编辑提交后被删除了")
        XCTAssertNotNil(editor.map.node(child), "中心节点空编辑提交后子节点被删除了")
        XCTAssertEqual(editor.map.node(root)?.text, String(localized: "中心主题"), "中心节点应回填「中心主题」")
    }

    /// 开始输入时把按键交给输入框，而不是先把 event.characters 写进节点
    func testTypingLetterStartsEditingThroughTextView() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()
        let branch = try XCTUnwrap(node(editor, "里程碑"))
        editor.select(branch.id)

        let event = try XCTUnwrap(keyEvent("a", keyCode: 0, in: window))
        canvas.keyDown(with: event)

        let textView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.last)
        XCTAssertTrue(textView.isEditable)
        XCTAssertEqual(textView.string, "a", "按键没有交给输入框处理")
        canvas.commitEditing()
    }

    /// 新的默认快捷键：空格编辑、回车同级、Tab 子节点、F3 折叠
    func testEditingShortcutDefaults() {
        XCTAssertEqual(ShortcutAction.editNode.defaultCombo, KeyCombo(key: "space"))
        XCTAssertEqual(ShortcutAction.newSibling.defaultCombo, KeyCombo(key: "return"))
        XCTAssertEqual(ShortcutAction.newChild.defaultCombo, KeyCombo(key: "tab"))
        XCTAssertEqual(ShortcutAction.toggleCollapse.defaultCombo, KeyCombo(key: "f3"))
    }
}

extension MindscapeFeatureTests {
    /// 多头部节点的 Markdown / OPML 导出不能只导出第一棵树
    func testMultipleHeadsExportIncludesEveryTree() throws {
        let (map, _, second, _) = makeTwoHeadMap()
        let markdown = ExportService.markdown(map: map)
        XCTAssertTrue(markdown.contains("- 项目规划"))
        XCTAssertTrue(markdown.contains("- 第二头部"))

        let opml = ExportService.opml(map: map)
        XCTAssertTrue(opml.contains("text=\"项目规划\""))
        XCTAssertTrue(opml.contains("text=\"第二头部\""))
        XCTAssertNotNil(map.node(second.id))
    }
}

extension MindscapeFeatureTests {
    /// 重排头部节点后，标题跟随新的第一个头部
    func testTitleFollowsHeadReorder() throws {
        let (map, first, second, _) = makeTwoHeadMap()
        let store = try DocumentStore(inMemory: true)
        let editor = MapEditor(map: map, store: store)
        editor.setText("第一头部", for: first)
        XCTAssertEqual(editor.map.title, "第一头部")

        editor.reorder(id: second.id, relativeTo: first, after: false)
        XCTAssertEqual(editor.map.rootIDs.first, second.id)
        XCTAssertEqual(editor.map.title, "第二头部")
    }
}

extension MindscapeFeatureTests {
    /// 复制头部节点应该得到新的头部，而不是挂到第一个头部下面
    func testDuplicateHeadCreatesNewHead() throws {
        let (map, _, second, _) = makeTwoHeadMap()
        let store = try DocumentStore(inMemory: true)
        let editor = MapEditor(map: map, store: store)
        let before = editor.map.rootIDs.count
        editor.select(second.id)

        XCTAssertTrue(editor.duplicateSelection())
        XCTAssertEqual(editor.map.rootIDs.count, before + 1)
        let copied = try XCTUnwrap(editor.selection.first)
        XCTAssertNil(editor.map.node(copied)?.parentID)
        XCTAssertNotEqual(copied, second.id)
    }
}

extension MindscapeFeatureTests {
    /// 空导图不应该把 selection 指向一个不存在的 UUID；仍能新增头部
    func testEmptyMapIsSafe() throws {
        let map = MindMap(title: "empty", nodes: [], layout: .mindMap, themeID: "paper")
        let layout = LayoutEngine.layout(map)
        XCTAssertTrue(layout.frames.isEmpty)
        XCTAssertEqual(layout.bounds, .zero)
        XCTAssertTrue(layout.rootIDs.isEmpty)

        let store = try DocumentStore(inMemory: true)
        let editor = MapEditor(map: map, store: store)
        XCTAssertTrue(editor.selection.isEmpty)
        let newID = try XCTUnwrap(editor.addRoot())
        XCTAssertEqual(editor.map.rootIDs, [newID])
        XCTAssertEqual(editor.selection, [newID])
        XCTAssertEqual(editor.map.title, "新主题")
    }

    /// 损坏数据里的重复节点 ID 不能让 Dictionary(uniqueKeysWithValues:) 崩溃
    func testDuplicateNodeIDsDoNotCrashLayout() throws {
        var map = MindMap.blank(title: "dup", themeID: "paper", layout: .mindMap)
        let rootID = map.rootID
        map.nodes.append(MindNode(id: rootID, parentID: nil, text: "重复头部", order: 1))
        let layout = LayoutEngine.layout(map)
        XCTAssertEqual(layout.rootIDs, [rootID])
        XCTAssertNotNil(layout.frames[rootID])
    }

    /// 环形父子关系不能让递归布局无限展开
    func testCyclicMapLayoutTerminates() throws {
        var map = MindMap.blank(title: "cycle", themeID: "paper", layout: .mindMap)
        let first = map.rootID
        let second = MindNode(parentID: first, text: "第二", order: 0)
        map.nodes.append(second)
        if let index = map.nodes.firstIndex(where: { $0.id == first }) {
            map.nodes[index].parentID = second.id
        }

        for style in MapLayout.allCases {
            var copy = map
            copy.layout = style
            let layout = LayoutEngine.layout(copy)
            XCTAssertEqual(layout.frames.count, 2, "layout \(style.rawValue)")
        }
    }

    /// 撤销栈按节点总数限流：大图连续编辑不能无限保留完整快照
    func testUndoStackKeepsNodeBudget() throws {
        var map = MindMap.blank(title: "big", themeID: "paper", layout: .mindMap)
        let root = map.rootID
        for index in 0..<1_500 {
            map.nodes.append(MindNode(parentID: root, text: "节点 \(index)", order: index))
        }
        let store = try DocumentStore(inMemory: true)
        let editor = MapEditor(map: map, store: store)

        for index in 0..<60 {
            editor.setIcon(index % 2 == 0 ? "star.fill" : nil, for: root)
        }
        XCTAssertLessThanOrEqual(editor.undoCount, 30, "大图撤销栈没有按节点数收缩")
    }
}

extension MindscapeFeatureTests {
    /// 组织架构图折叠分支 / 根节点时，节点不能整体左右跳
    func testOrgChartCollapseKeepsNodePositions() throws {
        let map = makeThreeBranchOrgMap()
        let expanded = LayoutEngine.layout(map)
        let root = map.rootID
        let rootFrame = try XCTUnwrap(expanded.frames[root])
        let branches = map.children(of: root)
        let design = try XCTUnwrap(branches.first(where: { $0.text == "设计" }))
        let designChild = try XCTUnwrap(map.children(of: design.id).first)
        let designFrame = try XCTUnwrap(expanded.frames[design.id])

        var branchCollapsed = map
        if let index = branchCollapsed.nodes.firstIndex(where: { $0.id == design.id }) {
            branchCollapsed.nodes[index].collapsed = true
        }
        let afterBranch = LayoutEngine.layout(branchCollapsed)
        XCTAssertEqual(afterBranch.frames[root]?.origin, rootFrame.origin, "折叠分支后根节点移位")
        XCTAssertEqual(afterBranch.frames[design.id]?.origin, designFrame.origin, "被折叠的节点自己移位")
        XCTAssertNil(afterBranch.frames[designChild.id])
        for branch in branches where branch.id != design.id {
            XCTAssertEqual(afterBranch.frames[branch.id]?.origin, expanded.frames[branch.id]?.origin, "兄弟分支移位")
        }

        var rootCollapsed = map
        if let index = rootCollapsed.nodes.firstIndex(where: { $0.id == root }) {
            rootCollapsed.nodes[index].collapsed = true
        }
        let afterRoot = LayoutEngine.layout(rootCollapsed)
        XCTAssertEqual(afterRoot.frames[root]?.origin, rootFrame.origin, "折叠根节点后根节点移位")
        for branch in branches {
            XCTAssertNil(afterRoot.frames[branch.id])
        }
    }
}

// MARK: - 多选删除 / 批量移动

extension MindscapeFeatureTests {
    /// Delete 键删除整个选区（含各自子树），且一步撤销可恢复
    func testDeleteSelectionRemovesEverySelectedSubtree() throws {
        let editor = try makeEditor()
        let milestone = try XCTUnwrap(node(editor, "里程碑"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let removed = editor.map.subtreeIDs(of: milestone.id)
            .union(editor.map.subtreeIDs(of: risk.id))
        let before = editor.map.nodes.count

        editor.setSelection([milestone.id, risk.id])
        editor.deleteSelection()

        XCTAssertEqual(editor.map.nodes.count, before - removed.count)
        for id in removed {
            XCTAssertNil(editor.map.node(id))
        }
        let fallback = try XCTUnwrap(editor.selection.first)
        XCTAssertNotNil(editor.map.node(fallback), "删除后的选中项必须仍然存在")

        editor.undo()
        XCTAssertEqual(editor.map.nodes.count, before)
        XCTAssertNotNil(editor.map.node(milestone.id))
        XCTAssertNotNil(editor.map.node(risk.id))
    }

    /// 批量移动：选中不同父级的节点，一起挂到新目标下
    func testBatchMoveSelectionReparentsAllNodes() throws {
        let editor = try makeEditor()
        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let target = try XCTUnwrap(node(editor, "目标"))
        let budgetParent = budget.parentID
        let riskParent = risk.parentID

        editor.setSelection([budget.id, risk.id])
        XCTAssertTrue(editor.canMoveSelection(to: target.id))
        XCTAssertTrue(editor.move(ids: editor.selection, to: target.id))
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, target.id)

        editor.undo()
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, budgetParent)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, riskParent)
    }

    /// 父节点和子节点都被选中时，只搬父节点，不能把子节点从子树里拆出来
    func testBatchMoveSkipsDescendantsAlreadyInSelection() throws {
        let editor = try makeEditor()
        let resource = try XCTUnwrap(node(editor, "资源"))
        let budget = try XCTUnwrap(node(editor, "预算"))
        let target = try XCTUnwrap(node(editor, "目标"))

        editor.setSelection([resource.id, budget.id])
        XCTAssertTrue(editor.move(ids: editor.selection, to: target.id))
        XCTAssertEqual(editor.map.node(resource.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, resource.id, "子节点被重复搬运了")
    }

    /// 自由布局下迁移节点：保留自由位置，且父子关系和位置一步撤销
    func testFreeLayoutReparentPreservesPositionInSingleUndo() throws {
        let editor = try makeEditor(layout: .free)
        let budget = try XCTUnwrap(node(editor, "预算"))
        let target = try XCTUnwrap(node(editor, "目标"))
        let oldParent = budget.parentID
        let origin = CGPoint(x: 123, y: 456)

        XCTAssertTrue(editor.move(
            ids: [budget.id],
            to: target.id,
            freeOrigins: [budget.id: origin]
        ))
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(budget.id)?.position, origin)

        editor.undo()
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, oldParent)
        XCTAssertNil(editor.map.node(budget.id)?.position)
    }

    /// 自由布局多选迁移：所有选中节点挂到目标下，位置保留，撤销/重做成组生效
    func testFreeLayoutMultiSelectionReparentPreservesPositionsAndUndoRedo() throws {
        let editor = try makeEditor(layout: .free)
        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let target = try XCTUnwrap(node(editor, "目标"))
        let oldBudgetParent = budget.parentID
        let oldRiskParent = risk.parentID
        let origins = [
            budget.id: CGPoint(x: 11, y: 22),
            risk.id: CGPoint(x: 33, y: 44)
        ]

        XCTAssertTrue(editor.move(ids: [budget.id, risk.id], to: target.id, freeOrigins: origins))
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(budget.id)?.position, origins[budget.id])
        XCTAssertEqual(editor.map.node(risk.id)?.position, origins[risk.id])

        editor.undo()
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, oldBudgetParent)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, oldRiskParent)
        XCTAssertNil(editor.map.node(budget.id)?.position)
        XCTAssertNil(editor.map.node(risk.id)?.position)

        editor.redo()
        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(budget.id)?.position, origins[budget.id])
        XCTAssertEqual(editor.map.node(risk.id)?.position, origins[risk.id])
    }

    /// 自由布局批量位移应该只产生一步撤销
    func testBatchFreeMoveUsesSingleUndoStep() throws {
        let editor = try makeEditor(layout: .free)
        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))

        editor.moveFreeNodes(origins: [
            budget.id: CGPoint(x: 10, y: 20),
            risk.id: CGPoint(x: 30, y: 40)
        ])
        XCTAssertEqual(editor.map.node(budget.id)?.position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(editor.map.node(risk.id)?.position, CGPoint(x: 30, y: 40))

        editor.undo()
        XCTAssertNil(editor.map.node(budget.id)?.position)
        XCTAssertNil(editor.map.node(risk.id)?.position)
    }

    /// 自由布局多选 ⌥ 拖拽：整组迁移，位置全部保留
    func testOptionDragReparentsMultiSelectionInFreeLayout() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let target = try XCTUnwrap(node(editor, "目标"))
        editor.setSelection([budget.id, risk.id])
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let endWorld = try XCTUnwrap(layout.frames[target.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(
            .leftMouseDragged, at: end, in: window, modifiers: [.option]
        )))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(
            .leftMouseUp, at: end, in: window, modifiers: [.option]
        )))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, target.id)
        XCTAssertNotNil(editor.map.node(budget.id)?.position)
        XCTAssertNotNil(editor.map.node(risk.id)?.position)
    }

    /// 自由布局拖到自己的后代上：不能迁移，只移动位置
    func testOptionDragOnDescendantDoesNotCreateCycle() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let parent = try XCTUnwrap(node(editor, "资源"))
        let child = try XCTUnwrap(node(editor, "预算"))
        let oldParent = parent.parentID
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[parent.id]).center
        let endWorld = try XCTUnwrap(layout.frames[child.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(
            .leftMouseDragged, at: end, in: window, modifiers: [.option]
        )))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(
            .leftMouseUp, at: end, in: window, modifiers: [.option]
        )))

        XCTAssertEqual(editor.map.node(parent.id)?.parentID, oldParent)
        XCTAssertNotNil(editor.map.node(parent.id)?.position)
        XCTAssertEqual(editor.map.node(child.id)?.parentID, parent.id)
    }

    /// 非自由布局的 ⌥ 拖到同级仍是调整兄弟顺序，不能回归成迁移
    func testOptionDragOnSiblingReordersInMindMapLayout() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let manpower = try XCTUnwrap(node(editor, "人力"))
        let oldParent = budget.parentID
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let manpowerFrame = try XCTUnwrap(layout.frames[manpower.id])
        let endWorld = CGPoint(x: manpowerFrame.midX, y: manpowerFrame.minY + manpowerFrame.height * 0.2)
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(
            .leftMouseDragged, at: end, in: window, modifiers: [.option]
        )))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(
            .leftMouseUp, at: end, in: window, modifiers: [.option]
        )))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, oldParent)
        XCTAssertEqual(editor.map.node(manpower.id)?.parentID, oldParent)
        let budgetOrder = try XCTUnwrap(editor.map.node(budget.id)?.order)
        let manpowerOrder = try XCTUnwrap(editor.map.node(manpower.id)?.order)
        XCTAssertLessThan(budgetOrder, manpowerOrder)
    }

    /// 自由布局拖到同级节点：迁移为对方的子节点，不是兄弟重排
    func testOptionDragOnSiblingReparentsInFreeLayout() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let oldParent = budget.parentID
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let endWorld = try XCTUnwrap(layout.frames[risk.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(
            .leftMouseDragged, at: end, in: window, modifiers: [.option]
        )))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(
            .leftMouseUp, at: end, in: window, modifiers: [.option]
        )))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, risk.id)
        XCTAssertNotEqual(editor.map.node(budget.id)?.parentID, oldParent)
        XCTAssertNotNil(editor.map.node(budget.id)?.position)
    }

    /// 自由布局普通拖动仍然只移动位置，不改变父子关系
    func testNormalDragMovesButDoesNotReparentInFreeLayout() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let target = try XCTUnwrap(node(editor, "目标"))
        let oldParent = budget.parentID
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let endWorld = try XCTUnwrap(layout.frames[target.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(.leftMouseDragged, at: end, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: end, in: window)))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, oldParent)
        XCTAssertNotNil(editor.map.node(budget.id)?.position)
    }

    /// 自由布局按住 ⌥ 拖到节点上：迁移父子关系并保留自由位置
    func testOptionDragReparentsNodeInFreeLayout() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let target = try XCTUnwrap(node(editor, "目标"))
        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let endWorld = try XCTUnwrap(layout.frames[target.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(
            .leftMouseDragged, at: end, in: window, modifiers: [.option]
        )))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(
            .leftMouseUp, at: end, in: window, modifiers: [.option]
        )))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertNotNil(editor.map.node(budget.id)?.position)
    }

    /// 画布 Delete 键必须真正刷新布局，而不是只改模型
    func testDeleteKeyDeletesSelectionOnCanvas() throws {
        let shortcuts = ShortcutStore.shared
        let old = shortcuts.combo(for: .deleteNode)
        shortcuts.set(KeyCombo(key: "delete"), for: .deleteNode)
        defer { shortcuts.set(old, for: .deleteNode) }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let milestone = try XCTUnwrap(node(editor, "里程碑"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let removed = editor.map.subtreeIDs(of: milestone.id)
            .union(editor.map.subtreeIDs(of: risk.id))
        let before = editor.map.nodes.count
        editor.setSelection([milestone.id, risk.id])

        let event = try XCTUnwrap(keyEvent("\u{7F}", keyCode: 51, in: window))
        canvas.keyDown(with: event)

        XCTAssertEqual(editor.map.nodes.count, before - removed.count)
        XCTAssertNil(editor.map.node(milestone.id))
        XCTAssertNil(editor.map.node(risk.id))
    }

    /// 多选后直接拖动其中一个节点，整组一起移动
    func testDraggingSelectionMovesWholeGroup() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let target = try XCTUnwrap(node(editor, "目标"))
        editor.setSelection([budget.id, risk.id])

        let layout = LayoutEngine.layout(editor.map)
        let startWorld = try XCTUnwrap(layout.frames[budget.id]).center
        let endWorld = try XCTUnwrap(layout.frames[target.id]).center
        let start = canvas.convert(canvas.worldToView(startWorld), to: nil)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(.leftMouseDragged, at: end, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: end, in: window)))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, target.id, "只移动了按下的那个节点")
    }

    /// Shift 点击可以加选 / 取消选择
    func testShiftClickTogglesSelection() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        editor.select(budget.id)

        let layout = LayoutEngine.layout(editor.map)
        let riskPoint = canvas.convert(
            canvas.worldToView(try XCTUnwrap(layout.frames[risk.id]).center),
            to: nil
        )

        canvas.mouseDown(with: try XCTUnwrap(
            mouseEvent(.leftMouseDown, at: riskPoint, in: window, modifiers: [.shift])
        ))
        canvas.mouseUp(with: try XCTUnwrap(
            mouseEvent(.leftMouseUp, at: riskPoint, in: window, modifiers: [.shift])
        ))
        XCTAssertEqual(editor.selection, [budget.id, risk.id])

        canvas.mouseDown(with: try XCTUnwrap(
            mouseEvent(.leftMouseDown, at: riskPoint, in: window, modifiers: [.shift])
        ))
        canvas.mouseUp(with: try XCTUnwrap(
            mouseEvent(.leftMouseUp, at: riskPoint, in: window, modifiers: [.shift])
        ))
        XCTAssertEqual(editor.selection, [budget.id], "Shift 再次点击没有取消选择")
    }

    /// 多选修饰键改成 ⌘ 后，⌘ 点击加选、Shift 点击恢复为普通单选
    func testSelectionModifierCanBeChangedToCommand() throws {
        let shortcuts = ShortcutStore.shared
        let old = shortcuts.selectionModifier
        shortcuts.setSelectionModifier(.command)
        defer { shortcuts.setSelectionModifier(old) }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        editor.select(budget.id)

        let layout = LayoutEngine.layout(editor.map)
        let riskPoint = canvas.convert(
            canvas.worldToView(try XCTUnwrap(layout.frames[risk.id]).center),
            to: nil
        )

        canvas.mouseDown(with: try XCTUnwrap(
            mouseEvent(.leftMouseDown, at: riskPoint, in: window, modifiers: [.command])
        ))
        canvas.mouseUp(with: try XCTUnwrap(
            mouseEvent(.leftMouseUp, at: riskPoint, in: window, modifiers: [.command])
        ))
        XCTAssertEqual(editor.selection, [budget.id, risk.id], "⌘ 点击没有加选")

        canvas.mouseDown(with: try XCTUnwrap(
            mouseEvent(.leftMouseDown, at: riskPoint, in: window, modifiers: [.shift])
        ))
        canvas.mouseUp(with: try XCTUnwrap(
            mouseEvent(.leftMouseUp, at: riskPoint, in: window, modifiers: [.shift])
        ))
        XCTAssertEqual(editor.selection, [risk.id], "改成 ⌘ 后 Shift 仍被当成多选修饰键")
    }

    /// 自由布局整组拖动：两个节点位移完全一致，相对位置不变
    func testDraggingFreeSelectionKeepsRelativeOffsets() throws {
        let editor = try makeEditor(layout: .free)
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        editor.setSelection([budget.id, risk.id])
        let layout = LayoutEngine.layout(editor.map)
        let budgetFrame = try XCTUnwrap(layout.frames[budget.id])
        let riskFrame = try XCTUnwrap(layout.frames[risk.id])

        let start = canvas.convert(canvas.worldToView(budgetFrame.center), to: nil)
        let endWorld = CGPoint(x: budgetFrame.midX + 60, y: budgetFrame.midY + 45)
        let end = canvas.convert(canvas.worldToView(endWorld), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        // ⌘ 关闭吸附，位移才能精确断言
        canvas.mouseDragged(with: try XCTUnwrap(
            mouseEvent(.leftMouseDragged, at: end, in: window, modifiers: [.command])
        ))
        canvas.mouseUp(with: try XCTUnwrap(
            mouseEvent(.leftMouseUp, at: end, in: window, modifiers: [.command])
        ))

        let budgetPosition = try XCTUnwrap(editor.map.node(budget.id)?.position)
        let riskPosition = try XCTUnwrap(editor.map.node(risk.id)?.position)
        XCTAssertEqual(budgetPosition.x - budgetFrame.minX, 60, accuracy: 0.5)
        XCTAssertEqual(budgetPosition.y - budgetFrame.minY, 45, accuracy: 0.5)
        XCTAssertEqual(riskPosition.x - riskFrame.minX, 60, accuracy: 0.5)
        XCTAssertEqual(riskPosition.y - riskFrame.minY, 45, accuracy: 0.5)
        XCTAssertEqual(
            budgetPosition.x - riskPosition.x,
            budgetFrame.minX - riskFrame.minX,
            accuracy: 0.5,
            "整组拖动后相对位置变了"
        )
    }

    /// 单选拖动必须保持原有行为，不能因为批量逻辑影响单节点
    func testDraggingSingleNodeStillReparentsOnlyIt() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let budget = try XCTUnwrap(node(editor, "预算"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        let target = try XCTUnwrap(node(editor, "目标"))
        editor.select(budget.id)
        let riskParent = risk.parentID

        let layout = LayoutEngine.layout(editor.map)
        let start = canvas.convert(canvas.worldToView(try XCTUnwrap(layout.frames[budget.id]).center), to: nil)
        let end = canvas.convert(canvas.worldToView(try XCTUnwrap(layout.frames[target.id]).center), to: nil)

        canvas.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown, at: start, in: window)))
        canvas.mouseDragged(with: try XCTUnwrap(mouseEvent(.leftMouseDragged, at: end, in: window)))
        canvas.mouseUp(with: try XCTUnwrap(mouseEvent(.leftMouseUp, at: end, in: window)))

        XCTAssertEqual(editor.map.node(budget.id)?.parentID, target.id)
        XCTAssertEqual(editor.map.node(risk.id)?.parentID, riskParent, "未选中的节点被一起移动了")
    }

    /// 自定义「删除节点」快捷键后，系统 Delete 键仍应删除选区
    func testDeleteKeyStillWorksWhenShortcutIsCustomized() throws {
        let shortcuts = ShortcutStore.shared
        let old = shortcuts.combo(for: .deleteNode)
        shortcuts.set(KeyCombo(key: "f12"), for: .deleteNode)
        defer { shortcuts.set(old, for: .deleteNode) }

        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        let milestone = try XCTUnwrap(node(editor, "里程碑"))
        let risk = try XCTUnwrap(node(editor, "风险"))
        editor.setSelection([milestone.id, risk.id])

        let event = try XCTUnwrap(keyEvent("\u{7F}", keyCode: 51, in: window))
        canvas.keyDown(with: event)

        XCTAssertNil(editor.map.node(milestone.id))
        XCTAssertNil(editor.map.node(risk.id))
    }

    /// 新手提示依赖画布交互回调：点击或按键后应立即触发一次
    func testCanvasNotifiesWhenUserStartsInteracting() throws {
        let editor = try makeEditor()
        let canvas = MindCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.attach(editor: editor, theme: MapTheme.byID("paper"))
        let window = canvas.attachToTestWindow()

        var interactions = 0
        canvas.onUserInteraction = { interactions += 1 }

        let emptyPoint = canvas.convert(NSPoint(x: 6, y: 6), to: nil)
        canvas.mouseDown(with: try XCTUnwrap(
            mouseEvent(.leftMouseDown, at: emptyPoint, in: window)
        ))
        XCTAssertEqual(interactions, 1, "点击画布没有通知收起提示")

        let event = try XCTUnwrap(keyEvent(" ", keyCode: 49, in: window))
        canvas.keyDown(with: event)
        XCTAssertEqual(interactions, 2, "按键开始编辑时没有通知收起提示")
        canvas.commitEditing()
    }

    /// 新手提示全局只自动展开一次，换导图 / 重启后都不再弹
    func testCanvasTipsGateOnlyShowsOnceGlobally() throws {
        let suiteName = "mindscape.tips.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let gate = CanvasTipsGate(defaults: defaults)
        XCTAssertTrue(gate.shouldShow, "首次使用应该自动展开")
        gate.markShown()

        XCTAssertFalse(gate.shouldShow, "同一会话内不应重复展开")
        XCTAssertFalse(
            CanvasTipsGate(defaults: defaults).shouldShow,
            "重新创建视图 / 重启后不应再次自动展开"
        )
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
