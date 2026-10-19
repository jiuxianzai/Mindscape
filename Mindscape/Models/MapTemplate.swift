import Foundation

enum MapTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank
    case project
    case meeting
    case reading
    case swot
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "空白导图"
        case .project: return "项目规划"
        case .meeting: return "会议纪要"
        case .reading: return "读书笔记"
        case .swot: return "SWOT 分析"
        case .weekly: return "周计划"
        }
    }

    var subtitle: String {
        switch self {
        case .blank: return "从中心主题开始"
        case .project: return "目标、里程碑与风险"
        case .meeting: return "议题、结论与待办"
        case .reading: return "观点、金句与联想"
        case .swot: return "优势、劣势、机会、威胁"
        case .weekly: return "本周重点与安排"
        }
    }

    var symbol: String {
        switch self {
        case .blank: return "circle.dashed"
        case .project: return "flag.checkered"
        case .meeting: return "person.2"
        case .reading: return "book"
        case .swot: return "square.grid.2x2"
        case .weekly: return "calendar"
        }
    }

    func makeMap(themeID: String, layout: MapLayout) -> MindMap {
        switch self {
        case .blank:
            let root = MindNode(parentID: nil, text: "中心主题", order: 0)
            return MindMap(title: "未命名导图", nodes: [root], layout: layout, themeID: themeID)
        case .project:
            return build(
                title: "项目规划",
                root: "项目规划",
                themeID: themeID,
                layout: layout,
                branches: [
                    ("目标", ["要解决的问题", "成功标准"]),
                    ("里程碑", ["第一阶段", "第二阶段", "上线"]),
                    ("资源", ["人力", "预算"]),
                    ("风险", ["已知风险", "应对方案"])
                ]
            )
        case .meeting:
            return build(
                title: "会议纪要",
                root: "会议纪要",
                themeID: themeID,
                layout: layout,
                branches: [
                    ("议题", ["议题一", "议题二"]),
                    ("结论", ["已达成的共识"]),
                    ("待办", ["负责人 / 截止时间"])
                ]
            )
        case .reading:
            return build(
                title: "读书笔记",
                root: "书名",
                themeID: themeID,
                layout: layout,
                branches: [
                    ("核心观点", ["观点一", "观点二"]),
                    ("金句", ["摘录"]),
                    ("我的思考", ["联想到"]),
                    ("行动", ["可以怎么做"])
                ]
            )
        case .swot:
            let root = MindNode(parentID: nil, text: "SWOT 分析", order: 0)
            var nodes: [MindNode] = [root]
            let items: [(String, [String])] = [
                ("S 优势", ["内部优势"]),
                ("W 劣势", ["内部劣势"]),
                ("O 机会", ["外部机会"]),
                ("T 威胁", ["外部威胁"])
            ]
            for (index, item) in items.enumerated() {
                let branch = MindNode(parentID: root.id, text: item.0, order: index)
                nodes.append(branch)
                for (childIndex, text) in item.1.enumerated() {
                    nodes.append(MindNode(parentID: branch.id, text: text, order: childIndex))
                }
            }
            return MindMap(title: "SWOT 分析", nodes: nodes, layout: layout, themeID: themeID)
        case .weekly:
            return build(
                title: "周计划",
                root: "本周",
                themeID: themeID,
                layout: layout,
                branches: [
                    ("重点", ["最重要的一件事"]),
                    ("安排", ["周一", "周二", "周三"]),
                    ("复盘", ["完成情况"])
                ]
            )
        }
    }

    private func build(title: String, root: String, themeID: String, layout: MapLayout, branches: [(String, [String])]) -> MindMap {
        let rootNode = MindNode(parentID: nil, text: root, order: 0)
        var nodes: [MindNode] = [rootNode]
        for (branchIndex, branch) in branches.enumerated() {
            let branchNode = MindNode(parentID: rootNode.id, text: branch.0, order: branchIndex)
            nodes.append(branchNode)
            for (childIndex, text) in branch.1.enumerated() {
                nodes.append(MindNode(parentID: branchNode.id, text: text, order: childIndex))
            }
        }
        return MindMap(title: title, nodes: nodes, layout: layout, themeID: themeID)
    }
}
