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
                    selected: yv.calendarView.anchorDate
                    onPicked: (d) => yv.calendarView.showDay(d)
                    onTitleClicked: { yv.calendarView.anchorDate = new Date(yv.year, index, 1); yv.calendarView.setMode("month") }
                }
            }
        }
    }
}
