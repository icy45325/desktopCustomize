# ChatDemo（路线 A：SwiftUI，macOS 14+）

桌面 IM 多窗口 Demo，方案见 [PLAN.md](PLAN.md)。覆盖 M1～M4。

```bash
cd ChatDemo && ./run.sh      # 或在 Xcode 中打开 Package.swift 直接 Run
```

首次运行会请求通知权限（通知只在 `run.sh` 打包出的 .app 中生效）。

## 结构

| 文件 | 职责 |
|---|---|
| `Core/ChatStore.swift` | 会话、消息、未读（Dock 角标）；收到消息时决定「计未读 / 发通知」 |
| `Core/UIStateStore.swift` | 草稿、滚动锚点、引用、未读分隔线；写入租约；草稿 JSON 持久化 |
| `Core/WindowManager.swift` | Placement、拆出/合并流程、输入法组合延迟、布局持久化与恢复、通知路由 |
| `Core/MockServer.swift` | 每 3～8 秒随机推消息；`Notifier` 系统通知 |
| `Views/ChatView.swift` | 主窗口与独立窗口共用的会话视图，挂载时恢复、变化时经租约写回 |
| `Views/ConversationListView.swift` | 列表：单击 / 双击拆出 / 右键 / 拖出主窗口 |
| `Support/WindowAccessor.swift` | 取 NSWindow：最小化检测、屏幕外纠正、frame 自动保存 |

## 与方案的差异

- `Placement.none` 命名为 `.closed`（避免与 `Optional.none` 歧义）。
- 光标位置（`draftSelection`）未保存：SwiftUI `TextEditor` 在 macOS 14 没有 selection 绑定，验收用例 1 中「光标位置一致」需要改为 NSTextView 包装后才能满足。
- 窗口位置/尺寸依赖 `NSWindow.setFrameAutosaveName`，SwiftUI 在个别版本可能覆盖它；若验收用例 10 位置不对，改为自己用 `UserDefaults` 存 frame。
- 底部判断用列表末尾的 1pt 标记的 `onAppear/onDisappear`，新消息到达瞬间可能有一帧抖动。

## 手动验收

按方案第 10 节 12 条逐条走；快捷键：`⌘⇧O` 拆出（主窗口）、`⌘⇧M` 合并（独立窗口）、`⌘W`、`↩`/`⇧↩`。
