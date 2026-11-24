import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 日程视图（Google「日程」/ macOS 列表）：按天分组列出事件与待办；query 非空时显示搜索结果。
Item {
    id: av
    objectName: "agendaView"
    property var calendarView
    property string query: ""
    property int span: 30

    property var rows: []
    readonly property string rangeKey: query + "|" + Cal.iso(calendarView.anchorDate) + "|" + span
    property string loadedKey: ""
    property int loadedRev: -1
    function refresh() { if ((visible || loadedRev < 0) && (loadedKey !== rangeKey || loadedRev !== CalendarStore.revision)) reload() }
    onVisibleChanged: refresh()
    onRangeKeyChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: CalendarStore; function onChanged() { av.refresh() } }
    function reload() {
        var list
        if (query !== "") {
            list = CalendarStore.search(query)
        } else {
            var from = Cal.iso(calendarView.anchorDate), to = Cal.iso(Cal.addDays(calendarView.anchorDate, span))
            list = CalendarStore.occurrences(from, to)
            if (CalendarStore.showTodos) list = list.concat(CalendarStore.todosInRange(from, to))
        }
        // 展开成「日期头 + 条目」的扁平列表；跨天事件只在开始那天出现（搜索）或每天出现（日程）
        var byDay = {}, days = []
        for (var i = 0; i < list.length; ++i) {
            var it = list[i]
            var keys = []
            if (it.type === "todo") keys = [it.dueIso]
            else if (query !== "") keys = [it.startIso]
            else {
                var d = Cal.parseIso(it.startIso < Cal.iso(calendarView.anchorDate) ? Cal.iso(calendarView.anchorDate) : it.startIso)
                var last = it.lastIso
                for (var k = 0; k < 62 && Cal.iso(d) <= last; ++k, d = Cal.addDays(d, 1)) keys.push(Cal.iso(d))
            }
            for (var j = 0; j < keys.length; ++j) {
                if (!byDay[keys[j]]) { byDay[keys[j]] = []; days.push(keys[j]) }
                byDay[keys[j]].push(it)
            }
        }
        days.sort()
        var out = []
        for (i = 0; i < days.length; ++i) {
            var arr = byDay[days[i]]
            arr.sort(function (a, b) {
                var ta = a.type === "todo" ? 1 : 0, tb = b.type === "todo" ? 1 : 0
                if (a.allDay !== b.allDay && ta === tb) return a.allDay ? -1 : 1
                return ta - tb || (a.startMs || a.dueMs) - (b.startMs || b.dueMs)
            })
            for (j = 0; j < arr.length; ++j) out.push({ day: days[i], first: j === 0, item: arr[j] })
        }
        rows = out
        loadedKey = rangeKey
        loadedRev = CalendarStore.revision
    }

    ListView {
        id: lv
        anchors.fill: parent
        anchors.topMargin: 6
        clip: true
        model: av.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            readonly property var it: modelData.item
            readonly property var day: Cal.parseIso(modelData.day)
            width: lv.width
            height: 44 + (modelData.first ? 8 : 0)

            Rectangle {
                visible: row.modelData.first
                x: 16; width: parent.width - 32; height: 1
                color: Theme.gridLine
            }
            // 左侧：日期（每天第一条显示）
            Row {
                visible: row.modelData.first
                x: 18; y: 14
                spacing: 8
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: Cal.isToday(row.day) ? Theme.accent : "transparent"
                    Text { anchors.centerIn: parent; text: row.day.getDate(); font.pixelSize: 17; font.bold: true
                        color: Cal.isToday(row.day) ? Theme.accentText : Theme.text }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: av.calendarView.showDay(row.day) }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.day.getFullYear() !== new Date().getFullYear() ? row.day.getFullYear() + "年" : "") + (row.day.getMonth() + 1) + "月 " + Cal.weekdayName(row.day)
                          + (Cal.relativeDay(row.day) !== "" ? " · " + Cal.relativeDay(row.day) : "")
                    font.pixelSize: 11
                    color: Cal.isToday(row.day) ? Theme.accent : Theme.textSecondary
                    width: 120
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: entry
                x: 200; y: row.modelData.first ? 10 : 2
                width: parent.width - x - 16; height: 38
                radius: 10
                color: entryMa.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10; anchors.rightMargin: 10
                    spacing: 10
                    Item {
                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                        Rectangle { visible: row.it.type !== "todo"; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: row.it.color }
                        CheckCircle {
                            visible: row.it.type === "todo"
                            anchors.centerIn: parent
                            size: 16
                            checked: row.it.type === "todo" && row.it.done
                            color: row.it.color
                            readOnly: row.it.readOnly
                            onToggled: CalendarStore.toggleTodo(row.it.uid)
                        }
                    }
                    Text {
                        Layout.preferredWidth: 112
                        text: row.it.type === "todo" ? (row.it.dueTime !== "" ? "截止 " + row.it.dueTime : "待办")
                            : row.it.allDay ? "全天"
                            : (row.it.multiDay ? Cal.hm(row.it.startMs) + " 起" : Cal.hm(row.it.startMs) + " – " + Cal.hm(row.it.endMs))
                        font.pixelSize: 12
                        color: Theme.textSecondary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.it.title + (row.it.location ? "  ·  " + row.it.location : "")
                        font.pixelSize: 13
                        font.strikeout: row.it.type === "todo" && row.it.done
                        color: row.it.type === "todo" && row.it.overdue ? Theme.danger : Theme.text
                        elide: Text.ElideRight
                    }
                    Text {
                        text: row.it.calendarName
                        font.pixelSize: 11
                        color: Theme.textTertiary
                        elide: Text.ElideRight
                        Layout.maximumWidth: 140
                    }
                }
                MouseArea {
                    id: entryMa
                    anchors.fill: parent
                    anchors.leftMargin: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (m) => av.calendarView.openItem(row.it, entryMa.mapToGlobal(m.x, m.y))
                }
            }
        }

        footer: Item {
            width: lv.width
            height: 64
            MacButton {
                anchors.centerIn: parent
                visible: av.query === ""
                text: "再看 30 天"
                onClicked: av.span += 30
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: av.rows.length === 0
        spacing: 8
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: av.query !== "" ? "⌕" : "☼"; font.pixelSize: 38; color: Theme.accent; opacity: 0.4 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: av.query !== "" ? "没有找到与「" + av.query + "」相关的日程" : "接下来 " + av.span + " 天没有安排"
            color: Theme.textSecondary
        }
    }
}
