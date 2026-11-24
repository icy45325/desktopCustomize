import QtQuick
import QtQuick.Controls
import ChatDemo
import "CalUtil.js" as Cal

// 年视图：12 个迷你月历（4 × 3，窄时 3 × 4），有事件的日子带圆点；点日期 → 日视图，点月份 → 月视图。
Item {
    id: yv
    objectName: "yearView"
    property var calendarView
    readonly property int year: calendarView.anchorDate.getFullYear()
    readonly property int cols: width > 760 ? 4 : 3
    // 一次查询全年（含首尾溢出的周），12 个迷你月历共用
    property var busy: ({})
    function reload() {
        var r = CalendarStore.busyDays(Cal.iso(new Date(year - 1, 11, 20)), Cal.iso(new Date(year + 1, 0, 12)))
        var m = {}
        for (var i = 0; i < r.length; ++i) m[r[i]] = true
        busy = m
        loadedYear = year
        loadedRev = CalendarStore.revision
    }
    property int loadedYear: -1
    property int loadedRev: -1
    function refresh() { if ((visible || loadedRev < 0) && (loadedYear !== year || loadedRev !== CalendarStore.revision)) reload() }
    onVisibleChanged: refresh()
    onYearChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: CalendarStore; function onChanged() { yv.refresh() } }

    Flickable {
        anchors.fill: parent
        anchors.margins: 18
        contentHeight: grid.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Grid {
            id: grid
            width: parent.width
            columns: yv.cols
            columnSpacing: 28
            rowSpacing: 22
            Repeater {
                model: 12
                MiniMonth {
                    required property int index
                    width: (grid.width - grid.columnSpacing * (yv.cols - 1)) / yv.cols
                    cell: 26
                    month: new Date(yv.year, index, 1)
                    showNav: false
                    compactTitle: true
                    busySource: yv.busy
                    selected: yv.calendarView.anchorDate
                    onPicked: (d) => yv.calendarView.showDay(d)
                    onTitleClicked: { yv.calendarView.anchorDate = new Date(yv.year, index, 1); yv.calendarView.setMode("month") }
                }
            }
        }
    }
}
