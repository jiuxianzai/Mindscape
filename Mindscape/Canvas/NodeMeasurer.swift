import AppKit

enum NodeMeasurer {
    static func font(level: Int) -> NSFont {
        switch level {
        case 0:
            return rounded(size: 19, weight: .semibold)
        case 1:
            return rounded(size: 14.5, weight: .semibold)
        default:
            return NSFont.systemFont(ofSize: 13, weight: .regular)
        }
    }

    static func rounded(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    static func iconSize(level: Int) -> CGFloat {
        switch level {
        case 0: return 19
        case 1: return 15
        default: return 13.5
        }
    }

    static let iconGap: CGFloat = 7

    static func displayText(_ node: MindNode) -> String {
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "新主题" : text
    }

    static func size(for node: MindNode, level: Int) -> CGSize {
        let font = font(level: level)
        let maxWidth: CGFloat = level == 0 ? 260 : 220
        let horizontalPadding: CGFloat = level == 0 ? 34 : 28
        let verticalPadding: CGFloat = level == 0 ? 30 : 22
        let minWidth: CGFloat = level == 0 ? 120 : 74
        let minHeight: CGFloat = level == 0 ? 58 : 40

        let iconWidth = node.icon == nil ? 0 : iconSize(level: level) + iconGap

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = level == 0 ? .center : .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let string = displayText(node)
        let textWidth = max(maxWidth - horizontalPadding - iconWidth, 40)
        let measured = (string as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let width = min(max(ceil(measured.width) + horizontalPadding + iconWidth, minWidth), maxWidth)
        let height = max(ceil(measured.height) + verticalPadding, minHeight)
        return CGSize(width: width, height: height)
    }
}
