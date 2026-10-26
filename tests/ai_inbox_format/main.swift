import Foundation

// AIInboxFormat 的无 UI 测试：不依赖 SwiftUI / Xcode 工程，直接 swiftc 编译运行。
// 运行方式：scripts/test-aibridge.sh（会把 tests/fixtures 作为第一个参数传进来）

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)")
    }
}

let fixturesPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tests/fixtures"
let icons: Set<String> = ["target", "calendar", "lightbulb"]

func fixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: fixturesPath).appendingPathComponent(name)
    return try Data(contentsOf: url)
}

func makeMap(_ name: String) throws -> MindMap {
    let request = try JSONDecoder().decode(AIRequest.self, from: try fixture(name))
    return try AIInboxFormat.makeMap(from: request, knownIcons: icons)
}

func makeMap(json: String) throws -> MindMap {
    let request = try JSONDecoder().decode(AIRequest.self, from: Data(json.utf8))
    return try AIInboxFormat.makeMap(from: request, knownIcons: icons)
}

func edits(_ name: String) throws -> [AIEdit] {
    try JSONDecoder().decode([AIEdit].self, from: try fixture(name))
}

print("create")

do {
    let map = try makeMap("authoring-minimal.json")
    expect(map.nodes.count == 1, "单节点")
    expect(map.title == "周会", "标题默认跟随根节点")
    expect(map.layout == .mindMap, "默认布局")
    expect(map.themeID == "paper", "默认主题")
} catch {
    expect(false, "最小请求抛错：\(error)")
}

do {
    let map = try makeMap("authoring-full.json")
    expect(map.nodes.count == 7, "七个节点")
    expect(map.title == "Q4 规划", "显式标题")
    expect(map.layout == .timeline, "布局生效")
    expect(map.themeID == "ink", "主题生效")

    let root = map.primaryRoot
    expect(root?.note == "北极星：DAU 提升 30%", "备注")
    expect(root?.icon == "target", "已知图标保留")

    let children = map.children(of: map.rootID)
    expect(children.map(\.text) == ["增长", "风险", "排期"], "同级顺序")
    expect(children.map(\.order) == [0, 1, 2], "order 连续")
    expect(children[1].colorHex == "#c26a4a", "颜色规范化成小写")
    expect(children[2].icon == "calendar", "第二个已知图标")
    expect(map.children(of: children[0].id).count == 2, "二级子节点")
} catch {
    expect(false, "完整请求抛错：\(error)")
}

do {
    // 未知图标静默丢弃
    let map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"icon\":\"not-a-real-symbol\"}}")
    expect(map.primaryRoot?.icon == nil, "未知图标丢弃")
} catch {
    expect(false, "未知图标抛错：\(error)")
}

do {
    // 层级超限：根 + 13 层
    var json = "{\"text\":\"leaf\"}"
    for _ in 0...AILimits.depth {
        json = "{\"text\":\"x\",\"children\":[" + json + "]}"
    }
    _ = try makeMap(json: "{\"op\":\"create\",\"tree\":" + json + "}")
    expect(false, "超深应被拒")
} catch let error as AIRequestError {
    expect(error.reason == "too_large", "超深 -> too_large")
} catch {
    expect(false, "超深抛了别的错：\(error)")
}

do {
    // 节点超限
    var children: [String] = []
    children.reserveCapacity(AILimits.nodes + 1)
    for _ in 0...AILimits.nodes {
        children.append("{\"text\":\"n\"}")
    }
    let json = "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"children\":[" + children.joined(separator: ",") + "]}}"
    _ = try makeMap(json: json)
    expect(false, "超量应被拒")
} catch let error as AIRequestError {
    expect(error.reason == "too_large", "超量 -> too_large")
} catch {
    expect(false, "超量抛了别的错：\(error)")
}

