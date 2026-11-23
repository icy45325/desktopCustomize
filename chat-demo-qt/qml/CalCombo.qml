import QtQuick
import QtQuick.Controls
import ChatDemo

// 下拉框：model 为 [{label, ...}] 时用 textRole: "label"。
ComboBox {
    id: cb
    implicitHeight: 32
    font.pixelSize: 12
    textRole: "label"
    background: Rectangle {
        radius: 8
        color: cb.hovered ? Theme.hover : Theme.input
        border.width: 1
        border.color: cb.popup.visible ? Theme.accent : Theme.fieldBorder
    }
    contentItem: Text {
        leftPadding: 10
        rightPadding: 24
        text: cb.displayText
        font: cb.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: cb.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        color: Theme.textSecondary
        font.pixelSize: 13
    }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: cb.popup.width
        height: 28
        highlighted: cb.highlightedIndex === index
        contentItem: Text {
            text: cb.textRole && typeof parent.modelData === "object" ? parent.modelData[cb.textRole] : parent.modelData
            color: cb.currentIndex === parent.index ? Theme.accent : Theme.text
            font.pixelSize: 12
            font.bold: cb.currentIndex === parent.index
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle { color: parent.highlighted ? Theme.hover : "transparent"; radius: 6 }
    }
    popup: Popup {
        y: cb.height + 2
        width: Math.max(cb.width, 160)
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        padding: 4
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: cb.popup.visible ? cb.delegateModel : null
            currentIndex: cb.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
            Component.onCompleted: positionViewAtIndex(cb.currentIndex, ListView.Center)
        }
        background: Rectangle { radius: 10; color: Theme.popup; border.width: 1; border.color: Theme.fieldBorder }
    }
}
