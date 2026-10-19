import AppKit
import SwiftUI

struct MapTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool
    let showsGrid: Bool

    let background: NSColor
    let backgroundBottom: NSColor
    let grid: NSColor
    let rootFill: NSColor
    let rootText: NSColor
    let branchFill: NSColor
    let branchText: NSColor
    let nodeFill: NSColor
    let nodeText: NSColor
    let border: NSColor
    let connector: NSColor
    let accent: NSColor

    static let defaultThemeID = "paper"

    private static func theme(
        id: String,
        name: String,
        isDark: Bool,
        showsGrid: Bool,
        bg: String,
        bgBottom: String? = nil,
        grid: String,
        rootFill: String,
        rootText: String,
        branchFill: String,
        branchText: String,
        nodeFill: String,
        nodeText: String,
        border: String,
        connector: String,
        accent: String
    ) -> MapTheme {
        MapTheme(
            id: id,
            name: name,
            isDark: isDark,
            showsGrid: showsGrid,
            background: NSColor(hex: bg),
            backgroundBottom: NSColor(hex: bgBottom ?? bg),
            grid: NSColor(hex: grid),
            rootFill: NSColor(hex: rootFill),
            rootText: NSColor(hex: rootText),
            branchFill: NSColor(hex: branchFill),
            branchText: NSColor(hex: branchText),
            nodeFill: NSColor(hex: nodeFill),
            nodeText: NSColor(hex: nodeText),
            border: NSColor(hex: border),
            connector: NSColor(hex: connector),
            accent: NSColor(hex: accent)
        )
    }

    static let all: [MapTheme] = [
        theme(
            id: "paper", name: "纸白", isDark: false, showsGrid: true,
            bg: "#FAF8F4", bgBottom: "#F4F1EB", grid: "#E7E1D7",
            rootFill: "#23211E", rootText: "#FBFAF7",
            branchFill: "#F0EBE2", branchText: "#3B3733",
            nodeFill: "#FFFFFF", nodeText: "#3B3733",
            border: "#E5DED2", connector: "#C5BBA9", accent: "#C26A4A"
        ),
        theme(
            id: "midnight", name: "深空", isDark: true, showsGrid: true,
            bg: "#0E0F13", bgBottom: "#12141A", grid: "#22252D",
            rootFill: "#F1F2F6", rootText: "#0E0F13",
            branchFill: "#1E2129", branchText: "#E8E9EF",
            nodeFill: "#191B22", nodeText: "#D9DBE4",
            border: "#2A2E38", connector: "#3E4453", accent: "#7C9CFF"
        ),
        theme(
            id: "morandi", name: "莫兰迪", isDark: false, showsGrid: true,
            bg: "#F1EFEA", bgBottom: "#EAE6DF", grid: "#DDD7CD",
            rootFill: "#6C7A6E", rootText: "#F7F8F5",
            branchFill: "#E5E0D6", branchText: "#3F443D",
            nodeFill: "#FBFAF7", nodeText: "#3F443D",
            border: "#D8D1C5", connector: "#B5AD9F", accent: "#7E8F80"
        ),
        theme(
            id: "corporate", name: "商务蓝", isDark: false, showsGrid: true,
            bg: "#F6F8FC", bgBottom: "#EEF3FA", grid: "#DEE6F1",
            rootFill: "#1E3A5F", rootText: "#FFFFFF",
            branchFill: "#E4EEFA", branchText: "#233A56",
            nodeFill: "#FFFFFF", nodeText: "#2B3A4A",
            border: "#D8E2EE", connector: "#A9BED6", accent: "#2F6FEB"
        ),
        theme(
            id: "blueprint", name: "蓝图", isDark: true, showsGrid: true,
            bg: "#0F2A44", bgBottom: "#0B2238", grid: "#1B3D5C",
            rootFill: "#E9F3FC", rootText: "#0F2A44",
            branchFill: "#173F5F", branchText: "#D9EBFA",
            nodeFill: "#123451", nodeText: "#CFE3F5",
            border: "#2A5478", connector: "#4C7EA3", accent: "#6FB3E0"
        ),
        theme(
            id: "neon", name: "霓虹", isDark: true, showsGrid: false,
            bg: "#0A0A0E", bgBottom: "#0E0E15", grid: "#1C1C26",
            rootFill: "#C8FF4D", rootText: "#0A0A0E",
            branchFill: "#1B1B25", branchText: "#E9E9F2",
            nodeFill: "#14141C", nodeText: "#D7D7E2",
            border: "#2C2C3C", connector: "#4A3D8F", accent: "#C8FF4D"
        ),
        theme(
            id: "sand", name: "暖砂", isDark: false, showsGrid: true,
            bg: "#F7F0E7", bgBottom: "#F1E7DA", grid: "#E6D8C6",
            rootFill: "#8A5A3B", rootText: "#FFF9F2",
            branchFill: "#F0E2D1", branchText: "#4A382B",
            nodeFill: "#FFFCF8", nodeText: "#4A382B",
            border: "#E4D3BF", connector: "#C6AE94", accent: "#C97B4A"
        ),
        theme(
            id: "ink", name: "墨线", isDark: false, showsGrid: false,
            bg: "#F4F4F4", bgBottom: "#EFEFEF", grid: "#E0E0E0",
            rootFill: "#111111", rootText: "#FFFFFF",
            branchFill: "#ECECEC", branchText: "#1A1A1A",
            nodeFill: "#FFFFFF", nodeText: "#2A2A2A",
            border: "#D6D6D6", connector: "#BDBDBD", accent: "#111111"
        )
    ]

    static func byID(_ id: String) -> MapTheme {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    var swiftUIColor: Color { Color(nsColor: accent) }
}
