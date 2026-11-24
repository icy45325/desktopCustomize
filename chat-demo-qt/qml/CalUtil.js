.pragma library

// 日历视图共用的日期工具。所有 Date 都按本地时间处理；与 C++ 之间用 "yyyy-MM-dd" 字符串 / 毫秒时间戳交换。
// 日期格式随界面语言变化（中文「11月23日 周一」/ 英文「Mon, Nov 23」），由 Main.qml 调用 setLang() 设置。

var lang = "zh"
function setLang(l) { lang = l === "en" ? "en" : "zh" }
function isEn() { return lang === "en" }

var weekdayZh = ["日", "一", "二", "三", "四", "五", "六"]
var weekdayEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var weekdayEnNarrow = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
var monthEn = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var monthEnLong = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var DAY_MS = 86400000

function pad(n) { return n < 10 ? "0" + n : "" + n }
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function parseIso(s) { var p = s.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]) }
function today() { var n = new Date(); return new Date(n.getFullYear(), n.getMonth(), n.getDate()) }
function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
function daysInMonth(d) { return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate() }
function addMonths(d, n) {
    var r = new Date(d.getFullYear(), d.getMonth() + n, 1)
    r.setDate(Math.min(d.getDate(), daysInMonth(r)))
    return r
}
function sameDay(a, b) { return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
function sameMonth(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() }
function isToday(d) { return sameDay(d, new Date()) }
function isWeekend(d) { return d.getDay() === 0 || d.getDay() === 6 }

function startOfWeek(d, mondayFirst) {
    var off = mondayFirst ? (d.getDay() + 6) % 7 : d.getDay()
    return addDays(d, -off)
}
function monthGridStart(d, mondayFirst) { return startOfWeek(new Date(d.getFullYear(), d.getMonth(), 1), mondayFirst) }
// narrow：迷你月历列头（一 / Mo）；否则：月视图列头（周一 / Mon）
function weekdayLabels(mondayFirst, narrow) {
    var r = []
    for (var i = 0; i < 7; ++i) {
        var k = (i + (mondayFirst ? 1 : 0)) % 7
        r.push(isEn() ? (narrow ? weekdayEnNarrow[k] : weekdayEn[k]) : (narrow ? weekdayZh[k] : "周" + weekdayZh[k]))
    }
    return r
}
// ISO 8601 周数
function weekNumber(d) {
    var t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)
    var w1 = new Date(t.getFullYear(), 0, 4)
    return 1 + Math.round(((t - w1) / DAY_MS - 3 + (w1.getDay() + 6) % 7) / 7)
}

function hm(ms) { var d = new Date(ms); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function minutesOfDay(d) { return d.getHours() * 60 + d.getMinutes() }
function md(d) { return isEn() ? monthEn[d.getMonth()] + " " + d.getDate() : (d.getMonth() + 1) + "月" + d.getDate() + "日" }
function ymd(d) { return isEn() ? md(d) + ", " + d.getFullYear() : d.getFullYear() + "年" + md(d) }
function ym(d) { return isEn() ? monthEnLong[d.getMonth()] + " " + d.getFullYear() : d.getFullYear() + "年" + (d.getMonth() + 1) + "月" }
function monthShort(d) { return isEn() ? monthEn[d.getMonth()] : (d.getMonth() + 1) + "月" }
function yearText(y) { return isEn() ? "" + y : y + "年" }
function weekdayName(d) { return isEn() ? weekdayEn[d.getDay()] : "周" + weekdayZh[d.getDay()] }
// 「周一 11月23日」/「Mon, Nov 23」
function dayTitle(d) { return isEn() ? weekdayName(d) + ", " + md(d) : md(d) + " " + weekdayName(d) }

function relativeDay(d) {
    var diff = Math.round((dayStart(d) - today()) / DAY_MS)
    if (diff === 0) return isEn() ? "Today" : "今天"
    if (diff === 1) return isEn() ? "Tomorrow" : "明天"
    if (diff === -1) return isEn() ? "Yesterday" : "昨天"
    if (diff === 2 && !isEn()) return "后天"
    return ""
}

// 「11月23日 周一 10:00 – 11:00」/「11月23日 – 25日（全天）」
function rangeText(item) {
    var s = new Date(item.startMs), e = new Date(item.endMs)
    var allDayText = isEn() ? " · All day" : " · 全天"
    if (item.allDay) {
        var last = parseIso(item.lastIso)
        if (sameDay(s, last)) return dayTitle(s) + allDayText
        return md(s) + " – " + (sameMonth(s, last) ? (isEn() ? "" + last.getDate() : last.getDate() + "日") : md(last)) + allDayText
    }
    if (sameDay(s, e) || item.endMs - item.startMs <= 0)
        return dayTitle(s) + " " + hm(item.startMs) + " – " + hm(item.endMs)
    return md(s) + " " + hm(item.startMs) + " – " + md(e) + " " + hm(item.endMs)
}

// "#RRGGBB" + 透明度 → "#AARRGGBB"（QML 颜色格式）
function alpha(hex, a) {
    var h = Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16)
    if (h.length < 2) h = "0" + h
    return "#" + h + hex.slice(hex.length - 6)
}

// 该事件是否覆盖某天（用 startIso / lastIso，避免时区问题）
function coversDay(item, dayIso) {
    if (item.type === "todo") return item.dueIso === dayIso
    return item.startIso <= dayIso && item.lastIso >= dayIso
}

