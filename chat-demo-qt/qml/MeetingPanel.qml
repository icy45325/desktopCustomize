import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 会议列表：顶部「下一个会议」卡片（倒计时 / 进行中进度、加入会议链接），下面按天列出接下来的会议。
// 「会议」= 有具体时间的活动（全天 / 跨天活动不算）。每 30 秒刷新倒计时。
Item {
    id: mp
    objectName: "meetingPanel"
    property string range: "today"          // today | week
    property double now: Date.now()
    Timer { interval: 30000; running: mp.visible; repeat: true; triggeredOnStart: true; onTriggered: mp.now = Date.now() }

    readonly property var meetings: {
        CalendarStore.revision
        var from = Cal.today()
        var list = CalendarStore.occurrences(Cal.iso(from), Cal.iso(Cal.addDays(from, 8)))
        return list.filter(function (e) { return !e.allDay && !e.multiDay })
    }
    readonly property var next: {
        for (var i = 0; i < meetings.length; ++i) if (meetings[i].endMs > now) return meetings[i]
        return null
    }
    readonly property var rows: {
        var t = Cal.iso(Cal.today()), out = [], last = ""
        for (var i = 0; i < meetings.length; ++i) {
            var e = meetings[i]
            if (range === "today" && e.startIso !== t) continue
            if (next && e.key === next.key) continue
            var g = e.startIso === t ? (e.endMs <= now ? "今天 · 已结束" : "今天") : Cal.relativeDay(Cal.parseIso(e.startIso)) || (Cal.md(Cal.parseIso(e.startIso)) + " " + Cal.weekdayName(Cal.parseIso(e.startIso)))
            out.push({ group: g, first: g !== last, item: e })
            last = g
        }
        // 今天已结束的放最后
        return out.filter(function (r) { return r.group !== "今天 · 已结束" }).concat(out.filter(function (r) { return r.group === "今天 · 已结束" }))
    }

    function joinLink(e) {
        var re = /(https?:\/\/[^\s，。)）]+)/
        var srcs = [e.url || "", e.location || "", e.notes || ""]
        for (var i = 0; i < srcs.length; ++i) { var m = re.exec(srcs[i]); if (m) return m[1] }
        return ""
    }
    function countdown(e) {
        var mins = Math.round((e.startMs - now) / 60000)
        if (e.startMs <= now) return "进行中 · 还剩 " + Math.max(1, Math.round((e.endMs - now) / 60000)) + " 分钟"
        if (mins < 60) return mins + " 分钟后开始"
        if (mins < 24 * 60) return Math.floor(mins / 60) + " 小时 " + (mins % 60) + " 分钟后开始"
        return (Cal.relativeDay(new Date(e.startMs)) || Cal.md(new Date(e.startMs))) + " " + Cal.hm(e.startMs)
    }
    function open(e) { WindowManager.focusCalendar(); CalendarStore.requestOpen(e) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // MARK: 下一个会议
        Rectangle {
            id: hero
            objectName: "nextMeetingCard"
            Layout.fillWidth: true
            visible: mp.next !== null
            implicitHeight: heroCol.implicitHeight + 24
            radius: 14
            readonly property bool live: mp.next !== null && mp.next.startMs <= mp.now
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accentSecondary }
            }
            ColumnLayout {
                id: heroCol
                x: 14; y: 12
                width: parent.width - 28
                spacing: 4
                Row {
                    spacing: 6
                    Rectangle {
                        width: 7; height: 7; radius: 3.5; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accentText
                        SequentialAnimation on opacity {
                            running: hero.live; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                        }
                    }
                    Text { text: hero.live ? "正在进行" : "下一个会议"; font.pixelSize: 11; font.bold: true; color: Theme.accentText; opacity: 0.85 }
                }
                Text {
                    Layout.fillWidth: true
                    text: mp.next ? mp.next.title : ""
                    font.pixelSize: 16; font.bold: true
                    color: Theme.accentText
                    elide: Text.ElideRight
                }
                Text {
                    text: mp.next ? Cal.hm(mp.next.startMs) + " – " + Cal.hm(mp.next.endMs) + (mp.next.location ? " · " + mp.next.location : "") : ""
                    font.pixelSize: 12; color: Theme.accentText; opacity: 0.9
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                // 进行中的进度条
                Rectangle {
                    visible: hero.live
                    Layout.fillWidth: true; Layout.topMargin: 4
                    height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.3)
                    Rectangle {
                        height: parent.height; radius: 2; color: Theme.accentText
                        width: !mp.next ? 0 : parent.width * Math.min(1, (mp.now - mp.next.startMs) / Math.max(1, mp.next.endMs - mp.next.startMs))
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Text {
                        Layout.fillWidth: true
                        text: mp.next ? mp.countdown(mp.next) : ""
                        font.pixelSize: 12; font.bold: true; color: Theme.accentText
                    }
                    Rectangle {
                        readonly property string link: mp.next ? mp.joinLink(mp.next) : ""
                        visible: link !== ""
                        implicitWidth: joinTxt.implicitWidth + 20; implicitHeight: 26; radius: 13
                        color: Theme.accentText
                        Text { id: joinTxt; anchors.centerIn: parent; text: "加入会议"; font.pixelSize: 12; font.bold: true; color: Theme.accent }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(parent.link) }
                    }
                }
            }
            MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: if (mp.next) mp.open(mp.next) }
        }

        // 范围切换
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "今天 " + mp.meetings.filter(function (e) { return e.startIso === Cal.iso(Cal.today()) }).length + " 个会议"
                font.pixelSize: 12; font.bold: true; color: Theme.textSecondary
            }
            Repeater {
                model: [{ k: "today", t: "今天" }, { k: "week", t: "7 天" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: mp.range === modelData.k
                    width: rt.implicitWidth + 16; height: 22; radius: 11
                    color: on ? Theme.accentSoft : "transparent"
                    Text { id: rt; anchors.centerIn: parent; text: modelData.t; font.pixelSize: 11; font.bold: parent.on; color: parent.on ? Theme.accent : Theme.textTertiary }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mp.range = modelData.k }
                }
            }
        }

        ListView {
            id: lv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: mp.rows
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                id: row
                required property var modelData
                readonly property var it: modelData.item
                readonly property bool past: it.endMs <= mp.now
                width: lv.width
                spacing: 2
                Text {
                    visible: row.modelData.first
                    topPadding: 6; bottomPadding: 2; leftPadding: 4
                    text: row.modelData.group
                    font.pixelSize: 11; font.bold: true; color: Theme.textTertiary
                }
                Rectangle {
                    width: parent.width; height: 48; radius: 10
                    color: ma.containsMouse ? Theme.hover : "transparent"
                    opacity: row.past ? 0.5 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6; anchors.rightMargin: 8
                        spacing: 8
                        Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 30; radius: 1.5; color: row.it.color }
                        Column {
                            Layout.preferredWidth: 40
                            Text { text: Cal.hm(row.it.startMs); font.pixelSize: 12; font.bold: true; color: Theme.text }
                            Text { text: Cal.hm(row.it.endMs); font.pixelSize: 10; color: Theme.textTertiary }
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { width: parent.width; text: row.it.title; font.pixelSize: 13; color: Theme.text; elide: Text.ElideRight }
                            Text {
                                width: parent.width
                                text: (row.it.location || row.it.calendarName) + (row.it.recurring ? " · ↻" : "")
                                font.pixelSize: 10; color: Theme.textSecondary; elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: mp.joinLink(row.it) !== "" && !row.past
                            text: "⇗"; font.pixelSize: 14; color: joinMa.containsMouse ? Theme.accent : Theme.textTertiary
                            MouseArea { id: joinMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(mp.joinLink(row.it)) }
                            ToolTip.visible: joinMa.containsMouse; ToolTip.text: "加入会议"; ToolTip.delay: 400
                        }
                    }
                    MouseArea { id: ma; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mp.open(row.it) }
                }
            }
        }

        Text {
            visible: mp.rows.length === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 30
            text: mp.next === null ? "接下来没有会议 ☕" : (mp.range === "today" ? "今天没有其它会议了" : "没有其它会议")
            color: Theme.textSecondary; font.pixelSize: 12
        }
    }
}
