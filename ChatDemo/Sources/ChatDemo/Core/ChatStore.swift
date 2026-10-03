import AppKit
import Observation

@Observable @MainActor
final class ChatStore {
    static let shared = ChatStore()

    private(set) var conversations: [Conversation] = []
    private(set) var messages: [String: [Message]] = [:]

    var sortedConversations: [Conversation] {
        conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// 未读数统一在这里计算，Dock 角标也从这里读。
    var totalUnread: Int { conversations.reduce(0) { $0 + $1.unreadCount } }

    private init() { seed() }

    func conversation(_ id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func messages(of id: String) -> [Message] { messages[id] ?? [] }

    func message(_ id: String, in convID: String) -> Message? {
        messages[convID]?.first { $0.id == id }
    }

    // MARK: - 收发

    func send(_ convID: String, text: String, replyTo: String?) {
        let m = Message(id: UUID().uuidString, conversationId: convID, sender: "我",
                        text: text, sentAt: Date(), isMine: true, replyToMsgId: replyTo)
        append(m)
    }

    /// MockServer 推来的消息。
    func receive(_ m: Message) {
        guard let i = conversations.firstIndex(where: { $0.id == m.conversationId }) else { return }
        let windows = WindowManager.shared
        let ui = UIStateStore.shared
        let id = m.conversationId

        // 决定未读 / 通知必须在追加之前（追加会改变底部标记）。
        let visibleInKeyWindow = windows.isActiveVisible(id)
        let canRead = visibleInKeyWindow && ui.state(id).atBottom

        append(m)

        if !canRead {
            let wasZero = conversations[i].unreadCount == 0
            conversations[i].unreadCount += 1
            if wasZero { ui.setDivider(id, m.id) }
            updateBadge()
        }
        if !visibleInKeyWindow {
            Notifier.shared.notify(title: conversations[i].title, body: "\(m.sender): \(m.text)", convID: id)
        }
    }

    func markRead(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }),
              conversations[i].unreadCount > 0 else { return }
        conversations[i].unreadCount = 0
        updateBadge()
    }

    private func append(_ m: Message) {
        messages[m.conversationId, default: []].append(m)
        if let i = conversations.firstIndex(where: { $0.id == m.conversationId }) {
            conversations[i].lastMessageAt = m.sentAt
        }
    }

    private func updateBadge() {
        let n = totalUnread
        NSApplication.shared.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    // MARK: - 种子数据

    private func seed() {
        let defs: [(String, String, [String])] = [
            ("c1", "产品群", ["小李", "小张", "Amy"]),
            ("c2", "设计评审", ["Bob", "Cindy"]),
            ("c3", "小王", ["小王"]),
            ("c4", "周报小组", ["老陈", "Dora", "Evan"]),
        ]
        let now = Date()
        for (n, def) in defs.enumerated() {
            let (id, title, people) = def
            var list: [Message] = []
            for k in 0..<40 {
                let mine = k % 5 == 4
                list.append(Message(
                    id: "\(id)-seed-\(k)", conversationId: id,
                    sender: mine ? "我" : people[k % people.count],
                    text: "这是第 \(k + 1) 条历史消息：" + String(repeating: "内容", count: 1 + k % 6),
                    sentAt: now.addingTimeInterval(Double(k - 60) * 60 - Double(n) * 10),
                    isMine: mine))
            }
            messages[id] = list
            conversations.append(Conversation(id: id, title: title, lastMessageAt: list.last!.sentAt))
        }
    }
}
