import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

ApplicationWindow {
    id: win
    width: 1180
    height: 720
    minimumWidth: 800
    minimumHeight: 440
    visible: true
    color: Theme.bgMid
    title: (WindowManager.module === "calendar" ? qsTr("日历") : "Chat") + (ChatStore.totalUnread > 0 ? " (" + ChatStore.totalUnread + ")" : "")
    font.pixelSize: Theme.fontBody

    Component.onCompleted: {
        var g = WindowManager.savedGeometry("main")
        if (g.valid) { x = g.x; y = g.y; width = g.width; height = g.height }
        WindowManager.registerMainWindow(win)
        WindowManager.restoreLayout()
    }
    // 关闭主窗口 = 退出 Demo（避免只剩独立窗口、布局被清掉）
    onClosing: WindowManager.quitApp()

    Timer {
        id: geoTimer
        interval: 300
        onTriggered: if (win.visibility === Window.Windowed) WindowManager.saveGeometry("main", win.x, win.y, win.width, win.height)
    }
    onXChanged: geoTimer.restart()
    onYChanged: geoTimer.restart()
    onWidthChanged: geoTimer.restart()
    onHeightChanged: geoTimer.restart()

    // 快捷键作用域 = 本窗口
    Shortcut { sequence: "Ctrl+Shift+O"; enabled: WindowManager.module === "chat"; onActivated: if (WindowManager.mainSelection !== "") WindowManager.detach(WindowManager.mainSelection) }
    Shortcut { sequence: "Ctrl+1"; onActivated: WindowManager.module = "chat" }
    Shortcut { sequence: "Ctrl+2"; onActivated: WindowManager.module = "calendar" }
    // 动态面板：打开 / 关闭（已拆成独立窗口时 = 合并回来）
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: WindowManager.panelDetached ? WindowManager.attachPanel() : (WindowManager.panelOpen = !WindowManager.panelOpen) }
    Shortcut { sequence: "Ctrl+Shift+D"; onActivated: Theme.toggle() }
    Shortcut { sequence: "Ctrl+W"; onActivated: WindowManager.module === "chat" && WindowManager.mainSelection !== "" ? WindowManager.select("") : win.close() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: WindowManager.quitApp() }

    // 渐变底（方案 C）；dark 下是深空底加两团微光（方案 B）
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.bgTop }
            GradientStop { position: 0.55; color: Theme.bgMid }
            GradientStop { position: 1.0; color: Theme.bgBottom }
        }
        Rectangle {
            visible: Theme.dark
            x: -160; y: parent.height - 260; width: 460; height: 460; radius: 230
            color: Theme.accentSecondary; opacity: 0.08
        }
    }

    // 界面语言：先切 CalUtil 的日期格式，再作为 key 让整棵界面树重建（qsTr 文本、日期格式、选项列表一次性全换掉）。
    // 会话草稿 / 选中状态 / 日历数据都在 C++ Store 里，重建后原样恢复。
    function langKey() { Cal.setLang(Settings.language); return Settings.language }

    Item {
        id: uiHost
        anchors.fill: parent
        Repeater {
            model: [win.langKey()]
            delegate: RowLayout {
                anchors.fill: parent
                spacing: 0

                NavRail { Layout.fillHeight: true; onSettingsRequested: settingsDialog.open() }

                // 模块容器：聊天页常驻（保留会话视图状态）；日历页首次进入时创建，之后常驻
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // 日历页：启动后空闲时异步预加载（分帧创建，不阻塞 UI），切换时只改 visible，几乎零开销
                    Loader {
                        id: calendarLoader
                        objectName: "calendarLoader"
                        anchors.fill: parent
                        asynchronous: true
                        active: false
                        visible: WindowManager.module === "calendar" && status === Loader.Ready
                        sourceComponent: CalendarView {}
                        Component.onCompleted: if (WindowManager.module === "calendar") { asynchronous = false; active = true }
                        Timer { interval: 800; running: !calendarLoader.active; onTriggered: calendarLoader.active = true }
                        Connections {
                            target: WindowManager
                            function onModuleChanged() { if (WindowManager.module === "calendar") calendarLoader.active = true }
                        }
                    }
                    // 预加载未完成时就切过来：显示一个轻量占位
                    Text {
                        anchors.centerIn: parent
                        visible: WindowManager.module === "calendar" && calendarLoader.status !== Loader.Ready
                        text: qsTr("正在打开日历…")
                        color: Theme.textTertiary
                    }

                    RowLayout {
                        id: chatPage
                        anchors.fill: parent
                        spacing: 0
                        visible: WindowManager.module === "chat"

                        ConversationList {
                            Layout.preferredWidth: 294
                            Layout.fillHeight: true
                        }

                        // 会话区：一张大卡片
                        Card {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.margins: 14
                            radius: 20
                            elevation: 1.3

                            Item {
                                id: detail
                                anchors.fill: parent

                                // 用单元素数组做 model：选中会话变化时整个 ChatView 销毁重建（等价于 SwiftUI 的 .id(convId)）
                                Repeater {
                                    model: WindowManager.mainSelection !== "" ? [WindowManager.mainSelection] : []
                                    delegate: ChatView {
                                        required property string modelData
                                        anchors.fill: detail
                                        convId: modelData
                                        detached: false
                                    }
                                }

                                // 空态：已拆出
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 14
                                    readonly property string where: WindowManager.ghost === "" ? "" : (WindowManager.panelConv, WindowManager.placementOf(WindowManager.ghost))   // 读 panelConv 只为在面板会话变化时重算
                                    visible: WindowManager.mainSelection === "" && (where === "detached" || where === "panel")
                                    Text { text: "⧉"; font.pixelSize: 44; color: Theme.accent; opacity: 0.5; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text {
                                        text: (parent.where === "panel" ? qsTr("「%1」已在右侧面板打开") : qsTr("「%1」已在独立窗口打开")).arg(ChatStore.title(WindowManager.ghost))
                                        color: Theme.textSecondary; font.pixelSize: Theme.fontBody
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                    MacButton { text: parent.where === "panel" ? qsTr("移回这里") : qsTr("前往该窗口"); anchors.horizontalCenter: parent.horizontalCenter; onClicked: WindowManager.select(WindowManager.ghost) }
                                }
                                // 空态：未选择
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    visible: WindowManager.mainSelection === "" && WindowManager.ghost === ""
                                    Text { text: "◌"; font.pixelSize: 40; color: Theme.accent; opacity: 0.4; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text { text: qsTr("选择一个会话开始聊天"); color: Theme.textSecondary; anchors.horizontalCenter: parent.horizontalCenter }
                                }
                            }
                        }
                    }
                }

                // 全局动态面板（停靠）。拆成独立窗口时这里卸载，由 PanelWindow 挂载同一个 SidePanel
                Loader {
                    id: dockedPanel
                    objectName: "dockedPanel"
                    Layout.preferredWidth: 288
                    Layout.fillHeight: true
                    visible: active
                    active: WindowManager.panelOpen && !WindowManager.panelDetached
                    sourceComponent: SidePanel {}
                }
            }
        }
    }

    // 设置放在重建的界面树之外：切换语言时对话框保持打开（文字随 retranslate 更新）
    SettingsDialog { id: settingsDialog }
    Shortcut { sequences: [StandardKey.Preferences, "Ctrl+,"]; onActivated: settingsDialog.opened ? settingsDialog.close() : settingsDialog.open() }
    Connections { target: WindowManager; function onSettingsRequested() { settingsDialog.open() } }
}
