import AppKit
import Observation
import SwiftUI

struct PresentationSlide: Identifiable {
    let nodeID: UUID?
    let title: String
    let subtitle: String

    var id: String { nodeID?.uuidString ?? "overview" }
}

@MainActor
@Observable
final class PresentationModel {
    let editor: MapEditor
    let bridge = CanvasBridge()
    let slides: [PresentationSlide]
    let mapTitle: String
    var index = 0

    init(map: MindMap, store: DocumentStore) {
        editor = MapEditor(map: map, store: store)
        mapTitle = map.title

        var items: [PresentationSlide] = [
            PresentationSlide(
                nodeID: nil,
                title: map.title,
                subtitle: String(format: String(localized: "整张导图 · %lld 个节点"), map.nodes.count)
            )
        ]
        let rootIDs = Set(map.rootIDs)
        for id in map.breadthFirstIDs where !rootIDs.contains(id) {
            guard let node = map.node(id) else { continue }
            let isFirstLevel = node.parentID.map { rootIDs.contains($0) } ?? false
            let hasChildren = !map.children(of: id).isEmpty
            guard isFirstLevel || hasChildren else { continue }
            let count = map.subtreeIDs(of: id).count
            items.append(PresentationSlide(
                nodeID: id,
                title: node.text.isEmpty ? String(localized: "未命名") : node.text,
                subtitle: String(format: String(localized: "%lld 个节点"), count)
            ))
        }
        slides = items
    }

    func applyCurrent() {
        guard slides.indices.contains(index) else { return }
        let slide = slides[index]
        editor.setSelection(slide.nodeID.map { Set([$0]) } ?? [])
        editor.setFocus(slide.nodeID)
        bridge.focusSubtree(slide.nodeID, fit: true)
    }

    func next() {
        guard index + 1 < slides.count else { return }
        index += 1
        applyCurrent()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        applyCurrent()
    }
}

struct PresentationView: View {
    @Bindable var model: PresentationModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black
            MapCanvasRepresentable(
                editor: model.editor,
                revision: model.editor.revision,
                themeID: model.editor.map.themeID,
                bridge: model.bridge,
                readOnly: true,
                activeSearchID: nil,
                focusDimAlpha: 0.08
            )
            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)

            VStack(spacing: 0) {
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
        .onAppear {
            model.applyCurrent()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.mapTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.slides[model.index].title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(model.index + 1) / \(model.slides.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                model.previous()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(PresentationButtonStyle())
            .disabled(model.index == 0)
            .help("上一页")

            Button {
                model.next()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(PresentationButtonStyle())
            .disabled(model.index + 1 >= model.slides.count)
            .help("下一页")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(PresentationButtonStyle())
            .help("退出演示（Esc）")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if !model.slides[model.index].subtitle.isEmpty {
                Text(model.slides[model.index].subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("← → 切换 · Esc 退出 · 空格下一页")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct PresentationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.55 : 0.78))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
    }
}

@MainActor
final class PresentationWindowController {
    static let shared = PresentationWindowController()

    private var window: NSWindow?
    private var monitor: Any?
    private var model: PresentationModel?
    private var store: DocumentStore?

    private init() {}

    func present(map: MindMap) {
        close()
        guard let store = try? DocumentStore(inMemory: true) else { return }
        self.store = store

        let model = PresentationModel(map: map, store: store)
        self.model = model

        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = PresentationWindow(
            contentRect: screen,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(
            rootView: PresentationView(model: model, onClose: { [weak self] in
                self?.close()
            })
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch event.keyCode {
            case 53: // Esc
                self.close()
                return nil
            case 123, 126: // ← / ↑
                self.model?.previous()
                return nil
            case 124, 125, 49, 36: // → / ↓ / Space / Return
                self.model?.next()
                return nil
            default:
                return event
            }
        }

        model.applyCurrent()
    }

    func close() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        window?.orderOut(nil)
        window = nil
        model = nil
        store = nil
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class PresentationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
