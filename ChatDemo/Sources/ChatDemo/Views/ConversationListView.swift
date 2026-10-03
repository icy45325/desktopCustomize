import AppKit
import SwiftUI

struct ConversationListView: View {
    @Environment(ChatStore.self) private var chat
    @Environment(WindowManager.self) private var windows

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chat.sortedConversations) { conv in
                        row(conv)
                    }
                }
            }
            Divider()
            Text("总未读：\(chat.totalUnread)").font(.caption).foregroundStyle(.secondary).padding(6)
        }
    }

    private func row(_ conv: Conversation) -> some View {
        let placement = windows.placement(of: conv.id)
        let last = chat.messages(of: conv.id).last
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(conv.title).font(.body.weight(.medium))
                    if placement == .detached {
                        Image(systemName: "rectangle.on.rectangle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(last.map { "\($0.sender)：\($0.text)" } ?? "").font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if conv.unreadCount > 0 {
                Text("\(conv.unreadCount)").font(.caption2).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(windows.mainSelection == conv.id ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        // 双击拆出必须写在单击之前，否则双击会被单击吞掉。
        .onTapGesture(count: 2) { windows.detach(conv.id) }
        .onTapGesture { windows.select(conv.id) }
        // 拖出主窗口 → 拆出，并把新窗口放到光标位置（M4）
        .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .global).onEnded { _ in
            let p = NSEvent.mouseLocation
            if let main = windows.mainWindow, !main.frame.contains(p) {
                windows.detach(conv.id, at: p)
            }
        })
        .contextMenu {
            Button("在新窗口打开") { windows.detach(conv.id) }
        }
    }
}
