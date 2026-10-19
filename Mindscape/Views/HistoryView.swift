import SwiftUI

struct HistoryView: View {
    @Bindable var editor: MapEditor
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [SnapshotRecord] = []
    @State private var snapshotName = ""

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

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
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("快照名称（可选）", text: $snapshotName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button {
                    let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
                    editor.createSnapshot(name: name.isEmpty ? "手动快照" : name)
                    snapshotName = ""
                    reload()
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
        .frame(width: 560, height: 470)
        .onAppear(perform: reload)
    }

    private func reload() {
        snapshots = editor.snapshots()
    }
}
