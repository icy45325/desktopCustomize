import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

ApplicationWindow {
    id: win
    width: 980
    height: 660
    minimumWidth: 740
    minimumHeight: 440
    visible: true
    color: Theme.bgMid
    title: "Chat" + (ChatStore.totalUnread > 0 ? " (" + ChatStore.totalUnread + ")" : "")
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
    Shortcut { sequence: "Ctrl+Shift+O"; onActivated: if (WindowManager.mainSelection !== "") WindowManager.detach(WindowManager.mainSelection) }
    Shortcut { sequence: "Ctrl+Shift+D"; onActivated: Theme.toggle() }
    Shortcut { sequence: "Ctrl+W"; onActivated: WindowManager.mainSelection !== "" ? WindowManager.select("") : win.close() }
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

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
                    visible: WindowManager.mainSelection === "" && WindowManager.ghost !== ""
                             && WindowManager.placementOf(WindowManager.ghost) === "detached"
                    Text { text: "⧉"; font.pixelSize: 44; color: Theme.accent; opacity: 0.5; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: "「" + ChatStore.title(WindowManager.ghost) + "」已在独立窗口打开"
                        color: Theme.textSecondary; font.pixelSize: Theme.fontBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    MacButton { text: "前往该窗口"; anchors.horizontalCenter: parent.horizontalCenter; onClicked: WindowManager.select(WindowManager.ghost) }
                }
                // 空态：未选择
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: WindowManager.mainSelection === "" && WindowManager.ghost === ""
                    Text { text: "◌"; font.pixelSize: 40; color: Theme.accent; opacity: 0.4; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "选择一个会话开始聊天"; color: Theme.textSecondary; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
    }
}
