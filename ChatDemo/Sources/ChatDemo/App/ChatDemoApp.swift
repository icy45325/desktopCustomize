import SwiftUI

// 快捷键作用域：通过 focusedSceneValue 区分「主窗口」与「独立窗口」。
private struct MainConvKey: FocusedValueKey { typealias Value = String }
private struct DetachedConvKey: FocusedValueKey { typealias Value = String }
extension FocusedValues {
    var mainConv: String? {
        get { self[MainConvKey.self] }
        set { self[MainConvKey.self] = newValue }
    }
    var detachedConv: String? {
        get { self[DetachedConvKey.self] }
        set { self[DetachedConvKey.self] = newValue }
    }
}

struct ChatCommands: Commands {
    @FocusedValue(\.mainConv) private var mainConv
    @FocusedValue(\.detachedConv) private var detachedConv

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("在新窗口打开会话") {
                if let id = mainConv { WindowManager.shared.detach(id) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(mainConv == nil)

            Button("合并到主窗口") {
                if let id = detachedConv { WindowManager.shared.attach(id) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(detachedConv == nil)
        }
        // ⌘W：独立窗口 → 关闭该窗口；主窗口 → 先关闭右侧会话，没有会话时才关窗口
        CommandGroup(replacing: .saveItem) {
            Button("关闭") {
                if let id = detachedConv {
                    WindowManager.shared.closeDetached(id)
                } else if mainConv != nil {
                    WindowManager.shared.select(nil)
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }
}

@main
struct ChatDemoApp: App {
    @State private var chat = ChatStore.shared
    @State private var ui = UIStateStore.shared
    @State private var windows = WindowManager.shared

    var body: some Scene {
        Window("Chat", id: "main") {
            MainView()
                .environment(chat).environment(ui).environment(windows)
        }
        .commands { ChatCommands() }

        // WindowGroup(for:)：同一个值（会话 ID）只对应一个窗口，再次 openWindow 会前置已有窗口。
        WindowGroup("会话", for: String.self) { $convID in
            if let id = convID {
                DetachedChatWindow(convID: id)
                    .environment(chat).environment(ui).environment(windows)
            }
        }
        .defaultSize(width: 480, height: 640)
    }
}
