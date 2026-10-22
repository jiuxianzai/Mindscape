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

    /// SF Symbols 的宽高比并不统一（实测 0.64 ~ 1.78，相差近 3 倍）。
    /// 统一按高度对齐、宽度按符号自身比例分配，图标才不会被拉扁或挤瘦。
    /// 两端各留一个夹取的余量，避免未来某个符号把节点撑得过宽。
    private static let iconAspectRange: ClosedRange<CGFloat> = 0.55...1.8
    private static var iconAspectCache: [String: CGFloat] = [:]

    /// 按「实际绘制时的字号」量宽高比：SF Symbols 在小字号下会切换光学变体，
    /// 用 100pt 量出来的比例和 15pt 画出来的并不完全一致，会差 5~7%。
    static func iconAspect(for symbol: String, pointSize: CGFloat) -> CGFloat {
        let key = "\(symbol)|\(Int((pointSize * 10).rounded()))"
        if let cached = iconAspectCache[key] { return cached }
        var ratio: CGFloat = 1
        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(
               NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
           ),
           configured.size.width > 0,
           configured.size.height > 0 {
            ratio = configured.size.width / configured.size.height
        }
        let clamped = min(max(ratio, iconAspectRange.lowerBound), iconAspectRange.upperBound)
        iconAspectCache[key] = clamped
        return clamped
    }

    static func iconAspect(for symbol: String) -> CGFloat {
        iconAspect(for: symbol, pointSize: iconSize(level: 1))
    }

    /// 图标占的宽度：高度固定为 iconSize，宽度跟随符号自身比例
    static func iconWidth(for node: MindNode, level: Int) -> CGFloat {
        guard let icon = node.icon else { return 0 }
        return iconSize(level: level) * iconAspect(for: icon, pointSize: iconSize(level: level))
    }

    /// 备注圆点的直径和它与文字的间距
    static let noteDotDiameter: CGFloat = 6.5
    static let noteDotGap: CGFloat = 4.5

    static func hasNote(_ node: MindNode) -> Bool {
        !node.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 备注圆点要占的宽度：算进节点尺寸，左右内边距才能对称
    static func noteWidth(for node: MindNode) -> CGFloat {
        hasNote(node) ? noteDotGap + noteDotDiameter : 0
    }

    static func displayText(_ node: MindNode) -> String {
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "新主题") : text
    }

    struct NodeTextLayout {
        var font: NSFont
        var alignment: NSTextAlignment
        var contentWidth: CGFloat
        var textRect: CGRect
        /// 文字块实际占的尺寸（按换行后的结果），用于把备注圆点贴在文字后面
        var measuredSize: CGSize
        var iconRect: CGRect?
        /// 图标占位（宽度随符号比例变化，高度固定）
        var iconBox: CGSize
        var iconGap: CGFloat
    }

    private struct LayoutKey: Hashable {
        let text: String
        let icon: String?
        let hasNote: Bool
        let level: Int
        let width: Int
        let height: Int
    }

    private static var layoutCache: [LayoutKey: NodeTextLayout] = [:]

    /// 画布渲染和就地编辑共用同一份文字布局，保证进入编辑时文字不跳动。
    /// 动画期间每帧都会调用，按内容 + 尺寸缓存，避免重复做文本测量。
    static func textLayout(for node: MindNode, in rect: CGRect, level: Int) -> NodeTextLayout {
        let key = LayoutKey(
            text: displayText(node),
            icon: node.icon,
            hasNote: hasNote(node),
            level: level,
            width: Int((rect.width * 2).rounded()),
            height: Int((rect.height * 2).rounded())
        )
        let base: NodeTextLayout
        if let cached = layoutCache[key] {
            base = cached
        } else {
            base = measureTextLayout(for: node, in: CGRect(origin: .zero, size: rect.size), level: level)
            if layoutCache.count > 800 {
                layoutCache.removeAll(keepingCapacity: true)
            }
            layoutCache[key] = base
        }

        var result = base
        result.textRect.origin.x += rect.minX
        result.textRect.origin.y += rect.minY
        if let iconRect = result.iconRect {
            result.iconRect = iconRect.offsetBy(dx: rect.minX, dy: rect.minY)
        }
        return result
    }

    private static func measureTextLayout(for node: MindNode, in rect: CGRect, level: Int) -> NodeTextLayout {
        let font = font(level: level)
        let horizontalPadding: CGFloat = level == 0 ? 17 : 14
        let box = node.icon == nil
            ? CGSize.zero
            : CGSize(width: iconWidth(for: node, level: level), height: iconSize(level: level))
        let gap = node.icon == nil ? 0 : iconGap
        let note = noteWidth(for: node)
        let contentWidth = max(rect.width - horizontalPadding * 2 - box.width - gap - note, 10)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = level == 0 ? .center : .left

        let string = NSAttributedString(
            string: displayText(node),
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let measured = string.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let groupWidth = box.width + gap + measured.width + note
        let startX = level == 0 ? rect.midX - groupWidth / 2 : rect.minX + horizontalPadding
        let textX = startX + box.width + gap
        let textWidth = level == 0 ? max(measured.width, 10) : contentWidth
        let textRect = CGRect(
            x: textX,
            y: rect.midY - measured.height / 2,
            width: textWidth,
            height: measured.height + 2
        )
        let iconRect = node.icon == nil
            ? nil
            : CGRect(x: startX, y: rect.midY - box.height / 2, width: box.width, height: box.height)

        return NodeTextLayout(
            font: font,
            alignment: paragraph.alignment,
            contentWidth: contentWidth,
            textRect: textRect,
            measuredSize: measured.size,
            iconRect: iconRect,
            iconBox: box,
            iconGap: gap
        )
    }

    static func size(for node: MindNode, level: Int) -> CGSize {
        let font = font(level: level)
        let maxWidth: CGFloat = level == 0 ? 260 : 220
        let horizontalPadding: CGFloat = level == 0 ? 34 : 28
        let verticalPadding: CGFloat = level == 0 ? 30 : 22
        let minWidth: CGFloat = level == 0 ? 120 : 74
        let minHeight: CGFloat = level == 0 ? 58 : 40

        let iconWidth = node.icon == nil ? 0 : iconWidth(for: node, level: level) + iconGap
        let noteWidth = noteWidth(for: node)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = level == 0 ? .center : .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let string = displayText(node)
        let textWidth = max(maxWidth - horizontalPadding - iconWidth - noteWidth, 40)
        let measured = (string as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let width = min(max(ceil(measured.width) + horizontalPadding + iconWidth + noteWidth, minWidth), maxWidth)
        let height = max(ceil(measured.height) + verticalPadding, minHeight)
        return CGSize(width: width, height: height)
    }
}
