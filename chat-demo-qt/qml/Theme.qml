pragma Singleton
import QtQuick
import ChatDemo

// 两套色板：Light 取自方案 C（柔和渐变底 + 紫色强调），Dark 取自方案 B（深空底 + 青绿霓虹）。
// 所有颜色带 Behavior，切换主题时整体渐变过渡。
QtObject {
    readonly property bool dark: WindowManager.darkMode
    function toggle() { WindowManager.darkMode = !WindowManager.darkMode }

    // 强调色
    property color accent: dark ? "#5EEAD4" : "#6C5CE7"
    property color accentSoft: dark ? "#1A5EEAD4" : "#F3F1FF"      // 气泡（对方）/ 轻底
    property color accentGlow: dark ? "#805EEAD4" : "#666C5CE7"    // 阴影 / 光晕
    property color onAccent: dark ? "#0D0F14" : "#FFFFFF"
    property color accentSecondary: dark ? "#A78BFA" : "#A29BFE"   // 分隔线渐变终点、引用

    // 底与面
    property color bgTop: dark ? "#0D0F14" : "#F3EEFF"
    property color bgMid: dark ? "#0F121A" : "#EAF4FF"
    property color bgBottom: dark ? "#12151E" : "#EFFBF4"
    property color card: dark ? "#161A23" : "#FFFFFF"
    property color cardMuted: dark ? "#13161D" : "#C7FFFFFF"   // QML 颜色是 #AARRGGBB
    property color cardBorder: dark ? "#1AFFFFFF" : "#00000000"
    property color surface: dark ? "#1C2029" : "#F6F5FB"           // 时间胶囊、引用栏
    property color input: dark ? "#13161D" : "#FFFFFF"
    property color inputBorder: dark ? "#5EEAD4" : "#E6E3F5"
    property color shadow: dark ? "#66000000" : "#243C3278"

    // 文本
    property color text: dark ? "#ECEDEF" : "#1F1D2B"
    property color textSecondary: dark ? "#9DA3B0" : "#7A7793"
    property color textTertiary: dark ? "#7C8190" : "#9A95B5"
    property color bubbleOtherText: dark ? "#ECEDEF" : "#1F1D2B"
    property color badge: dark ? "#5EEAD4" : "#6C5CE7"
    property color onBadge: dark ? "#0D0F14" : "#FFFFFF"
    property color online: dark ? "#5EEAD4" : "#2ECC8A"

    // 发言人名字按名字哈希取色（方案 B）
    readonly property var senderPalette: dark
        ? ["#A78BFA", "#FBBF24", "#60A5FA", "#F472B6", "#4ADE80"]
        : ["#7C3AED", "#D97706", "#2563EB", "#DB2777", "#059669"]
    readonly property var avatarPalette: dark
        ? ["#A78BFA", "#FBBF24", "#60A5FA", "#F472B6", "#4ADE80"]
        : ["#FF6B8B", "#4C9BFF", "#FFB13B", "#2ECC8A", "#A66CFF"]
    function hash(s) { var h = 0; for (var i = 0; i < s.length; ++i) h = (h * 31 + s.charCodeAt(i)) & 0x7fffffff; return h }
    function senderColor(name) { return senderPalette[hash(name) % senderPalette.length] }
    function avatarColor(name) { return avatarPalette[hash(name) % avatarPalette.length] }

    readonly property int fontBody: 13
    readonly property int fontSmall: 11
    readonly property int fontTitle: 15
    readonly property int radiusBubble: 18
    readonly property int radiusCard: 16

    // 注意：Qt 6.4 在 QML 单例里放 Behavior 会在创建时崩溃，颜色过渡放在各视图的 Behavior on color 里。
}
