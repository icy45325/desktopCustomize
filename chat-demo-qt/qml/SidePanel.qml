import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo
import "CalUtil.js" as Cal

// 全局动态面板：消息 / 日历两个模块共用，也可以拆成独立窗口（PanelWindow）。
// 标签：待办 / 会议 / 日历 / 聊天 / 助手。停靠时隐藏与当前模块重复的标签（日历模块不显示「日历」，消息模块不显示「聊天」）。
// 面板状态（打开、标签、面板里的会话）都在 WindowManager，所以停靠 ↔ 独立窗口切换时内容不丢。
Item {
    id: panel
    objectName: "sidePanel"
    property bool inWindow: false
    readonly property string hostModule: inWindow ? "" : WindowManager.module

    readonly property var allTabs: [
        { k: "todo", t: qsTr("待办"), g: "☑" },
        { k: "meetings", t: qsTr("会议"), g: "◷" },
        { k: "calendar", t: qsTr("日历"), g: "▦" },
        { k: "chat", t: qsTr("聊天"), g: "✉" },
        { k: "assistant", t: qsTr("助手"), g: "✦" }
    ]
    readonly property var tabs: allTabs.filter(function (t) {
        return !(t.k === "calendar" && hostModule === "calendar") && !(t.k === "chat" && hostModule === "chat")
    })
    readonly property string tab: tabs.some(function (t) { return t.k === WindowManager.panelTab }) ? WindowManager.panelTab : "todo"

    Card {
        anchors.fill: parent
        anchors.topMargin: panel.inWindow ? 10 : 14
        anchors.bottomMargin: panel.inWindow ? 10 : 14
        anchors.rightMargin: panel.inWindow ? 10 : 14
        anchors.leftMargin: panel.inWindow ? 10 : 4
        radius: 20
        elevation: 1.0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // 标签栏 + 拆出 / 合并 / 关闭
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 14
                    color: Theme.surface
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: panel.tabs
                            Rectangle {
                                required property var modelData
                                readonly property bool on: panel.tab === modelData.k
                                objectName: "panelTab-" + modelData.k
                                width: Math.min(46, (panel.width - 100) / panel.tabs.length); height: 38; radius: 11
                                color: on ? Theme.card : (tabMa.containsMouse ? Theme.hover : "transparent")
                                border.width: on && Theme.dark ? 1 : 0
                                border.color: Theme.accentGlow
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.g; font.pixelSize: 14; color: parent.parent.on ? Theme.accent : Theme.textSecondary }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t; font.pixelSize: Cal.isEn() ? 9 : 10; font.bold: parent.parent.on; color: parent.parent.on ? Theme.accent : Theme.textTertiary }
                                }
                                // 待办数 / 面板会话未读
                                Rectangle {
                                    readonly property int n: modelData.k === "todo" ? CalendarStore.openTodoCount
                                                           : modelData.k === "chat" && WindowManager.panelConv !== "" ? ChatStore.unread(WindowManager.panelConv) + ChatStore.totalUnread * 0 : 0
                                    visible: n > 0
                                    x: parent.width - width - 2; y: 2
                                    height: 14; width: Math.max(14, nTxt.implicitWidth + 6); radius: 7
                                    color: Theme.danger
                                    Text { id: nTxt; anchors.centerIn: parent; text: parent.n; color: "white"; font.pixelSize: 9; font.bold: true }
                                }
                                MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WindowManager.panelTab = modelData.k }
                            }
                        }
                    }
                }
                Column {
                    spacing: 2
                    component HeadBtn: Rectangle {
                        id: hb
                        property string glyph
                        property string tip
                        signal clicked()
                        width: 22; height: 20; radius: 6
                        color: hbMa.containsMouse ? Theme.hover : "transparent"
                        Text { anchors.centerIn: parent; text: hb.glyph; font.pixelSize: 12; color: hbMa.containsMouse ? Theme.accent : Theme.textTertiary }
                        MouseArea { id: hbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hb.clicked() }
                        ToolTip.visible: hbMa.containsMouse; ToolTip.text: hb.tip; ToolTip.delay: 500
                    }
                    HeadBtn {
                        objectName: "panelDetachToggle"
                        glyph: panel.inWindow ? "⇲" : "⧉"
                        tip: panel.inWindow ? qsTr("合并回主窗口") : qsTr("在独立窗口中打开")
                        onClicked: panel.inWindow ? WindowManager.attachPanel() : WindowManager.detachPanel()
                    }
                    HeadBtn { glyph: "✕"; tip: qsTr("关闭面板（⌘⇧P）"); onClicked: WindowManager.panelOpen = false }
                }
            }

            // 内容：首次打开某标签时创建，之后保留（切换标签不重建）
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: ["todo", "meetings", "calendar", "chat", "assistant"].indexOf(panel.tab)
                component Lazy: Loader {
                    property string key
                    active: false
                    readonly property bool current: panel.tab === key
                    onCurrentChanged: if (current) active = true
                    Component.onCompleted: if (current) active = true
                }
                Lazy { key: "todo"; sourceComponent: TodoPanel {} }
                Lazy { key: "meetings"; sourceComponent: MeetingPanel {} }
                Lazy { key: "calendar"; sourceComponent: PanelCalendar {} }
                // 聊天：持有会话租约，只在标签可见时挂载，离开时释放
                Loader { active: panel.tab === "chat"; sourceComponent: PanelChat {} }
                Lazy { key: "assistant"; sourceComponent: AssistantPanel {} }
            }
        }
    }
}
