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
    // 显示哪几列（隐藏周末时 5 列）；key 里带上列和回历设置，变化时才重建 / 重载
    readonly property string colsKey: Cal.weekColumns(CalendarStore.weekStartsMonday, CalendarStore.showWeekends, CalendarStore.weekendDays).join(",")
    readonly property var cols: colsKey.split(",").map(function (c) { return +c })
    readonly property string gridKey: Cal.iso(gridStart) + "/" + rows + "/" + colsKey + "/" + (CalendarStore.showHijri ? CalendarStore.hijriAdjust : "x")
    property var hijri: []                  // 整个 rows × 7 网格的回历日期（关闭时为空）
    property var items: []
    property string loadedKey: ""
    property int loadedRev: -1
    function reload() {
        var from = Cal.iso(gridStart), to = Cal.iso(Cal.addDays(gridStart, rows * 7))
        var r = CalendarStore.occurrences(from, to)
        items = CalendarStore.showTodos ? r.concat(CalendarStore.todosInRange(from, to)) : r
        hijri = CalendarStore.showHijri ? CalendarStore.hijriRange(from, rows * 7) : []
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
                model: { var all = Cal.weekdayLabels(CalendarStore.weekStartsMonday); return mv.cols.map(function (c) { return all[c] }) }
                Text {
                    required property string modelData
                    width: mv.width / mv.cols.length
                    height: 28
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    font.pixelSize: 11
                    color: Theme.textSecondary
                }
            }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: mv.cols.length
            readonly property real cw: width / mv.cols.length
            readonly property real ch: height / mv.rows

            Repeater {
                model: mv.rows * mv.cols.length
                Item {
                    id: cell
                    required property int index
                    // 第 row 行第 col 列 → 网格起点之后的第 row*7 + cols[col] 天
                    readonly property int offset: Math.floor(index / mv.cols.length) * 7 + mv.cols[index % mv.cols.length]
                    readonly property var date: Cal.addDays(mv.stableStart, offset)
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
                    Rectangle { visible: index % mv.cols.length !== 0; width: 1; height: parent.height; color: Theme.gridLine }

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
                            text: cell.date.getDate() === 1 ? Cal.md(cell.date) : cell.date.getDate()
                            font.pixelSize: 12
                            font.bold: cell.isToday || cell.date.getDate() === 1
                            color: cell.isToday ? Theme.accentText : (!cell.inMonth ? Theme.textTertiary : (Cal.isWeekend(cell.date, CalendarStore.weekendDays) ? Theme.textSecondary : Theme.text))
                        }
                        MouseArea { id: numMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mv.calendarView.showDay(cell.date) }
                    }
                    // 回历日期（右上角；回历每月 1 日带月份并用强调色）
                    Text {
                        readonly property var h: mv.hijri[cell.offset] || null   // 换月瞬间数组可能还是旧的长度
                        visible: h !== null
                        anchors.right: parent.right; anchors.rightMargin: 7
                        y: 9
                        width: Math.min(implicitWidth, parent.width - 40)
                        elide: Text.ElideRight
                        text: h ? h.label : ""
                        font.pixelSize: 10
                        font.bold: h !== null && h.first
                        color: h && h.first ? Theme.accent : Theme.textTertiary
                        opacity: cell.inMonth ? 1 : 0.6
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
                            text: qsTr("还有 %n 项", "", cell.list.length - cell.shown)
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
