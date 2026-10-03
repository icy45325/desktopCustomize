import AppKit
import SwiftUI
import Observation

/// 会话 → 容器 的映射、拆出/合并流程、布局持久化。
@Observable @MainActor
final class WindowManager {
    static let shared = WindowManager()

    private(set) var placements: [String: Placement] = [:]
    /// 主窗口右侧当前显示的会话。
    private(set) var mainSelection: String?
    /// 刚被拆出的会话，主窗口右侧显示「已在独立窗口打开」。
    private(set) var ghost: String?
    /// 处于「key 窗口 + 未最小化」的会话（已读 / 通知判断用）。
    private(set) var activeVisible: Set<String> = []

    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored var dismissWindow: DismissWindowAction?
    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored var pendingOrigin: [String: NSPoint] = [:]
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var terminating = false

    private let detachedKey = "layout.detached"
    private let selectionKey = "layout.mainSelection"

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminating = true }
        }
    }

    func placement(of id: String) -> Placement { placements[id] ?? .closed }
    func isActiveVisible(_ id: String) -> Bool { activeVisible.contains(id) }

    func setActiveVisible(_ id: String, _ v: Bool) {
        if v { activeVisible.insert(id) } else { activeVisible.remove(id) }
    }

    // MARK: - 打开

    /// 会话列表点击。已在独立窗口 → 前置；否则在主窗口右侧打开。
    func select(_ id: String?) {
        guard let id else {
            if let old = mainSelection { release(old) }
            mainSelection = nil
            saveLayout()
            return
        }
        if placement(of: id) == .detached {
            openWindow?(value: id)   // 同值 → 系统前置已有窗口
            return
        }
        if let old = mainSelection, old != id { release(old) }
        mainSelection = id
        ghost = nil
        placements[id] = .main
        saveLayout()
    }

    private func release(_ id: String) {
        UIStateStore.shared.flush(id)
        if placements[id] == .main { placements[id] = .closed }
    }

    // MARK: - 拆出 / 合并

    func detach(_ id: String, at origin: NSPoint? = nil) {
        if placement(of: id) == .detached { openWindow?(value: id); return }
        guard !deferIfComposing({ [weak self] in self?.detach(id, at: origin) }) else { return }
        UIStateStore.shared.flush(id)                      // 1. 旧视图 flush
        placements[id] = .detached                         // 3. 更新 Placement（租约在视图卸载/新视图挂载时交接）
        if mainSelection == id { mainSelection = nil; ghost = id }
        if let origin { pendingOrigin[id] = origin }
        saveLayout()
        openWindow?(value: id)                             // 4. 新容器挂载
    }

    func attach(_ id: String) {
        guard placement(of: id) == .detached else { return }
        guard !deferIfComposing({ [weak self] in self?.attach(id) }) else { return }
        UIStateStore.shared.flush(id)
        if let old = mainSelection, old != id { release(old) }
        placements[id] = .main
        mainSelection = id
        ghost = nil
        saveLayout()
        dismissWindow?(value: id)
        openWindow?(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌘W / 关闭按钮：会话状态保留，Placement 变为 closed。
    func closeDetached(_ id: String) {
        UIStateStore.shared.flush(id)
        placements[id] = .closed
        saveLayout()
        dismissWindow?(value: id)
    }

    /// DetachedChatWindow.onDisappear 调用：仍是 detached 说明是用户直接点了关闭按钮。
    func detachedWindowDisappeared(_ id: String) {
        guard !terminating, placement(of: id) == .detached else { return }
        placements[id] = .closed
        saveLayout()
    }

    /// 系统自行恢复了独立窗口（或启动恢复）时，把 Placement 对齐。
    func adoptDetached(_ id: String) {
        if mainSelection == id { mainSelection = nil }
        if placements[id] != .detached { placements[id] = .detached; saveLayout() }
    }

    /// 通知点击路由。
    func route(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        if placement(of: id) == .detached {
            openWindow?(value: id)
        } else {
            select(id)
            openWindow?(id: "main")
        }
    }

    // MARK: - 输入法组合

    /// 组合中（中文尚未上屏）不迁移，等组合结束后再执行。
    static func isComposing() -> Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private func deferIfComposing(_ retry: @escaping @MainActor () -> Void) -> Bool {
        guard Self.isComposing() else { return false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            retry()
        }
        return true
    }

    // MARK: - 布局持久化

    func saveLayout() {
        guard !terminating else { return }
        let ids = placements.filter { $0.value == .detached }.map(\.key).sorted()
        UserDefaults.standard.set(ids, forKey: detachedKey)
        UserDefaults.standard.set(mainSelection, forKey: selectionKey)
    }

    /// 启动时调用一次。窗口位置/尺寸由 WindowAccessor 里的 frameAutosaveName 负责。
    func restoreLayout() {
        guard !restored else { return }
        restored = true
        let d = UserDefaults.standard
        if let sel = d.string(forKey: selectionKey) { mainSelection = sel; placements[sel] = .main }
        let ids = d.stringArray(forKey: detachedKey) ?? []
        for id in ids { placements[id] = .detached }
        Task { @MainActor in
            for id in ids {
                openWindow?(value: id)
                try? await Task.sleep(for: .milliseconds(150))
            }
            NSApp.windows.first { $0 === mainWindow }?.makeKeyAndOrderFront(nil)
        }
    }
}
