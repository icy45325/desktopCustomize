# 桌面 IM 多窗口 Demo 方案

## 1. 目标与范围

**验证目标**

- 会话可以在主窗口和独立窗口之间拆出、合并。
- 拆合过程中，草稿、滚动位置、引用回复都不丢。
- 多窗口下，已读和通知的规则正确。

**不做**

真实后端、富文本、音视频通话、跨设备同步。消息由本地 Mock 定时生成。

## 2. 参考方案

| | 微信 4.0 | WhatsApp Mac |
|---|---|---|
| 技术栈 | Qt + C++，Qt 静态链接；Web 内容（公众号、小程序）由独立的 Chromium 进程渲染 | Mac Catalyst，基于 iOS 版代码，使用系统原生 API |
| 窗口模型 | 单进程，多个顶层窗口共享 C++ 核心 | UIScene 场景模型，一个场景对应一个窗口 |
| Demo 借鉴点 | 核心层和数据只有一份，窗口只是 QML 组件的不同实例 | 窗口由"场景值"（会话 ID）驱动，同一个值只对应一个窗口 |

## 3. 技术路线

| 路线 | 对应参考 | 适用 | 结论 |
|---|---|---|---|
| A：SwiftUI（macOS 14+） | WhatsApp | 只验证 Mac 体验 | **先做**，工作量最小，单实例窗口由系统直接提供 |
| B：Qt 6 + QML + C++ | 微信 4.0 | 需要验证跨平台（Win/Mac/Linux） | 第二步做，用于评估正式方案 |

两条路线共用同一套架构和规则（第 4～6 节），只在实现层有差异（第 7、8 节）。

## 4. 架构

```
┌────────────────────────────────────────────────────────┐
│ 视图层   ConversationListView · ChatView（纯视图，无状态） │
├────────────────────────────────────────────────────────┤
│ 容器层   主窗口右侧栏  ·  独立窗口                         │
├────────────────────────────────────────────────────────┤
│ WindowManager   会话→容器映射 · 写入租约 · 布局持久化       │
├──────────────────────────┬─────────────────────────────┤
│ ChatStore                │ UIStateStore                │
│ 会话 · 消息 · 未读        │ 草稿 · 滚动锚点 · 引用        │
├──────────────────────────┴─────────────────────────────┤
│ MockServer   每 3～8 秒随机给某个会话推一条消息              │
└────────────────────────────────────────────────────────┘
```

**原则**：视图不保存业务状态和会话 UI 状态，挂载时从 Store 读取，变化时写回。拆出和合并只是换一个容器渲染同一个会话。

## 5. 数据模型

```
Conversation
  id: String
  title: String
  lastMessageAt: Date
  unreadCount: Int

Message
  id: String
  conversationId: String
  sender: String
  text: String
  sentAt: Date

ConversationUIState            // key = conversationId
  draftText: String
  draftSelection: Range?
  replyToMsgId: String?
  scrollAnchorMsgId: String?
  atBottom: Bool
  unreadDividerMsgId: String?  // 打开会话时确定，之后不变

Placement                      // WindowManager 内部
  conversationId → .main | .detached(windowId) | .none
  leases: conversationId → leaseToken
```

## 6. 交互与规则

### 6.1 打开与单实例

- 同一个会话同一时刻只存在于一个容器中。
- 在会话列表点击某个会话：
  - 如果它已在独立窗口中，前置并聚焦那个窗口，主窗口右侧不变。
  - 否则在主窗口右侧打开。

### 6.2 拆出与合并入口

| 操作 | 入口 |
|---|---|
| 拆出 | 会话右键「在新窗口打开」、双击会话、`⌘⇧O`、把会话拖出主窗口（M4） |
| 合并 | 独立窗口工具栏「合并到主窗口」、`⌘⇧M` |
| 关闭独立窗口 | `⌘W` 或关闭按钮；会话状态保留，Placement 变为 `.none` |

拆出后，主窗口右侧回到空态，并显示「该会话已在独立窗口打开」，点击可以跳过去。

### 6.3 状态迁移（拆出、合并共用）

1. 旧视图 flush：立即写入防抖队列中尚未写回的草稿和滚动锚点。
2. 旧视图释放写入租约。
3. 更新 Placement。
4. 新容器挂载视图，获取租约，从 UIStateStore 恢复状态。

补充规则：

- 输入法组合中（中文尚未上屏）不触发迁移，等组合结束后再执行。
- 不持有租约的写入一律丢弃，防止迁移后迟到的异步回调覆盖新状态。
- 草稿写回防抖 300ms；滚动只在滚动停止后写回。

### 6.4 已读

满足以下全部条件时，才把会话标记为已读：

- 应用处于前台。
- 会话所在窗口是 key 窗口。
- 会话所在窗口未最小化。
- 列表停在底部（`atBottom = true`）。

