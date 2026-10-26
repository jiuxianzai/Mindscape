import Foundation

// 验证 AI 写入前的忙判定信号，以及 applyExternal 的撤销语义。
// 不需要 UI、不需要 Xcode 工程：scripts/test-editor-state.sh

@main
struct EditorStateTests {
    @MainActor static var failures = 0

    @MainActor
    static func check(_ condition: Bool, _ label: String) {
        print(condition ? "  ok   \(label)" : "  FAIL \(label)")
        if !condition { failures += 1 }
    }

    @MainActor
    static func main() throws {
        let store = try DocumentStore(inMemory: true)
        var map = MindMap()
        map.title = "根"
        map.nodes = [MindNode(text: "根", order: 0)]
        let rootID = map.rootID

        let editor = MapEditor(map: map, store: store)

        check(!editor.hasPendingSave, "新打开：没有待保存改动")
        check(editor.editingNodeID == nil, "新打开：不在编辑")

        editor.setText("根（改）", for: rootID)
        check(editor.hasPendingSave, "改完文字：待保存 = true（AI 应被拒绝）")
        check(editor.map.primaryRoot?.text == "根（改）", "模型已更新")

        editor.saveNow()
        check(!editor.hasPendingSave, "保存后：待保存 = false（AI 可以写）")

        editor.editingNodeID = rootID
        check(editor.editingNodeID != nil, "进入编辑：editingNodeID 有值（AI 应被拒绝）")
        editor.editingNodeID = nil

        var external = editor.map
        external.nodes.append(MindNode(parentID: rootID, text: "AI 加的", order: 0))
        let revisionBefore = editor.revision
        let undoBefore = editor.undoCount

        editor.applyExternal(external)

        check(editor.map.nodes.count == 2, "applyExternal：节点数 2")
        check(editor.revision == revisionBefore + 1, "applyExternal：revision +1（画布会重排）")
        check(editor.undoCount == undoBefore + 1, "applyExternal：可撤销")
        check(!editor.hasPendingSave, "applyExternal：不触发重复保存")

        editor.undo()
        check(editor.map.nodes.count == 1, "⌘Z 能撤掉 AI 的改动")
        // undo() 内部会 scheduleSave：撤销本身也是要落盘的改动
        check(editor.hasPendingSave, "撤销后标记为待保存（正确行为）")
        editor.saveNow()
        check(!editor.hasPendingSave, "落盘后回到干净状态")

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
