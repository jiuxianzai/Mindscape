import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTab: Int

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("通用").tag(0)
                    Text("快捷键").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if selectedTab == 0 {
                GeneralSettingsView()
            } else {
                ShortcutSettingsView(store: app.shortcuts)
            }
        }
        .frame(width: 680, height: 620)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("defaultThemeID") private var themeID = MapTheme.defaultThemeID
    @AppStorage("defaultLayout") private var layoutRaw = MapLayout.mindMap.rawValue

    @State private var errorMessage: String?

    private let accent = Color(nsColor: NSColor(hex: "#C26A4A"))

    var body: some View {
        Form {
            Section("新建导图") {
                Picker("默认布局", selection: $layoutRaw) {
                    ForEach(MapLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                Picker("默认主题", selection: $themeID) {
                    ForEach(MapTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Text("只影响新建导图；当前导图的主题在工具栏或属性面板中切换。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("数据目录") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accent)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.store.directoryURL?.path ?? "内存模式")
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Text("导图保存在该目录的 mindscape.sqlite 中，完全本地。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Button("选择目录…") {
                        chooseDirectory()
                    }
                    Button("恢复默认") {
                        resetDirectory()
                    }
                    .disabled(app.store.directoryURL?.standardizedFileURL == DocumentStore.defaultDirectory.standardizedFileURL)

                    Spacer()

                    Button("在 Finder 中打开") {
                        if let url = app.store.directoryURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Text("切换目录时会复制当前数据；如果目标目录中已有 Mindscape 数据，会直接打开其中的导图。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                }
                LabeledContent("Mindscape") {
                    Text("本地优先的思维导图")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择存放 Mindscape 数据的文件夹"
        if let current = app.store.directoryURL {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL == app.store.directoryURL?.standardizedFileURL { return }
        let databaseURL = url.appendingPathComponent("mindscape.sqlite")
        let hasExisting = FileManager.default.fileExists(atPath: databaseURL.path)

        if hasExisting {
            let alert = NSAlert()
            alert.messageText = "该目录中已有 Mindscape 数据"
            alert.informativeText = "切换后会打开该目录中的导图。当前目录的数据仍会保留在原处，不会被删除。"
            alert.addButton(withTitle: "使用该目录")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if let error = app.switchDataDirectory(to: url, useExisting: true) {
                errorMessage = error
            }
        } else {
            if let error = app.switchDataDirectory(to: url, useExisting: false) {
                errorMessage = error
            }
        }
    }

    private func resetDirectory() {
        let defaultDirectory = DocumentStore.defaultDirectory
        if defaultDirectory.standardizedFileURL == app.store.directoryURL?.standardizedFileURL { return }
        let hasExisting = FileManager.default.fileExists(
            atPath: defaultDirectory.appendingPathComponent("mindscape.sqlite").path
        )

        let alert = NSAlert()
        alert.messageText = "恢复默认数据目录？"
        alert.informativeText = hasExisting
            ? "将打开默认目录中已有的导图，当前目录的数据仍会保留。"
            : "当前数据会复制到默认目录。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let error = app.resetDataDirectory() {
            errorMessage = error
        }
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    @ObservedObject var store: ShortcutStore
    @State private var recording: ShortcutAction?

    private let categories = ["文件", "编辑", "节点", "视图", "历史"]

    var body: some View {
        let conflicts = store.conflictingActions()

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("快捷键")
                        .font(.system(size: 15, weight: .semibold))
                    Text("点击右侧按钮重新录制，Esc 取消。菜单快捷键至少需要一个 ⌘ / ⌥ / ⌃ 修饰键；节点快捷键只在画布获得焦点时生效。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("恢复全部默认") {
                    store.resetAll()
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .padding(.bottom, 3)

                            ForEach(ShortcutAction.allCases.filter { $0.category == category }) { action in
                                ShortcutRow(
                                    action: action,
                                    store: store,
                                    conflicted: conflicts.contains(action),
                                    onRecord: { recording = action }
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $recording) { action in
            ShortcutRecorderSheet(action: action, store: store)
        }
    }
}

struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore
    let conflicted: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(action.title)
                .font(.system(size: 12))
            if conflicted {
                Text("冲突")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.10), in: Capsule())
            }
            Spacer()

            Button(action: onRecord) {
                Text(store.combo(for: action).display)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                store.reset(action)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isDefault(action) ? Color.secondary.opacity(0.35) : Color.secondary)
            .disabled(store.isDefault(action))
            .help("恢复默认")
        }
        .padding(.vertical, 3)
    }
}

struct ShortcutRecorderSheet: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore
    @Environment(\.dismiss) private var dismiss

    @State private var monitor: Any?
    @State private var message = "请按下新的快捷键（Esc 取消）"
    @State private var isError = false

    var body: some View {
        VStack(spacing: 14) {
            Text(action.title)
                .font(.system(size: 15, weight: .semibold))
            Text(store.combo(for: action).display)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("清除快捷键") {
                    store.clear(action)
                    dismiss()
                }
                .controlSize(.small)
                Button("取消") {
                    dismiss()
                }
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 380, height: 200)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    dismiss()
                    return nil
                }
                guard let combo = KeyCombo(event: event) else { return nil }
                if let error = store.validationError(for: combo, action: action) {
                    message = error
                    isError = true
                    return nil
                }
                store.set(combo, for: action)
                dismiss()
                return nil
            }
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
