import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 面板里的聊天（日历模块 / 面板独立窗口中使用）：
//  - 没有选会话：精简会话列表，点一下在面板里打开（Placement = panel，与主窗口 / 独立窗口互斥，单实例）
//  - 已选会话：返回 / 在消息中打开 / 拆成独立窗口 + 共用的 ChatView（草稿、光标、引用经 UIStateStore 迁移）
Item {
    id: pch
    objectName: "panelChat"
    readonly property string conv: WindowManager.panelConv

    // 会话列表
    ListView {
        id: convList
        anchors.fill: parent
        visible: pch.conv === ""
        clip: true
        model: ChatStore
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        header: Text {
            width: convList.width
            bottomPadding: 6; leftPadding: 4
            text: qsTr("选择会话，在面板里聊天")
            font.pixelSize: 11; color: Theme.textTertiary
        }
        delegate: Rectangle {
            required property string convId
            required property string title
            required property string lastText
            required property int unread
            required property string placement
            width: convList.width
            height: 50
            radius: 10
            color: rowMa.containsMouse ? Theme.hover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6; anchors.rightMargin: 8
                spacing: 8
                Avatar { name: title; size: 32 }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { width: parent.width; text: title; font.pixelSize: 12; font.bold: true; color: Theme.text; elide: Text.ElideRight }
                    Text {
                        width: parent.width
                        text: placement === "detached" ? qsTr("⧉ 已在独立窗口") : placement === "main" ? qsTr("正在主窗口中查看") : lastText
                        font.pixelSize: 11; color: Theme.textSecondary; elide: Text.ElideRight
                    }
                }
                Rectangle {
                    visible: unread > 0
                    height: 18; width: Math.max(18, ut.implicitWidth + 8); radius: 9
                    color: Theme.badge
                    Text { id: ut; anchors.centerIn: parent; text: unread; color: Theme.badgeText; font.pixelSize: 10; font.bold: true }
                }
            }
            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WindowManager.openInPanel(convId) }
        }
    }

    // 会话详情
    ColumnLayout {
        anchors.fill: parent
        visible: pch.conv !== ""
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: "‹"; font.pixelSize: 20; color: backMa.containsMouse ? Theme.accent : Theme.textSecondary
                MouseArea { id: backMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WindowManager.closePanelConv() }
                ToolTip.visible: backMa.containsMouse; ToolTip.text: qsTr("返回会话列表"); ToolTip.delay: 500
            }
            Avatar { name: ChatStore.title(pch.conv); size: 26 }
            Text {
                Layout.fillWidth: true
                text: ChatStore.title(pch.conv)
                font.pixelSize: 13; font.bold: true; color: Theme.text; elide: Text.ElideRight
            }
            component Btn: Text {
                id: b
                property string tip
                signal clicked()
                font.pixelSize: 13
                color: bMa.containsMouse ? Theme.accent : Theme.textTertiary
                MouseArea { id: bMa; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
                ToolTip.visible: bMa.containsMouse; ToolTip.text: b.tip; ToolTip.delay: 500
            }
            Btn { text: "⤢"; tip: qsTr("在消息中打开"); onClicked: { var c = pch.conv; WindowManager.module = "chat"; WindowManager.select(c) } }
            Btn { text: "⧉"; tip: qsTr("拆出为独立窗口"); onClicked: WindowManager.detach(pch.conv) }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.gridLine }

        // 按会话重建（同主窗口的做法）：换会话时旧视图 flush 并释放租约
        Item {
            id: host
            Layout.fillWidth: true
            Layout.fillHeight: true
            Repeater {
                model: pch.conv !== "" ? [pch.conv] : []
                delegate: ChatView {
                    required property string modelData
                    anchors.fill: host
                    convId: modelData
                    compact: true
                }
            }
        }
    }
}
