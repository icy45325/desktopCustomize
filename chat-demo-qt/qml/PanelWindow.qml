import QtQuick
import QtQuick.Controls
import ChatDemo

// 动态面板的独立窗口：显示全部标签；关闭窗口 = 关闭面板，⇲ 合并回主窗口。
ApplicationWindow {
    id: win
    objectName: "panelWindow"
    width: 340
    height: 640
    minimumWidth: 300
    minimumHeight: 420
    color: Theme.bgMid
    title: "动态面板"
    font.pixelSize: Theme.fontBody

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.bgTop }
            GradientStop { position: 1.0; color: Theme.bgBottom }
        }
    }

    SidePanel { anchors.fill: parent; inWindow: true }

    Shortcut { sequence: "Ctrl+Shift+D"; onActivated: Theme.toggle() }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: WindowManager.attachPanel() }

    onClosing: WindowManager.panelWindowClosed()

    Timer {
        id: geoTimer
        interval: 300
        onTriggered: if (win.visibility === Window.Windowed) WindowManager.saveGeometry("panel", win.x, win.y, win.width, win.height)
    }
    onXChanged: geoTimer.restart()
    onYChanged: geoTimer.restart()
    onWidthChanged: geoTimer.restart()
    onHeightChanged: geoTimer.restart()
}
