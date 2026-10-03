import QtQuick
import QtQuick.Controls
import ChatDemo

ApplicationWindow {
    id: win
    required property string convId

    width: 480
    height: 640
    minimumWidth: 360
    minimumHeight: 360
    color: Theme.windowBg
    title: ChatStore.title(convId)
    font.pixelSize: Theme.fontBody

    ChatView {
        anchors.fill: parent
        convId: win.convId
        detached: true
    }

    // 快捷键作用域 = 本独立窗口
    Shortcut {
        sequence: "Ctrl+Shift+M"
        onActivated: WindowManager.attach(win.convId)
    }
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: WindowManager.closeDetached(win.convId)
    }

    onClosing: WindowManager.detachedClosed(convId)

    Timer {
        id: geoTimer
        interval: 300
        onTriggered: if (win.visibility === Window.Windowed) WindowManager.saveGeometry(win.convId, win.x, win.y, win.width, win.height)
    }
    onXChanged: geoTimer.restart()
    onYChanged: geoTimer.restart()
    onWidthChanged: geoTimer.restart()
    onHeightChanged: geoTimer.restart()
}
