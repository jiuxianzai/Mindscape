import SwiftUI

struct HistoryView: View {
    @Bindable var editor: MapEditor
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [SnapshotRecord] = []
    @State private var snapshotName = ""
    @State private var renameTarget: SnapshotRecord?
    @State private var deleteTarget: SnapshotRecord?
    @State private var feedback: String?
    @State private var feedbackIcon = "checkmark.circle.fill"
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            snapshotList
            Divider()
            footer
        }
        .frame(width: 560, height: 470)
        .overlay(alignment: .bottom) {
            if let feedback {
                Label(feedback, systemImage: feedbackIcon)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .padding(.bottom, 58)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: feedback)
        .onAppear(perform: reload)
        .onDisappear {
            feedbackTask?.cancel()
        }
        .alert("删除快照？", isPresented: deleteBinding) {
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
            Button("删除", role: .destructive) {
                deleteSnapshot()
            }
        } message: {
            Text("「\(deleteTarget?.name ?? "快照")」删除后不可恢复。")
        }
        .sheet(item: $renameTarget) { snapshot in
            SnapshotRenameSheet(snapshot: snapshot) { name in
                let success = editor.renameSnapshot(id: snapshot.id, name: name)
                reload()
                showFeedback(success ? "快照已重命名" : "重命名失败", success: success)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("历史版本")
                    .font(.system(size: 15, weight: .semibold))
                Text("恢复前会自动保存当前版本，回滚也可以撤销。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    @ViewBuilder
    private var snapshotList: some View {
        if snapshots.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("还没有历史快照")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("编辑后会自动生成，也可以手动创建。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(snapshots) { snapshot in
                HStack(spacing: 10) {
                    Image(systemName: snapshot.isAuto ? "clock" : "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(snapshot.isAuto ? Color.secondary : Color(nsColor: NSColor(hex: "#C26A4A")))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(snapshot.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            if snapshot.isAuto {
                                Text("自动")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("\(RelativeDate.full(snapshot.createdAt)) · \(snapshot.nodeCount) 个节点")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("恢复") {
                        editor.restore(snapshot: snapshot)
                        dismiss()
                    }
                    .controlSize(.small)

                    Menu {
                        Button("重命名…") {
                            renameTarget = snapshot
                        }
                        Divider()
                        Button("删除…", role: .destructive) {
                            deleteTarget = snapshot
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("快照操作")
                    .accessibilityLabel("快照操作")
                }
                .padding(.vertical, 3)
                .contextMenu {
                    Button("重命名…") {
                        renameTarget = snapshot
                    }
                    Button("删除…", role: .destructive) {
                        deleteTarget = snapshot
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField("快照名称（可选）", text: $snapshotName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Button {
                createSnapshot()
            } label: {
                Label("创建快照", systemImage: "camera")
            }
            Spacer()
            Text("自动快照每 10 分钟一份，最多保留 20 份")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func reload() {
        snapshots = editor.snapshots()
    }

    private func createSnapshot() {
        let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = editor.createSnapshot(name: name.isEmpty ? "手动快照" : name)
        snapshotName = ""
        reload()
        showFeedback(success ? "快照已创建" : "创建快照失败", success: success)
    }

    private func deleteSnapshot() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        let success = editor.deleteSnapshot(id: target.id)
        reload()
        showFeedback(success ? "快照已删除" : "删除失败", success: success)
    }

    private func showFeedback(_ message: String, success: Bool) {
        feedbackTask?.cancel()
        feedbackIcon = success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        feedback = message
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation {
                feedback = nil
            }
        }
    }
}

private struct SnapshotRenameSheet: View {
    let snapshot: SnapshotRecord
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(snapshot: SnapshotRecord, onSave: @escaping (String) -> Void) {
        self.snapshot = snapshot
        self.onSave = onSave
        _name = State(initialValue: snapshot.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名快照")
                .font(.system(size: 15, weight: .semibold))
            TextField("快照名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("只修改快照名称，不影响导图内容。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(trimmedName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
