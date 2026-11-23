import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 日 / 周视图：顶部日期头 + 全天栏（全天/跨天事件、待办），下方 24 小时时间网格。
//  - 空白处按下拖动 = 选取时间段新建（单击 = 新建 1 小时），15 分钟吸附
//  - 拖动事件块 = 改期（可跨天）；拖底边 = 改结束时间（仅本地、非重复事件）
//  - 重叠事件分列；今天有红色「当前时间」线
Item {
    id: tg
    objectName: "timeGrid"
    property var calendarView
    property int days: 7
    property var startDate: Cal.today()
    readonly property int gutter: 56
    readonly property real hourH: 48
    readonly property real dayW: (width - gutter - 10) / days
    property real nowMin: Cal.minutesOfDay(new Date())

    readonly property var dayList: { var r = []; for (var i = 0; i < days; ++i) r.push(Cal.addDays(startDate, i)); return r }
    readonly property var items: {
        CalendarStore.revision
        var from = Cal.iso(startDate), to = Cal.iso(Cal.addDays(startDate, days))
        var r = CalendarStore.occurrences(from, to)
        return CalendarStore.showTodos ? r.concat(CalendarStore.todosInRange(from, to)) : r
    }
    function topItems(day) {   // 全天栏：全天 / 跨天事件 + 待办
        var iso = Cal.iso(day), r = []
        for (var i = 0; i < items.length; ++i) {
            var it = items[i]
            if ((it.type === "todo" || Cal.isBanner(it)) && Cal.coversDay(it, iso)) r.push(it)
        }
        return r
    }
    readonly property int maxTop: {
        var m = 0
        for (var i = 0; i < dayList.length; ++i) m = Math.max(m, topItems(dayList[i]).length)
        return m
    }
    readonly property int topRows: Math.min(maxTop, days === 1 ? 8 : 4)

    Timer { interval: 60000; running: true; repeat: true; onTriggered: tg.nowMin = Cal.minutesOfDay(new Date()) }

    function snap(min) { return Math.max(0, Math.min(1440, Math.round(min / 15) * 15)) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // MARK: 日期头
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Item {
                width: tg.gutter; height: parent.height
                Text {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    anchors.right: parent.right; anchors.rightMargin: 8
                    text: "GMT" + (function () { var o = -new Date().getTimezoneOffset() / 60; return (o >= 0 ? "+" : "") + o })()
                    font.pixelSize: 9; color: Theme.textTertiary
                }
            }
            Repeater {
                model: tg.dayList
                Item {
                    required property var modelData
                    readonly property bool today: Cal.isToday(modelData)
                    width: tg.dayW; height: 54
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Cal.weekdayName(modelData)
                            font.pixelSize: 11
                            color: parent.parent.today ? Theme.accent : Theme.textSecondary
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 30; height: 30; radius: 15
                            color: parent.parent.today ? Theme.accent : (hdrMa.containsMouse ? Theme.hover : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: modelData.getDate()
                                font.pixelSize: 16; font.bold: parent.parent.parent.today
                                color: parent.parent.parent.today ? Theme.accentText : (Cal.isWeekend(modelData) ? Theme.textSecondary : Theme.text)
                            }
                            MouseArea { id: hdrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tg.calendarView.showDay(modelData) }
                        }
                    }
                }
            }
        }

        // MARK: 全天栏
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(28, tg.topRows * 22 + 8 + (tg.maxTop > tg.topRows ? 18 : 0))
            Item {
                width: tg.gutter; height: parent.height
                Text { anchors.right: parent.right; anchors.rightMargin: 8; y: 7; text: "全天"; font.pixelSize: 10; color: Theme.textTertiary }
            }
            Repeater {
                model: tg.dayList
                Item {
                    id: topCell
                    required property var modelData
                    readonly property var list: tg.topItems(modelData)
                    width: tg.dayW; height: parent.height
                    Rectangle { width: 1; height: parent.height; color: Theme.gridLine }
                    MouseArea {   // 双击全天栏空白 = 新建全天活动
                        anchors.fill: parent
                        onDoubleClicked: tg.calendarView.createAt(topCell.modelData.getTime(), topCell.modelData.getTime(), true)
                    }
                    Column {
                        x: 3; y: 4
                        width: parent.width - 6
                        spacing: 2
                        Repeater {
                            model: topCell.list.slice(0, tg.topRows)
                            EventChip {
                                required property var modelData
                                width: parent.width
                                item: modelData
                                showTime: tg.dayW > 140
                                onClicked: (it, p) => tg.calendarView.openItem(it, p)
                            }
                        }
                        Text {
                            visible: topCell.list.length > tg.topRows
                            text: "还有 " + (topCell.list.length - tg.topRows) + " 项"
                            font.pixelSize: 10; color: Theme.textSecondary
                            leftPadding: 4
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.calendarView.showDay(topCell.modelData) }
                        }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.gridLineStrong }

        // MARK: 时间网格
        Flickable {
            id: flick
            objectName: "timeGridFlick"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: 24 * tg.hourH + 16
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Component.onCompleted: {
                // 默认从 7:30 开始显示；如果当前时间不在可见范围内，改为当前时间前 2 小时
                var showsToday = tg.dayList.some(function (d) { return Cal.isToday(d) })
                var visibleHours = height / tg.hourH
                var h = 7.5
                if (showsToday && tg.nowMin / 60 > h + visibleHours - 1) h = tg.nowMin / 60 - 2
                contentY = Math.min(h * tg.hourH, Math.max(0, contentHeight - height))
            }

            Item {
                width: flick.width
                height: flick.contentHeight

                // 小时线 + 刻度
                Repeater {
                    model: 25
                    Item {
                        required property int index
                        y: 8 + index * tg.hourH
                        width: parent.width
                        Text {
                            visible: index > 0 && index < 24
                            anchors.right: parent.left; anchors.rightMargin: -tg.gutter + 8
                            y: -7
                            text: Cal.pad(index) + ":00"
                            font.pixelSize: 10
                            color: Theme.textTertiary
                        }
                        Rectangle { x: tg.gutter - 4; width: parent.width - x - 10; height: 1; color: Theme.gridLine }
                        Rectangle {   // 半点虚线感：更浅的线
                            visible: index < 24
                            x: tg.gutter; y: tg.hourH / 2; width: parent.width - x - 10; height: 1
                            color: Theme.gridLine; opacity: 0.45
                        }
                    }
                }

                Repeater {
                    model: tg.dayList
                    Item {
                        id: col
                        required property var modelData
                        required property int index
                        readonly property bool today: Cal.isToday(modelData)
                        x: tg.gutter + index * tg.dayW
                        y: 8
                        width: tg.dayW
                        height: 24 * tg.hourH
                        z: dragging ? 5 : 1
                        property bool dragging: false

                        Rectangle { anchors.fill: parent; visible: Cal.isWeekend(col.modelData) && tg.days > 1; color: Theme.weekendBg }
                        Rectangle { width: 1; height: parent.height; color: Theme.gridLine }

                        // 拖选新建
                        MouseArea {
                            id: createMa
                            anchors.fill: parent
                            preventStealing: true
                            property real a: -1
                            property real b: -1
                            onPressed: (m) => { a = tg.snap(Math.floor(m.y / tg.hourH * 60 / 15) * 15); b = a + 60 }
                            onPositionChanged: (m) => {
                                var cur = tg.snap(m.y / tg.hourH * 60)
                                b = Math.max(cur, a + 15)
                            }
                            onReleased: {
                                var s = Cal.at(col.modelData, a).getTime(), e = Cal.at(col.modelData, Math.min(b, 1440)).getTime()
                                if (b >= 1440) e = Cal.addDays(col.modelData, 1).getTime()
                                a = -1
                                tg.calendarView.createAt(s, e, false)
                            }
                            onCanceled: a = -1
                        }
                        Rectangle {   // 选区预览
                            visible: createMa.a >= 0
                            x: 2; width: parent.width - 6
                            y: createMa.a / 60 * tg.hourH
                            height: (createMa.b - createMa.a) / 60 * tg.hourH
                            radius: 6
                            color: Theme.accentSoft
                            border.width: 1.5; border.color: Theme.accent
                            Text {
                                x: 6; y: 3
                                text: "新活动 · " + Cal.pad(Math.floor(createMa.a / 60)) + ":" + Cal.pad(createMa.a % 60) + " – "
                                      + Cal.pad(Math.floor(createMa.b / 60) % 24) + ":" + Cal.pad(createMa.b % 60)
                                font.pixelSize: 11; font.bold: true; color: Theme.accent
                            }
                        }

                        // 事件块
                        Repeater {
                            model: Cal.layoutDay(tg.items, col.modelData)
                            Item {
                                id: block
                                required property var modelData
                                readonly property var it: modelData.item
                                readonly property bool editable: !it.readOnly && !it.recurring
                                readonly property real colW: col.width - 6
                                x: 2 + modelData.col * colW / modelData.cols
                                y: modelData.top / 60 * tg.hourH + 1
                                width: colW / modelData.cols - (modelData.cols > 1 ? 2 : 0)
                                height: Math.max(18, (modelData.bottom - modelData.top) / 60 * tg.hourH - 2) + resizeDy
                                z: moveMa.drag.active || moveMa.pressed ? 10 : 2
                                property real resizeDy: 0
                                readonly property bool past: it.endMs < Date.now()
                                objectName: "eventBlock"

                                transform: Translate { id: shift }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: Cal.alpha(block.it.color, Theme.dark ? 0.34 : (block.past ? 0.13 : 0.2))
                                    border.width: moveMa.containsMouse || moveMa.pressed ? 1 : 0
                                    border.color: block.it.color
                                    Rectangle { width: 3; height: parent.height - 4; y: 2; x: 2; radius: 1.5; color: block.it.color; opacity: block.past ? 0.6 : 1 }
                                    Column {
                                        x: 9; y: 3
                                        width: parent.width - 12
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: block.it.title
                                            font.pixelSize: 11; font.bold: true
                                            color: Theme.text; opacity: block.past ? 0.6 : 1
                                            elide: Text.ElideRight
                                            wrapMode: block.height > 44 ? Text.Wrap : Text.NoWrap
                                            maximumLineCount: Math.max(1, Math.floor((block.height - 22) / 14))
                                        }
                                        Text {
                                            visible: block.height > 30
                                            width: parent.width
                                            text: Cal.hm(block.it.startMs) + " – " + Cal.hm(block.it.endMs) + (block.it.recurring ? "  ↻" : "")
                                            font.pixelSize: 10; color: Theme.textSecondary
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: block.height > 58 && block.it.location !== ""
                                            width: parent.width
                                            text: "⌖ " + block.it.location
                                            font.pixelSize: 10; color: Theme.textSecondary
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // 移动（拖动）/ 点击打开详情
                                MouseArea {
                                    id: moveMa
                                    anchors.fill: parent
                                    anchors.bottomMargin: block.editable ? 6 : 0
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: pressed && block.editable ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    property point p0
                                    property bool moved: false
                                    onPressed: (m) => { p0 = Qt.point(m.x, m.y); moved = false; col.dragging = true }
                                    onPositionChanged: (m) => {
                                        if (!pressed || !block.editable) return
                                        var dx = m.x - p0.x, dy = m.y - p0.y
                                        if (!moved && Math.abs(dx) + Math.abs(dy) < 5) return
                                        moved = true
                                        shift.x = Math.round(dx / tg.dayW) * tg.dayW
                                        shift.y = Math.round(dy / (tg.hourH / 4)) * (tg.hourH / 4)
                                    }
                                    onReleased: (m) => {
                                        col.dragging = false
                                        if (moved && block.editable) {
                                            var dDays = Math.round(shift.x / tg.dayW)
                                            var dMin = Math.round(shift.y / (tg.hourH / 4)) * 15
                                            shift.x = 0; shift.y = 0
                                            if (dDays !== 0 || dMin !== 0) {
                                                var s = new Date(block.it.startMs)
                                                s = new Date(s.getFullYear(), s.getMonth(), s.getDate() + dDays, s.getHours(), s.getMinutes() + dMin)
                                                CalendarStore.moveEvent(block.it.uid, s.getTime())
                                            }
                                        } else {
                                            tg.calendarView.openItem(block.it, moveMa.mapToGlobal(m.x, m.y))
                                        }
                                    }
                                    onCanceled: { col.dragging = false; shift.x = 0; shift.y = 0 }
                                }
                                // 拖底边改结束时间
                                MouseArea {
                                    visible: block.editable
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 6
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    property real y0
                                    onPressed: (m) => { y0 = mapToItem(col, m.x, m.y).y; col.dragging = true }
                                    onPositionChanged: (m) => {
                                        var dy = mapToItem(col, m.x, m.y).y - y0
                                        block.resizeDy = Math.max(-(block.height - block.resizeDy) + tg.hourH / 4, Math.round(dy / (tg.hourH / 4)) * (tg.hourH / 4))
                                    }
                                    onReleased: {
                                        col.dragging = false
                                        var dMin = Math.round(block.resizeDy / (tg.hourH / 4)) * 15
                                        block.resizeDy = 0
                                        if (dMin !== 0) CalendarStore.updateEvent(block.it.uid, { endMs: block.it.endMs + dMin * 60000 })
                                    }
                                }
                            }
                        }

                        // 当前时间线（macOS 红线 + 圆点）
                        Item {
                            visible: col.today
                            y: tg.nowMin / 60 * tg.hourH
                            width: parent.width
                            z: 20
                            Rectangle { width: parent.width; height: 2; y: -1; color: Theme.danger }
                            Rectangle { x: -5; y: -5; width: 10; height: 10; radius: 5; color: Theme.danger }
                        }
                    }
                }

                // 当前时间刻度
                Rectangle {
                    visible: tg.dayList.some(function (d) { return Cal.isToday(d) })
                    x: 4; y: 8 + tg.nowMin / 60 * tg.hourH - 8
                    width: tg.gutter - 12; height: 16; radius: 8
                    color: Theme.danger
                    Text {
                        anchors.centerIn: parent
                        text: Cal.pad(Math.floor(tg.nowMin / 60)) + ":" + Cal.pad(Math.floor(tg.nowMin % 60))
                        font.pixelSize: 10; font.bold: true; color: "white"
                    }
                }
            }
        }
    }
}
