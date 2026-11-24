import QtQuick
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 月视图：5～6 行 × 7 列。每格显示日期 + 尽量多的条目，放不下时「还有 N 项」。
// 单击日期数字 → 日视图；双击空白 → 新建全天活动（macOS）；条目单击 → 详情。
Item {
    id: mv
    objectName: "monthView"
    property var calendarView
    readonly property var anchorDate: calendarView.anchorDate
    readonly property var gridStart: Cal.monthGridStart(anchorDate, CalendarStore.weekStartsMonday)
    // 只需要 5 行时不显示第 6 行
    readonly property int rows: Cal.addDays(gridStart, 35).getMonth() === anchorDate.getMonth() ? 6 : 5
    readonly property var stableStart: Cal.parseIso(gridKey.split("/")[0])   // 同一个月内点选日期不触发 42 个格子重算
    readonly property string gridKey: Cal.iso(gridStart) + "/" + rows
    property var items: []
    property string loadedKey: ""
    property int loadedRev: -1
    function reload() {
        var from = Cal.iso(gridStart), to = Cal.iso(Cal.addDays(gridStart, rows * 7))
        var r = CalendarStore.occurrences(from, to)
        items = CalendarStore.showTodos ? r.concat(CalendarStore.todosInRange(from, to)) : r
        loadedKey = gridKey
        loadedRev = CalendarStore.revision
    }
    function refresh() { if ((visible || loadedRev < 0) && (loadedKey !== gridKey || loadedRev !== CalendarStore.revision)) reload() }
    onVisibleChanged: refresh()
    onGridKeyChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: CalendarStore; function onChanged() { mv.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Repeater {
                model: Cal.weekdayLabels(CalendarStore.weekStartsMonday)
                Text {
                    required property string modelData
                    width: mv.width / 7
                    height: 28
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "周" + modelData
                    font.pixelSize: 11
                    color: Theme.textSecondary
                }
            }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            readonly property real cw: width / 7
            readonly property real ch: height / mv.rows

            Repeater {
                model: mv.rows * 7
                Item {
                    id: cell
                    required property int index
                    readonly property var date: Cal.addDays(mv.stableStart, index)
                    readonly property string dayIso: Cal.iso(date)
                    readonly property bool inMonth: date.getMonth() === mv.anchorDate.getMonth()
                    readonly property bool isToday: Cal.isToday(date)
                    readonly property bool isSel: Cal.sameDay(date, mv.anchorDate)
                    readonly property var list: Cal.itemsForDay(mv.items, dayIso)
                    readonly property int fit: Math.max(0, Math.floor((height - 30) / 21))
                    readonly property int shown: list.length > fit ? Math.max(0, fit - 1) : list.length
                    width: grid.cw
                    height: grid.ch
                    objectName: "monthCell-" + dayIso

                    Rectangle {
                        anchors.fill: parent
                        color: cell.isSel && !cell.isToday ? Theme.accentSoft
                             : (!cell.inMonth ? Theme.weekendBg : (cellMa.containsMouse ? Theme.hover : "transparent"))
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.gridLine }
                    Rectangle { visible: index % 7 !== 0; width: 1; height: parent.height; color: Theme.gridLine }

                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mv.calendarView.anchorDate = cell.date
                        onDoubleClicked: mv.calendarView.createAt(cell.date.getTime(), cell.date.getTime(), true)
                    }

                    // 日期数字（每月 1 号带月份，同 Google）
                    Rectangle {
                        x: 6; y: 5
                        height: 22
                        width: Math.max(22, dayNum.implicitWidth + 10)
                        radius: 11
                        color: cell.isToday ? Theme.accent : (numMa.containsMouse ? Theme.hover : "transparent")
                        Text {
                            id: dayNum
                            anchors.centerIn: parent
                            text: cell.date.getDate() === 1 ? (cell.date.getMonth() + 1) + "月1日" : cell.date.getDate()
                            font.pixelSize: 12
                            font.bold: cell.isToday || cell.date.getDate() === 1
                            color: cell.isToday ? Theme.accentText : (!cell.inMonth ? Theme.textTertiary : (Cal.isWeekend(cell.date) ? Theme.textSecondary : Theme.text))
                        }
                        MouseArea { id: numMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.calendarView.showDay(cell.date) }
                    }

                    Column {
                        x: 3; y: 30
                        width: parent.width - 6
                        spacing: 1
                        Repeater {
                            model: cell.list.slice(0, cell.shown)
                            EventChip {
                                required property var modelData
                                width: parent.width
                                item: modelData
                                showTime: grid.cw > 124
                                opacity: cell.inMonth ? 1 : 0.55
                                onClicked: (it, p) => mv.calendarView.openItem(it, p)
                            }
                        }
                        Text {
                            visible: cell.list.length > cell.shown
                            leftPadding: 6
                            height: 18
                            verticalAlignment: Text.AlignVCenter
                            text: "还有 " + (cell.list.length - cell.shown) + " 项"
                            font.pixelSize: 11; font.bold: true
                            color: moreMa.containsMouse ? Theme.accent : Theme.textSecondary
                            MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.calendarView.showDay(cell.date) }
                        }
                    }
                }
            }
        }
    }
}
