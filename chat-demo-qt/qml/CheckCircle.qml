import QtQuick
import ChatDemo

// 圆形勾选框（macOS 提醒事项风格）：未完成 = 彩色描边空心圆，完成 = 实心 + ✓。
Item {
    id: cc
    property bool checked: false
    property color color: Theme.accent
    property int size: 18
    property bool readOnly: false
    signal toggled()
    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: cc.checked ? cc.color : (ma.containsMouse && !cc.readOnly ? Qt.rgba(cc.color.r, cc.color.g, cc.color.b, 0.15) : "transparent")
        border.width: 1.6
        border.color: cc.color
        opacity: cc.readOnly && !cc.checked ? 0.6 : 1
        scale: ma.pressed ? 0.85 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 160 } }
        Text {
            anchors.centerIn: parent
            visible: cc.checked
            text: "✓"
            color: "white"
            font.pixelSize: cc.size * 0.62
            font.bold: true
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -3
        hoverEnabled: true
        enabled: !cc.readOnly
        cursorShape: Qt.PointingHandCursor
        onClicked: cc.toggled()
    }
}
