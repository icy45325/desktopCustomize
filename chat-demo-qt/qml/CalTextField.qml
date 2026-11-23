import QtQuick
import QtQuick.Controls
import ChatDemo

// 日历弹窗里的输入框：圆角、聚焦时强调色描边。
TextField {
    id: f
    implicitHeight: 34
    font.pixelSize: 13
    color: Theme.text
    placeholderTextColor: Theme.textTertiary
    selectionColor: Theme.accentGlow
    selectedTextColor: Theme.text
    leftPadding: 10; rightPadding: 10
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle {
        radius: 8
        color: Theme.input
        border.width: f.activeFocus ? 1.5 : 1
        border.color: f.activeFocus ? Theme.accent : Theme.fieldBorder
    }
}
