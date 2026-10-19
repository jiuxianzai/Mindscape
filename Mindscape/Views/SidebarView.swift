import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @State private var showTrash = false

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header
            scopePicker
            searchField
            documentList
            Divider()
            footer
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 27, height: 27)
            Text("Mindscape")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Menu {
                Button {
                    app.createDocument(template: .blank)
                } label: {
                    Label("空白导图", systemImage: "circle.dashed")
                }
                Divider()
                ForEach(MapTemplate.allCases.filter { $0 != .blank }) { template in
                    Button {
                        app.createDocument(template: template)
                    } label: {
                        Label(template.title, systemImage: template.symbol)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("新建导图")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var scopePicker: some View {
        @Bindable var app = app
        return Picker("范围", selection: $app.scope) {
            ForEach(LibraryScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        @Bindable var app = app
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索导图", text: $app.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if app.visibleDocuments.isEmpty {
                    VStack(spacing: 6) {
                        Text(app.scope == .starred ? "还没有收藏的导图" : "还没有导图")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
                } else {
                    ForEach(app.visibleDocuments) { record in
                        DocumentRow(record: record, selected: record.id == app.selectedDocumentID)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                app.selectDocument(record.id)
                            }
                            .contextMenu {
                                Button(record.starred ? "取消收藏" : "收藏") {
                                    app.toggleStar(record.id)
                                }
                                Button("移到回收站", role: .destructive) {
                                    app.trashDocument(record.id)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                showTrash = true
            } label: {
                Label("回收站", systemImage: "trash")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if !app.trashDocuments.isEmpty {
                Text("\(app.trashDocuments.count)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct DocumentRow: View {
    let record: DocumentRecord
    var selected: Bool = false

    private var theme: MapTheme { MapTheme.byID(record.themeID) }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: theme.branchFill))
                    .frame(width: 27, height: 27)
                Image(systemName: record.layout.symbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.branchText))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if record.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#E6B450")))
                    }
                }
                Text("\(record.nodeCount) 个节点 · \(RelativeDate.short(record.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.13) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color(nsColor: NSColor(hex: "#C26A4A")).opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("回收站")
                        .font(.system(size: 15, weight: .semibold))
                    Text("删除的导图会保留在这里，可随时恢复。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if app.trashDocuments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("回收站是空的")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.trashDocuments) { record in
                        HStack(spacing: 10) {
                            Image(systemName: record.layout.symbol)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("删除于 \(record.deletedAt.map { RelativeDate.short($0) } ?? "—")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复") { app.restoreDocument(record.id) }
                                .controlSize(.small)
                            Button("彻底删除", role: .destructive) {
                                app.deletePermanently(record.id)
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 440)
    }
}
