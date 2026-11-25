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
        if (searchText !== "") return qsTr("搜索：%1").arg(searchText)
        switch (mode) {
        case "day": return Cal.md(d)
        case "week": {
            var s = rangeStart, e = Cal.addDays(rangeStart, 6)
            if (s.getFullYear() !== e.getFullYear()) return Cal.ym(s) + " – " + Cal.ym(e)
            if (s.getMonth() !== e.getMonth()) return Cal.isEn() ? Cal.monthShort(s) + " – " + Cal.monthShort(e) + " " + s.getFullYear()
                                                                 : s.getFullYear() + "年" + (s.getMonth() + 1) + "–" + (e.getMonth() + 1) + "月"
            return Cal.ym(s)
        }
        case "month": return Cal.ym(d)
        case "year": return Cal.yearText(d.getFullYear())
        default: return qsTr("日程")
        }
    }
    function subtitle() {
        if (searchText !== "") return ""
        if (mode === "week") return qsTr("第 %1 周").arg(Cal.weekNumber(rangeStart)) + " · " + Cal.md(rangeStart) + " – " + Cal.md(Cal.addDays(rangeStart, 6))
        if (mode === "day") {
            var r = Cal.relativeDay(anchorDate), adj = CalendarStore.hijriAdjust   // 读一下校正值：它变化时副标题重算
            return Cal.yearText(anchorDate.getFullYear()) + " · " + Cal.weekdayName(anchorDate) + (r !== "" ? " · " + r : "")
                   + (CalendarStore.showHijri ? " · " + CalendarStore.hijriText(Cal.iso(anchorDate)) : "")
        }
        if (mode === "agenda") return qsTr("自 %1 起").arg(Cal.ymd(anchorDate))
        return ""
    }

    function modes() {
        return [{ k: "day", t: qsTr("日"), s: "D" }, { k: "week", t: qsTr("周"), s: "W" }, { k: "month", t: qsTr("月"), s: "M" },
                { k: "year", t: qsTr("年"), s: "Y" }, { k: "agenda", t: qsTr("日程"), s: "A" }]
    }
    function modeLabel(k) { var m = modes(); for (var i = 0; i < m.length; ++i) if (m[i].k === k) return m[i].t; return "" }
    function goToday() { anchorDate = Cal.today() }
    function step(n) {
        switch (mode) {
        case "day": {
            // 隐藏周末时，按天翻页跳过周末（同 Google 日历）
            var d = Cal.addDays(anchorDate, n)
            for (var i = 0; i < 3 && !CalendarStore.showWeekends && Cal.isWeekend(d, CalendarStore.weekendDays); ++i) d = Cal.addDays(d, n)
            anchorDate = d
            break
        }
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

    // 面板 / 助手等日历视图之外的地方：打开条目详情、新建
    Connections {
        target: CalendarStore
        function onOpenRequested(item) {
            var iso = item.type === "todo" ? item.dueIso : item.startIso
            if (iso) calRoot.anchorDate = Cal.parseIso(iso)
            if (calRoot.mode === "year") CalendarStore.viewMode = "day"
            calRoot.searchText = ""; searchField.text = ""
            // 详情气泡放在视图区中间偏上
            Qt.callLater(function () { detail.show(item, calRoot.width / 2 - 60, 150) })
        }
        function onCreateRequested(kind) { calRoot.createAt(null, null, false, kind) }
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
            Layout.leftMargin: 4; Layout.rightMargin: WindowManager.panelOpen && !WindowManager.panelDetached ? 4 : 14
            radius: 20
            elevation: 1.3

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // MARK: 工具栏
                RowLayout {
                    id: toolbar
                    // 窄时（如打开右侧面板、英文标签更长）把视图分段控件收成一个下拉按钮，给标题留出空间
                    readonly property bool compact: width < 640
                    Layout.fillWidth: true
                    Layout.margins: 14
                    Layout.bottomMargin: 10
                    spacing: 8

                    MacButton { text: qsTr("今天"); objectName: "todayButton"; onClicked: calRoot.goToday(); ToolTip.visible: hovered; ToolTip.text: qsTr("回到今天（T）"); ToolTip.delay: 600 }
                    MacButton { circular: true; text: "‹"; font.pixelSize: 18; onClicked: calRoot.step(-1); ToolTip.visible: hovered; ToolTip.text: qsTr("上一页（K / ←）"); ToolTip.delay: 600 }
                    MacButton { circular: true; text: "›"; font.pixelSize: 18; onClicked: calRoot.step(1); ToolTip.visible: hovered; ToolTip.text: qsTr("下一页（J / →）"); ToolTip.delay: 600 }
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
                            placeholderText: qsTr("搜索日程")
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
                        ToolTip.visible: !expanded && searchHover.hovered; ToolTip.text: qsTr("搜索（/ 或 ⌘F）"); ToolTip.delay: 500
                        HoverHandler { id: searchHover }
                        Timer { id: searchTimer; interval: 250; onTriggered: calRoot.searchText = searchField.text.trim() }
                    }

                    // 视图切换：窄时为下拉按钮
                    MacButton {
                        id: modeButton
                        objectName: "modeMenuButton"
                        visible: toolbar.compact
                        text: calRoot.modeLabel(calRoot.mode) + "  ⌄"
                        onClicked: modeMenu.popup(modeButton, 0, modeButton.height + 4)
                        Menu {
                            id: modeMenu
                            Repeater {
                                model: calRoot.modes()
                                MenuItem {
                                    required property var modelData
                                    text: modelData.t + "    " + modelData.s
                                    onTriggered: calRoot.setMode(modelData.k)
                                }
                            }
                        }
                    }
                    // 视图切换（分段控件）
                    Rectangle {
                        visible: !toolbar.compact
                        implicitHeight: 30
                        implicitWidth: seg.implicitWidth + 6
                        radius: 15
                        color: Theme.surface
                        Row {
                            id: seg
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: calRoot.modes()
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
                                    ToolTip.visible: segMa.containsMouse; ToolTip.delay: 600; ToolTip.text: qsTr("%1视图（%2）").arg(modelData.t).arg(modelData.s)
                                }
                            }
                        }
                    }

                    MacButton {
                        objectName: "todoPanelToggle"
                        circular: true
                        text: "☑"
                        font.pixelSize: 15
                        // 打开动态面板并切到「待办」；已在「待办」时再点 = 关闭
                        readonly property bool showing: WindowManager.panelOpen && WindowManager.panelTab === "todo"
                        primary: showing
                        onClicked: {
                            if (showing && !WindowManager.panelDetached) { WindowManager.panelOpen = false; return }
                            WindowManager.panelTab = "todo"
                            WindowManager.panelOpen = true
                        }
                        ToolTip.visible: hovered; ToolTip.text: showing ? qsTr("隐藏待办") : qsTr("在右侧面板显示待办"); ToolTip.delay: 500
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
                // 每种视图首次使用时创建，之后保留（隐藏时不刷新数据，重新可见时才补刷新），切换视图不再重建整棵树
                Item {
                    id: viewHost
                    objectName: "viewHost"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property string current: calRoot.searchText !== "" ? "agenda"
                                                    : calRoot.mode === "day" || calRoot.mode === "week" ? "grid" : calRoot.mode
                    // 自测用：当前显示的视图
                    readonly property Item item: current === "grid" ? gridLoader.item : current === "month" ? monthLoader.item
                                               : current === "year" ? yearLoader.item : agendaLoader.item

                    component ViewLoader: Loader {
                        property string key
                        // 用显式条件而非 visible：日历页在后台预加载时（整页不可见）当前视图也要一并建好
                        readonly property bool wanted: viewHost.current === key
                        anchors.fill: parent
                        active: false
                        visible: wanted
                        onWantedChanged: if (wanted) active = true
                        Component.onCompleted: if (wanted) active = true
                    }
                    ViewLoader { id: gridLoader; key: "grid"; sourceComponent: TimeGridView { calendarView: calRoot; days: calRoot.mode === "day" ? 1 : 7; startDate: calRoot.rangeStart } }
                    ViewLoader { id: monthLoader; key: "month"; sourceComponent: MonthView { calendarView: calRoot } }
                    ViewLoader { id: yearLoader; key: "year"; sourceComponent: YearView { calendarView: calRoot } }
                    ViewLoader { id: agendaLoader; key: "agenda"; sourceComponent: AgendaView { calendarView: calRoot; query: calRoot.searchText } }
                }
            }
        }
    }

    EventEditor { id: editor; objectName: "eventEditor" }
    EventDetail { id: detail; objectName: "eventDetail"; calendarView: calRoot }
    SubscribeDialog { id: subscribeDialog; objectName: "subscribeDialog" }

    function openSubscribe(calId) { subscribeDialog.openFor(calId || "") }
}
