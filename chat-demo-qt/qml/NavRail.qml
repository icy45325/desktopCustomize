import QtQuick
import QtQuick.Controls
import ChatDemo
import "Icons.js" as Icons

// 最左侧模块导航（类似飞书 / Slack 的竖向导航条）：消息、日历。
Item {
    id: rail
    implicitWidth: 66
    signal settingsRequested()

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
        ToolTip.text: rb.label + (rb.module === "chat" ? qsTr("（⌘1）") : qsTr("（⌘2）"))
    }

    Column {
        anchors.top: parent.top
        anchors.topMargin: 16
        width: parent.width
        spacing: 6

        RailButton {
            id: chatBtn
            module: "chat"; label: qsTr("消息"); badge: ChatStore.totalUnread
            // 聊天气泡（矢量绘制，抗锯齿）：未选中 = 描边，选中 = 实心 + 反色的三个点
            Canvas {
                id: chatIcon
                anchors.centerIn: parent
                width: 24; height: 24
                readonly property color c: chatBtn.active ? Theme.accent : Theme.textSecondary
                readonly property bool filled: chatBtn.active
                readonly property color dotColor: filled ? Theme.accentText : c
                onCChanged: requestPaint()
                onFilledChanged: requestPaint()
                onDotColorChanged: requestPaint()
                onPaint: Icons.chatBubble(getContext("2d"), c, dotColor, filled)
            }
        }
        RailButton {
            id: calBtn
            module: "calendar"; label: qsTr("日历"); badgeDot: CalendarStore.openTodoCount > 0
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

    // 底部：设置（⌘,）
    Item {
        objectName: "railSettings"
        anchors.bottom: panelToggle.top
        anchors.bottomMargin: 4
        width: parent.width
        height: 40
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 36; radius: 11
            color: gearMa.containsMouse ? Theme.hover : "transparent"
            Text {
                anchors.centerIn: parent
                text: "⚙"
                font.pixelSize: 19
                color: gearMa.containsMouse ? Theme.accent : Theme.textSecondary
                rotation: gearMa.containsMouse ? 45 : 0
                Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { id: gearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rail.settingsRequested() }
        ToolTip.visible: gearMa.containsMouse
        ToolTip.delay: 500
        ToolTip.text: qsTr("设置（⌘,）")
    }

    // 底部：全局动态面板开关（⌘⇧P）
    Item {
        id: panelToggle
        objectName: "railPanelToggle"
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: parent.width
        height: 40
        readonly property bool on: WindowManager.panelOpen
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 36; radius: 11
            color: panelMa.containsMouse ? Theme.hover : "transparent"
            // 「侧边栏」图标：外框 + 右侧一栏，打开时右栏填充
            Rectangle {
                anchors.centerIn: parent
                width: 20; height: 16; radius: 4
                color: "transparent"
                border.width: 1.8
                border.color: parent.parent.on ? Theme.accent : Theme.textSecondary
                Rectangle {
                    x: parent.width - width - 3; y: 3
                    width: 5; height: parent.height - 6; radius: 1.5
                    color: parent.border.color
                    opacity: parent.parent.parent.on ? 1 : 0.45
                }
            }
        }
        MouseArea {
            id: panelMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: WindowManager.panelDetached ? WindowManager.attachPanel() : (WindowManager.panelOpen = !WindowManager.panelOpen)
        }
        ToolTip.visible: panelMa.containsMouse
        ToolTip.delay: 500
        ToolTip.text: (WindowManager.panelDetached ? qsTr("面板已在独立窗口，点击合并回来") : WindowManager.panelOpen ? qsTr("隐藏动态面板") : qsTr("显示动态面板")) + qsTr("（⌘⇧P）")
    }
}