后台独立窗口收到新消息时只累加未读并显示「新消息」分隔线；窗口变为 key 后再上报已读。未读数统一由 ChatStore 计算，Dock 角标从它读取。

### 6.5 通知

| 会话状态 | 行为 |
|---|---|
| 在 key 窗口中可见 | 不发系统通知 |
| 在后台独立窗口中 | 发通知，点击后前置该独立窗口 |
| 未打开 | 发通知，点击后在主窗口打开 |

### 6.6 快捷键

| 快捷键 | 作用域 | 行为 |
|---|---|---|
| `⌘⇧O` | 主窗口 | 把当前会话拆到新窗口 |
| `⌘⇧M` | 独立窗口 | 合并回主窗口 |
| `⌘W` | 当前窗口 | 主窗口中关闭右侧会话；独立窗口中关闭该窗口 |
| `↩` / `⇧↩` | 输入框 | 发送 / 换行 |

### 6.7 布局持久化

- 退出时保存：独立窗口的会话 ID 列表、各窗口的位置和尺寸、主窗口当前选中的会话。
- 启动时恢复。窗口如果完全不在任何屏幕上，挪到主屏居中。
- 草稿持久化到本地（Demo 用 JSON 文件即可）；滚动位置不跨重启保存。

## 7. 路线 A：SwiftUI 实现

### 7.1 工程结构

```
ChatDemo/
  App/ChatDemoApp.swift
  Core/ChatStore.swift  UIStateStore.swift  WindowManager.swift  MockServer.swift
  Views/MainView.swift  ConversationListView.swift  ChatView.swift  DetachedChatWindow.swift
  Support/WindowAccessor.swift          // 取到 NSWindow，用于定位、最小化检测
```

### 7.2 Scene 定义

`WindowGroup(for:)` 对应 Catalyst 的 UIScene 模型。用同一个值调用 `openWindow(value:)` 时，系统会前置已有窗口，单实例规则不需要自己实现。

```swift
@main
struct ChatDemoApp: App {
    @State private var chat = ChatStore.shared
    @State private var ui = UIStateStore.shared
    @State private var windows = WindowManager.shared

    var body: some Scene {
        WindowGroup("Chat", id: "main") {
            MainView()
                .environment(chat).environment(ui).environment(windows)
        }
        WindowGroup("会话", for: String.self) { $convID in
            if let id = convID {
                DetachedChatWindow(convID: id)
                    .environment(chat).environment(ui).environment(windows)
            }
        }
        .defaultSize(width: 480, height: 640)
    }
}
```

### 7.3 拆出与合并

```swift
@Environment(\.openWindow) private var openWindow
@Environment(\.dismissWindow) private var dismissWindow

func detach(_ id: String) {
    ui.flush(id)
    windows.place(id, .detached)
    openWindow(value: id)
}

func attach(_ id: String) {
    ui.flush(id)
    windows.place(id, .main)
    dismissWindow(value: id)
}
```

在 `DetachedChatWindow` 的 `onDisappear` 中，如果 Placement 仍是 `.detached`，说明是用户手动关闭了窗口，把 Placement 置为 `.none`。

### 7.4 视图与状态绑定

- **Store**：`UIStateStore` 用 `@Observable`，内部是 `[String: ConversationUIState]`。
- **草稿**：`ChatView` 中的 `TextEditor` 绑定到 Store 中的 draft；用 `.onChange` 加防抖写回。
- **滚动**：使用 `.scrollPosition(id:anchor: .top)` 绑定 `scrollAnchorMsgId`。`atBottom` 通过最后一条消息的 `onAppear` / `onDisappear` 维护。
- **已读判断**：

```swift
@Environment(\.controlActiveState) private var activeState   // .key / .active / .inactive
var canMarkRead: Bool {
    NSApp.isActive && activeState == .key && !isMiniaturized && uiState.atBottom
}
```

`isMiniaturized` 通过 `WindowAccessor` 拿到 NSWindow，监听 `NSWindow.didMiniaturizeNotification` 和 `NSWindow.didDeminiaturizeNotification` 维护。

### 7.5 其他

- **拖拽拆出（M4）**：会话行使用 `DragGesture(coordinateSpace: .global)`。松手时用 `NSEvent.mouseLocation` 判断是否在主窗口 frame 之外；如果在外面，执行 `detach`，并在新窗口出现后通过 `WindowAccessor` 调用 `setFrameTopLeftPoint` 把它放到光标位置。
- **通知**：使用 `UNUserNotificationCenter`，`userInfo` 中带上会话 ID，点击回调中交给 WindowManager 路由。
- **布局恢复**：独立窗口的会话 ID 存在 `UserDefaults`，启动时逐个调用 `openWindow(value:)`。不依赖系统的窗口恢复，因为它受用户的「退出时关闭窗口」设置影响。

## 8. 路线 B：Qt 6 + QML 实现

### 8.1 工程结构

