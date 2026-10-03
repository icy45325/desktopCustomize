import SwiftUI

struct MainView: View {
    @Environment(WindowManager.self) private var windows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            ConversationListView().frame(width: 260)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(WindowAccessor(onWindow: { w in
            windows.mainWindow = w
            w.setFrameAutosaveName("main-window")
            w.ensureOnScreen()
        }))
        .focusedSceneValue(\.mainConv, windows.mainSelection)
        .task {
            windows.openWindow = openWindow
            windows.dismissWindow = dismissWindow
            Notifier.shared.setup()
            MockServer.shared.start()
            windows.restoreLayout()
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = windows.mainSelection {
            ChatView(convID: id, detached: false).id(id)
        } else if let g = windows.ghost, windows.placement(of: g) == .detached {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("该会话已在独立窗口打开").foregroundStyle(.secondary)
                Button("跳转到该窗口") { windows.select(g) }
            }
        } else {
            Text("选择一个会话").foregroundStyle(.secondary)
        }
    }
}
