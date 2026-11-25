import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 设置（⌘, / 导航条 ⚙）：外观（浅色 / 深色 / 跟随系统）、界面语言（简体中文 / English）、日历偏好。
// 所有选项立即生效并持久化；语言切换后界面重建，草稿 / 选中会话 / 日历数据都保留。
Popup {
    id: dlg
    objectName: "settingsDialog"
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 460
    modal: true
    focus: true
    padding: 22
    background: Card { radius: 18; color: Theme.popup; elevation: 1.6 }
    Overlay.modal: Rectangle { color: Theme.dark ? "#66000000" : "#33000000" }

    // 迷你窗口预览（浅色 / 深色）
    component Preview: Rectangle {
        property bool darkLook
        radius: 7
        color: darkLook ? "#12151E" : "#F3EEFF"
        border.width: 1; border.color: darkLook ? "#2A2F3A" : "#E2DDF5"
        clip: true
        Rectangle { x: 6; y: 8; width: 18; height: parent.height - 16; radius: 3; color: parent.darkLook ? "#161A23" : "#FFFFFF" }
        Rectangle { x: 28; y: 8; width: parent.width - 34; height: parent.height - 16; radius: 3; color: parent.darkLook ? "#161A23" : "#FFFFFF" }
        Rectangle { x: 32; y: 14; width: 26; height: 6; radius: 3; color: parent.darkLook ? "#5EEAD4" : "#6C5CE7" }
        Rectangle { x: 32; y: 24; width: 40; height: 4; radius: 2; color: parent.darkLook ? "#3A3F4A" : "#E6E3F5" }
        Rectangle { x: 32; y: 32; width: 34; height: 4; radius: 2; color: parent.darkLook ? "#3A3F4A" : "#E6E3F5" }
    }

    component SectionTitle: Text {
        font.pixelSize: 12; font.bold: true
        color: Theme.textTertiary
        Layout.topMargin: 4
    }

    // 外观选项卡：小预览 + 名称
    component ThemeCard: Item {
        id: tc
        property string mode
        property string label
        readonly property bool on: Settings.themeMode === mode
        objectName: "themeOption-" + mode
        Layout.fillWidth: true
        implicitHeight: 104

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: ma.containsMouse ? Theme.hover : "transparent"
            border.width: tc.on ? 2 : 1
            border.color: tc.on ? Theme.accent : Theme.fieldBorder
        }
        Column {
            anchors.centerIn: parent
            spacing: 8
            // 迷你窗口预览；「跟随系统」左浅右深
            Item {
                width: 92; height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                Preview { anchors.fill: parent; darkLook: tc.mode === "dark"; visible: tc.mode !== "system" }
                Item {
                    anchors.fill: parent
                    visible: tc.mode === "system"
                    Preview { anchors.fill: parent; darkLook: false }
                    Item {
                        x: parent.width / 2; width: parent.width / 2; height: parent.height
                        clip: true
                        Preview { x: -parent.x; width: 92; height: 56; darkLook: true }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Rectangle {
                    width: 14; height: 14; radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    color: tc.on ? Theme.accent : "transparent"
                    border.width: tc.on ? 0 : 1.5; border.color: Theme.textTertiary
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.accentText; visible: tc.on }
                }
                Text { text: tc.label; font.pixelSize: 12; font.bold: tc.on; color: tc.on ? Theme.accent : Theme.text }
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Settings.themeMode = tc.mode }
    }

    // 语言选项：语言名用它本身的文字显示（不翻译），方便看不懂当前语言的人找到自己的语言
    component LangRow: Rectangle {
        id: lr
        property string lang
        property string name
        property string hint
        readonly property bool on: Settings.language === lang
        objectName: "langOption-" + lang
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 10
        color: on ? Theme.accentSoft : (lma.containsMouse ? Theme.hover : "transparent")
        border.width: on ? 1.5 : 1
        border.color: on ? Theme.accent : Theme.fieldBorder
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 14
            Text { text: lr.name; font.pixelSize: 13; font.bold: lr.on; color: lr.on ? Theme.accent : Theme.text }
            Text { text: lr.hint; font.pixelSize: 11; color: Theme.textTertiary; Layout.fillWidth: true }
            Text { visible: lr.on; text: "✓"; font.pixelSize: 14; font.bold: true; color: Theme.accent }
        }
        MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Settings.language = lr.lang }
    }

    component Toggle: Item {
        id: tg
        property string text
        property bool checked
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: 30
        RowLayout {
            anchors.fill: parent
            Text { text: tg.text; font.pixelSize: 13; color: Theme.text; Layout.fillWidth: true }
            Rectangle {   // 开关
                width: 36; height: 20; radius: 10
                color: tg.checked ? Theme.accent : Theme.surface
                border.width: tg.checked ? 0 : 1; border.color: Theme.fieldBorder
                Behavior on color { ColorAnimation { duration: 150 } }
                Rectangle {
                    width: 16; height: 16; radius: 8; y: 2
                    x: tg.checked ? parent.width - width - 2 : 2
                    color: "white"
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    property string page: "general"         // general | calendar

    // 分段选择（周末是哪两天、回历校正）
    component Segmented: Rectangle {
        id: sg
        property var options: []             // [{v, t}]
        property var value
        signal picked(var v)
        implicitHeight: 28
        implicitWidth: segRow.implicitWidth + 6
        radius: 14
        color: Theme.surface
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: sg.options
                Rectangle {
                    required property var modelData
                    readonly property bool on: sg.value === modelData.v
                    objectName: "seg-" + modelData.v
                    width: Math.max(34, st.implicitWidth + 16); height: 22; radius: 11
                    color: on ? Theme.card : (sma.containsMouse ? Theme.hover : "transparent")
                    border.width: on && Theme.dark ? 1 : 0; border.color: Theme.accentGlow
                    Text { id: st; anchors.centerIn: parent; text: modelData.t; font.pixelSize: 12; font.bold: parent.on; color: parent.on ? Theme.accent : Theme.textSecondary }
                    MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.picked(modelData.v) }
                }
            }
        }
    }
    component OptionLine: RowLayout {
        property string text
        default property alias control: holder.data
        Layout.fillWidth: true
        implicitHeight: 30
        Text { text: parent.text; font.pixelSize: 13; color: Theme.text; Layout.fillWidth: true }
        Item { id: holder; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }

    contentItem: ColumnLayout {
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Text { text: qsTr("设置"); font.pixelSize: 18; font.bold: true; color: Theme.text }
            // 标签页：通用 / 日历
            Segmented {
                objectName: "settingsTabs"
                options: [{ v: "general", t: qsTr("通用") }, { v: "calendar", t: qsTr("日历") }]
                value: dlg.page
                onPicked: (v) => dlg.page = v
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "✕"; font.pixelSize: 14; color: closeMa.containsMouse ? Theme.text : Theme.textTertiary
                MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dlg.close() }
            }
        }

        // MARK: 通用
        ColumnLayout {
            visible: dlg.page === "general"
            Layout.fillWidth: true
            spacing: 12

            SectionTitle { text: qsTr("外观") }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ThemeCard { mode: "light"; label: qsTr("浅色") }
                ThemeCard { mode: "dark"; label: qsTr("深色") }
                ThemeCard { mode: "system"; label: qsTr("跟随系统") }
            }
            Text {
                visible: Settings.themeMode === "system"
                text: qsTr("系统当前为%1模式，切换系统外观时会自动跟随。").arg(Settings.systemDark ? qsTr("深色") : qsTr("浅色"))
                font.pixelSize: 11
                color: Theme.textSecondary
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            SectionTitle { text: qsTr("语言") }
            LangRow { lang: "zh"; name: "简体中文"; hint: "Chinese (Simplified)" }
            LangRow { lang: "en"; name: "English"; hint: "英语" }
        }

        // MARK: 日历
        ColumnLayout {
            visible: dlg.page === "calendar"
            Layout.fillWidth: true
            spacing: 8

            SectionTitle { text: qsTr("视图") }
            Toggle { objectName: "toggleWeekends"; text: qsTr("显示周末"); checked: CalendarStore.showWeekends; onToggled: CalendarStore.showWeekends = !CalendarStore.showWeekends }
            OptionLine {
                text: qsTr("周末")
                Segmented {
                    options: [{ v: "sat-sun", t: qsTr("周六、周日") }, { v: "fri-sat", t: qsTr("周五、周六") }]
                    value: CalendarStore.weekendDays
                    onPicked: (v) => CalendarStore.weekendDays = v
                }
            }
            Toggle { text: qsTr("每周从周一开始"); checked: CalendarStore.weekStartsMonday; onToggled: CalendarStore.weekStartsMonday = !CalendarStore.weekStartsMonday }
            Toggle { text: qsTr("在日历中显示待办"); checked: CalendarStore.showTodos; onToggled: CalendarStore.showTodos = !CalendarStore.showTodos }
            Toggle { text: qsTr("显示已完成的待办"); checked: CalendarStore.showCompleted; onToggled: CalendarStore.showCompleted = !CalendarStore.showCompleted }

            SectionTitle { text: qsTr("节假日与伊斯兰历"); Layout.topMargin: 10 }
            Toggle { objectName: "toggleUae"; text: qsTr("阿联酋公共假日"); checked: CalendarStore.showUaeHolidays; onToggled: CalendarStore.showUaeHolidays = !CalendarStore.showUaeHolidays }
            Toggle { objectName: "toggleIslamic"; text: qsTr("伊斯兰节日（斋月、开斋节、宰牲节等）"); checked: CalendarStore.showIslamicHolidays; onToggled: CalendarStore.showIslamicHolidays = !CalendarStore.showIslamicHolidays }
            Toggle { objectName: "toggleHijri"; text: qsTr("显示回历（伊斯兰历）日期"); checked: CalendarStore.showHijri; onToggled: CalendarStore.showHijri = !CalendarStore.showHijri }
            OptionLine {
                text: qsTr("回历日期调整")
                Segmented {
                    options: [{ v: -2, t: "−2" }, { v: -1, t: "−1" }, { v: 0, t: "0" }, { v: 1, t: "+1" }, { v: 2, t: "+2" }]
                    value: CalendarStore.hijriAdjust
                    onPicked: (v) => CalendarStore.hijriAdjust = v
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("回历日期按算法推算，与官方根据新月观测公布的日期可能相差 1～2 天，可用上面的调整对齐。今天：%1")
                          .arg((CalendarStore.hijriAdjust, CalendarStore.hijriText(Qt.formatDate(new Date(), "yyyy-MM-dd"))))   // 读 hijriAdjust：调整后立即刷新
                font.pixelSize: 11
                color: Theme.textSecondary
            }
        }

        Text {
            Layout.topMargin: 4
            text: qsTr("快捷键：⌘, 打开设置 · ⌘⇧D 切换浅色 / 深色")
            font.pixelSize: 10
            color: Theme.textTertiary
        }
    }
}
