import Foundation
import UserNotifications

/// 每 3～8 秒随机给某个会话推一条消息。
@MainActor
final class MockServer {
    static let shared = MockServer()
    private var task: Task<Void, Never>?

    private let lines = ["在吗？", "看下这个方案", "今天下午三点开会", "收到，我来处理",
                         "这个需求有变化", "辛苦了～", "能再确认一下吗", "OK 没问题",
                         "晚点同步一下进度", "我把文档发你了"]

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
                push()
            }
        }
    }

    private func push() {
        let chat = ChatStore.shared
        guard let conv = chat.conversations.randomElement() else { return }
        let m = Message(id: UUID().uuidString, conversationId: conv.id,
                        sender: conv.id == "c3" ? "小王" : ["小李", "小张", "Amy", "Bob"].randomElement()!,
                        text: lines.randomElement()!, sentAt: Date())
        chat.receive(m)
    }
}

/// 系统通知。SwiftPM 裸可执行文件没有 bundle id，此时静默降级（用 run.sh 打包成 .app 即可启用）。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var enabled: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard enabled else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notify(title: String, body: String, convID: String) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["convID": convID]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // 应用在前台但会话不在 key 窗口时，也要展示横幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["convID"] as? String
        Task { @MainActor in
            if let id { WindowManager.shared.route(id) }
            completionHandler()
        }
    }
}
