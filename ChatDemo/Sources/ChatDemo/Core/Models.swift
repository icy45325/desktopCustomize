import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var lastMessageAt: Date
    var unreadCount: Int = 0
}

struct Message: Identifiable, Codable, Hashable {
    let id: String
    let conversationId: String
    let sender: String
    let text: String
    let sentAt: Date
    var isMine: Bool = false
    var replyToMsgId: String? = nil
}

/// 会话级 UI 状态，key = conversationId。视图不持有这些状态，只在挂载时读、变化时写。
struct ConversationUIState: Codable, Equatable {
    var draftText: String = ""
    var replyToMsgId: String? = nil
    var scrollAnchorMsgId: String? = nil
    var atBottom: Bool = true
    /// 打开会话时确定，之后不变；卸载且无未读时清除。
    var unreadDividerMsgId: String? = nil
}

enum Placement: Equatable {
    case main
    case detached
    case closed   // 方案中的 .none
}
