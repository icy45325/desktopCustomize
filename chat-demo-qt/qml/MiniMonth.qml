import QtQuick
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 迷你月历：侧栏导航、年视图、日期选择器共用。
// 今天 = 强调色实心圆；选中 = 淡色圆；有事件的日子底部一个小点（showBusy）。
Item {
    id: mm
    property var month: Cal.today()          // 显示的月份（任意一天）
    property var selected: null               // 选中的日期
    property var rangeStart: null             // 高亮范围（周视图时高亮整周）
    property var rangeEnd: null
    property bool showHeader: true
    property bool showNav: true
    property bool showBusy: true
    property bool compactTitle: false
    property int cell: 28
    signal picked(var date)
    signal titleClicked()

    readonly property var gridStart: Cal.monthGridStart(month, CalendarStore.weekStartsMonday)
    property var busySource: null             // 外部批量算好的忙碌日（年视图一次算全年，避免 12 次查询）
    readonly property var busy: {
        if (busySource !== null) return busySource
        CalendarStore.revision
        if (!showBusy) return ({})
        var r = CalendarStore.busyDays(Cal.iso(gridStart), Cal.iso(Cal.addDays(gridStart, 42)))
        var m = {}
        for (var i = 0; i < r.length; ++i) m[r[i]] = true
        return m
    }

    implicitWidth: cell * 7
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 2

        RowLayout {
            visible: mm.showHeader
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            Text {
                Layout.fillWidth: true
                leftPadding: 4
                text: mm.compactTitle ? (mm.month.getMonth() + 1) + "月" : mm.month.getFullYear() + "年" + (mm.month.getMonth() + 1) + "月"
                font.pixelSize: mm.compactTitle ? 14 : 13
                font.bold: true
                color: mm.compactTitle && Cal.sameMonth(mm.month, new Date()) ? Theme.accent : Theme.text
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mm.titleClicked() }
            }
            Repeater {
                model: mm.showNav ? ["‹", "›"] : []
                Text {
                    required property string modelData
                    required property int index
                    text: modelData
                    font.pixelSize: 18
                    color: navMa.containsMouse ? Theme.accent : Theme.textSecondary
                    width: 20; horizontalAlignment: Text.AlignHCenter
                    MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: mm.month = Cal.addMonths(new Date(mm.month.getFullYear(), mm.month.getMonth(), 1), index === 0 ? -1 : 1) }
                }
            }
        }

        Row {
            Repeater {
                model: Cal.weekdayLabels(CalendarStore.weekStartsMonday)
                Text {
                    required property string modelData
                    width: mm.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: 10
                    color: Theme.textTertiary
                }
            }
        }

        Grid {
            columns: 7
            Repeater {
                model: 42
                Item {
                    id: dayCell
                    required property int index
                    readonly property var date: Cal.addDays(mm.gridStart, index)
                    readonly property bool inMonth: Cal.sameMonth(date, mm.month)
                    readonly property bool isToday: Cal.isToday(date)
                    readonly property bool isSel: mm.selected !== null && Cal.sameDay(date, mm.selected)
                    readonly property bool inRange: mm.rangeStart !== null && date >= mm.rangeStart && date < mm.rangeEnd
                    width: mm.width / 7
                    height: mm.cell - 2

                    Rectangle {   // 范围高亮（整周）
                        anchors.fill: parent
                        anchors.topMargin: 1; anchors.bottomMargin: 1
                        visible: dayCell.inRange && !dayCell.isToday
                        color: Theme.accentSoft
                        radius: 4
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2; height: width; radius: width / 2
                        color: dayCell.isToday ? Theme.accent : (dayCell.isSel ? Theme.accentSoft : (dma.containsMouse ? Theme.hover : "transparent"))
                        border.width: dayCell.isSel && !dayCell.isToday ? 1 : 0
                        border.color: Theme.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.date.getDate()
                        font.pixelSize: 11
                        font.bold: dayCell.isToday || dayCell.isSel
                        color: dayCell.isToday ? Theme.accentText
                             : !dayCell.inMonth ? Theme.textTertiary
                             : (Cal.isWeekend(dayCell.date) ? Theme.textSecondary : Theme.text)
                        opacity: dayCell.inMonth ? 1 : 0.55
                    }
                    Rectangle {
                        visible: mm.showBusy && dayCell.inMonth && mm.busy[Cal.iso(dayCell.date)] === true
                        width: 3; height: 3; radius: 1.5
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                        color: dayCell.isToday ? Theme.accentText : Theme.accent
                        opacity: 0.8
                    }
                    MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mm.picked(dayCell.date) }
                }
            }
        }
    }
}
