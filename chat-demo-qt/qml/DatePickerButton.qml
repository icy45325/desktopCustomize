import QtQuick
import QtQuick.Controls
import ChatDemo
import "CalUtil.js" as Cal

// 日期字段：显示「11月23日 周一」，点击弹出迷你月历选择。
Item {
    id: dp
    property var date: Cal.today()
    signal picked(var date)
    implicitWidth: 138
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: ma.containsMouse && dp.enabled ? Theme.hover : Theme.input
        border.width: 1
        border.color: pop.opened ? Theme.accent : Theme.fieldBorder
        opacity: dp.enabled ? 1 : 0.5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            text: dp.date ? (dp.date.getFullYear() !== new Date().getFullYear() ? dp.date.getFullYear() + "年" : "") + Cal.md(dp.date) + " " + Cal.weekdayName(dp.date) : "选择日期"
            font.pixelSize: 12
            color: Theme.text
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: dp.enabled; cursorShape: Qt.PointingHandCursor; onClicked: pop.open() }

    Popup {
        id: pop
        y: dp.height + 4
        padding: 10
        background: Card { radius: 12; color: Theme.popup; elevation: 1.2 }
        onAboutToShow: picker.month = dp.date || Cal.today()
        MiniMonth {
            id: picker
            width: 210
            cell: 28
            showBusy: false
            selected: dp.date
            onPicked: (d) => { dp.date = d; dp.picked(d); pop.close() }
        }
    }
}
