import AppKit
import SwiftUI

struct MapCanvasRepresentable: NSViewRepresentable {
    let editor: MapEditor
    let revision: Int
    let themeID: String
    let bridge: CanvasBridge
    var readOnly = false
    var searchMatches: Set<UUID> = []
    var activeSearchID: UUID?
    var focusDimAlpha: CGFloat = 0.35
    /// 用户在画布上开始点击 / 输入时回调，用于收起新手提示
    var onUserInteraction: (() -> Void)?

    func makeNSView(context: Context) -> MindCanvasView {
        let view = MindCanvasView(frame: .zero)
        view.isReadOnly = readOnly
        view.focusDimAlpha = focusDimAlpha
        view.onUserInteraction = onUserInteraction
        view.attach(editor: editor, theme: MapTheme.byID(themeID))
        view.setSearchResults(searchMatches, active: activeSearchID)
        wire(view)
        return view
    }

    func updateNSView(_ nsView: MindCanvasView, context: Context) {
        _ = revision
        nsView.isReadOnly = readOnly
        nsView.focusDimAlpha = focusDimAlpha
        nsView.onUserInteraction = onUserInteraction
        nsView.attach(editor: editor, theme: MapTheme.byID(themeID))
        nsView.setSearchResults(searchMatches, active: activeSearchID)
        if bridge.canvas !== nsView {
            wire(nsView)
        }
    }

    private func wire(_ view: MindCanvasView) {
        let bridge = self.bridge
        view.onZoomChanged = { [weak bridge] zoom in
            guard let bridge, abs(bridge.zoom - zoom) > 0.0005 else { return }
            bridge.zoom = zoom
        }
        bridge.attachCanvas(view)
    }
}

struct WorkspaceView: View {
    @Bindable var editor: MapEditor
    /// 全局只自动展开一次：有数据的用户首次打开导图、无数据用户首次新建导图时触发
    private let tipsGate = CanvasTipsGate()
    @State private var showHistory = false
    @State private var showInspector = true
    @State private var showExport = false
    @State private var showOutline = false
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchIndex = 0
    @State private var canvasBridge = CanvasBridge()
    @State private var showThemePicker = false
    @State private var showTips = false
    @State private var tipsAutoShowTask: Task<Void, Never>?
    @State private var snapshotToast: String?
    @State private var snapshotToastIcon = "checkmark.circle.fill"
    @State private var snapshotToastTask: Task<Void, Never>?

    private var matches: [UUID] {
        guard showSearch else { return [] }
        return editor.searchMatches(searchText)
    }

    private var activeMatchID: UUID? {
        guard !matches.isEmpty else { return nil }
        return matches[min(searchIndex, matches.count - 1)]
    }

