import SwiftUI

struct DetachedChatWindow: View {
    let convID: String

    @Environment(ChatStore.self) private var chat
    @Environment(WindowManager.self) private var windows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ChatView(convID: convID, detached: true)
            .frame(minWidth: 360, minHeight: 360)
            .navigationTitle(chat.conversation(convID)?.title ?? "会话")
            .background(WindowAccessor(onWindow: { w in
                if let p = windows.pendingOrigin.removeValue(forKey: convID) {
                    w.setFrameTopLeftPoint(NSPoint(x: p.x - 40, y: p.y + 20))   // 放到拖出时的光标处
                } else {
                    w.setFrameAutosaveName("conv-\(convID)")                     // 恢复上次位置/尺寸
                }
                w.ensureOnScreen()
            }))
            .focusedSceneValue(\.detachedConv, convID)
            .onAppear {
                // 启动恢复 / 系统自行恢复窗口时，保证 openWindow 可用且 Placement 对齐
                if windows.openWindow == nil { windows.openWindow = openWindow }
                if windows.dismissWindow == nil { windows.dismissWindow = dismissWindow }
                windows.adoptDetached(convID)
            }
            .onDisappear { windows.detachedWindowDisappeared(convID) }
    }
}
