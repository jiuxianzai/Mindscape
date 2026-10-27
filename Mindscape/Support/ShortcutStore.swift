import AppKit
import Combine
import SwiftUI

enum ShortcutScope {
    case menu
    case canvas
}

enum ShortcutAction: String, CaseIterable, Identifiable, Hashable {
    case newDocument
    case saveDocument
    case exportDocument
    case undo
    case redo
    case showHistory
    case fitCanvas
    case zoomIn
    case zoomOut
    case toggleInspector
    case newChild
    case newSibling
    case editNode
    case deleteNode
    case toggleCollapse
    case findNode
    case duplicateNode
    case importDocument
    case focusMode
    case zoomToBranch
    case collapseAll
    case expandAll
    case toggleOutline
    case presentMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newDocument: return String(localized: "新建导图")
        case .saveDocument: return String(localized: "保存")
        case .exportDocument: return String(localized: "导出…")
        case .undo: return String(localized: "撤销")
        case .redo: return String(localized: "重做")
        case .showHistory: return String(localized: "历史版本")
        case .fitCanvas: return String(localized: "适配画布")
        case .zoomIn: return String(localized: "放大")
        case .zoomOut: return String(localized: "缩小")
        case .toggleInspector: return String(localized: "显示 / 隐藏属性面板")
        case .newChild: return String(localized: "新建子主题")
        case .newSibling: return String(localized: "新建同级主题")
        case .editNode: return String(localized: "编辑当前节点")
        case .deleteNode: return String(localized: "删除节点")
        case .toggleCollapse: return String(localized: "折叠 / 展开")
        case .findNode: return String(localized: "图内搜索")
        case .duplicateNode: return String(localized: "创建副本")
        case .importDocument: return String(localized: "导入…")
        case .focusMode: return String(localized: "专注模式")
        case .zoomToBranch: return String(localized: "缩放到分支")
        case .collapseAll: return String(localized: "折叠全部子分支")
        case .expandAll: return String(localized: "展开全部")
        case .toggleOutline: return String(localized: "显示 / 隐藏大纲")
        case .presentMode: return String(localized: "演示模式")
        }
    }

    var category: String {
        switch self {
        case .newDocument, .saveDocument, .exportDocument, .importDocument: return String(localized: "文件")
        case .undo, .redo, .findNode, .duplicateNode: return String(localized: "编辑")
        case .newChild, .newSibling, .editNode, .deleteNode, .toggleCollapse: return String(localized: "节点")
        case .fitCanvas, .zoomIn, .zoomOut, .toggleInspector,
             .focusMode, .zoomToBranch, .collapseAll, .expandAll, .toggleOutline, .presentMode:
            return String(localized: "视图")
        case .showHistory: return String(localized: "历史")
        }
    }

    var scope: ShortcutScope {
        switch self {
        case .newChild, .newSibling, .editNode, .deleteNode, .toggleCollapse:
            return .canvas
        default:
            return .menu
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .newDocument: return KeyCombo(key: "n", command: true)
        case .saveDocument: return KeyCombo(key: "s", command: true)
        case .exportDocument: return KeyCombo(key: "e", command: true)
        case .undo: return KeyCombo(key: "z", command: true)
        case .redo: return KeyCombo(key: "z", command: true, shift: true)
        case .showHistory: return KeyCombo(key: "h", command: true, shift: true)
        case .fitCanvas: return KeyCombo(key: "0", command: true)
        case .zoomIn: return KeyCombo(key: "=", command: true)
        case .zoomOut: return KeyCombo(key: "-", command: true)
        case .toggleInspector: return KeyCombo(key: "i", command: true, option: true)
        case .newChild: return KeyCombo(key: "tab")
        case .newSibling: return KeyCombo(key: "return")
        case .editNode: return KeyCombo(key: "space")
        case .deleteNode: return KeyCombo(key: "delete")
        case .toggleCollapse: return KeyCombo(key: "f3")
        case .findNode: return KeyCombo(key: "f", command: true)
        case .duplicateNode: return KeyCombo(key: "d", command: true)
        case .importDocument: return KeyCombo(key: "i", command: true, shift: true)
        case .focusMode: return KeyCombo(key: "f", command: true, shift: true)
        case .zoomToBranch: return KeyCombo(key: "b", command: true, shift: true)
        case .collapseAll: return KeyCombo(key: "c", command: true, shift: true)
        case .expandAll: return KeyCombo(key: "e", command: true, shift: true)
        case .toggleOutline: return KeyCombo(key: "o", command: true, shift: true)
        case .presentMode: return KeyCombo(key: "p", command: true, shift: true)
        }
    }

    var defaultLabel: String { defaultCombo.display }
}

