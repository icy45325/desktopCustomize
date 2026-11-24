import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// AI 小助手：对话式查询 / 安排日程与待办。消息记录在 C++ 单例里，切标签、拆窗口都不丢。
Item {
    id: ap
    objectName: "assistantPanel"

    function send() {
        if (input.text.trim() === "") return
        Assistant.send(input.text)
        input.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                width: 26; height: 26; radius: 13
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.accent }
                    GradientStop { position: 1; color: Theme.accentSecondary }
                }
                Text { anchors.centerIn: parent; text: "✦"; color: Theme.accentText; font.pixelSize: 13 }
            }
            Column {
                Layout.fillWidth: true
                Text { text: "日历小助手"; font.pixelSize: 13; font.bold: true; color: Theme.text }
                Text { text: Assistant.thinking ? "正在思考…" : "查日程 · 找空闲 · 建活动 / 待办"; font.pixelSize: 10; color: Theme.textTertiary }
            }
            Text {
                text: "清空"; font.pixelSize: 11
                color: clrMa.containsMouse ? Theme.accent : Theme.textTertiary
                MouseArea { id: clrMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Assistant.clear() }
            }
        }

        ListView {
            id: lv
            objectName: "assistantMessages"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            model: Assistant.messages
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            onCountChanged: Qt.callLater(positionViewAtEnd)
            Component.onCompleted: positionViewAtEnd()

            delegate: Item {
                id: msg
                required property var modelData
                required property int index
                readonly property bool mine: modelData.role === "user"
                width: lv.width
                height: col.implicitHeight

                Column {
                    id: col
                    width: parent.width
                    spacing: 6

                    // 气泡
                    Item {
                        width: parent.width
                        height: bubble.height
                        Rectangle {
                            id: bubble
                            anchors.right: msg.mine ? parent.right : undefined
                            width: Math.min(parent.width * 0.88, bubbleText.implicitWidth + 22)
                            height: bubbleText.implicitHeight + 16
                            radius: 14
                            color: msg.mine ? Theme.accent : Theme.surface
                            Text {
                                id: bubbleText
                                x: 11; y: 8
                                width: Math.min(implicitWidth, msg.width * 0.88 - 22)
                                text: msg.modelData.text
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                lineHeight: 1.15
                                color: msg.mine ? Theme.accentText : Theme.text
                            }
                        }
                    }

                    // 结果卡片（事件 / 待办）
                    Repeater {
                        model: msg.mine ? [] : msg.modelData.items
                        Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool todo: modelData.type === "todo"
                            width: col.width * 0.88
                            height: 38
                            radius: 10
                            color: cardMa.containsMouse ? Theme.hover : Theme.card
                            border.width: 1; border.color: Theme.gridLine
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                spacing: 8
                                Rectangle { visible: !card.todo; Layout.preferredWidth: 3; Layout.preferredHeight: 22; radius: 1.5; color: card.modelData.color }
                                CheckCircle {
                                    visible: card.todo
                                    size: 14
                                    checked: card.todo && CalendarStore.revision >= 0 && CalendarStore.todo(card.modelData.uid).done === true
                                    color: card.modelData.color
                                    readOnly: card.modelData.readOnly
                                    onToggled: CalendarStore.toggleTodo(card.modelData.uid)
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Text { width: parent.width; text: card.modelData.title; font.pixelSize: 12; font.bold: true; color: Theme.text; elide: Text.ElideRight }
                                    Text {
                                        width: parent.width
                                        readonly property var it: card.modelData
                                        text: card.todo ? (it.dueIso !== "" ? "截止 " + Cal.md(Cal.parseIso(it.dueIso)) + (it.dueTime !== "" ? " " + it.dueTime : "") : "无截止日期")
                                                                       : Cal.rangeText(it)
                                        font.pixelSize: 10; color: Theme.textSecondary; elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                anchors.leftMargin: card.todo ? 28 : 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { WindowManager.focusCalendar(); CalendarStore.requestOpen(card.modelData) }
                            }
                        }
                    }

                    // 操作（如「撤销」）
                    MacButton {
                        visible: !msg.mine && msg.modelData.action.label !== undefined
                        enabled: !msg.modelData.done
                        text: msg.modelData.done ? "已撤销" : (msg.modelData.action.label || "")
                        implicitHeight: 26
                        font.pixelSize: 11
                        onClicked: Assistant.runAction(msg.index)
                    }
                }
            }

            footer: Item {
                width: lv.width
                height: Assistant.thinking ? 34 : 0
                Rectangle {
                    visible: Assistant.thinking
                    y: 8; width: 52; height: 26; radius: 13
                    color: Theme.surface
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 6; height: 6; radius: 3; color: Theme.accent
                                SequentialAnimation on opacity {
                                    running: Assistant.thinking; loops: Animation.Infinite
                                    PauseAnimation { duration: index * 150 }
                                    NumberAnimation { to: 0.2; duration: 300 }
                                    NumberAnimation { to: 1; duration: 300 }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 快捷提问
        Flow {
            Layout.fillWidth: true
            visible: Assistant.messages.length <= 3
            spacing: 6
            Repeater {
                model: Assistant.suggestions
                Rectangle {
                    required property string modelData
                    height: 24; width: Math.min(sg.implicitWidth + 16, ap.width)
                    radius: 12
                    color: sgMa.containsMouse ? Theme.accentSoft : Theme.surface
                    Text { id: sg; anchors.centerIn: parent; width: Math.min(implicitWidth, ap.width - 16); elide: Text.ElideRight; text: modelData; font.pixelSize: 11; color: Theme.accent }
                    MouseArea { id: sgMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Assistant.send(modelData) }
                }
            }
        }

        // 输入
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: 20
            color: Theme.input
            border.width: 1
            border.color: input.activeFocus ? Theme.accent : Theme.fieldBorder
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 5
                TextField {
                    id: input
                    objectName: "assistantInput"
                    Layout.fillWidth: true
                    background: null
                    placeholderText: "问问日程，或说「明天3点 评审」"
                    placeholderTextColor: Theme.textTertiary
                    color: Theme.text
                    font.pixelSize: 12
                    onAccepted: ap.send()
                }
                MacButton { circular: true; primary: true; text: "↑"; font.pixelSize: 14; enabled: input.text.trim() !== "" && !Assistant.thinking; onClicked: ap.send() }
            }
        }
    }
}
