import AppKit
import SwiftUI

/// 纯视图：挂载时从 Store 恢复，变化时通过租约写回。主窗口和独立窗口复用同一个实现。
struct ChatView: View {
    let convID: String
    let detached: Bool

    @Environment(ChatStore.self) private var chat
    @Environment(UIStateStore.self) private var ui
    @Environment(WindowManager.self) private var windows
    @Environment(\.controlActiveState) private var activeState

    @State private var token: String?
    @State private var draft = ""
    @State private var anchor: String?
    @State private var restored = false
    @State private var isMiniaturized = false
    @State private var draftTask: Task<Void, Never>?
    @State private var scrollTask: Task<Void, Never>?

    private var state: ConversationUIState { ui.state(convID) }
    private var isActiveVisible: Bool { activeState == .key && !isMiniaturized }
    /// 已读条件：前台 + key 窗口 + 未最小化 + 停在底部。
    private var canMarkRead: Bool { isActiveVisible && state.atBottom }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                Divider()
                messageList(proxy)
                Divider()
                composer(proxy)
            }
            .onAppear { mount(proxy) }
            .onDisappear { unmount() }
        }
        .background(WindowAccessor(onMiniaturizedChange: { isMiniaturized = $0 }))
        .onChange(of: isActiveVisible, initial: true) { _, v in windows.setActiveVisible(convID, v) }
        .onChange(of: canMarkRead, initial: true) { _, v in if v { chat.markRead(convID) } }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack {
            Text(chat.conversation(convID)?.title ?? convID).font(.headline)
            Spacer()
            if detached {
                Button { windows.attach(convID) } label: {
                    Label("合并到主窗口", systemImage: "rectangle.compress.vertical")
                }
            } else {
                Button { windows.detach(convID) } label: {
                    Label("在新窗口打开", systemImage: "rectangle.on.rectangle")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func messageList(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(chat.messages(of: convID)) { m in
                    if m.id == state.unreadDividerMsgId { unreadDivider }
                    bubble(m)
                }
                Color.clear.frame(height: 1).id("bottom")
                    .onAppear { writeUI { $0.atBottom = true } }
                    .onDisappear { writeUI { $0.atBottom = false } }
            }
            .scrollTargetLayout()
            .padding(12)
        }
        .scrollPosition(id: $anchor, anchor: .top)
        .onChange(of: anchor) { _, new in
            guard restored else { return }
            scrollTask?.cancel()
            // 滚动停止后再写回
            scrollTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                writeUI { $0.scrollAnchorMsgId = new }
            }
        }
        .onChange(of: chat.messages(of: convID).count) { _, _ in
            if state.atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var unreadDivider: some View {
        HStack {
            VStack { Divider() }
            Text("新消息").font(.caption).foregroundStyle(.red)
            VStack { Divider() }
        }
    }

    private func bubble(_ m: Message) -> some View {
        HStack {
            if m.isMine { Spacer(minLength: 40) }
            VStack(alignment: m.isMine ? .trailing : .leading, spacing: 2) {
                if !m.isMine { Text(m.sender).font(.caption).foregroundStyle(.secondary) }
                if let rid = m.replyToMsgId, let r = chat.message(rid, in: convID) {
                    Text("↩ \(r.sender)：\(r.text)").font(.caption).lineLimit(1)
                        .padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(m.text).padding(8)
                    .background(m.isMine ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
            if !m.isMine { Spacer(minLength: 40) }
        }
        .id(m.id)
        .contextMenu {
            Button("引用回复") { writeUI { $0.replyToMsgId = m.id } }
        }
    }

    private func composer(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if let rid = state.replyToMsgId, let r = chat.message(rid, in: convID) {
                HStack {
                    Text("引用 \(r.sender)：\(r.text)").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button { writeUI { $0.replyToMsgId = nil } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.top, 6)
            }
            HStack(alignment: .bottom) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(height: 64)
                    .onChange(of: draft) { _, _ in scheduleDraftWrite() }
                    // ↩ 发送，⇧↩ 换行；输入法组合中交给系统（用于确认上屏）。
                    .onKeyPress(.return) { press in
                        if press.modifiers.contains(.shift) || WindowManager.isComposing() { return .ignored }
                        send(proxy)
                        return .handled
                    }
                Button("发送") { send(proxy) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
    }

    // MARK: - 生命周期与状态写回

    private func mount(_ proxy: ScrollViewProxy) {
        let t = ui.acquireLease(convID)
        token = t
        // 打开会话时确定未读分隔线
        let unread = chat.conversation(convID)?.unreadCount ?? 0
        let msgs = chat.messages(of: convID)
        if unread > 0, state.unreadDividerMsgId == nil, msgs.count >= unread {
            ui.setDivider(convID, msgs[msgs.count - unread].id)
        } else if unread == 0 {
            ui.setDivider(convID, nil)
        }
        let s = ui.state(convID)
        draft = s.draftText
        ui.registerFlusher(convID, token: t) { flushNow() }

        // 恢复滚动位置（等一帧让布局就绪）
        DispatchQueue.main.async {
            if s.atBottom || s.scrollAnchorMsgId == nil {
                proxy.scrollTo("bottom", anchor: .bottom)
            } else if let a = s.scrollAnchorMsgId {
                proxy.scrollTo(a, anchor: .top)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                restored = true
            }
        }
    }

    private func unmount() {
        flushNow()
        windows.setActiveVisible(convID, false)
        if (chat.conversation(convID)?.unreadCount ?? 0) == 0 { ui.setDivider(convID, nil) }
        ui.releaseLease(convID, token: token)
        token = nil
    }

    private func writeUI(_ mutate: (inout ConversationUIState) -> Void) {
        ui.update(convID, token: token, mutate)
    }

    private func scheduleDraftWrite() {
        draftTask?.cancel()
        draftTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))   // 防抖 300ms
            guard !Task.isCancelled else { return }
            writeUI { $0.draftText = draft }
        }
    }

    /// 立即写入防抖队列中尚未写回的草稿和滚动锚点。
    private func flushNow() {
        draftTask?.cancel()
        scrollTask?.cancel()
        let d = draft, a = anchor
        let wasRestored = restored
        writeUI {
            $0.draftText = d
            if wasRestored { $0.scrollAnchorMsgId = a }
        }
    }

    private func send(_ proxy: ScrollViewProxy) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.send(convID, text: text, replyTo: state.replyToMsgId)
        draftTask?.cancel()
        draft = ""
        writeUI { $0.draftText = ""; $0.replyToMsgId = nil; $0.atBottom = true }
        DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
