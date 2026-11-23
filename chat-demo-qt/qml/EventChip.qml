import QtQuick
import ChatDemo
import "CalUtil.js" as Cal

// 月视图 / 全天栏里的一行：
//  - 全天 / 跨天事件：浅色底 + 左侧色条（banner）
//  - 定时事件：彩色圆点 + 时间 + 标题（Google 月视图样式）
//  - 待办：圆形勾选框 + 标题（完成后划线）
Item {
    id: chip
    property var item
    property bool showTime: true
    signal clicked(var item, point globalPos)
    readonly property bool isTodo: item && item.type === "todo"
    readonly property bool banner: item && !isTodo && (item.allDay || item.multiDay)
    implicitHeight: 20

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: chip.banner ? Cal.alpha(chip.item.color, Theme.dark ? 0.32 : 0.2)
                           : (ma.containsMouse ? Theme.hover : "transparent")
        Rectangle {
            visible: chip.banner
            width: 3; height: parent.height - 6; radius: 1.5
            anchors.verticalCenter: parent.verticalCenter; x: 3
            color: chip.item ? chip.item.color : "transparent"
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: chip.banner ? 10 : 4
        width: parent.width - x - 4
        spacing: 5

        CheckCircle {
            visible: chip.isTodo
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            checked: chip.isTodo && chip.item.done
            color: chip.item ? chip.item.color : Theme.accent
            readOnly: chip.isTodo && chip.item.readOnly
            onToggled: CalendarStore.toggleTodo(chip.item.uid)
        }
        Rectangle {
            visible: !chip.banner && !chip.isTodo
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 3.5
            color: chip.item ? chip.item.color : "transparent"
        }
        Text {
            id: timeText
            visible: chip.showTime && !chip.banner && (chip.isTodo ? chip.item.dueTime !== "" : true)
            anchors.verticalCenter: parent.verticalCenter
            text: !chip.item ? "" : (chip.isTodo ? chip.item.dueTime : Cal.hm(chip.item.startMs))
            font.pixelSize: 11
            color: Theme.textSecondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x
            text: chip.item ? chip.item.title : ""
            elide: Text.ElideRight
            font.pixelSize: 11
            font.bold: chip.banner
            font.strikeout: chip.isTodo && chip.item.done
            color: chip.isTodo && chip.item.done ? Theme.textTertiary
                 : (chip.isTodo && chip.item.overdue ? Theme.danger : Theme.text)
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.leftMargin: chip.isTodo ? 20 : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => chip.clicked(chip.item, ma.mapToGlobal(m.x, m.y))
    }
}
