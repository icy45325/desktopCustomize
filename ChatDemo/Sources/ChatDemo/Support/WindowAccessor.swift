import AppKit
import SwiftUI

/// 取到宿主 NSWindow：用于定位、屏幕外检测、最小化检测。
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void = { _ in }
    var onMiniaturizedChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = HostView()
        v.onMove = { [weak c = context.coordinator] w in c?.bind(w) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindow = onWindow
        context.coordinator.onMini = onMiniaturizedChange
    }

    final class HostView: NSView {
        var onMove: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { onMove?(w) }
        }
    }

    final class Coordinator {
        var onWindow: (NSWindow) -> Void = { _ in }
        var onMini: (Bool) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        private weak var window: NSWindow?

        func bind(_ w: NSWindow) {
            guard window !== w else { return }
            unbind()
            window = w
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: w, queue: .main) { [weak self] _ in
                    self?.onMini(true)
                },
                nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: w, queue: .main) { [weak self] _ in
                    self?.onMini(false)
                },
            ]
            DispatchQueue.main.async { [weak self] in
                self?.onMini(w.isMiniaturized)
                self?.onWindow(w)
            }
        }

        private func unbind() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        deinit { unbind() }
    }
}

extension NSWindow {
    /// 窗口完全不在任何屏幕上（例如断开外接屏）→ 挪到主屏居中。
    func ensureOnScreen() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { center() }
    }
}