```
chat-demo-qt/
  CMakeLists.txt
  src/main.cpp  ChatStore.*  UIStateStore.*  WindowManager.*  MockServer.*
  qml/Main.qml  ConversationList.qml  ChatView.qml  DetachedWindow.qml
```

单进程、单个 `QQmlEngine`。所有窗口共享同一组 C++ 单例 Store，这与微信 4.0 的单进程共享核心思路一致。

### 8.2 C++ 单例

```cpp
class UIStateStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    Q_INVOKABLE QVariantMap state(const QString &convId) const;
    Q_INVOKABLE QString acquireLease(const QString &convId);
    Q_INVOKABLE void releaseLease(const QString &convId, const QString &token);
    Q_INVOKABLE void update(const QString &convId, const QVariantMap &patch, const QString &token);
signals:
    void changed(const QString &convId);
private:
    QHash<QString, QVariantMap> m_states;
    QHash<QString, QString> m_leases;   // token 不匹配时 update 直接丢弃
};

class WindowManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    Q_INVOKABLE void detach(const QString &convId, QPoint globalPos = {});
    Q_INVOKABLE void attach(const QString &convId);
    Q_INVOKABLE QString placementOf(const QString &convId) const;
signals:
    void placementChanged(const QString &convId);
private:
    QHash<QString, QPointer<QQuickWindow>> m_windows;
    QQmlComponent *m_windowComponent = nullptr;   // DetachedWindow.qml
};
```

`detach` 的实现：

- 如果 `m_windows` 中已有该会话的窗口，调用 `raise()` 和 `requestActivate()`。
- 否则用 `m_windowComponent->createWithInitialProperties({{"convId", convId}})` 创建窗口，再 `setPosition(globalPos)`、`show()`。

### 8.3 QML 要点

- **草稿**：`ChatView` 中 `TextArea` 的 `onTextChanged` 重启一个 300ms 的 `Timer`，超时后写回 Store。`Component.onDestruction` 中立即 flush。
- **输入法**：迁移前检查 `TextArea.inputMethodComposing`，为 `true` 时等它变为 `false` 再执行。
- **滚动**：
  - 记录：用 `ListView.indexAt(0, contentY)` 得到锚点消息，`atYEnd` 维护 `atBottom`。
  - 恢复：`positionViewAtIndex(index, ListView.Beginning)`。
- **已读判断**：

```qml
readonly property bool canMarkRead:
    Qt.application.state === Qt.ApplicationActive
    && Window.active
    && Window.visibility !== Window.Minimized
    && listView.atYEnd
```

- **拖拽拆出（M4）**：会话行的 `MouseArea` 在 `onReleased` 中用 `mapToGlobal` 取得全局坐标，判断是否落在 `Window.window` 的几何区域之外；如果在外面，调用 `WindowManager.detach(id, pos)`。
- **通知**：Demo 使用 `QSystemTrayIcon::showMessage`，点击 `messageClicked` 后交给 WindowManager 路由。
- **布局恢复**：用 `QSettings` 保存独立窗口的会话 ID 和 geometry，启动时重建窗口。

## 9. 里程碑

| 阶段 | 内容 | 预估 |
|---|---|---|
| M1 | MockServer、ChatStore、主窗口（列表 + 会话），可收发消息 | 1 天 |
| M2 | UIStateStore、写入租约、「在新窗口打开」、单实例、合并回主窗口 | 2 天 |
| M3 | 已读规则、通知路由、快捷键作用域 | 1 天 |
| M4 | 拖拽拆出、布局持久化与恢复 | 1～2 天 |

路线 A 和 B 分别估算；路线 B 的 M1 需要额外约 1 天搭建工程。

## 10. 验收用例

| # | 操作 | 预期 |
|---|---|---|
| 1 | 在会话 A 输入一半草稿后拆出 | 新窗口中草稿完整，光标位置一致 |
| 2 | 在会话 A 上滚到历史消息后拆出 | 新窗口停在同一条锚点消息 |
| 3 | 设置引用回复后合并回主窗口 | 引用仍在 |
| 4 | 会话 A 已在独立窗口，在列表中再次点击 A | 前置该独立窗口，不新开 |
| 5 | 中文输入法组合中按 `⌘⇧O` | 组合完成后才拆出，不丢字、不重复 |
| 6 | 独立窗口在后台时收到 A 的新消息 | 未读 +1、发系统通知，不自动已读 |
| 7 | 点击 6 中的通知 | 前置 A 的独立窗口，随后标记已读 |
| 8 | A 在 key 窗口可见时收到新消息 | 不发通知，直接已读 |
| 9 | 最小化 A 的独立窗口后收到新消息 | 未读 +1，不已读 |
| 10 | 打开两个独立窗口后退出，再重启 | 两个窗口在原位置恢复，草稿还在 |
| 11 | 断开外接屏后重启 | 原本在外接屏上的窗口挪到主屏 |
| 12 | 在独立窗口按 `⌘W` | 只关闭该窗口；草稿保留，下次打开可恢复 |