    var body: some View {
        HStack(spacing: 0) {
            if showOutline {
                OutlineView(editor: editor) { id in
                    canvasBridge.revealNode(id)
                }
                .frame(width: 248)
                Divider()
            }
            canvas
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(
                editor: editor,
                onShowHistory: { showHistory = true }
            )
            .inspectorColumnWidth(min: 250, ideal: 286, max: 360)
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showHistory) {
            HistoryView(editor: editor)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(editor: editor)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeShowHistory)) { _ in
            showHistory = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeShowExport)) { _ in
            showExport = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeToggleInspector)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                showInspector.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeFind)) { _ in
            openSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeToggleOutline)) { _ in
            toggleOutline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapePresent)) { _ in
            PresentationWindowController.shared.present(map: editor.map)
        }
        .background(
            InspectorTitlebarToggle()
                .frame(width: 1, height: 1)
        )
        .navigationTitle("")
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeFirstRunPromptsWillPresent)) { _ in
            tipsAutoShowTask?.cancel()
            showTips = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeFirstRunPromptsDidFinish)) { _ in
            guard tipsGate.shouldShow else { return }
            showTips = false
            scheduleTipsAutoShow()
        }
        .overlay(alignment: .bottom) {
            if let snapshotToast {
                Label(snapshotToast, systemImage: snapshotToastIcon)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .padding(.bottom, 62)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: snapshotToast)
        .onReceive(NotificationCenter.default.publisher(for: .mindscapeSnapshotCreated)) { note in
            let success = note.object as? Bool ?? false
            showSnapshotToast(
                success ? "快照已创建" : "创建快照失败",
                success: success
            )
        }
        .onDisappear {
            tipsAutoShowTask?.cancel()
            snapshotToastTask?.cancel()
        }
    }

    private var canvas: some View {
        MapCanvasRepresentable(
            editor: editor,
            revision: editor.revision,
            themeID: editor.theme.id,
            bridge: canvasBridge,
            searchMatches: Set(matches),
            activeSearchID: activeMatchID,
            onUserInteraction: {
                if showTips { showTips = false }
            }
        )
        .background(Color(nsColor: editor.theme.background))
        .overlay(alignment: .top) {
            if showSearch {
                CanvasSearchBar(
                    text: $searchText,
                    matchCount: matches.count,
                    activeIndex: matches.isEmpty ? 0 : min(searchIndex, matches.count - 1),
                    onPrevious: { stepSearch(-1) },
                    onNext: { stepSearch(1) },
                    onClose: closeSearch
                )
                .padding(.top, 14)
            }
        }
        .overlay(alignment: .bottom) {
            CanvasZoomBar(bridge: canvasBridge)
                .padding(.bottom, 16)
        }
        .overlay(alignment: .topLeading) {
            if let id = editor.focusNodeID, let node = editor.map.node(id) {
                focusChip(node)
                    .padding(.top, showSearch ? 54 : 14)
                    .padding(.leading, 14)
            }
        }
        .onChange(of: searchText) { _, _ in
            searchIndex = 0
            revealCurrentMatch()
        }
        .onAppear {
            // 全局只弹一次：有数据的用户打开已有导图、没数据的用户新建导图，
            // 最终都会走到这里，因此不需要再区分是否刚创建。
            guard tipsGate.shouldShow else { return }
            guard !FirstRunPromptCoordinator.shared.isRunning else {
                // 更新 / Agent 的 sheet 还在排队，等它们全部关闭后再展开。
                return
            }
            scheduleTipsAutoShow()
        }
        .onChange(of: showTips) { _, isShowing in
            // 真正展示后再记账；如果锚点没准备好而没弹出来，下次还有机会。
            if isShowing { tipsGate.markShown() }
        }
    }

    private func showSnapshotToast(_ message: String, success: Bool) {
        snapshotToastTask?.cancel()
        snapshotToastIcon = success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        snapshotToast = message
        snapshotToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation {
                snapshotToast = nil
            }
        }
    }

    private func scheduleTipsAutoShow() {
        tipsAutoShowTask?.cancel()
        tipsAutoShowTask = Task { @MainActor in
            // 等工具栏完成布局，也避开刚关闭 sheet 的动画。
            for _ in 0..<8 {
                if !hasAttachedSheet { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  !FirstRunPromptCoordinator.shared.isRunning,
                  tipsGate.shouldShow,
                  !showTips,
                  !hasAttachedSheet else { return }
            showTips = true
        }
    }

    private var hasAttachedSheet: Bool {
        NSApp.windows.contains { $0.isVisible && $0.attachedSheet != nil }
    }

    private func focusChip(_ node: MindNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 10, weight: .semibold))
            Text("专注：\(node.text.isEmpty ? "未命名" : node.text)")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button {
                editor.setFocus(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("退出专注模式")
        }
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func toggleOutline() {
        withAnimation(.easeOut(duration: 0.16)) {
            showOutline.toggle()
        }
        // 侧栏改变画布宽度后重新适配，避免边缘节点被遮住
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            canvasBridge.fitCanvas()
        }
    }

    private func openSearch() {
        if !showSearch {
            showSearch = true
            searchIndex = 0
        }
        revealCurrentMatch()
    }

    private func closeSearch() {
        showSearch = false
        searchText = ""
        searchIndex = 0
    }

    private func stepSearch(_ delta: Int) {
        guard !matches.isEmpty else { return }
        searchIndex = (min(searchIndex, matches.count - 1) + delta + matches.count) % matches.count
        revealCurrentMatch()
    }

    private func revealCurrentMatch() {
        guard showSearch, !matches.isEmpty else { return }
        let index = min(max(searchIndex, 0), matches.count - 1)
        let id = matches[index]
        editor.select(id)
        canvasBridge.revealNode(id)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            TextField("未命名导图", text: Binding(
                get: { editor.map.title },
                set: { editor.setTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13.5, weight: .semibold))
            .frame(width: 200)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if showSearch {
                    closeSearch()
                } else {
                    openSearch()
                }
            } label: {
                Label("查找节点", systemImage: "magnifyingglass")
            }
            .help("图内搜索（⌘F）")

            Button {
                toggleOutline()
            } label: {
                Label("大纲", systemImage: "list.bullet.indent")
            }
            .help("显示 / 隐藏大纲侧栏（⌘⇧O）")

            Button {
                editor.toggleFocus()
            } label: {
                Label("专注模式", systemImage: editor.focusNodeID == nil ? "scope" : "target")
            }
            .help("只聚焦当前分支（⌘⇧F）")

            Button {
                PresentationWindowController.shared.present(map: editor.map)
            } label: {
                Label("演示", systemImage: "play.rectangle")
            }
            .help("进入演示模式（⌘⇧P）")

            Menu {
                ForEach(MapLayout.allCases) { layout in
                    Button {
                        editor.setLayout(layout)
                    } label: {
                        if editor.map.layout == layout {
                            Label(layout.title, systemImage: "checkmark")
                        } else {
                            Label(layout.title, systemImage: layout.symbol)
                        }
                    }
                }
            } label: {
                Label("布局", systemImage: "square.grid.2x2")
            }
            .help("切换布局")

            Button {
                showThemePicker.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(nsColor: editor.theme.accent))
                        .frame(width: 8, height: 8)
                    Text(editor.theme.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(width: 100, height: 24)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("切换主题")
            .accessibilityLabel("切换主题")
            .popover(isPresented: $showThemePicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    ThemePickerGrid(selectedID: editor.map.themeID) { themeID in
                        editor.setTheme(themeID)
                        showThemePicker = false
                    }
                    Text("浅色 / 深色主题分别保存")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(width: 236)
            }

            Button {
                showHistory = true
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
            .help("历史版本")

            Button {
                showExport = true
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出 / 分享")

            Button {
                showTips.toggle()
            } label: {
                Label("操作提示", systemImage: showTips ? "lightbulb.fill" : "lightbulb")
            }
            .help("画布操作提示")
            .accessibilityLabel("画布操作提示")
            .popover(isPresented: $showTips, arrowEdge: .bottom) {
                CanvasTipsPopover(store: ShortcutStore.shared) {
                    showTips = false
                }
            }
        }
    }
}
