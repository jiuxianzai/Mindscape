import SwiftUI

struct IconPickerView: View {
    @Bindable var editor: MapEditor
    let node: MindNode

    @State private var expanded = true
    @State private var query = ""

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 6)

    private var results: [IconChoice] {
        IconCatalog.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("图标")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let icon = node.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                    Button("清除") {
                        editor.setIcon(nil, for: node.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                }
            }

            if expanded {
                searchField

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(results) { choice in
                            iconButton(choice)
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 150)
                .scrollIndicators(.automatic)

                if results.isEmpty {
                    Text("没有匹配的图标，换个关键词试试。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: expanded)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索图标含义，如：目标 / 风险 / 时间", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .frame(height: 18)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func iconButton(_ choice: IconChoice) -> some View {
        let selected = node.icon == choice.symbol
        return Button {
            editor.setIcon(choice.symbol, for: node.id)
        } label: {
            Image(systemName: choice.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? accent : Color.primary.opacity(0.72))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? accent.opacity(0.15) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .help(choice.name)
        .accessibilityLabel(choice.name)
    }
}