struct KeyCombo: Codable, Equatable, Hashable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    init?(event: NSEvent) {
        guard let key = KeyCombo.keyName(for: event) else { return nil }
        self.init(
            key: key,
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
    }

    var isEmpty: Bool { key.isEmpty }

    var hasModifier: Bool { command || shift || option || control }
    var hasCommandLikeModifier: Bool { command || option || control }

    var display: String {
        guard !key.isEmpty else { return String(localized: "未设置") }
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += keyLabel
        return result
    }

    var keyLabel: String {
        switch key {
        case "tab": return "Tab"
        case "return": return "↩"
        case "delete": return "⌫"
        case "space": return "Space"
        case "escape": return "Esc"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "home": return "Home"
        case "end": return "End"
        case "pageup": return "PgUp"
        case "pagedown": return "PgDn"
        default: return key.uppercased()
        }
    }

    var keyEquivalent: KeyEquivalent? {
        guard !key.isEmpty else { return nil }
        switch key {
        case "tab": return .tab
        case "return": return .return
        case "delete": return .delete
        case "space": return .space
        case "escape": return .escape
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        case "home": return .home
        case "end": return .end
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        case "f1": return KeyCombo.functionKey(NSF1FunctionKey)
        case "f2": return KeyCombo.functionKey(NSF2FunctionKey)
        case "f3": return KeyCombo.functionKey(NSF3FunctionKey)
        case "f4": return KeyCombo.functionKey(NSF4FunctionKey)
        case "f5": return KeyCombo.functionKey(NSF5FunctionKey)
        case "f6": return KeyCombo.functionKey(NSF6FunctionKey)
        case "f7": return KeyCombo.functionKey(NSF7FunctionKey)
        case "f8": return KeyCombo.functionKey(NSF8FunctionKey)
        case "f9": return KeyCombo.functionKey(NSF9FunctionKey)
        case "f10": return KeyCombo.functionKey(NSF10FunctionKey)
        case "f11": return KeyCombo.functionKey(NSF11FunctionKey)
        case "f12": return KeyCombo.functionKey(NSF12FunctionKey)
        default:
            guard key.count == 1, let character = key.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    var swiftModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let candidate = KeyCombo(event: event), !key.isEmpty else { return false }
        if candidate == self { return true }
        // ⌘= / ⌘+、⌘- / ⌘_ 视为同一个快捷键
        if key == "=", candidate.key == "=",
           command == candidate.command, option == candidate.option, control == candidate.control {
            return true
        }
        if key == "-", candidate.key == "-",
           command == candidate.command, option == candidate.option, control == candidate.control {
            return true
        }
        return false
    }

    static func functionKey(_ value: Int) -> KeyEquivalent? {
        guard let scalar = UnicodeScalar(UInt32(value)) else { return nil }
        return KeyEquivalent(Character(scalar))
    }

    static func keyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 48: return "tab"
        case 36, 76: return "return"
        case 51, 117: return "delete"
        case 49: return "space"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 115: return "home"
        case 119: return "end"
        case 116: return "pageup"
        case 121: return "pagedown"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        default:
            if let name = ansiKeys[event.keyCode] { return name }
            guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                  let first = characters.first,
                  first.unicodeScalars.first.map({ $0.value >= 32 }) == true else { return nil }
            return String(first)
        }
    }

    private static let ansiKeys: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`"
    ]
}

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var combos: [ShortcutAction: KeyCombo]
    /// 画布多选修饰键，默认 Shift；可在设置里改成 Command。
    @Published private(set) var selectionModifier: SelectionModifier = .shift

    private static let storageKey = "mindscape.shortcuts.v2"
    private static let selectionModifierKey = "mindscape.selectionModifier.v1"

    private init() {
        var loaded: [ShortcutAction: KeyCombo] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let raw = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            for action in ShortcutAction.allCases {
                if let combo = raw[action.rawValue] {
                    loaded[action] = combo
                }
            }
        }
        for action in ShortcutAction.allCases where loaded[action] == nil {
            loaded[action] = action.defaultCombo
        }
        // 0.5.1 之前 Space 是折叠、F2 是编辑；现在改成 Space 编辑、F3 折叠。
        // 只在用户还停留在旧默认值时迁移，避免覆盖自定义快捷键。
        var migrated = false
        if loaded[.editNode] == KeyCombo(key: "f2") {
            loaded[.editNode] = KeyCombo(key: "space")
            migrated = true
        }
        if loaded[.toggleCollapse] == KeyCombo(key: "space") {
            loaded[.toggleCollapse] = KeyCombo(key: "f3")
            migrated = true
        }
        combos = loaded
        if let raw = UserDefaults.standard.string(forKey: Self.selectionModifierKey),
           let modifier = SelectionModifier(rawValue: raw) {
            selectionModifier = modifier
        }
        if migrated {
            persist()
        }
    }

    /// 修改多选修饰键；与快捷键一样写入 UserDefaults，重启后保留。
    func setSelectionModifier(_ modifier: SelectionModifier) {
        guard selectionModifier != modifier else { return }
        selectionModifier = modifier
        UserDefaults.standard.set(modifier.rawValue, forKey: Self.selectionModifierKey)
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        combos[action] ?? action.defaultCombo
    }

    func set(_ combo: KeyCombo, for action: ShortcutAction) {
        combos[action] = combo
        persist()
    }

    func reset(_ action: ShortcutAction) {
        set(action.defaultCombo, for: action)
    }

    func resetAll() {
        for action in ShortcutAction.allCases {
            combos[action] = action.defaultCombo
        }
        persist()
    }

    func clear(_ action: ShortcutAction) {
        set(KeyCombo(key: ""), for: action)
    }

    func isDefault(_ action: ShortcutAction) -> Bool {
        combo(for: action) == action.defaultCombo
    }

    /// 返回与当前组合冲突的另一个动作。
    func conflict(with candidate: KeyCombo, excluding action: ShortcutAction) -> ShortcutAction? {
        guard !candidate.isEmpty else { return nil }
        return ShortcutAction.allCases.first { other in
            other != action && !combo(for: other).isEmpty && combo(for: other) == candidate
        }
    }

    func conflictingActions() -> Set<ShortcutAction> {
        var groups: [KeyCombo: [ShortcutAction]] = [:]
        for action in ShortcutAction.allCases {
            let current = combo(for: action)
            guard !current.isEmpty else { continue }
            groups[current, default: []].append(action)
        }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    func validationError(for candidate: KeyCombo, action: ShortcutAction) -> String? {
        if candidate.isEmpty { return String(localized: "快捷键不能为空") }
        if action.scope == .menu && !candidate.hasCommandLikeModifier {
            return String(localized: "菜单快捷键至少需要 ⌘ / ⌥ / ⌃ 中的一个，避免和输入冲突")
        }
        if let conflict = conflict(with: candidate, excluding: action) {
            return String(localized: "该快捷键已被「\(conflict.title)」使用")
        }
        if candidate.command, candidate.key == "q", !candidate.shift, !candidate.option, !candidate.control {
            return String(localized: "⌘Q 是系统退出快捷键")
        }
        return nil
    }

    func action(for event: NSEvent, scope: ShortcutScope) -> ShortcutAction? {
        ShortcutAction.allCases.first { action in
            action.scope == scope && !combo(for: action).isEmpty && combo(for: action).matches(event)
        }
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension View {
    /// 只在快捷键存在时应用，清空后菜单里不再显示快捷键。
    @ViewBuilder
    func appShortcut(_ combo: KeyCombo) -> some View {
        if let key = combo.keyEquivalent, !combo.isEmpty {
            keyboardShortcut(key, modifiers: combo.swiftModifiers)
        } else {
            self
        }
    }
}

extension Notification.Name {
    static let mindscapeShowHistory = Notification.Name("mindscape.showHistory")
    static let mindscapeToggleInspector = Notification.Name("mindscape.toggleInspector")
    static let mindscapeShowExport = Notification.Name("mindscape.showExport")
    static let mindscapeFind = Notification.Name("mindscape.find")
    static let mindscapeToggleOutline = Notification.Name("mindscape.toggleOutline")
    static let mindscapePresent = Notification.Name("mindscape.present")
}
