import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 侧栏：参考 macOS Messages / Mail —— 浅灰底、选中项蓝底白字、右上角时间
Rectangle {
    color: Theme.sidebarBg

    Text {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16; topMargin: 14 }
        text: "消息"
        font.pixelSize: 22
        font.bold: true
        color: Theme.textPrimary
    }

    ListView {
        id: list
        anchors { top: header.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: footer.top }
        clip: true
        model: ChatStore
        spacing: 2
        leftMargin: 8; rightMargin: 8

        delegate: Rectangle {
            id: del
            required property string convId
            required property string title
            required property string lastText
            required property int unread
            required property string placement
            readonly property bool selected: WindowManager.mainSelection === convId

            width: ListView.view.width - 16
            height: 60
            radius: 8
            color: selected ? Theme.accent : (ma.containsMouse ? Theme.sidebarHover : "transparent")

            // 头像：首字 + 柔和配色
            Rectangle {
                id: avatar
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 40; height: 40; radius: 20
                color: ["#5AC8FA", "#FF9F0A", "#34C759", "#AF52DE", "#FF2D55"][del.convId.charCodeAt(del.convId.length - 1) % 5]
                Text {
                    anchors.centerIn: parent
                    text: del.title.charAt(0)
                    color: "white"; font.pixelSize: 17; font.bold: true
                }
            }

            ColumnLayout {
                anchors { left: avatar.right; leftMargin: 10; right: badgeArea.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: del.title
                        font.pixelSize: Theme.fontBody; font.bold: true
                        color: del.selected ? Theme.textOnAccent : Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: del.placement === "detached"
                        text: "⧉"
                        font.pixelSize: 12
                        color: del.selected ? Theme.textOnAccent : Theme.textSecondary
                        opacity: 0.8
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: del.lastText
                    elide: Text.ElideRight
                    color: del.selected ? Theme.textOnAccent : Theme.textSecondary
                    opacity: del.selected ? 0.9 : 1
                    font.pixelSize: 12
                }
            }

            Item {
                id: badgeArea
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                width: badge.visible ? badge.width : 0
                height: 20
                Rectangle {
                    id: badge
                    visible: del.unread > 0
                    anchors.centerIn: parent
                    color: del.selected ? Theme.textOnAccent : Theme.badge
                    radius: 10
                    width: Math.max(20, badgeText.implicitWidth + 12)
                    height: 20
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: del.unread
                        color: del.selected ? Theme.accent : "white"
                        font.pixelSize: 11; font.bold: true
                    }
                }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property point pressPos
                onPressed: (m) => {
                    pressPos = Qt.point(m.x, m.y)
                    if (m.button === Qt.RightButton) menu.popup()
                }
                onClicked: (m) => { if (m.button === Qt.LeftButton) WindowManager.select(del.convId) }
                onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) WindowManager.detach(del.convId) }
                // 拖出主窗口 → 拆出，并把新窗口放到光标位置（M4）
                onReleased: (m) => {
                    if (m.button !== Qt.LeftButton) return
                    if (Math.hypot(m.x - pressPos.x, m.y - pressPos.y) < 12) return
                    var g = ma.mapToGlobal(m.x, m.y)
                    var w = del.Window.window
                    if (g.x < w.x || g.x > w.x + w.width || g.y < w.y || g.y > w.y + w.height)
                        WindowManager.detachAt(del.convId, g.x, g.y)
                }
            }
            Menu {
                id: menu
                MenuItem { text: "在新窗口打开"; onTriggered: WindowManager.detach(del.convId) }
            }
        }
    }

    Rectangle { anchors { left: parent.left; right: parent.right; bottom: footer.top } height: 1; color: Theme.separatorLight }
    Text {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        padding: 10
        text: ChatStore.totalUnread > 0 ? ChatStore.totalUnread + " 条未读" : "没有未读消息"
        color: Theme.textSecondary
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }
}
