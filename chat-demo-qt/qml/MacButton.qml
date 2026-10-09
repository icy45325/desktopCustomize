import QtQuick
import QtQuick.Controls
import ChatDemo

// 胶囊按钮：默认为强调色淡底；primary = 强调色实底（dark 下带光晕）；circular = 圆形图标钮
Button {
    id: btn
    property bool primary: false
    property bool circular: false
    implicitHeight: circular ? 32 : 30
    implicitWidth: circular ? 32 : Math.max(60, label.implicitWidth + 28)
    hoverEnabled: true
    font.pixelSize: Theme.fontBody
    font.bold: true

    background: Item {
        // 光晕 / 投影
        Rectangle {
            anchors.fill: parent; anchors.margins: -3
            radius: height / 2
            color: Theme.accentGlow
            opacity: btn.primary && btn.enabled ? (btn.hovered ? 0.9 : 0.55) : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: !btn.enabled ? Theme.surface
                 : btn.primary ? Theme.accent
                 : Theme.accentSoft
            opacity: btn.down ? 0.8 : 1
            scale: btn.down ? 0.96 : (btn.hovered ? 1.03 : 1)
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
    contentItem: Text {
        id: label
        text: btn.text
        font: btn.font
        color: !btn.enabled ? Theme.textTertiary : (btn.primary ? Theme.onAccent : Theme.accent)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: 200 } }
    }
}
