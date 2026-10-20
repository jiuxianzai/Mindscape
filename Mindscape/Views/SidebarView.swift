import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @State private var showTrash = false
    @State private var renamingFolder: FolderRecord?
    @State private var renameText = ""
    @State private var deletingFolder: FolderRecord?

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header
            scopePicker
            searchField
            content
            Divider()
            footer
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .alert("重命名目录", isPresented: renameBinding) {
            TextField("目录名称", text: $renameText)
            Button("保存") {
                if let folder = renamingFolder {
                    app.renameFolder(folder.id, to: renameText)
                }
                renamingFolder = nil
            }
            Button("取消", role: .cancel) {
                renamingFolder = nil
            }
        }
        .alert("删除目录？", isPresented: deleteBinding) {
            Button("删除", role: .destructive) {
                if let folder = deletingFolder {
                    app.deleteFolder(folder.id)
                }
                deletingFolder = nil
            }
            Button("取消", role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            Text("目录中的导图和子目录会移动到上一级，不会删除内容。")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deletingFolder != nil },
            set: { if !$0 { deletingFolder = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 27, height: 27)
            Text("Mindscape")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()

            Button {
                createRootFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("新建目录")

            Menu {
                Button {
                    app.createDocument(template: .blank)
                } label: {
                    Label("新建导图", systemImage: "doc.badge.plus")
                }
                Button {
                    createRootFolder()
                } label: {
                    Label("新建目录", systemImage: "folder.badge.plus")
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                if app.scope == .starred || app.isSearching {
                    flatList
                } else {
                    folderTree
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var flatList: some View {
        if app.visibleDocuments.isEmpty {
            emptyMessage(app.isSearching ? "没有找到匹配的导图" : "还没有收藏的导图")
        } else {
            ForEach(app.visibleDocuments) { record in
                DocumentTreeRow(record: record, depth: 0)
            }
        }
    }

    @ViewBuilder
    private var folderTree: some View {
        if app.rootFolders.isEmpty, app.rootDocuments.isEmpty {
            emptyMessage("还没有导图")
        } else {
            ForEach(app.rootFolders) { folder in
                FolderSubtreeView(
                    folderID: folder.id,
                    depth: 0,
                    onRename: { folder in
                        renamingFolder = folder
                        renameText = folder.name
                    },
                    onDelete: { folder in
                        deletingFolder = folder
                    }
                )
            }
            ForEach(app.rootDocuments) { record in
                DocumentTreeRow(record: record, depth: 0)
            }
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("点击右上角 + 新建")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    // MARK: - Footer

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

    private func createRootFolder() {
        guard let id = app.createFolder(parentID: nil),
              let folder = app.folders.first(where: { $0.id == id }) else { return }
        renamingFolder = folder
        renameText = folder.name
    }
}

// MARK: - Folder subtree

struct FolderSubtreeView: View {
    @Environment(AppModel.self) private var app
    let folderID: UUID
    let depth: Int
    let onRename: (FolderRecord) -> Void
    let onDelete: (FolderRecord) -> Void

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        if let folder = app.folders.first(where: { $0.id == folderID }) {
            folderRow(folder)
            if app.expandedFolders.contains(folderID) {
                ForEach(app.childFolders(of: folderID)) { child in
                    FolderSubtreeView(
                        folderID: child.id,
                        depth: depth + 1,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
                ForEach(app.documents(in: folderID)) { record in
                    DocumentTreeRow(record: record, depth: depth + 1)
                }
            }
        }
    }

    private func folderRow(_ folder: FolderRecord) -> some View {
        FolderRowView(
            folder: folder,
            depth: depth,
            onRename: onRename,
            onDelete: onDelete
        )
    }
}

struct FolderRowView: View {
    @Environment(AppModel.self) private var app
    let folder: FolderRecord
    let depth: Int
    let onRename: (FolderRecord) -> Void
    let onDelete: (FolderRecord) -> Void

    @State private var dropTargeted = false

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        let expanded = app.expandedFolders.contains(folder.id)
        let selected = app.selectedFolderID == folder.id
        let count = app.documentCount(in: folder.id)

        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)

            Image(systemName: expanded ? "folder.fill" : "folder")
                .font(.system(size: 11.5))
                .foregroundStyle(accent.opacity(0.85))

            Text(folder.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8 + CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? accent.opacity(0.07) : (dropTargeted ? accent.opacity(0.14) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(dropTargeted ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            app.toggleFolder(folder.id)
        }
        .contextMenu {
            Button("在此新建导图") {
                app.selectedFolderID = folder.id
                app.createDocument(template: .blank)
            }
            Button("新建子目录") {
                if let id = app.createFolder(parentID: folder.id),
                   let child = app.folders.first(where: { $0.id == id }) {
                    onRename(child)
                }
            }
            Divider()
            Button("重命名") {
                onRename(folder)
            }
            Button("删除目录", role: .destructive) {
                onDelete(folder)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let documentID = UUID(uuidString: value) else { return false }
            app.moveDocument(documentID, to: folder.id)
            app.expandFolder(folder.id)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) {
                dropTargeted = targeted
            }
        }
    }
}

// MARK: - Document row

struct DocumentTreeRow: View {
    @Environment(AppModel.self) private var app
    let record: DocumentRecord
    let depth: Int

    var body: some View {
        DocumentRow(
            record: record,
            selected: record.id == app.selectedDocumentID,
            indent: CGFloat(depth) * 14
        )
        .contentShape(Rectangle())
        .onTapGesture {
            app.selectDocument(record.id)
        }
        .contextMenu {
            Button(record.starred ? "取消收藏" : "收藏") {
                app.toggleStar(record.id)
            }

            Menu("移动到") {
                Button("根目录") {
                    app.moveDocument(record.id, to: nil)
                }
                if !app.folders.isEmpty {
                    Divider()
                    ForEach(app.folders) { folder in
                        Button(app.folderPath(for: folder.id)) {
                            app.moveDocument(record.id, to: folder.id)
                        }
                    }
                }
            }

            Divider()
            Button("移到回收站", role: .destructive) {
                app.trashDocument(record.id)
            }
        }
        .draggable(record.id.uuidString)
    }
}

struct DocumentRow: View {
    let record: DocumentRecord
    var selected: Bool = false
    var indent: CGFloat = 0

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
        .padding(.leading, 8 + indent)
        .padding(.trailing, 8)
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

// MARK: - Trash

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
