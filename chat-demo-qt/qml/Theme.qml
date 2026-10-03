pragma Singleton
import QtQuick

// macOS 风格色板（参考 Messages / Mail 的浅色外观）
QtObject {
    readonly property color accent: "#007AFF"
    readonly property color accentPressed: "#0062CC"
    readonly property color windowBg: "#FFFFFF"
    readonly property color sidebarBg: "#F2F2F7"
    readonly property color sidebarHover: "#E5E5EA"
    readonly property color separator: "#D1D1D6"
    readonly property color separatorLight: "#E5E5EA"
    readonly property color textPrimary: "#1C1C1E"
    readonly property color textSecondary: "#8E8E93"
    readonly property color textOnAccent: "#FFFFFF"
    readonly property color bubbleMine: "#007AFF"
    readonly property color bubbleOther: "#E9E9EB"
    readonly property color bubbleOtherText: "#1C1C1E"
    readonly property color quoteBg: "#F2F2F7"
    readonly property color badge: "#FF3B30"
    readonly property color controlBg: "#FFFFFF"
    readonly property color controlBorder: "#D1D1D6"
    readonly property color inputBg: "#FFFFFF"

    readonly property int fontBody: 13
    readonly property int fontSmall: 11
    readonly property int fontTitle: 15
    readonly property int radiusBubble: 18
    readonly property int radiusControl: 6
}
