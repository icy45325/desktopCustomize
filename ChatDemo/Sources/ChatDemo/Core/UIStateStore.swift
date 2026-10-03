import Foundation
import Observation

/// 会话 UI 状态（草稿、滚动锚点、引用、未读分隔线）+ 写入租约。
/// 租约保证：迁移后旧视图迟到的异步写入会被丢弃。
@Observable @MainActor
final class UIStateStore {
    static let shared = UIStateStore()

    private(set) var states: [String: ConversationUIState] = [:]

    @ObservationIgnored private var leases: [String: String] = [:]
    @ObservationIgnored private var flushers: [String: () -> Void] = [:]

    private struct Persisted: Codable { var draftText: String; var replyToMsgId: String? }
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("drafts.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Persisted].self, from: data) {
            for (id, p) in saved {
                states[id] = ConversationUIState(draftText: p.draftText, replyToMsgId: p.replyToMsgId)
            }
        }
    }

    func state(_ id: String) -> ConversationUIState { states[id] ?? ConversationUIState() }

    // MARK: 租约

    /// 获取租约，同时使上一个持有者的租约失效。
    func acquireLease(_ id: String) -> String {
        let token = UUID().uuidString
        leases[id] = token
        return token
    }

    func releaseLease(_ id: String, token: String?) {
        if leases[id] == token { leases[id] = nil; flushers[id] = nil }
    }

    func registerFlusher(_ id: String, token: String?, _ f: @escaping () -> Void) {
        if leases[id] == token { flushers[id] = f }
    }

    /// 迁移前调用：让旧视图把防抖队列里尚未写回的内容立即写入。
    func flush(_ id: String) { flushers[id]?() }

    /// 无租约（token 不匹配）的写入一律丢弃。
    func update(_ id: String, token: String?, _ mutate: (inout ConversationUIState) -> Void) {
        guard let token, leases[id] == token else { return }
        var s = state(id)
        let before = s
        mutate(&s)
        guard s != before else { return }
        states[id] = s
        if s.draftText != before.draftText || s.replyToMsgId != before.replyToMsgId { persist() }
    }

    /// 由 ChatStore 在新未读到来时写入分隔线，不经过租约。
    func setDivider(_ id: String, _ msgID: String?) {
        var s = state(id)
        s.unreadDividerMsgId = msgID
        states[id] = s
    }

    private func persist() {
        var out: [String: Persisted] = [:]
        for (id, s) in states where !s.draftText.isEmpty || s.replyToMsgId != nil {
            out[id] = Persisted(draftText: s.draftText, replyToMsgId: s.replyToMsgId)
        }
        if let data = try? JSONEncoder().encode(out) { try? data.write(to: fileURL, options: .atomic) }
    }
}
