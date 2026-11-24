import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 面板里的迷你日历（消息模块中使用）：迷你月历 + 选中日期的活动与待办；点条目 / 「在日历中打开」跳到日历模块。
Item {
    id: pc
    objectName: "panelCalendar"
    property var day: Cal.today()

    readonly property var items: {
        CalendarStore.revision
        var a = Cal.iso(day), b = Cal.iso(Cal.addDays(day, 1))
        var r = CalendarStore.occurrences(a, b)
        return CalendarStore.showTodos ? r.concat(CalendarStore.todosInRange(a, b)) : r
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        MiniMonth {
            Layout.fillWidth: true
            cell: 26
            selected: pc.day
            onPicked: (d) => pc.day = d
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Cal.md(pc.day) + " " + Cal.weekdayName(pc.day) + (Cal.relativeDay(pc.day) ? " · " + Cal.relativeDay(pc.day) : "")
                font.pixelSize: 13; font.bold: true; color: Theme.text
            }
            Text {
                text: "在日历中打开 ›"
                font.pixelSize: 11; color: openMa.containsMouse ? Theme.accent : Theme.textTertiary
                MouseArea {
                    id: openMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { WindowManager.focusCalendar(); CalendarStore.revealRequested(Cal.iso(pc.day)) }
                }
            }
        }

        ListView {
            id: lv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: pc.items
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool todo: modelData.type === "todo"
                width: lv.width
                height: 44
                radius: 10
                color: Cal.alpha(modelData.color, Theme.dark ? 0.22 : 0.12)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    spacing: 8
                    Rectangle { visible: !row.todo; Layout.preferredWidth: 3; Layout.preferredHeight: 28; radius: 1.5; color: row.modelData.color }
                    CheckCircle {
                        visible: row.todo
                        size: 16
                        checked: row.todo && row.modelData.done
                        color: row.modelData.color
                        readOnly: row.modelData.readOnly
                        onToggled: CalendarStore.toggleTodo(row.modelData.uid)
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            width: parent.width
                            text: row.modelData.title
                            font.pixelSize: 12; font.bold: !row.todo
                            font.strikeout: row.todo && row.modelData.done
                            color: Theme.text; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: row.todo ? (row.modelData.dueTime !== "" ? "截止 " + row.modelData.dueTime : "待办")
                                 : row.modelData.allDay || row.modelData.multiDay ? "全天" : Cal.hm(row.modelData.startMs) + " – " + Cal.hm(row.modelData.endMs)
                            font.pixelSize: 10; color: Theme.textSecondary; elide: Text.ElideRight
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: row.todo ? 30 : 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { WindowManager.focusCalendar(); CalendarStore.requestOpen(row.modelData) }
                }
            }
        }
        Text {
            visible: pc.items.length === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 30
            text: "这一天没有安排"
            color: Theme.textSecondary; font.pixelSize: 12
        }
    }
}
