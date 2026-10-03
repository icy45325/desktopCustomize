import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

ApplicationWindow {
    id: win
    width: 900
    height: 640
    minimumWidth: 700
    minimumHeight: 420
    visible: true
    title: "Chat" + (ChatStore.totalUnread > 0 ? " (" + ChatStore.totalUnread + ")" : "")

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
    Shortcut {
        sequence: "Ctrl+Shift+O"
        onActivated: if (WindowManager.mainSelection !== "") WindowManager.detach(WindowManager.mainSelection)
    }
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: WindowManager.mainSelection !== "" ? WindowManager.select("") : win.close()
    }
    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: WindowManager.quitApp()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ConversationList {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
        }
        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: "#d0d0d0" }

        Item {
            id: detail
            Layout.fillWidth: true
            Layout.fillHeight: true

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

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: WindowManager.mainSelection === "" && WindowManager.ghost !== ""
                         && WindowManager.placementOf(WindowManager.ghost) === "detached"
                Label { text: "该会话已在独立窗口打开"; color: "#808080"; anchors.horizontalCenter: parent.horizontalCenter }
                Button { text: "跳转到该窗口"; onClicked: WindowManager.select(WindowManager.ghost) }
            }
            Label {
                anchors.centerIn: parent
                color: "#808080"
                text: "选择一个会话"
                visible: WindowManager.mainSelection === "" && WindowManager.ghost === ""
            }
        }
    }
}
