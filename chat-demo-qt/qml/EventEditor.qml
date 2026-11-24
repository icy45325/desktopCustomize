import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 新建 / 编辑：活动 与 待办 两个标签页（同 Google 的「活动 | 任务」）。
Popup {
    id: ed
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 460
    modal: true
    focus: true
    padding: 20
    closePolicy: Popup.CloseOnEscape
    background: Card { radius: 18; color: Theme.popup; elevation: 1.6 }
    Overlay.modal: Rectangle { color: Theme.dark ? "#66000000" : "#33000000" }

    property string kind: "event"          // event | todo
    property string uid: ""                 // 空 = 新建
    readonly property bool isNew: uid === ""
    readonly property var timeOptions: Cal.timeOptions()
    readonly property var writableCals: CalendarStore.calendars.filter(function (c) { return !c.readOnly })

    // 活动字段
    property var startDay: Cal.today()
    property var endDay: Cal.today()
    property int startMin: 540
    property int endMin: 600
    property bool allDay: false
    property string rrule: ""
    property int reminder: 10
    // 待办字段
    property bool hasDue: true
    property var dueDay: Cal.today()
    property string dueTime: ""
    property int priority: 0

    function calIndex(id) {
        for (var i = 0; i < writableCals.length; ++i) if (writableCals[i].id === id) return i
        return 0
    }
    function resetCommon(k, calId) {
        kind = k
        titleField.text = ""
        locationField.text = ""
        notesField.text = ""
        calCombo.currentIndex = calIndex(calId)
    }

    function openNew(startMs, endMs, isAllDay, k) {
        uid = ""
        resetCommon(k, k === "todo" ? CalendarStore.defaultTodoList() : CalendarStore.defaultCalendar())
        var s = new Date(startMs), e = new Date(endMs)
        allDay = isAllDay
        startDay = Cal.dayStart(s); startMin = Cal.minutesOfDay(s)
        if (isAllDay) { endDay = Cal.dayStart(e); endMin = startMin + 60 }
        else {
            // 结束在次日 0 点：显示为当天 24:00 → 用次日 00:00
            endDay = Cal.dayStart(e); endMin = Cal.minutesOfDay(e)
        }
        rrule = ""
        reminder = isAllDay ? -1 : 10
        hasDue = true; dueDay = Cal.dayStart(s); dueTime = ""; priority = 0
        open()
        titleField.forceActiveFocus()
    }
    function openEvent(item) {
        var full = CalendarStore.event(item.uid)   // 编辑整个系列：用系列的首个实例时间
        uid = item.uid
        resetCommon("event", item.calendarId)
        titleField.text = full.title === qsTr("（无标题）") ? "" : full.title
        locationField.text = full.location
        notesField.text = full.notes
        allDay = full.allDay
        var s = new Date(full.startMs), e = new Date(full.endMs)
        startDay = Cal.dayStart(s); startMin = Cal.minutesOfDay(s)
        if (allDay) { endDay = Cal.parseIso(full.lastIso); endMin = startMin + 60 }
        else { endDay = Cal.dayStart(e); endMin = Cal.minutesOfDay(e) }
        rrule = full.rrule
        reminder = full.reminder
        open()
    }
    function openTodo(item) {
        uid = item.uid
        resetCommon("todo", item.calendarId)
        titleField.text = item.title === qsTr("（无标题）") ? "" : item.title
        notesField.text = item.notes
        hasDue = item.dueIso !== ""
        dueDay = hasDue ? Cal.parseIso(item.dueIso) : Cal.today()
        dueTime = item.dueTime
        priority = item.priority
        open()
    }

    function save() {
        var calId = writableCals.length > 0 ? writableCals[calCombo.currentIndex].id : ""
        if (kind === "todo") {
            if (titleField.text.trim() === "") { titleField.forceActiveFocus(); return }
            var t = { title: titleField.text, notes: notesField.text, calendarId: calId, priority: priority,
                      dueIso: hasDue ? Cal.iso(dueDay) : "", dueTime: hasDue ? dueTime : "" }
            isNew ? CalendarStore.createTodo(t) : CalendarStore.updateTodo(uid, t)
        } else {
            var s = allDay ? startDay : Cal.at(startDay, startMin)
            var e = allDay ? endDay : Cal.at(endDay, endMin)
            if (!allDay && e <= s) e = new Date(s.getTime() + 3600000)
            if (allDay && e < s) e = s
            var m = { title: titleField.text, location: locationField.text, notes: notesField.text, calendarId: calId,
                      allDay: allDay, startMs: s.getTime(), endMs: e.getTime(), rrule: rrule, reminder: reminder }
            isNew ? CalendarStore.createEvent(m) : CalendarStore.updateEvent(uid, m)
        }
        close()
    }

    contentItem: ColumnLayout {
        spacing: 12

        // 标签页 + 关闭
        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                visible: ed.isNew
                implicitHeight: 30; implicitWidth: tabs.implicitWidth + 6; radius: 15
                color: Theme.surface
                Row {
                    id: tabs
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: [{ k: "event", t: qsTr("活动") }, { k: "todo", t: qsTr("待办") }]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: ed.kind === modelData.k
                            width: 64; height: 24; radius: 12
                            color: on ? Theme.card : "transparent"
                            Text { anchors.centerIn: parent; text: modelData.t; font.pixelSize: 12; font.bold: parent.on; color: parent.on ? Theme.accent : Theme.textSecondary }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { ed.kind = modelData.k; calCombo.currentIndex = ed.calIndex(modelData.k === "todo" ? CalendarStore.defaultTodoList() : CalendarStore.defaultCalendar()) } }
                        }
                    }
                }
            }
            Text {
                visible: !ed.isNew
                text: ed.kind === "todo" ? qsTr("编辑待办") : qsTr("编辑活动")
                font.pixelSize: 15; font.bold: true; color: Theme.text
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; font.pixelSize: 14; color: Theme.textTertiary
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: ed.close() }
            }
        }

        // 标题
        TextField {
            id: titleField
            objectName: "editorTitle"
            Layout.fillWidth: true
            placeholderText: ed.kind === "todo" ? qsTr("待办事项") : qsTr("添加标题")
            placeholderTextColor: Theme.textTertiary
            font.pixelSize: 20
            color: Theme.text
            leftPadding: 2
            background: Rectangle {
                y: parent.height - 2; width: parent.width; height: 2
                color: titleField.activeFocus ? Theme.accent : Theme.fieldBorder
            }
            onAccepted: ed.save()
        }

        // MARK: 活动
        GridLayout {
            visible: ed.kind === "event"
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12; rowSpacing: 10

            Text { text: "◷"; color: Theme.textTertiary; font.pixelSize: 15; Layout.alignment: Qt.AlignTop; Layout.topMargin: 6 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    spacing: 6
                    DatePickerButton {
                        date: ed.startDay
                        onPicked: (d) => {
                            var span = Math.round((ed.endDay - ed.startDay) / Cal.DAY_MS)
                            ed.startDay = d
                            ed.endDay = Cal.addDays(d, Math.max(0, span))
                        }
                    }
                    CalCombo {
                        visible: !ed.allDay
                        Layout.preferredWidth: 86
                        textRole: ""
                        model: ed.timeOptions
                        currentIndex: Math.floor(ed.startMin / 15)
                        onActivated: (i) => {
                            var dur = (ed.endDay - ed.startDay) / 60000 + ed.endMin - ed.startMin
                            ed.startMin = i * 15
                            var end = Cal.at(ed.startDay, ed.startMin + Math.max(15, dur))
                            ed.endDay = Cal.dayStart(end); ed.endMin = Cal.minutesOfDay(end)
                        }
                    }
                    Text { text: "–"; color: Theme.textSecondary }
                    CalCombo {
                        visible: !ed.allDay
                        Layout.preferredWidth: 86
                        textRole: ""
                        model: ed.timeOptions
                        currentIndex: Math.floor(ed.endMin / 15)
                        onActivated: (i) => ed.endMin = i * 15
                    }
                }
                RowLayout {
                    spacing: 6
                    visible: ed.allDay || !Cal.sameDay(ed.startDay, ed.endDay) || ed.endMin <= ed.startMin
                    Text { text: ed.allDay ? qsTr("至") : qsTr("结束日期"); color: Theme.textSecondary; font.pixelSize: 12 }
                    DatePickerButton { date: ed.endDay; onPicked: (d) => ed.endDay = d < ed.startDay ? ed.startDay : d }
                }
                RowLayout {
                    spacing: 14
                    CheckBox {
                        id: allDayBox
                        text: qsTr("全天")
                        checked: ed.allDay
                        onToggled: ed.allDay = checked
                        font.pixelSize: 12
                        contentItem: Text { leftPadding: allDayBox.indicator.width + 6; text: allDayBox.text; font: allDayBox.font; color: Theme.text; verticalAlignment: Text.AlignVCenter }
                    }
                    CalCombo {
                        Layout.preferredWidth: 220
                        model: {
                            var opts = Cal.repeatOptions(ed.startDay)
                            if (ed.rrule !== "" && !opts.some(function (o) { return o.rrule === ed.rrule }))
                                opts.push({ label: qsTr("%1（自定义）").arg(CalendarStore.describeRule(ed.rrule)), rrule: ed.rrule })
                            return opts
                        }
                        currentIndex: { for (var i = 0; i < model.length; ++i) if (model[i].rrule === ed.rrule) return i; return 0 }
                        onActivated: (i) => ed.rrule = model[i].rrule
                    }
                }
            }

            Text { text: "♪"; color: Theme.textTertiary; font.pixelSize: 15 }
            CalCombo {
                Layout.preferredWidth: 160
                model: Cal.reminderOptions()
                currentIndex: { for (var i = 0; i < model.length; ++i) if (model[i].value === ed.reminder) return i; return 0 }
                onActivated: (i) => ed.reminder = model[i].value
            }

            Text { text: "⌖"; color: Theme.textTertiary; font.pixelSize: 15 }
            CalTextField { id: locationField; Layout.fillWidth: true; placeholderText: qsTr("添加地点") }
        }

        // MARK: 待办
        GridLayout {
            visible: ed.kind === "todo"
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12; rowSpacing: 10

            Text { text: "◷"; color: Theme.textTertiary; font.pixelSize: 15 }
            RowLayout {
                spacing: 8
                CheckBox {
                    id: dueBox
                    text: qsTr("截止")
                    checked: ed.hasDue
                    onToggled: ed.hasDue = checked
                    font.pixelSize: 12
                    contentItem: Text { leftPadding: dueBox.indicator.width + 6; text: dueBox.text; font: dueBox.font; color: Theme.text; verticalAlignment: Text.AlignVCenter }
                }
                DatePickerButton { enabled: ed.hasDue; date: ed.dueDay; onPicked: (d) => ed.dueDay = d }
                CalCombo {
                    enabled: ed.hasDue
                    Layout.preferredWidth: 96
                    textRole: ""
                    model: [qsTr("无时间")].concat(ed.timeOptions)
                    currentIndex: ed.dueTime === "" ? 0 : ed.timeOptions.indexOf(ed.dueTime) + 1
                    onActivated: (i) => ed.dueTime = i === 0 ? "" : ed.timeOptions[i - 1]
                }
            }
            Text { text: "!"; color: Theme.textTertiary; font.pixelSize: 15; font.bold: true; Layout.leftMargin: 4 }
            RowLayout {
                spacing: 6
                Text { text: qsTr("优先级"); color: Theme.textSecondary; font.pixelSize: 12 }
                Repeater {
                    model: Cal.priorityOptions()
                    Rectangle {
                        required property var modelData
                        readonly property bool on: ed.priority === modelData.value
                        width: 44; height: 26; radius: 13
                        color: on ? Theme.accent : Theme.surface
                        Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 12; color: parent.on ? Theme.accentText : Theme.textSecondary }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.priority = modelData.value }
                    }
                }
            }
        }

        // 日历 + 备注（共用）
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text { text: "▣"; color: Theme.textTertiary; font.pixelSize: 15 }
            CalCombo {
                id: calCombo
                Layout.fillWidth: true
                model: ed.writableCals
                textRole: "name"
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: calCombo.popup.width
                    height: 28
                    contentItem: Row {
                        spacing: 8
                        Rectangle { width: 10; height: 10; radius: 5; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.name; font.pixelSize: 12; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    }
                    background: Rectangle { color: calCombo.highlightedIndex === index ? Theme.hover : "transparent"; radius: 6 }
                }
                Rectangle {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: ed.writableCals.length > 0 ? ed.writableCals[calCombo.currentIndex].color : "transparent"
                }
                contentItem: Text {
                    leftPadding: 28
                    text: calCombo.displayText
                    font: calCombo.font
                    color: Theme.text
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text { text: "≡"; color: Theme.textTertiary; font.pixelSize: 15; Layout.alignment: Qt.AlignTop; Layout.topMargin: 8 }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                TextArea {
                    id: notesField
                    placeholderText: qsTr("添加备注")
                    placeholderTextColor: Theme.textTertiary
                    color: Theme.text
                    font.pixelSize: 12
                    wrapMode: TextArea.Wrap
                    background: Rectangle { radius: 8; color: Theme.input; border.width: 1; border.color: notesField.activeFocus ? Theme.accent : Theme.fieldBorder }
                }
            }
        }

        Text {
            visible: !ed.isNew && ed.kind === "event" && ed.rrule !== ""
            text: qsTr("修改将应用到整个重复系列")
            font.pixelSize: 11
            color: Theme.textTertiary
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            MacButton {
                visible: !ed.isNew
                text: qsTr("删除")
                onClicked: {
                    ed.kind === "todo" ? CalendarStore.deleteTodo(ed.uid) : CalendarStore.deleteEvent(ed.uid)
                    ed.close()
                }
            }
            Item { Layout.fillWidth: true }
            MacButton { text: qsTr("取消"); onClicked: ed.close() }
            MacButton { objectName: "editorSave"; text: qsTr("保存"); primary: true; onClicked: ed.save() }
        }
    }
}
