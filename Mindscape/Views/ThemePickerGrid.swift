import SwiftUI

/// 主题选择网格。
///
/// 之前工具栏用的是菜单式 `Picker`：菜单会记住当前选中项，选到靠后的主题后
/// 再打开，菜单会从选中项附近开始展示，上面的主题看起来像「消失」了。
/// 这里改成固定两列的网格，8 套主题永远完整显示，选中项只加高亮。
struct ThemePickerGrid: View {
    @Environment(\.colorScheme) private var colorScheme

    let selectedID: String
    var onSelect: (String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(MapTheme.all.filter {
                ThemePolicy.allows($0.id, isDark: colorScheme == .dark)
            }) { theme in
                themeButton(theme)
            }
        }
    }

    private func themeButton(_ theme: MapTheme) -> some View {
        let selected = theme.id == selectedID
        return Button {
            onSelect(theme.id)
        } label: {
            HStack(spacing: 7) {
                themePreview(theme)
                Text(theme.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(nsColor: theme.accent))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.09 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: theme.accent).opacity(selected ? 0.55 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func themePreview(_ theme: MapTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: theme.background))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
            Circle()
                .fill(Color(nsColor: theme.accent))
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
    }
}
