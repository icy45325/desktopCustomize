import QtQuick
import ChatDemo

// 悬浮卡片：无需 GraphicalEffects，用两层半透明圆角矩形模拟柔和投影。
Item {
    id: card
    property real radius: Theme.radiusCard
    property color color: Theme.card
    property color borderColor: Theme.cardBorder
    property real borderWidth: 1
    property real elevation: 1.0          // 0 = 无阴影
    property color shadowColor: Theme.shadow
    default property alias content: inner.data

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 6 * card.elevation; anchors.bottomMargin: -6 * card.elevation
        anchors.leftMargin: -2 * card.elevation; anchors.rightMargin: -2 * card.elevation
        radius: card.radius + 4
        color: card.shadowColor
        opacity: 0.35 * card.elevation
        visible: card.elevation > 0
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2 * card.elevation; anchors.bottomMargin: -3 * card.elevation
        radius: card.radius + 1
        color: card.shadowColor
        opacity: 0.45 * card.elevation
        visible: card.elevation > 0
    }
    Rectangle {
        id: inner
        anchors.fill: parent
        radius: card.radius
        color: card.color
        border.width: card.borderWidth
        border.color: card.borderColor
        clip: true
    }
}
