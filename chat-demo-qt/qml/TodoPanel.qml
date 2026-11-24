import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 右侧待办面板（Google Tasks 侧栏 + macOS 提醒事项的智能列表）：
// 今天（含逾期）/ 计划 / 全部 / 已完成；顶部快速添加；按「逾期 / 今天 / 明天 / 以后 / 无日期」分组。
Item {
    id: tp
    objectName: "todoPanel"
    property string filter: "today"

    readonly property var rows: {
        CalendarStore.revision
        var list = CalendarStore.todos(filter)
        var out = [], last = ""
        var t = Cal.iso(Cal.today()), tm = Cal.iso(Cal.addDays(Cal.today(), 1))
        for (var i = 0; i < list.length; ++i) {
            var it = list[i], g
            if (filter === "completed") g = qsTr("已完成")
            else if (it.dueIso === "") g = qsTr("无日期")
            else if (it.dueIso < t) g = qsTr("已逾期")
            else if (it.dueIso === t) g = qsTr("今天")
            else if (it.dueIso === tm) g = qsTr("明天")
            else g = qsTr("以后")
            out.push({ group: g, first: g !== last, item: it })
            last = g
        }
        return out
    }
    function count(f) { CalendarStore.revision; return CalendarStore.todos(f).length }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 智能列表（2 × 2 卡片，同 macOS 提醒事项）
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8; rowSpacing: 8
            Repeater {
                model: [{ k: "today", t: qsTr("今天"), g: "◉" }, { k: "scheduled", t: qsTr("计划"), g: "▦" },
                        { k: "all", t: qsTr("全部"), g: "☰" }, { k: "completed", t: qsTr("已完成"), g: "✓" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: tp.filter === modelData.k
                    objectName: "todoFilter-" + modelData.k
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 12
                    color: on ? Theme.accent : Theme.surface
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text { x: 10; y: 8; text: modelData.g; font.pixelSize: 15; color: parent.on ? Theme.accentText : Theme.accent }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 10; y: 6
                        text: tp.count(modelData.k)
                        font.pixelSize: 18; font.bold: true
                        color: parent.on ? Theme.accentText : Theme.text
                    }
                    Text { x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 7; text: modelData.t; font.pixelSize: 12; font.bold: true
                        color: parent.on ? Theme.accentText : Theme.textSecondary }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tp.filter = modelData.k }
                }
            }
        }

        // 快速添加：回车保存。「今天」列表里添加的待办默认截止今天
        Rectangle {
            Layout.fillWidth: true
            visible: tp.filter !== "completed"
            implicitHeight: 34
            radius: 10
            color: Theme.input
            border.width: 1
            border.color: quickAdd.activeFocus ? Theme.accent : Theme.fieldBorder
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 6
                spacing: 6
                Text { text: qsTr("＋"); color: Theme.accent; font.pixelSize: 14 }
                TextField {
                    id: quickAdd
                    objectName: "todoQuickAdd"
                    Layout.fillWidth: true
                    background: null
                    placeholderText: tp.filter === "today" ? qsTr("添加今天的待办，回车保存") : qsTr("添加待办，回车保存")
                    placeholderTextColor: Theme.textTertiary
                    color: Theme.text
                    font.pixelSize: 12
                    onAccepted: {
                        if (text.trim() === "") return
                        var m = { title: text, calendarId: CalendarStore.defaultTodoList() }
                        if (tp.filter === "today" || tp.filter === "scheduled") m.dueIso = Cal.iso(Cal.today())
                        CalendarStore.createTodo(m)
                        text = ""
                    }
                }
                Text {
                    text: "⋯"; font.pixelSize: 14; color: moreMa.containsMouse ? Theme.accent : Theme.textTertiary
                    MouseArea { id: moreMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { WindowManager.focusCalendar(); CalendarStore.requestCreate("todo") } }
                    ToolTip.visible: moreMa.containsMouse; ToolTip.text: qsTr("更多选项（截止时间、优先级、备注）"); ToolTip.delay: 500
                }
            }
        }

        ListView {
            id: lv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: tp.rows
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Column {
                id: row
                required property var modelData
                readonly property var it: modelData.item
                width: lv.width
                spacing: 2

                Text {
                    visible: row.modelData.first
                    topPadding: 8; bottomPadding: 2; leftPadding: 4
                    text: row.modelData.group
                    font.pixelSize: 11; font.bold: true
                    color: row.modelData.group === qsTr("已逾期") ? Theme.danger : Theme.textTertiary
                }
                Rectangle {
                    width: parent.width
                    height: Math.max(40, content.implicitHeight + 14)
                    radius: 10
                    color: rowMa.containsMouse ? Theme.hover : "transparent"
                    objectName: "todoRow"

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { WindowManager.focusCalendar(); CalendarStore.requestOpen(row.it) }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6; anchors.rightMargin: 6
                        spacing: 10
                        CheckCircle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 9
                            size: 18
                            checked: row.it.done
                            color: row.it.color
                            readOnly: row.it.readOnly
                            onToggled: CalendarStore.toggleTodo(row.it.uid)
                        }
                        Column {
                            id: content
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                width: parent.width
                                text: (Cal.priorityMark(row.it.priority) !== "" ? Cal.priorityMark(row.it.priority) + " " : "") + row.it.title
                                font.pixelSize: 13
                                font.strikeout: row.it.done
                                color: row.it.done ? Theme.textTertiary : Theme.text
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: {
                                    var parts = []
                                    if (row.it.dueIso !== "") {
                                        var d = Cal.parseIso(row.it.dueIso)
                                        parts.push((Cal.relativeDay(d) || Cal.md(d)) + (row.it.dueTime !== "" ? " " + row.it.dueTime : ""))
                                    }
                                    if (row.it.notes !== "") parts.push(row.it.notes.split("\n")[0])
                                    return parts.join(" · ")
                                }
                                font.pixelSize: 11
                                color: row.it.overdue ? Theme.danger : Theme.textSecondary
                                elide: Text.ElideRight
                            }
                            Row {
                                spacing: 4
                                Rectangle { width: 6; height: 6; radius: 3; color: row.it.color; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: row.it.calendarName + (row.it.readOnly ? qsTr(" · 只读") : ""); font.pixelSize: 10; color: Theme.textTertiary }
                            }
                        }
                        Text {
                            visible: rowMa.containsMouse && !row.it.readOnly
                            text: "✕"
                            font.pixelSize: 11
                            color: delMa.containsMouse ? Theme.danger : Theme.textTertiary
                            MouseArea { id: delMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: CalendarStore.deleteTodo(row.it.uid) }
                        }
                    }
                }
            }
        }

        Text {
            visible: tp.rows.length === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 40
            text: tp.filter === "today" ? qsTr("今天没有待办 🎉") : tp.filter === "completed" ? qsTr("还没有完成的待办") : qsTr("没有待办")
            color: Theme.textSecondary
            font.pixelSize: 12
        }
    }
}
