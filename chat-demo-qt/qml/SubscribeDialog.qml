import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 订阅日历：粘贴 .ics / webcal 链接（Google「iCal 格式的公开 / 私密地址」、iCloud 公开日历、Outlook 发布的 ICS）。
// 也可以选本地 .ics 文件路径。订阅日历只读，按设定间隔自动刷新。
Popup {
    id: dlg
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 480
    modal: true
    focus: true
    padding: 20
    background: Card { radius: 18; color: Theme.popup; elevation: 1.6 }
    Overlay.modal: Rectangle { color: Theme.dark ? "#66000000" : "#33000000" }

    property string editId: ""          // 非空 = 编辑已有订阅
    property string color: CalendarStore.palette()[4]
    property string pendingId: ""
    property string status: ""
    property bool failed: false

    readonly property var refreshOptions: [
        { label: qsTr("每 15 分钟"), value: 15 }, { label: qsTr("每小时"), value: 60 }, { label: qsTr("每 6 小时"), value: 360 },
        { label: qsTr("每天"), value: 1440 }, { label: qsTr("不自动刷新"), value: 0 }
    ]
    readonly property var presets: [
        { label: qsTr("示例：团队公共日历（内置）"), url: "qrc:/qt/qml/ChatDemo/data/team-sample.ics" },
        { label: qsTr("中国节假日（Google 公共日历）"), url: "https://calendar.google.com/calendar/ical/zh-cn.china%23holiday%40group.v.calendar.google.com/public/basic.ics" }
    ]

    function openFor(id) {
        editId = id
        status = ""; failed = false; pendingId = ""
        if (id !== "") {
            var cs = CalendarStore.calendars
            for (var i = 0; i < cs.length; ++i) if (cs[i].id === id) {
                urlField.text = cs[i].url
                nameField.text = cs[i].name
                color = cs[i].color
                for (var j = 0; j < refreshOptions.length; ++j) if (refreshOptions[j].value === cs[i].refreshMinutes) refreshCombo.currentIndex = j
            }
        } else {
            urlField.text = ""
            nameField.text = ""
            refreshCombo.currentIndex = 1
            color = CalendarStore.palette()[(CalendarStore.calendars.length + 3) % 8]
        }
        open()
        urlField.forceActiveFocus()
    }

    function submit() {
        var url = urlField.text.trim()
        if (url === "") { urlField.forceActiveFocus(); return }
        var minutes = refreshOptions[refreshCombo.currentIndex].value
        if (editId !== "") {
            CalendarStore.updateSubscription(editId, url, minutes)
            if (nameField.text.trim() !== "") CalendarStore.renameCalendar(editId, nameField.text)
            CalendarStore.setCalendarColor(editId, color)
            close()
            return
        }
        failed = false
        status = qsTr("正在订阅…")
        pendingId = "?"   // 本地文件会同步完成，先占位以接收 syncFinished
        var id = CalendarStore.subscribe(url, nameField.text, color, minutes)
        if (pendingId === "?") {
            // 网络订阅：等待 syncFinished；已订阅过的同一地址直接关闭
            var syncing = CalendarStore.calendars.some(function (c) { return c.id === id && c.syncing })
            if (syncing) pendingId = id
            else { pendingId = ""; status = ""; close() }
        }
    }

    Connections {
        target: CalendarStore
        function onSyncFinished(id, ok, error) {
            if (dlg.pendingId !== "?" && dlg.pendingId !== id) return
            dlg.pendingId = ""
            if (ok) { dlg.status = ""; dlg.close() }
            else { dlg.failed = true; dlg.status = qsTr("已添加，但首次同步失败：%1（可稍后在列表里右键「立即刷新」）").arg(error) }
        }
    }

    contentItem: ColumnLayout {
        spacing: 12

        Text { text: dlg.editId !== "" ? qsTr("编辑订阅") : qsTr("订阅日历"); font.pixelSize: 17; font.bold: true; color: Theme.text }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("粘贴日历的 iCal（.ics）地址：Google 日历 → 设置 → 某个日历 →「iCal 格式的公开 / 私密地址」；macOS / iCloud 日历 → 共享 →「公开日历」；Outlook → 发布日历 → ICS。也支持 webcal:// 和本地 .ics 文件路径。")
            font.pixelSize: 11
            color: Theme.textSecondary
            lineHeight: 1.2
        }

        CalTextField {
            id: urlField
            objectName: "subscribeUrl"
            Layout.fillWidth: true
            placeholderText: qsTr("https://… 或 webcal://… 或 /path/to/calendar.ics")
            onAccepted: dlg.submit()
        }

        // 常用订阅
        Flow {
            visible: dlg.editId === ""
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: dlg.presets
                Rectangle {
                    required property var modelData
                    height: 24; width: pt.implicitWidth + 18; radius: 12
                    color: pma.containsMouse ? Theme.accentSoft : Theme.surface
                    Text { id: pt; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 11; color: Theme.accent }
                    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: urlField.text = modelData.url }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12; rowSpacing: 10
            Text { text: qsTr("名称"); color: Theme.textSecondary; font.pixelSize: 12 }
            CalTextField { id: nameField; Layout.fillWidth: true; placeholderText: qsTr("留空则使用日历自带的名称") }
            Text { text: qsTr("颜色"); color: Theme.textSecondary; font.pixelSize: 12 }
            Row {
                spacing: 8
                Repeater {
                    model: CalendarStore.palette()
                    Rectangle {
                        required property string modelData
                        width: 22; height: 22; radius: 11; color: modelData
                        border.width: dlg.color === modelData ? 3 : 0; border.color: Theme.text
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.color = parent.modelData }
                    }
                }
            }
            Text { text: qsTr("自动刷新"); color: Theme.textSecondary; font.pixelSize: 12 }
            CalCombo { id: refreshCombo; Layout.preferredWidth: 160; model: dlg.refreshOptions; currentIndex: 1 }
        }

        Text {
            visible: dlg.status !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: dlg.status
            font.pixelSize: 12
            color: dlg.failed ? Theme.danger : Theme.accent
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            MacButton { text: dlg.failed ? qsTr("关闭") : qsTr("取消"); onClicked: dlg.close() }
            MacButton {
                objectName: "subscribeSubmit"
                visible: !dlg.failed
                text: dlg.editId !== "" ? qsTr("保存") : qsTr("订阅")
                primary: true
                enabled: urlField.text.trim() !== "" && dlg.pendingId === ""
                onClicked: dlg.submit()
            }
        }
    }
}
