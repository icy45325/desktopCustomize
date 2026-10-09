import QtQuick
import ChatDemo

Rectangle {
    property string name: ""
    property int size: 40
    width: size; height: size; radius: size / 2
    color: Theme.avatarColor(name)
    Behavior on color { ColorAnimation { duration: 260 } }
    Text {
        anchors.centerIn: parent
        text: name.charAt(0)
        color: Theme.dark ? "#0D0F14" : "white"
        font.pixelSize: size * 0.42
        font.bold: true
    }
}
