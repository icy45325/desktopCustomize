import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 事件 / 待办详情气泡（点击条目后出现在旁边，同 Google 的快速查看卡片）。
Popup {
    id: pop
    property var calendarView
    property var item: null
    readonly property bool isTodo: item !== null && item.type === "todo"
    parent: Overlay.overlay
    width: 340
    padding: 18
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Card { radius: 16; color: Theme.popup; elevation: 1.5 }

    function show(it, px, py) {
        item = it
        confirmRow.visible = false
        // 尽量放在点击位置右侧；放不下就放左侧，并保持在窗口内
        var W = parent.width, H = parent.height
        var p = parent.mapFromItem(calendarView, px, py)
        x = p.x + 16 + width < W ? p.x + 16 : Math.max(8, p.x - width - 16)
        open()
        y = Math.max(8, Math.min(p.y - 40, H - implicitHeight - 8))
    }

    // 订阅数据刷新后，条目可能已被删除或改变
    Connections {
        target: CalendarStore
        function onChanged() {
            if (!pop.opened || pop.item === null) return
            if (pop.isTodo) {
                var t = CalendarStore.todo(pop.item.uid)
                if (t.uid === undefined) pop.close(); else pop.item = t
            } else if (CalendarStore.event(pop.item.uid).uid === undefined) pop.close()
        }
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            spacing: 10
            Item {
                Layout.preferredWidth: 18; Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                Rectangle { visible: !pop.isTodo; anchors.fill: parent; radius: 5; color: pop.item ? pop.item.color : "transparent" }
                CheckCircle {
                    visible: pop.isTodo
                    anchors.fill: parent
                    checked: pop.isTodo && pop.item.done
                    color: pop.item ? pop.item.color : Theme.accent
                    readOnly: pop.item ? pop.item.readOnly : true
                    onToggled: CalendarStore.toggleTodo(pop.item.uid)
                }
            }
            Text {
                Layout.fillWidth: true
                text: pop.item ? pop.item.title : ""
                font.pixelSize: 17; font.bold: true
                font.strikeout: pop.isTodo && pop.item.done
                color: Theme.text
                wrapMode: Text.Wrap
            }
        }

        component InfoRow: RowLayout {
            property string icon
            property string text
            property color textColor: Theme.textSecondary
            visible: text !== ""
            spacing: 10
            Layout.fillWidth: true
            Text { text: parent.icon; font.pixelSize: 13; color: Theme.textTertiary; Layout.preferredWidth: 18; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignTop }
            Text { text: parent.text; font.pixelSize: 12; color: parent.textColor; wrapMode: Text.Wrap; Layout.fillWidth: true; textFormat: Text.PlainText }
        }

        InfoRow {
            icon: "◷"
            text: !pop.item ? "" : pop.isTodo
                  ? (pop.item.dueIso === "" ? qsTr("无截止日期") : qsTr("截止 %1").arg(Cal.dayTitle(Cal.parseIso(pop.item.dueIso)) + (pop.item.dueTime !== "" ? " " + pop.item.dueTime : "")) + (pop.item.overdue ? qsTr("（已逾期）") : ""))
                  : Cal.rangeText(pop.item)
            textColor: pop.isTodo && pop.item && pop.item.overdue ? Theme.danger : Theme.text
        }
        InfoRow { icon: "↻"; text: pop.item && !pop.isTodo && pop.item.recurring ? CalendarStore.describeRule(pop.item.rrule) : "" }
        InfoRow { icon: "!"; text: pop.isTodo && pop.item.priority > 0 ? qsTr("优先级：%1").arg(Cal.priorityName(pop.item.priority)) : "" }
        InfoRow { icon: "⌖"; text: pop.item && !pop.isTodo ? pop.item.location : "" }
        InfoRow {
            icon: "♪"
            text: !pop.item || pop.isTodo || pop.item.reminder < 0 ? ""
                  : Cal.reminderOptions().filter(function (o) { return o.value === pop.item.reminder })
                        .map(function (o) { return qsTr("提醒：%1").arg(o.label) })[0] || qsTr("提醒：提前 %1 分钟").arg(pop.item.reminder)
        }
        InfoRow { icon: "≡"; text: pop.item ? pop.item.notes : "" }
        InfoRow { icon: "⇗"; text: pop.item && pop.item.url ? pop.item.url : "" }
        InfoRow {
            icon: "▣"
            text: pop.item ? pop.item.calendarName + (pop.item.readOnly ? qsTr(" · 订阅日历（只读）") : "") : ""
        }

        // 操作
        RowLayout {
            id: actions
            visible: pop.item !== null && !pop.item.readOnly && !confirmRow.visible
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Item { Layout.fillWidth: true }
            MacButton {
                text: qsTr("删除")
                onClicked: {
                    if (!pop.isTodo && pop.item.recurring) { confirmRow.visible = true; return }
                    pop.isTodo ? CalendarStore.deleteTodo(pop.item.uid) : CalendarStore.deleteEvent(pop.item.uid)
                    pop.close()
                }
            }
            MacButton {
                text: qsTr("编辑")
                primary: true
                objectName: "detailEdit"
                onClicked: { var it = pop.item; pop.close(); pop.calendarView.editItem(it) }
            }
        }
        // 重复事件删除：仅此次 / 整个系列
        RowLayout {
            id: confirmRow
            visible: false
            Layout.fillWidth: true
            spacing: 8
            Text { text: qsTr("删除重复活动："); font.pixelSize: 12; color: Theme.textSecondary; Layout.fillWidth: true }
            MacButton { text: qsTr("仅此次"); onClicked: { CalendarStore.deleteEvent(pop.item.uid, "this", pop.item.startMs); pop.close() } }
            MacButton { text: qsTr("所有"); primary: true; onClicked: { CalendarStore.deleteEvent(pop.item.uid, "all"); pop.close() } }
        }
    }
}