// 某天格子里放的内容：全天/跨天事件、定时事件、待办
function itemsForDay(items, dayIso) {
    var r = []
    for (var i = 0; i < items.length; ++i) if (coversDay(items[i], dayIso)) r.push(items[i])
    return r
}

// 时间网格里「放到顶部全天栏」的条件：全天或跨天
function isBanner(item) { return item.type === "todo" ? false : (item.allDay || item.multiDay) }

// 某天的定时事件排版：重叠的事件分列显示（类似 Google / macOS）。
// 返回 [{item, top(分钟), bottom(分钟), col, cols}]
function layoutDay(items, day) {
    var d0 = dayStart(day).getTime(), d1 = d0 + DAY_MS
    var evs = []
    for (var i = 0; i < items.length; ++i) {
        var it = items[i]
        if (it.type === "todo" || isBanner(it)) continue
        if (it.startMs >= d1 || Math.max(it.endMs, it.startMs + 1) <= d0) continue
        var top = Math.max(0, (it.startMs - d0) / 60000)
        var bottom = Math.min(1440, (Math.max(it.endMs, it.startMs + 15 * 60000) - d0) / 60000)
        evs.push({ item: it, top: top, bottom: Math.max(bottom, top + 20), col: 0, cols: 1 })
    }
    evs.sort(function (a, b) { return a.top - b.top || (b.bottom - b.top) - (a.bottom - a.top) })
    // 按传递重叠分组，组内贪心分列
    var group = [], groupEnd = -1
    function flush() {
        var n = 0
        for (var k = 0; k < group.length; ++k) n = Math.max(n, group[k].col + 1)
        for (k = 0; k < group.length; ++k) group[k].cols = n
        group = []
    }
    for (i = 0; i < evs.length; ++i) {
        var e = evs[i]
        if (e.top >= groupEnd) { flush(); groupEnd = -1 }
        var used = {}
        for (var j = 0; j < group.length; ++j) if (group[j].bottom > e.top) used[group[j].col] = true
        var c = 0
        while (used[c]) ++c
        e.col = c
        group.push(e)
        groupEnd = Math.max(groupEnd, e.bottom)
    }
    flush()
    return evs
}

function reminderOptions() {
    var en = isEn()
    return [
        { label: en ? "None" : "不提醒", value: -1 }, { label: en ? "At start" : "开始时", value: 0 },
        { label: en ? "5 min before" : "5 分钟前", value: 5 }, { label: en ? "10 min before" : "10 分钟前", value: 10 },
        { label: en ? "15 min before" : "15 分钟前", value: 15 }, { label: en ? "30 min before" : "30 分钟前", value: 30 },
        { label: en ? "1 hour before" : "1 小时前", value: 60 }, { label: en ? "1 day before" : "1 天前", value: 1440 }
    ]
}

// 重复选项（与 Google / macOS 的快捷项一致）；rrule 为空 = 不重复
function repeatOptions(day) {
    var wd = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][day.getDay()]
    var nth = Math.floor((day.getDate() - 1) / 7) + 1
    if (isEn()) {
        var ord = ["", "1st", "2nd", "3rd", "4th", "5th"][nth]
        var full = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day.getDay()]
        return [
            { label: "Does not repeat", rrule: "" },
            { label: "Daily", rrule: "FREQ=DAILY" },
            { label: "Every weekday (Mon–Fri)", rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" },
            { label: "Weekly on " + full, rrule: "FREQ=WEEKLY;BYDAY=" + wd },
            { label: "Every 2 weeks on " + full, rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=" + wd },
            { label: "Monthly on day " + day.getDate(), rrule: "FREQ=MONTHLY" },
            { label: "Monthly on the " + ord + " " + full, rrule: "FREQ=MONTHLY;BYDAY=" + nth + wd },
            { label: "Annually on " + md(day), rrule: "FREQ=YEARLY" }
        ]
    }
    return [
        { label: "不重复", rrule: "" },
        { label: "每天", rrule: "FREQ=DAILY" },
        { label: "每个工作日（周一至周五）", rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" },
        { label: "每周（" + weekdayName(day) + "）", rrule: "FREQ=WEEKLY;BYDAY=" + wd },
        { label: "每两周（" + weekdayName(day) + "）", rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=" + wd },
        { label: "每月（" + day.getDate() + " 日）", rrule: "FREQ=MONTHLY" },
        { label: "每月（第 " + nth + " 个" + weekdayName(day) + "）", rrule: "FREQ=MONTHLY;BYDAY=" + nth + wd },
        { label: "每年（" + md(day) + "）", rrule: "FREQ=YEARLY" }
    ]
}

// 15 分钟一档的时间选项
function timeOptions() {
    var r = []
    for (var m = 0; m < 1440; m += 15) r.push(pad(Math.floor(m / 60)) + ":" + pad(m % 60))
    return r
}
function parseHm(s) { var p = s.split(":"); return (+p[0]) * 60 + (+p[1]) }
function at(day, minutes) { return new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(minutes / 60), minutes % 60) }

function priorityOptions() {
    var en = isEn()
    return [{ label: en ? "None" : "无", value: 0 }, { label: en ? "High" : "高", value: 1 },
            { label: en ? "Med" : "中", value: 5 }, { label: en ? "Low" : "低", value: 9 }]
}
function priorityName(p) { return p === 0 ? "" : (p <= 4 ? (isEn() ? "High" : "高") : p === 5 ? (isEn() ? "Medium" : "中") : (isEn() ? "Low" : "低")) }
function priorityMark(p) { return p === 0 ? "" : (p <= 4 ? "!!!" : (p === 5 ? "!!" : "!")) }
