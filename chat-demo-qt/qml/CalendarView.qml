import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 日历模块根视图：左侧栏（创建 / 迷你月历 / 日历列表）+ 中间视图（日 / 周 / 月 / 年 / 日程）+ 右侧待办面板。
// 交互参考 Google Calendar（快捷键、拖选创建、待办面板）与 macOS 日历（视图切换、今天红线、勾选框）。
Item {
    id: calRoot
    objectName: "calendarView"

    property var anchorDate: Cal.today()            // 当前视图所在日期
    readonly property string mode: CalendarStore.viewMode
    property string searchText: ""
    readonly property bool popupOpen: editor.opened || detail.opened || subscribeDialog.opened

    // 当前视图覆盖的范围（用于标题、取数据）
    readonly property var rangeStart: mode === "day" ? anchorDate
                                    : mode === "week" ? Cal.startOfWeek(anchorDate, CalendarStore.weekStartsMonday)
                                    : mode === "month" ? Cal.monthGridStart(anchorDate, CalendarStore.weekStartsMonday)
                                    : mode === "year" ? new Date(anchorDate.getFullYear(), 0, 1)
                                    : anchorDate
    readonly property int rangeDays: mode === "day" ? 1 : mode === "week" ? 7 : mode === "month" ? 42 : mode === "year" ? 366 : 60

    // 标题简洁（同 macOS 日历）：周/月视图只写年月，细节放副标题
    function title() {
        var d = anchorDate
        if (searchText !== "") return "搜索：" + searchText
        switch (mode) {
        case "day": return Cal.md(d)
        case "week": {
            var s = rangeStart, e = Cal.addDays(rangeStart, 6)
            if (s.getFullYear() !== e.getFullYear()) return s.getFullYear() + "年" + (s.getMonth() + 1) + "月 – " + e.getFullYear() + "年" + (e.getMonth() + 1) + "月"
            if (s.getMonth() !== e.getMonth()) return s.getFullYear() + "年" + (s.getMonth() + 1) + "–" + (e.getMonth() + 1) + "月"
            return s.getFullYear() + "年" + (s.getMonth() + 1) + "月"
        }
        case "month": return d.getFullYear() + "年" + (d.getMonth() + 1) + "月"
        case "year": return d.getFullYear() + "年"
        default: return "日程"
        }
    }
    function subtitle() {
        if (searchText !== "") return ""
        if (mode === "week") return "第 " + Cal.weekNumber(rangeStart) + " 周 · " + Cal.md(rangeStart) + " – " + Cal.md(Cal.addDays(rangeStart, 6))
        if (mode === "day") { var r = Cal.relativeDay(anchorDate); return anchorDate.getFullYear() + "年 · " + Cal.weekdayName(anchorDate) + (r !== "" ? " · " + r : "") }
        if (mode === "agenda") return "自 " + Cal.ymd(anchorDate) + " 起"
        return ""
    }

    function goToday() { anchorDate = Cal.today() }
    function step(n) {
        switch (mode) {
        case "day": anchorDate = Cal.addDays(anchorDate, n); break
        case "week": anchorDate = Cal.addDays(anchorDate, 7 * n); break
        case "month": anchorDate = Cal.addMonths(anchorDate, n); break
        case "year": anchorDate = new Date(anchorDate.getFullYear() + n, anchorDate.getMonth(), 1); break
        default: anchorDate = Cal.addDays(anchorDate, 30 * n)
        }
    }
    function setMode(m) { searchText = ""; searchField.text = ""; CalendarStore.viewMode = m }
    function showDay(d) { anchorDate = Cal.dayStart(d); setMode("day") }

    // 新建：startMs/endMs 可省略（默认下一个整点，时长 1 小时）
    function createAt(startMs, endMs, allDay, kind) {
        var s
        if (startMs === undefined || startMs === null) {
            var now = new Date()
            var base = Cal.sameDay(anchorDate, now) ? now : Cal.at(anchorDate, 9 * 60)
            s = new Date(base.getFullYear(), base.getMonth(), base.getDate(), base.getHours() + (Cal.sameDay(anchorDate, now) ? 1 : 0), 0)
            startMs = s.getTime()
            endMs = startMs + 3600000
        }
        editor.openNew(startMs, endMs || startMs + 3600000, allDay === true, kind || "event")
    }
    function openItem(item, globalPos) {
        var p = calRoot.mapFromGlobal(globalPos.x, globalPos.y)
        detail.show(item, p.x, p.y)
    }
    function editItem(item) { item.type === "todo" ? editor.openTodo(item) : editor.openEvent(item) }

    Connections {
        target: CalendarStore
        // 点击提醒通知：跳到事件所在日期
        function onRevealRequested(dateIso) {
            calRoot.anchorDate = Cal.parseIso(dateIso)
            if (calRoot.mode === "year" || calRoot.mode === "agenda") CalendarStore.viewMode = "day"
        }
    }

    // MARK: 快捷键（Google Calendar 风格；文本框聚焦时字母键交给输入框）
    readonly property bool keysEnabled: visible && !popupOpen && !searchField.activeFocus
    Shortcut { sequence: "T"; enabled: calRoot.keysEnabled; onActivated: calRoot.goToday() }
    Shortcut { sequence: "D"; enabled: calRoot.keysEnabled; onActivated: calRoot.setMode("day") }
    Shortcut { sequence: "W"; enabled: calRoot.keysEnabled; onActivated: calRoot.setMode("week") }
    Shortcut { sequence: "M"; enabled: calRoot.keysEnabled; onActivated: calRoot.setMode("month") }
    Shortcut { sequence: "Y"; enabled: calRoot.keysEnabled; onActivated: calRoot.setMode("year") }
    Shortcut { sequence: "A"; enabled: calRoot.keysEnabled; onActivated: calRoot.setMode("agenda") }
    Shortcut { sequence: "C"; enabled: calRoot.keysEnabled; onActivated: calRoot.createAt() }
    Shortcut { sequences: ["J", "N", "Right"]; enabled: calRoot.keysEnabled; onActivated: calRoot.step(1) }
    Shortcut { sequences: ["K", "P", "Left"]; enabled: calRoot.keysEnabled; onActivated: calRoot.step(-1) }
    Shortcut { sequence: "Ctrl+T"; enabled: calRoot.visible; onActivated: calRoot.goToday() }
    Shortcut { sequence: "Ctrl+N"; enabled: calRoot.visible && !calRoot.popupOpen; onActivated: calRoot.createAt() }
    Shortcut { sequence: "Ctrl+F"; enabled: calRoot.visible; onActivated: searchField.forceActiveFocus() }
    Shortcut { sequence: "/"; enabled: calRoot.keysEnabled; onActivated: searchField.forceActiveFocus() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        CalSidebar {
            Layout.preferredWidth: 236
            Layout.fillHeight: true
            calendarView: calRoot
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14; Layout.bottomMargin: 14
            Layout.leftMargin: 4; Layout.rightMargin: CalendarStore.todoPanelOpen ? 4 : 14
            radius: 20
            elevation: 1.3

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // MARK: 工具栏
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 14
                    Layout.bottomMargin: 10
                    spacing: 8

                    MacButton { text: "今天"; objectName: "todayButton"; onClicked: calRoot.goToday(); ToolTip.visible: hovered; ToolTip.text: "回到今天（T）"; ToolTip.delay: 600 }
                    MacButton { circular: true; text: "‹"; font.pixelSize: 18; onClicked: calRoot.step(-1); ToolTip.visible: hovered; ToolTip.text: "上一页（K / ←）"; ToolTip.delay: 600 }
                    MacButton { circular: true; text: "›"; font.pixelSize: 18; onClicked: calRoot.step(1); ToolTip.visible: hovered; ToolTip.text: "下一页（J / →）"; ToolTip.delay: 600 }
                    Column {
                        Layout.leftMargin: 6
                        Layout.fillWidth: true
                        Text {
                            objectName: "calendarTitle"
                            width: parent.width
                            text: calRoot.title()
                            font.pixelSize: 18; font.bold: true
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: text !== ""
                            text: calRoot.subtitle()
                            font.pixelSize: 11
                            color: Theme.textTertiary
                        }
                    }

                    // 搜索：收起时是一个圆形图标，聚焦或有内容时展开
                    Rectangle {
                        id: searchBox
                        readonly property bool expanded: searchField.activeFocus || searchField.text !== ""
                        Layout.preferredWidth: expanded ? 180 : 30
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        implicitHeight: 30
                        radius: 15
                        color: expanded ? Theme.surface : Theme.accentSoft
                        border.width: 1
                        border.color: searchField.activeFocus ? Theme.accent : "transparent"
                        Text {
                            x: searchBox.expanded ? 10 : (parent.width - width) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌕"; font.pixelSize: 15
                            color: searchBox.expanded ? Theme.textTertiary : Theme.accent
                        }
                        TextField {
                            id: searchField
                            objectName: "calendarSearch"
                            anchors.fill: parent
                            anchors.leftMargin: 26; anchors.rightMargin: 8
                            opacity: searchBox.expanded ? 1 : 0
                            placeholderText: "搜索日程"
                            placeholderTextColor: Theme.textTertiary
                            color: Theme.text
                            font.pixelSize: 12
                            background: null
                            verticalAlignment: TextInput.AlignVCenter
                            onTextChanged: searchTimer.restart()
                            Keys.onEscapePressed: { text = ""; calRoot.forceActiveFocus() }
                        }
                        MouseArea {
                            anchors.fill: parent
                            visible: !searchBox.expanded
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchField.forceActiveFocus()
                        }
                        ToolTip.visible: !expanded && searchHover.hovered; ToolTip.text: "搜索（/ 或 ⌘F）"; ToolTip.delay: 500
                        HoverHandler { id: searchHover }
                        Timer { id: searchTimer; interval: 250; onTriggered: calRoot.searchText = searchField.text.trim() }
                    }

                    // 视图切换（分段控件）
                    Rectangle {
                        implicitHeight: 30
                        implicitWidth: seg.implicitWidth + 6
                        radius: 15
                        color: Theme.surface
                        Row {
                            id: seg
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [{ k: "day", t: "日", s: "D" }, { k: "week", t: "周", s: "W" }, { k: "month", t: "月", s: "M" },
                                        { k: "year", t: "年", s: "Y" }, { k: "agenda", t: "日程", s: "A" }]
                                Rectangle {
                                    required property var modelData
                                    readonly property bool on: calRoot.mode === modelData.k && calRoot.searchText === ""
                                    objectName: "mode-" + modelData.k
                                    width: Math.max(34, segText.implicitWidth + 18); height: 24; radius: 12
                                    color: on ? Theme.card : (segMa.containsMouse ? Theme.hover : "transparent")
                                    border.width: on && Theme.dark ? 1 : 0
                                    border.color: Theme.accentGlow
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { id: segText; anchors.centerIn: parent; text: modelData.t; font.pixelSize: 12; font.bold: parent.on; color: parent.on ? Theme.accent : Theme.textSecondary }
                                    MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calRoot.setMode(modelData.k) }
                                    ToolTip.visible: segMa.containsMouse; ToolTip.delay: 600; ToolTip.text: modelData.t + "视图（" + modelData.s + "）"
                                }
                            }
                        }
                    }

                    MacButton {
                        objectName: "todoPanelToggle"
                        circular: true
                        text: "☑"
                        font.pixelSize: 15
                        primary: CalendarStore.todoPanelOpen
                        onClicked: CalendarStore.todoPanelOpen = !CalendarStore.todoPanelOpen
                        ToolTip.visible: hovered; ToolTip.text: CalendarStore.todoPanelOpen ? "隐藏待办面板" : "显示待办面板"; ToolTip.delay: 500
                        Rectangle {
                            visible: CalendarStore.openTodoCount > 0
                            x: parent.width - width / 2 - 3; y: -4
                            height: 15; width: Math.max(15, todoBadge.implicitWidth + 6); radius: 7.5
                            color: Theme.danger
                            Text { id: todoBadge; anchors.centerIn: parent; text: CalendarStore.openTodoCount; color: "white"; font.pixelSize: 9; font.bold: true }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.gridLine }

                // MARK: 视图
                Loader {
                    id: viewLoader
                    objectName: "viewLoader"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: calRoot.searchText !== "" ? agendaComp
                                   : calRoot.mode === "day" || calRoot.mode === "week" ? gridComp
                                   : calRoot.mode === "month" ? monthComp
                                   : calRoot.mode === "year" ? yearComp
                                   : agendaComp
                }
            }
        }

        TodoPanel {
            visible: CalendarStore.todoPanelOpen
            Layout.preferredWidth: 272
            Layout.fillHeight: true
            calendarView: calRoot
        }
    }

    Component { id: gridComp; TimeGridView { calendarView: calRoot; days: calRoot.mode === "day" ? 1 : 7; startDate: calRoot.rangeStart } }
    Component { id: monthComp; MonthView { calendarView: calRoot } }
    Component { id: yearComp; YearView { calendarView: calRoot } }
    Component { id: agendaComp; AgendaView { calendarView: calRoot; query: calRoot.searchText } }

    EventEditor { id: editor; objectName: "eventEditor" }
    EventDetail { id: detail; objectName: "eventDetail"; calendarView: calRoot }
    SubscribeDialog { id: subscribeDialog; objectName: "subscribeDialog" }

    function openSubscribe(calId) { subscribeDialog.openFor(calId || "") }
}
