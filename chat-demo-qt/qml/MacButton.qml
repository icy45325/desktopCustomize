import QtQuick
import QtQuick.Controls
import ChatDemo

// macOS 工具栏按钮：白底、细边、圆角 6，按下变灰；primary 时蓝底白字
Button {
    id: btn
    property bool primary: false
    property bool circular: false
    implicitHeight: circular ? 28 : 26
    implicitWidth: circular ? 28 : Math.max(60, label.implicitWidth + 24)
    hoverEnabled: true
    font.pixelSize: Theme.fontBody

    background: Rectangle {
        radius: btn.circular ? width / 2 : Theme.radiusControl
        color: !btn.enabled ? (btn.primary ? "#B3D4FF" : "#F5F5F7")
             : btn.primary ? (btn.down ? Theme.accentPressed : Theme.accent)
             : btn.down ? "#E5E5EA" : (btn.hovered ? "#F7F7F9" : Theme.controlBg)
        border.width: btn.primary ? 0 : 1
        border.color: Theme.controlBorder
        // 轻微投影，接近 macOS 的凸起按钮
        Rectangle {
            visible: !btn.primary && !btn.down
            anchors.fill: parent; anchors.topMargin: 1
            z: -1; radius: parent.radius; color: "#14000000"
        }
    }
    contentItem: Text {
        id: label
        text: btn.text
        font: btn.font
        color: btn.primary ? Theme.textOnAccent : (btn.enabled ? Theme.textPrimary : Theme.textSecondary)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
