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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newDocument: return "新建导图"
        case .saveDocument: return "保存"
        case .undo: return "撤销"
        case .redo: return "重做"
        case .showHistory: return "历史版本"
        case .fitCanvas: return "适配画布"
        case .zoomIn: return "放大"
        case .zoomOut: return "缩小"
        case .toggleInspector: return "显示 / 隐藏属性面板"
        case .newChild: return "新建子主题"
        case .newSibling: return "新建同级主题"
        case .editNode: return "编辑当前节点"
        case .deleteNode: return "删除节点"
        case .toggleCollapse: return "折叠 / 展开"
        }
    }

    var category: String {
        switch self {
        case .newDocument, .saveDocument: return "文件"
        case .undo, .redo: return "编辑"
        case .newChild, .newSibling, .editNode, .deleteNode, .toggleCollapse: return "节点"
        case .fitCanvas, .zoomIn, .zoomOut, .toggleInspector: return "视图"
        case .showHistory: return "历史"
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
        case .undo: return KeyCombo(key: "z", command: true)
        case .redo: return KeyCombo(key: "z", command: true, shift: true)
        case .showHistory: return KeyCombo(key: "h", command: true, shift: true)
        case .fitCanvas: return KeyCombo(key: "0", command: true)
        case .zoomIn: return KeyCombo(key: "=", command: true)
        case .zoomOut: return KeyCombo(key: "-", command: true)
        case .toggleInspector: return KeyCombo(key: "i", command: true, option: true)
        case .newChild: return KeyCombo(key: "tab")
        case .newSibling: return KeyCombo(key: "return")
        case .editNode: return KeyCombo(key: "f2")
        case .deleteNode: return KeyCombo(key: "delete")
        case .toggleCollapse: return KeyCombo(key: "space")
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
        guard !key.isEmpty else { return "未设置" }
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

    private static let storageKey = "mindscape.shortcuts.v2"

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
        combos = loaded
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
        if candidate.isEmpty { return "快捷键不能为空" }
        if action.scope == .menu && !candidate.hasCommandLikeModifier {
            return "菜单快捷键至少需要 ⌘ / ⌥ / ⌃ 中的一个，避免和输入冲突"
        }
        if let conflict = conflict(with: candidate, excluding: action) {
            return "该快捷键已被「\(conflict.title)」使用"
        }
        if candidate.command, candidate.key == "q", !candidate.shift, !candidate.option, !candidate.control {
            return "⌘Q 是系统退出快捷键"
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
}
