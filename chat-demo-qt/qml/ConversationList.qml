import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

Item {
    ListView {
        id: list
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: footer.top }
        clip: true
        model: ChatStore

        delegate: Rectangle {
            id: del
            required property string convId
            required property string title
            required property string lastText
            required property int unread
            required property string placement

            width: ListView.view.width
            height: 56
            color: WindowManager.mainSelection === convId ? "#302a7fff" : (ma.containsMouse ? "#10000000" : "transparent")

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        spacing: 4
                        Label { text: del.title; font.bold: true }
                        Label { visible: del.placement === "detached"; text: "⧉"; color: "#808080" }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: del.lastText
                        elide: Text.ElideRight
                        color: "#808080"
                        font.pixelSize: 12
                    }
                }
                Rectangle {
                    visible: del.unread > 0
                    color: "#e53935"
                    radius: 9
                    implicitWidth: Math.max(18, badge.implicitWidth + 10)
                    implicitHeight: 18
                    Label { id: badge; anchors.centerIn: parent; text: del.unread; color: "white"; font.pixelSize: 11 }
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

    Rectangle { id: sep; anchors { left: parent.left; right: parent.right; bottom: footer.top } height: 1; color: "#d0d0d0" }
    Label {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        padding: 8
        text: "总未读：" + ChatStore.totalUnread
        color: "#808080"
        font.pixelSize: 12
    }
}