print("patch")

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"Q4\",\"children\":[{\"text\":\"风险\"}]}}")
    try AIInboxFormat.apply(try edits("edits-mixed.json"), to: &map, knownIcons: icons)

    expect(map.primaryRoot?.text == "Q4 规划", "setText 走路径寻址")
    guard let risk = map.nodes.first(where: { $0.text == "风险" }) else {
        expect(false, "找不到风险节点")
        exit(1)
    }
    expect(risk.colorHex == "#8c857b", "setColor")
    expect(risk.note == "两个风险", "setNote")
    expect(map.children(of: risk.id).map(\.text) == ["预算", "人手"], "addChildren 顺序")
} catch {
    expect(false, "patch 抛错：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"children\":[{\"text\":\"A\",\"children\":[{\"text\":\"A1\"}]},{\"text\":\"B\"}]}}")
    let before = map.nodes.count
    try AIInboxFormat.apply(try edits("edits-remove.json"), to: &map, knownIcons: icons)
    expect(map.nodes.count == before - 2, "remove 连带子树")
    expect(map.children(of: map.rootID).map(\.text) == ["B"], "剩余同级")
} catch {
    expect(false, "remove 抛错：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"children\":[{\"text\":\"A\"},{\"text\":\"B\"}]}}")
    try AIInboxFormat.apply(try edits("edits-move.json"), to: &map, knownIcons: icons)
    guard let b = map.nodes.first(where: { $0.text == "B" }) else {
        expect(false, "找不到 B")
        exit(1)
    }
    expect(map.children(of: b.id).map(\.text) == ["A"], "move 换父节点")
} catch {
    expect(false, "move 抛错：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"children\":[{\"text\":\"A\"}]}}")
    _ = try AIInboxFormat.apply(try edits("edits-invalid-move.json"), to: &map, knownIcons: icons)
    expect(false, "移进自己子树应被拒")
} catch let error as AIRequestError {
    expect(error.reason == "invalid", "移进自己子树 -> invalid")
} catch {
    expect(false, "抛了别的错：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\"}}")
    let snapshot = map
    do {
        try AIInboxFormat.apply(try edits("edits-atomic.json"), to: &map, knownIcons: icons)
        expect(false, "整批应失败")
    } catch let error as AIRequestError {
        expect(error.reason == "not_found", "找不到节点 -> not_found")
        expect(map.title == snapshot.title && map.nodes.count == snapshot.nodes.count, "整批原子：失败不落盘")
    }
} catch {
    expect(false, "原子性用例外层失败：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\"}}")
    try AIInboxFormat.apply(try edits("edits-layout.json"), to: &map, knownIcons: icons)
    expect(map.layout == .braceMap, "setLayout")
    expect(map.themeID == "neon", "setTheme")
} catch {
    expect(false, "布局/主题抛错：\(error)")
}

do {
    var map = try makeMap(json: "{\"op\":\"create\",\"tree\":{\"text\":\"根\",\"children\":[{\"text\":\"A\"}]}}")
    let rootID = map.rootID.uuidString
    do {
        try AIInboxFormat.apply(
            try JSONDecoder().decode([AIEdit].self, from: Data(("[{\"kind\":\"remove\",\"target\":{\"id\":\"" + rootID + "\"}}]").utf8)),
            to: &map,
            knownIcons: icons
        )
        expect(false, "删根节点应被拒")
    } catch let error as AIRequestError {
        expect(error.reason == "invalid", "删根节点 -> invalid")
    }
} catch {
    expect(false, "删根用例外层失败：\(error)")
}

print("color")
expect(AIInboxFormat.normalizeColor("#AABBCC") == "#aabbcc", "大写转小写")
expect(AIInboxFormat.normalizeColor(" #AABBCC ") == "#aabbcc", "去空白")
expect(AIInboxFormat.normalizeColor("#abc") == nil, "短格式拒绝")
expect(AIInboxFormat.normalizeColor("red") == nil, "非 hex 拒绝")
expect(AIInboxFormat.normalizeColor("#GGGGGG") == nil, "非法字符拒绝")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
