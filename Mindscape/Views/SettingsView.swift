import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable, Identifiable {
    case general = 0
    case shortcuts = 1
    case about = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcuts: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: SettingsTab

    init(initialTab: Int = 0) {
        _tab = State(initialValue: SettingsTab(rawValue: initialTab) ?? .general)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 780, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mindscape")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Text("设置")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 18)

            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab == item ? appAccent.opacity(0.11) : Color.clear)
                    )
                    .foregroundStyle(tab == item ? appAccent : Color.primary.opacity(0.72))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }

            Spacer()

            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(width: 180)
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch tab {
                case .general:
                    GeneralSettingsContent()
                case .shortcuts:
                    ShortcutSettingsContent(store: app.shortcuts)
                case .about:
                    AboutSettingsContent()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

// MARK: - Shared style

private let appAccent = Color(nsColor: NSColor(hex: "#C26A4A"))

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
            )
    }
}

struct SettingsActionButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary ? appAccent.opacity(configuration.isPressed ? 0.8 : 1) : Color.primary.opacity(configuration.isPressed ? 0.09 : 0.05))
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private func settingsRow<Content: View>(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 12)
        content()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}

// MARK: - General

struct GeneralSettingsContent: View {
    @Environment(AppModel.self) private var app
    @AppStorage("defaultThemeID") private var themeID = MapTheme.defaultThemeID
    @AppStorage("defaultLayout") private var layoutRaw = MapLayout.mindMap.rawValue

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(title: "通用", subtitle: "新建导图、数据存放位置")

            SettingsSection("新建导图") {
                SettingsCard {
                    VStack(spacing: 0) {
                        settingsRow("默认布局", subtitle: "新导图使用的布局") {
                            HStack(spacing: 5) {
                                Image(systemName: MapLayout(rawValue: layoutRaw)?.symbol ?? "square.grid.2x2")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Picker("默认布局", selection: $layoutRaw) {
                                    ForEach(MapLayout.allCases) { layout in
                                        Text(layout.title).tag(layout.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }
                        }
                        Divider().padding(.leading, 12)
                        settingsRow("默认主题", subtitle: "只影响新建导图") {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: MapTheme.byID(themeID).accent))
                                    .frame(width: 8, height: 8)
                                Picker("默认主题", selection: $themeID) {
                                    ForEach(MapTheme.all) { theme in
                                        Text(theme.name).tag(theme.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            SettingsSection("数据目录") {
                SettingsCard {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(appAccent)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
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
                        .padding(12)

                        Divider().padding(.leading, 12)

                        HStack(spacing: 8) {
                            Button {
                                chooseDirectory()
                            } label: {
                                Label("选择目录", systemImage: "folder.badge.gearshape")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(SettingsActionButtonStyle(primary: true))

                            Button {
                                resetDirectory()
                            } label: {
                                Label("恢复默认", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(SettingsActionButtonStyle())
                            .disabled(app.store.directoryURL?.standardizedFileURL == DocumentStore.defaultDirectory.standardizedFileURL)

                            Spacer()

                            Button {
                                if let url = app.store.directoryURL {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label("在 Finder 中打开", systemImage: "arrow.up.forward.square")
                            }
                            .buttonStyle(SettingsActionButtonStyle())
                        }
                        .padding(12)
                    }
                }

                Text("切换目录时会复制当前数据；如果目标目录中已有 Mindscape 数据，会直接打开其中的导图。所有导图都保存在该目录的一个 mindscape.sqlite 文件中。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if app.recentDataDirectories.count > 1 {
                SettingsSection("最近目录") {
                    SettingsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(app.recentDataDirectories.enumerated()), id: \.element) { index, url in
                                recentDirectoryRow(url)
                                if index < app.recentDataDirectories.count - 1 {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }

                    Text("每个目录的导图都存在自己的 mindscape.sqlite 中；切换目录不会删除另一个目录的数据。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("说明") {
                Text("主题只影响画布。窗口和侧栏跟随系统外观；当前导图的主题可以在工具栏或属性面板中切换。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func recentDirectoryRow(_ url: URL) -> some View {
        let current = url.standardizedFileURL == app.store.directoryURL?.standardizedFileURL
        let count = (try? DocumentStore(directory: url).list(includeDeleted: false).count) ?? 0
        return HStack(spacing: 9) {
            Image(systemName: current ? "folder.fill" : "folder")
                .font(.system(size: 12.5))
                .foregroundStyle(appAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(current ? "\(count) 张导图 · 当前目录" : "\(count) 张导图 · 可切换")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if current {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(appAccent)
            } else {
                Button("切换") {
                    if let error = app.switchDataDirectory(to: url, useExisting: true) {
                        errorMessage = error
                    }
                }
                .buttonStyle(SettingsActionButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

struct ShortcutSettingsContent: View {
    @ObservedObject var store: ShortcutStore
    @State private var recording: ShortcutAction?

    private let categories = ["文件", "编辑", "节点", "视图", "历史"]

    var body: some View {
        let conflicts = store.conflictingActions()

        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                SettingsPageHeader(
                    title: "快捷键",
                    subtitle: "点击按钮重新录制，Esc 取消。菜单快捷键至少需要一个修饰键。"
                )
                Spacer()
                Button {
                    store.resetAll()
                } label: {
                    Label("恢复全部默认", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SettingsActionButtonStyle())
            }

            ForEach(categories, id: \.self) { category in
                SettingsSection(category) {
                    SettingsCard {
                        VStack(spacing: 0) {
                            let actions = ShortcutAction.allCases.filter { $0.category == category }
                            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                                ShortcutRow(
                                    action: action,
                                    store: store,
                                    conflicted: conflicts.contains(action),
                                    onRecord: { recording = action }
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)

                                if index < actions.count - 1 {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
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

// MARK: - About

struct AboutSettingsContent: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(title: "关于", subtitle: "本地优先的思维导图")

            HStack(spacing: 14) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mindscape")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("数据只存在本机，不联网、不需要账号。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("存储") {
                SettingsCard {
                    VStack(spacing: 0) {
                        infoRow("数据库", value: app.store.directoryURL?.path ?? "内存模式")
                        Divider().padding(.leading, 12)
                        infoRow("存储方式", value: "SQLite · 完全本地")
                        Divider().padding(.leading, 12)
                        infoRow("网络请求", value: "无")
                    }
                }
            }

            HStack {
                Spacer()
                Text("© 2026 Mindscape")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
