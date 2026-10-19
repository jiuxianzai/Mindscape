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
        case .mindMap: return "思维导图"
        case .logicRight: return "逻辑图（右）"
        case .logicLeft: return "逻辑图（左）"
        case .orgChart: return "组织架构图"
        case .tree: return "树形图"
        case .timeline: return "时间轴"
        case .braceMap: return "括号图"
        case .free: return "自由布局"
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
