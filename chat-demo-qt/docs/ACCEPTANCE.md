# 本地验收清单（Qt 版）

## 0. 环境与构建（macOS）

```bash
brew install qt cmake                       # Qt 6.5+；已装可跳过
git fetch origin claude/repo-review-qewl9h && git checkout claude/repo-review-qewl9h
cd chat-demo-qt
cmake -B build -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build -j
```

Windows / Linux：用 Qt 在线安装器装 6.4+（勾选 Qt Quick、Qt Quick Controls、Qt 5 Compat 不需要），`-DCMAKE_PREFIX_PATH` 指向 `Qt/6.x/<kit>`。

## 1. 自动化（先跑，2 分钟）

```bash
export QT_QPA_PLATFORM=offscreen CHATDEMO_DATA_DIR=$(mktemp -d)
./build/bin/ChatDemo --selftest             # 期望末行 SELFTEST OK (0 failed)
./build/bin/ChatDemo --selftest --phase2    # 期望 SELFTEST OK，验证重启恢复
unset QT_QPA_PLATFORM CHATDEMO_DATA_DIR
```

覆盖：草稿/光标迁移、输入法组合延迟、单实例、租约、后台未读+通知、合并、关闭单窗口、恢复后滚到分隔线、重启恢复。

## 2. 手动（真机，约 15 分钟）

启动：`./build/bin/ChatDemo`（macOS 上也可 `open build/bin/ChatDemo.app` 若有）。MockServer 每 3～8 秒随机推一条消息，等它来就行。

| # | 操作 | 预期 | ✔ |
|---|---|---|---|
| 1 | 点「产品群」，输入「你好 hello」，光标移到中间，右键消息 →「引用回复」，再 ⌘⇧O | 独立窗口里草稿、光标位置、引用都在；主窗口右侧变「已在独立窗口打开」 | |
| 2 | 在主窗口把会话滚到第 10 条附近，⌘⇧O | 独立窗口停在同一条消息上 | |
| 3 | 独立窗口里 ⌘⇧M | 回到主窗口，草稿/光标/引用仍在，独立窗口关闭 | |
| 4 | 会话已在独立窗口时，在列表再次单击它 / 双击它 | 只前置原窗口，不新开 | |
| 5 | 切中文输入法，拼音打到一半（候选框还在）按 ⌘⇧O | 候选框消失、字上屏后才拆出；不丢字、不重复 | |
| 6 | 把独立窗口放到后面（点主窗口），等它收到新消息 | 侧栏角标 +1 并弹跳；系统通知出现；独立窗口不自动已读 | |
| 7 | 点 6 的通知 | 前置该独立窗口；列表自动滚到「N 条新消息 ↓」；到底后已读、角标消失 | |
| 8 | 让某会话在 key 窗口可见并停在底部，等新消息 | 新消息上浮进入，不发通知，不计未读 | |
| 9 | 最小化独立窗口（⌘M），等新消息 | 未读 +1，不已读；恢复窗口后滚到分隔线 | |
| 10 | 拆出两个窗口，挪动位置、改尺寸，⌘Q 退出，重开 | 两个窗口原位恢复；草稿还在；主窗口选中的会话也恢复 | |
| 11 | 把一个独立窗口拖到外接屏，退出，拔掉外接屏，重开 | 该窗口出现在主屏居中 | |
| 12 | 独立窗口 ⌘W | 只关该窗口；侧栏「独立窗口」标签消失；再打开草稿还在 | |
| 13 | 列表里按住会话向右拖出主窗口再松手 | 在光标处弹出独立窗口 | |
| 14 | ⌘⇧D（任意窗口）或侧栏 ☾/☀ | 所有窗口同时切换，颜色渐变过渡，按钮转一圈；重启后保持 | |
| 15 | hover 侧栏卡片 / 按发送 / 等新消息 | 卡片上浮、发送键回弹、新消息上浮进入；选中卡片缓慢漂浮 | |

## 3. 已知与预期不一致（不算 bug）

- 通知点击只能路由到「最近一条通知的会话」（`QSystemTrayIcon` 限制），正式方案换原生通知 API。
- 恢复窗口时若分隔线离底部很近，滚到分隔线即到底 → 立即已读（符合四条件规则）。
- 容器截图用的是 DejaVu 字体，Mac 上会是 SF。

## 4. 反馈

把失败项的编号、操作系统/Qt 版本、以及终端里的输出（QML 报错会打印在终端）贴回来即可。
