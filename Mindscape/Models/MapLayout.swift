import Foundation

enum MapLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case mindMap
    case logicRight
    case logicLeft
    case orgChart
    case tree
    case timeline
    case braceMap
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mindMap: return String(localized: "思维导图")
        case .logicRight: return String(localized: "逻辑图（右）")
        case .logicLeft: return String(localized: "逻辑图（左）")
        case .orgChart: return String(localized: "组织架构图")
        case .tree: return String(localized: "树形图")
        case .timeline: return String(localized: "时间轴")
        case .braceMap: return String(localized: "括号图")
        case .free: return String(localized: "自由布局")
        }
    }

    var symbol: String {
        switch self {
        case .mindMap: return "circle.hexagongrid"
        case .logicRight: return "arrow.right.to.line"
        case .logicLeft: return "arrow.left.to.line"
        case .orgChart: return "rectangle.split.3x1"
        case .tree: return "list.bullet.indent"
        case .timeline: return "chart.bar.xaxis"
        case .braceMap: return "curlybraces"
        case .free: return "hand.draw"
        }
    }

    var usesAutoLayout: Bool { self != .free }
}

/// 思维导图一级分支的左右排列方式。
/// - remember：记住用户拖动后的左右侧，不再自动改动
/// - balanced：每次布局按分支高度自动平衡左右两侧
enum MindMapLayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case remember
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remember: return String(localized: "记住布局")
        case .balanced: return String(localized: "平衡布局")
        }
    }

    var subtitle: String {
        switch self {
        case .remember: return String(localized: "保留你拖动后的左右分支")
        case .balanced: return String(localized: "自动平衡左右两侧，会改动你的布局")
        }
    }

    var symbol: String {
        switch self {
        case .remember: return "pin"
        case .balanced: return "arrow.left.and.right"
        }
    }
}
