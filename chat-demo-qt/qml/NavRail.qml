import QtQuick
import QtQuick.Controls
import ChatDemo

// 最左侧模块导航（类似飞书 / Slack 的竖向导航条）：消息、日历。
Item {
    id: rail
    implicitWidth: 66

    component RailButton: Item {
        id: rb
        property string module
        property string label
        property int badge: 0
        property bool badgeDot: false
        default property alias icon: iconBox.data
        readonly property bool active: WindowManager.module === module
        width: rail.width
        height: 62
        objectName: "rail-" + module

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            width: 44; height: 40; radius: 12
            color: rb.active ? Theme.accentSoft : (ma.containsMouse ? Theme.hover : "transparent")
            border.width: rb.active && Theme.dark ? 1 : 0
            border.color: Theme.accentGlow
            Behavior on color { ColorAnimation { duration: 180 } }
            Item { id: iconBox; anchors.centerIn: parent; width: 24; height: 24 }

            Rectangle {
                visible: rb.badge > 0 || rb.badgeDot
                x: parent.width - width / 2 - 4; y: -4
                height: rb.badgeDot && rb.badge === 0 ? 9 : 17
                width: rb.badgeDot && rb.badge === 0 ? 9 : Math.max(17, bt.implicitWidth + 8)
                radius: height / 2
                color: rb.badgeDot && rb.badge === 0 ? Theme.danger : Theme.badge
                border.width: 2; border.color: Theme.bgMid
                Text { id: bt; anchors.centerIn: parent; visible: rb.badge > 0; text: rb.badge > 99 ? "99+" : rb.badge; color: Theme.badgeText; font.pixelSize: 9; font.bold: true }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46
            text: rb.label
            font.pixelSize: 10
            font.bold: rb.active
            color: rb.active ? Theme.accent : Theme.textTertiary
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WindowManager.module = rb.module }
        ToolTip.visible: ma.containsMouse
        ToolTip.delay: 600
        ToolTip.text: rb.label + (rb.module === "chat" ? "（⌘1）" : "（⌘2）")
    }

    Column {
        anchors.top: parent.top
        anchors.topMargin: 16
        width: parent.width
        spacing: 6

        RailButton {
            id: chatBtn
            module: "chat"; label: "消息"; badge: ChatStore.totalUnread
            // 聊天气泡
            Rectangle {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -1
                width: 21; height: 16; radius: 7
                color: "transparent"; border.width: 2
                border.color: chatBtn.active ? Theme.accent : Theme.textSecondary
                Rectangle { x: 3; y: parent.height - 3; width: 6; height: 6; rotation: 45; color: parent.border.color }
                Row {
                    anchors.centerIn: parent; spacing: 3
                    Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: parent.parent.border.color } }
                }
            }
        }
        RailButton {
            id: calBtn
            module: "calendar"; label: "日历"; badgeDot: CalendarStore.openTodoCount > 0
            // 日历图标：顶部色条 + 今天的日期（与 macOS 日历的 Dock 图标同理）
            Rectangle {
                id: calIcon
                readonly property color c: calBtn.active ? Theme.accent : Theme.textSecondary
                anchors.centerIn: parent
                width: 21; height: 20; radius: 4
                color: "transparent"; border.width: 2; border.color: c
                Rectangle { width: parent.width; height: 6; radius: 3; color: calIcon.c }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 5
                    text: new Date().getDate()
                    font.pixelSize: 10; font.bold: true; color: calIcon.c
                }
            }
        }
    }
}
