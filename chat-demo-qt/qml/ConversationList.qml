import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 侧栏：每个会话是一张悬浮卡片（方案 C），选中项轻微漂浮 + 强调色描边；dark 下描边发光（方案 B）。
Item {
    id: sidebar

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        anchors.rightMargin: 0
        spacing: 10

        // 标题 + 主题切换
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 8
            Text {
                text: "消息"
                font.pixelSize: 22
                font.bold: true
                color: Theme.text
                Behavior on color { ColorAnimation { duration: 260 } }
            }
            Item { Layout.fillWidth: true }
            MacButton {
                objectName: "themeToggle"
                circular: true
                text: Theme.dark ? "☀" : "☾"
                font.pixelSize: 15
                ToolTip.visible: hovered
                ToolTip.text: Theme.dark ? "切换到浅色（⌘⇧D）" : "切换到深色（⌘⇧D）"
                onClicked: Theme.toggle()
                // 点一下转一圈
                contentItem: Text {
                    text: parent.text; font: parent.font; color: Theme.accent
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    rotation: Theme.dark ? 360 : 0
                    Behavior on rotation { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                }
            }
        }

        // 搜索胶囊
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 17
            color: Theme.cardMuted
            border.color: Theme.dark ? Theme.cardBorder : "#1F6C5CE7"
            Behavior on color { ColorAnimation { duration: 260 } }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 8
                Text { text: "⌕"; font.pixelSize: 16; color: Theme.textTertiary }
                Text { text: "搜索会话"; font.pixelSize: Theme.fontBody; color: Theme.textTertiary }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ChatStore
            spacing: 8
            rightMargin: 14

            delegate: Item {
                id: del
                required property string convId
                required property string title
                required property string lastText
                required property int unread
                required property string placement
                readonly property bool selected: WindowManager.mainSelection === convId

                width: ListView.view.width - 14
                height: 64

                // 选中项漂浮；hover 上浮
                Card {
                    id: cardBg
                    anchors.fill: parent
                    radius: Theme.radiusCard
                    color: del.selected ? Theme.card : Theme.cardMuted
                    elevation: del.selected ? 1.4 : (ma.containsMouse ? 1.0 : 0.5)
                    borderColor: del.selected ? Theme.accent : Theme.cardBorder
                    borderWidth: del.selected ? 2 : 1
                    shadowColor: del.selected ? Theme.accentGlow : Theme.shadow
                    Behavior on elevation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 260 } }
                    Behavior on borderColor { ColorAnimation { duration: 260 } }

                    transform: Translate { id: lift; y: 0 }
                    SequentialAnimation on y {
                        running: del.selected
                        loops: Animation.Infinite
                        NumberAnimation { to: -2; duration: 1800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine }
                    }
                    Behavior on y { enabled: !del.selected; NumberAnimation { duration: 200 } }
                    states: State { when: ma.containsMouse && !del.selected; PropertyChanges { target: lift; y: -2 } }
                    transitions: Transition { NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11; anchors.rightMargin: 11
                        spacing: 11

                        Avatar { name: del.title; size: 42 }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: del.title
                                    font.pixelSize: Theme.fontBody; font.bold: true
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 260 } }
                                }
                                // 已拆出标签
                                Rectangle {
                                    visible: del.placement === "detached"
                                    radius: 7; implicitHeight: 16
                                    implicitWidth: detachedLabel.implicitWidth + 12
                                    color: Theme.accentSoft
                                    Text {
                                        id: detachedLabel
                                        anchors.centerIn: parent
                                        text: "⧉ 独立窗口"
                                        font.pixelSize: 10; font.bold: true
                                        color: Theme.accent
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: del.lastText
                                elide: Text.ElideRight
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                Behavior on color { ColorAnimation { duration: 260 } }
                            }
                        }

                        // 未读角标：数字变化时弹跳
                        Rectangle {
                            id: badge
                            visible: del.unread > 0
                            radius: 11
                            implicitWidth: Math.max(22, badgeText.implicitWidth + 14)
                            implicitHeight: 22
                            color: Theme.badge
                            Behavior on color { ColorAnimation { duration: 260 } }
                            Rectangle {   // 光晕
                                anchors.fill: parent; anchors.margins: -3; radius: height / 2
                                color: Theme.accentGlow; opacity: 0.6; z: -1
                            }
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: del.unread
                                color: Theme.onBadge
                                font.pixelSize: 11; font.bold: true
                            }
                            property int lastUnread: 0
                            Connections {
                                target: del
                                function onUnreadChanged() {
                                    if (del.unread > badge.lastUnread) pop.restart()
                                    badge.lastUnread = del.unread
                                }
                            }
                            SequentialAnimation {
                                id: pop
                                NumberAnimation { target: badge; property: "scale"; to: 1.35; duration: 120; easing.type: Easing.OutQuad }
                                NumberAnimation { target: badge; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                            }
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

        // 状态行
        RowLayout {
            Layout.leftMargin: 6
            spacing: 6
            Rectangle {
                width: 7; height: 7; radius: 3.5
                color: Theme.online
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Text {
                text: "在线 · " + (ChatStore.totalUnread > 0 ? ChatStore.totalUnread + " 条未读" : "没有未读")
                font.pixelSize: Theme.fontSmall
                color: Theme.textTertiary
            }
        }
    }
}
