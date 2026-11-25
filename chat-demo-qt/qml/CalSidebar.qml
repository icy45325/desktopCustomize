import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 日历侧栏：创建按钮、迷你月历、「我的日历」「订阅日历」两组（勾选显示/隐藏、右键菜单）、视图选项。
Item {
    id: side
    property var calendarView

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        anchors.rightMargin: 6
        spacing: 12

        RowLayout {
            Layout.leftMargin: 4
            Text { text: qsTr("日历"); font.pixelSize: 22; font.bold: true; color: Theme.text; Layout.fillWidth: true }
            MacButton {
                circular: true
                text: Theme.dark ? "☀" : "☾"
                font.pixelSize: 15
                onClicked: Theme.toggle()
                ToolTip.visible: hovered; ToolTip.text: qsTr("切换主题（⌘⇧D）"); ToolTip.delay: 600
            }
        }

        // 创建（Google 的「＋ 创建」：活动 / 待办）
        MacButton {
            id: createBtn
            objectName: "createButton"
            primary: true
            Layout.fillWidth: true
            implicitHeight: 36
            text: qsTr("＋  创建")
            onClicked: createMenu.popup(createBtn, 0, createBtn.height + 4)
            Menu {
                id: createMenu
                MenuItem { text: qsTr("活动（C）"); onTriggered: side.calendarView.createAt() }
                MenuItem { text: qsTr("全天活动"); onTriggered: { var d = side.calendarView.anchorDate; side.calendarView.createAt(d.getTime(), d.getTime(), true) } }
                MenuItem { text: qsTr("待办"); onTriggered: side.calendarView.createAt(null, null, false, "todo") }
                MenuSeparator {}
                MenuItem { text: qsTr("新建日历…"); onTriggered: newCalPopup.open() }
                MenuItem { text: qsTr("订阅日历…"); onTriggered: side.calendarView.openSubscribe() }
            }
        }

        MiniMonth {
            id: mini
            objectName: "sidebarMiniMonth"
            Layout.fillWidth: true
            cell: 27
            selected: side.calendarView.anchorDate
            rangeStart: side.calendarView.mode === "week" ? side.calendarView.rangeStart : null
            rangeEnd: side.calendarView.mode === "week" ? Cal.addDays(side.calendarView.rangeStart, 7) : null
            onPicked: (d) => side.calendarView.anchorDate = d
            Connections {
                target: side.calendarView
                function onAnchorDateChanged() {
                    if (!Cal.sameMonth(mini.month, side.calendarView.anchorDate)) mini.month = side.calendarView.anchorDate
                }
            }
        }

        // 日历列表
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: lists.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: lists
                width: parent.width - 8
                spacing: 2

                component SectionHeader: RowLayout {
                    id: sh
                    property string text
                    property string tip
                    signal add()
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.leftMargin: 4
                    Text { text: sh.text; font.pixelSize: 11; font.bold: true; color: Theme.textTertiary; Layout.fillWidth: true }
                    Text {
                        visible: sh.tip !== ""
                        text: qsTr("＋"); font.pixelSize: 14; color: addMa.containsMouse ? Theme.accent : Theme.textTertiary
                        MouseArea { id: addMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.add() }
                        ToolTip.visible: addMa.containsMouse; ToolTip.text: sh.tip; ToolTip.delay: 500
                    }
                }

                component CalRow: Item {
                    id: row
                    property var cal
                    Layout.fillWidth: true
                    implicitHeight: 30
                    objectName: "calRow-" + cal.id
                    Rectangle { anchors.fill: parent; radius: 8; color: rowMa.containsMouse ? Theme.hover : "transparent" }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6; anchors.rightMargin: 6
                        spacing: 8
                        // 彩色方形勾选框（macOS / Google 一致）
                        Rectangle {
                            width: 16; height: 16; radius: 4
                            color: row.cal.visible ? row.cal.color : "transparent"
                            border.width: 2; border.color: row.cal.color
                            Text { anchors.centerIn: parent; visible: row.cal.visible; text: "✓"; color: "white"; font.pixelSize: 11; font.bold: true }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.cal.name
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: row.cal.visible ? Theme.text : Theme.textTertiary
                        }
                        // 订阅状态：同步中 / 出错 / 只读
                        Text {
                            visible: row.cal.kind === "subscription"
                            text: row.cal.syncing ? "⟳" : (row.cal.lastError !== "" ? "⚠" : "⇣")
                            color: row.cal.lastError !== "" ? Theme.danger : Theme.textTertiary
                            font.pixelSize: 12
                            RotationAnimation on rotation { running: row.cal.syncing; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) calMenu.popup()
                            else CalendarStore.setCalendarVisible(row.cal.id, !row.cal.visible)
                        }
                    }
                    ToolTip.visible: rowMa.containsMouse && row.cal.kind === "subscription"
                    ToolTip.delay: 700
                    ToolTip.text: row.cal.url + "\n" + (row.cal.lastError !== "" ? qsTr("刷新失败：%1").arg(row.cal.lastError)
                                                       : row.cal.lastSync !== "" ? qsTr("上次同步 %1").arg(row.cal.lastSync) : qsTr("尚未同步")) + qsTr("\n只读 · 右键可刷新 / 修改")
                    Menu {
                        id: calMenu
                        MenuItem { text: qsTr("仅显示此日历"); onTriggered: { var cs = CalendarStore.calendars; for (var i = 0; i < cs.length; ++i) CalendarStore.setCalendarVisible(cs[i].id, cs[i].id === row.cal.id) } }
                        MenuItem { text: qsTr("立即刷新"); visible: row.cal.kind === "subscription"; height: visible ? implicitHeight : 0; onTriggered: CalendarStore.refresh(row.cal.id) }
                        MenuItem { text: qsTr("编辑订阅…"); visible: row.cal.kind === "subscription"; height: visible ? implicitHeight : 0; onTriggered: side.calendarView.openSubscribe(row.cal.id) }
                        MenuItem { text: qsTr("重命名…"); visible: row.cal.kind === "local"; height: visible ? implicitHeight : 0; onTriggered: { renamePopup.calId = row.cal.id; renameField.text = row.cal.name; renamePopup.open() } }
                        MenuItem { text: qsTr("导出为 .ics"); visible: row.cal.kind === "local"; height: visible ? implicitHeight : 0
                            onTriggered: { var p = CalendarStore.exportCalendar(row.cal.id); toast.show(p !== "" ? qsTr("已导出到 %1").arg(p) : qsTr("导出失败")) } }
                        Menu {
                            title: qsTr("颜色")
                            enabled: row.cal.kind !== "builtin"
                            Repeater {
                                model: CalendarStore.palette()
                                MenuItem {
                                    required property string modelData
                                    text: (modelData === row.cal.color ? "✓ " : "    ") + "●"
                                    contentItem: Row {
                                        spacing: 8
                                        Rectangle { width: 14; height: 14; radius: 7; color: modelData; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: modelData === row.cal.color ? qsTr("当前") : ""; color: Theme.textSecondary; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    onTriggered: CalendarStore.setCalendarColor(row.cal.id, modelData)
                                }
                            }
                        }
                        MenuSeparator {}
                        MenuItem {
                            text: row.cal.kind === "builtin" ? qsTr("移除") : row.cal.kind === "subscription" ? qsTr("取消订阅") : qsTr("删除日历")
                            // 内置日历：移除 = 关掉设置里对应的开关，随时可再打开，无需确认
                            onTriggered: {
                                if (row.cal.kind === "builtin") { CalendarStore.removeCalendar(row.cal.id); return }
                                confirmRemove.calId = row.cal.id; confirmRemove.calName = row.cal.name; confirmRemove.open()
                            }
                        }
                    }
                }

                SectionHeader { text: qsTr("我的日历"); tip: qsTr("新建日历"); onAdd: newCalPopup.open() }
                Repeater {
                    model: CalendarStore.calendars.filter(function (c) { return c.kind === "local" })
                    CalRow { required property var modelData; cal: modelData }
                }
                SectionHeader { text: qsTr("订阅日历"); tip: qsTr("通过 URL 订阅（Google / iCloud / Outlook 的 .ics 链接）"); onAdd: side.calendarView.openSubscribe() }
                Repeater {
                    model: CalendarStore.calendars.filter(function (c) { return c.kind === "subscription" })
                    CalRow { required property var modelData; cal: modelData }
                }
                Text {
                    visible: CalendarStore.calendars.filter(function (c) { return c.kind === "subscription" }).length === 0
                    Layout.leftMargin: 6
                    text: qsTr("还没有订阅。点 ＋ 粘贴 .ics / webcal 链接")
                    font.pixelSize: 11; color: Theme.textTertiary
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // 其他日历（同 Google「Other calendars」）：内置的阿联酋公共假日 / 伊斯兰节日，＋ 打开设置里的日历页
                SectionHeader { text: qsTr("其他日历"); tip: qsTr("添加节假日 / 伊斯兰节日日历"); onAdd: WindowManager.openSettings("calendar") }
                Repeater {
                    model: CalendarStore.calendars.filter(function (c) { return c.kind === "builtin" })
                    CalRow { required property var modelData; cal: modelData }
                }
                Text {
                    visible: !CalendarStore.showUaeHolidays && !CalendarStore.showIslamicHolidays
                    Layout.leftMargin: 6
                    Layout.fillWidth: true
                    text: qsTr("点 ＋ 添加阿联酋公共假日、伊斯兰节日")
                    font.pixelSize: 11; color: Theme.textTertiary
                    wrapMode: Text.Wrap
                }

                SectionHeader { text: qsTr("选项"); tip: ""; Layout.topMargin: 14 }
                component OptionRow: Item {
                    id: opt
                    property string text
                    property bool checked
                    signal toggled()
                    Layout.fillWidth: true
                    implicitHeight: 26
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 6
                        spacing: 8
                        Rectangle {
                            width: 14; height: 14; radius: 4
                            color: opt.checked ? Theme.accent : "transparent"
                            border.width: 1.5; border.color: opt.checked ? Theme.accent : Theme.textTertiary
                            Text { anchors.centerIn: parent; visible: opt.checked; text: "✓"; color: Theme.accentText; font.pixelSize: 10; font.bold: true }
                        }
                        Text { text: opt.text; font.pixelSize: 12; color: Theme.textSecondary; Layout.fillWidth: true }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: opt.toggled() }
                }
                OptionRow { text: qsTr("显示周末"); checked: CalendarStore.showWeekends; onToggled: CalendarStore.showWeekends = !CalendarStore.showWeekends }
                OptionRow { text: qsTr("在日历中显示待办"); checked: CalendarStore.showTodos; onToggled: CalendarStore.showTodos = !CalendarStore.showTodos }
                OptionRow { text: qsTr("显示已完成的待办"); checked: CalendarStore.showCompleted; onToggled: CalendarStore.showCompleted = !CalendarStore.showCompleted }
                OptionRow { text: qsTr("每周从周一开始"); checked: CalendarStore.weekStartsMonday; onToggled: CalendarStore.weekStartsMonday = !CalendarStore.weekStartsMonday }

                Text {
                    Layout.topMargin: 10
                    Layout.leftMargin: 6
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("快捷键：T 今天 · D/W/M/Y/A 切换视图 · J/K 翻页 · C 新建 · / 搜索")
                    font.pixelSize: 10
                    color: Theme.textTertiary
                }
            }
        }
    }

    // MARK: 小弹窗

    component SmallDialog: Popup {
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: 18
        width: 320
        background: Card { radius: 14; color: Theme.popup; elevation: 1.4 }
        Overlay.modal: Rectangle { color: Theme.dark ? "#66000000" : "#33000000" }
    }

    SmallDialog {
        id: newCalPopup
        property string color: CalendarStore.palette()[CalendarStore.calendars.length % 8]
        onAboutToShow: { newCalName.text = ""; newCalName.forceActiveFocus() }
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text { text: qsTr("新建日历"); font.pixelSize: 15; font.bold: true; color: Theme.text }
            CalTextField { id: newCalName; Layout.fillWidth: true; placeholderText: qsTr("日历名称"); onAccepted: createCal() }
            Row {
                spacing: 8
                Repeater {
                    model: CalendarStore.palette()
                    Rectangle {
                        required property string modelData
                        width: 22; height: 22; radius: 11; color: modelData
                        border.width: newCalPopup.color === modelData ? 3 : 0; border.color: Theme.text
                        MouseArea { anchors.fill: parent; onClicked: newCalPopup.color = parent.modelData }
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                MacButton { text: qsTr("取消"); onClicked: newCalPopup.close() }
                MacButton { text: qsTr("创建"); primary: true; enabled: newCalName.text.trim() !== ""; onClicked: createCal() }
            }
        }
        function createCal() {
            if (newCalName.text.trim() === "") return
            CalendarStore.addCalendar(newCalName.text, color)
            close()
        }
    }

    SmallDialog {
        id: renamePopup
        property string calId
        onOpened: renameField.forceActiveFocus()
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text { text: qsTr("重命名日历"); font.pixelSize: 15; font.bold: true; color: Theme.text }
            CalTextField { id: renameField; Layout.fillWidth: true; onAccepted: { CalendarStore.renameCalendar(renamePopup.calId, text); renamePopup.close() } }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                MacButton { text: qsTr("取消"); onClicked: renamePopup.close() }
                MacButton { text: qsTr("保存"); primary: true; onClicked: { CalendarStore.renameCalendar(renamePopup.calId, renameField.text); renamePopup.close() } }
            }
        }
    }

    SmallDialog {
        id: confirmRemove
        property string calId
        property string calName
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text { text: qsTr("删除「%1」？").arg(confirmRemove.calName); font.pixelSize: 15; font.bold: true; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: confirmRemove.calId.indexOf("sub-") === 0 ? qsTr("取消订阅后，该日历的活动将不再显示。可随时重新订阅。")
                                                              : qsTr("日历中的所有活动和待办都会被删除，且无法恢复。")
                font.pixelSize: 12; color: Theme.textSecondary
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                MacButton { text: qsTr("取消"); onClicked: confirmRemove.close() }
                MacButton { text: qsTr("删除"); primary: true; onClicked: { CalendarStore.removeCalendar(confirmRemove.calId); confirmRemove.close() } }
            }
        }
    }

    // 轻提示
    Rectangle {
        id: toast
        parent: Overlay.overlay
        visible: opacity > 0
        opacity: 0
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        y: parent ? parent.height - 70 : 0
        width: Math.min(toastText.implicitWidth + 32, 520); height: 34; radius: 17
        color: Theme.dark ? "#E62A2F3A" : "#E61F1D2B"
        Text { id: toastText; anchors.centerIn: parent; width: parent.width - 24; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter; color: "white"; font.pixelSize: 12 }
        function show(t) { toastText.text = t; opacity = 1; toastTimer.restart() }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Timer { id: toastTimer; interval: 3000; onTriggered: toast.opacity = 0 }
    }
}
