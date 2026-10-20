import AppKit
import SwiftUI

/// 把属性面板开关固定在窗口标题栏最右侧。
struct InspectorTitlebarToggle: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = WindowAnchorView(frame: .zero)
        anchor.onWindowChange = { window in
            if let window {
                context.coordinator.install(in: window)
            } else {
                context.coordinator.uninstall()
            }
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        private var accessory: NSTitlebarAccessoryViewController?
        private weak var window: NSWindow?

        func install(in window: NSWindow) {
            guard accessory == nil, self.window !== window else { return }

            let hosting = NSHostingView(rootView: InspectorTitlebarButton())
            hosting.frame = NSRect(x: 0, y: 0, width: 48, height: 28)

            let controller = NSTitlebarAccessoryViewController()
            controller.view = hosting
            controller.layoutAttribute = .trailing
            window.addTitlebarAccessoryViewController(controller)

            accessory = controller
            self.window = window
        }

        func uninstall() {
            if let accessory, let window,
               let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            accessory = nil
            window = nil
        }
    }
}

private final class WindowAnchorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private struct InspectorTitlebarButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .mindscapeToggleInspector, object: nil)
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(hovering ? 0.10 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("显示 / 隐藏属性面板（⌥⌘I）")
        .padding(.horizontal, 10)
    }
}
