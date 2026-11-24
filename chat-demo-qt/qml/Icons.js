.pragma library

// 矢量图标的绘制代码。放在 .js 里而不是 Canvas.onPaint 内联：Qt 6.4 的 qmlcachegen 编译内联的绘制代码会崩溃。

// 聊天气泡：圆角气泡 + 左下角收拢的小尾巴（一条连续路径）+ 三个点。filled = 实心（选中态）
function chatBubble(ctx, color, dotColor, filled) {
    ctx.reset()
    var l = 2.5, t = 3.5, r = 21.5, b = 17.5, rad = 6.5
    ctx.beginPath()
    ctx.moveTo(l + rad, t)
    ctx.lineTo(r - rad, t)
    ctx.arcTo(r, t, r, t + rad, rad)
    ctx.lineTo(r, b - rad)
    ctx.arcTo(r, b, r - rad, b, rad)
    ctx.lineTo(10.5, b)
    ctx.bezierCurveTo(8.6, b, 6.6, 20.8, 4.2, 21.4)      // 尾巴外沿
    ctx.bezierCurveTo(5.4, 19.8, 5.7, 18.6, 5.4, 17.2)   // 尾巴内沿，回到气泡
    ctx.bezierCurveTo(3.6, 16.2, l, 14.4, l, b - rad)
    ctx.lineTo(l, t + rad)
    ctx.arcTo(l, t, l + rad, t, rad)
    ctx.closePath()
    ctx.lineJoin = "round"
    if (filled) {
        ctx.fillStyle = color
        ctx.fill()
    } else {
        ctx.lineWidth = 1.8
        ctx.strokeStyle = color
        ctx.stroke()
    }
    ctx.fillStyle = dotColor
    for (var i = 0; i < 3; ++i) {
        ctx.beginPath()
        ctx.arc(8 + i * 4, 10.5, 1.35, 0, Math.PI * 2)
        ctx.fill()
    }
}
