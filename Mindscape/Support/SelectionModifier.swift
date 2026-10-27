import AppKit

/// 画布多选修饰键：按住它点击节点可加选 / 减选，拖拽空白处可框选。
/// 只提供 Shift / Command 两个选项，避免和 ⌥ 同级排序、⌃ 右键菜单冲突。
enum SelectionModifier: String, CaseIterable, Identifiable, Codable {
    case shift
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        }
    }
}
