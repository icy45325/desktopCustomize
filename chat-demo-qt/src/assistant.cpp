#include "assistant.h"

#include "appsettings.h"
#include "calendarstore.h"

#include <QLocale>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QTimer>
#include <algorithm>

// 回复文字走 Qt 翻译（源文本中文，英文见 i18n/ChatDemo_en.ts）；解析同时支持中文和英文输入。

namespace {

const QString kCn = QStringLiteral("[零〇一二两三四五六七八九十]{1,3}");
const QString kNum = QStringLiteral("(?:\\d{1,2}|[零〇一二两三四五六七八九十]{1,3})");
const auto CI = QRegularExpression::CaseInsensitiveOption;

bool en() { return AppSettings::instance()->language() == QLatin1String("en"); }

int cnDigit(QChar c)
{
    static const QString d = QStringLiteral("零一二三四五六七八九");
    if (c == QChar(u'两')) return 2;
    if (c == QChar(u'〇')) return 0;
    return d.indexOf(c);
}

/// "15" / "十五" / "二十三" / "两" → 数字；失败 = -1
int cnNum(QString s)
{
    s = s.trimmed();
    s.remove(QChar(u'分'));
    bool ok = false;
    const int v = s.toInt(&ok);
    if (ok) return v;
    if (s.isEmpty()) return -1;
    const int ten = s.indexOf(QChar(u'十'));
    if (ten >= 0) {
        const int tens = ten == 0 ? 1 : cnDigit(s.at(0));
        const int ones = ten == s.size() - 1 ? 0 : cnDigit(s.at(ten + 1));
        return tens < 0 || ones < 0 ? -1 : tens * 10 + ones;
    }
    return s.size() == 1 ? cnDigit(s.at(0)) : -1;
}

/// 「11月24日 周二」/「Tue, Nov 24」
QString dateText(const QDate &d)
{
    if (en()) return QLocale(QLocale::English).toString(d, QStringLiteral("ddd, MMM d"));
    static const QStringList wd{QString(), "周一", "周二", "周三", "周四", "周五", "周六", "周日"};
    return QStringLiteral("%1月%2日 %3").arg(d.month()).arg(d.day()).arg(wd[d.dayOfWeek()]);
}

/// 「今天」「明天」…；不是相邻日期时返回空
QString relWord(const QDate &d, const QDate &today)
{
    switch (today.daysTo(d)) {
    case 0: return Assistant::tr("今天");
    case 1: return Assistant::tr("明天");
    case -1: return Assistant::tr("昨天");
    case 2: return en() ? QString() : Assistant::tr("后天");
    default: return {};
    }
}

/// 「今天（11月24日 周二）」/「today (Tue, Nov 24)」
QString dayLabel(const QDate &d, const QDate &today)
{
    const QString rel = relWord(d, today);
    return rel.isEmpty() ? dateText(d) : Assistant::tr("%1（%2）").arg(rel, dateText(d));
}
/// 简短：「今天」或「11月24日 周二」
QString dayShort(const QDate &d, const QDate &today)
{
    const QString rel = relWord(d, today);
    return rel.isEmpty() ? dateText(d) : rel;
}

QString rangeLabel(const Assistant::When &w, const QDate &today)
{
    if (w.singleDay) return dayLabel(w.from, today);
    return Assistant::tr("%1 – %2").arg(dateText(w.from), dateText(w.to.addDays(-1)));
}

QString hm(double ms) { return QDateTime::fromMSecsSinceEpoch(qint64(ms)).toString("HH:mm"); }

/// 一行事件描述
QString eventLine(const QVariantMap &e, bool withDate, const QDate &today)
{
    QString s = QStringLiteral("• ");
    if (withDate) s += dayShort(QDate::fromString(e["startIso"].toString(), Qt::ISODate), today) + QStringLiteral(" ");
    s += e["allDay"].toBool() ? Assistant::tr("全天") : hm(e["startMs"].toDouble()) + QStringLiteral("–") + hm(e["endMs"].toDouble());
    s += QStringLiteral(" ") + e["title"].toString();
    if (!e["location"].toString().isEmpty()) s += Assistant::tr("（%1）").arg(e["location"].toString());
    return s;
}

QString cleanTitle(QString s)
{
    static const QRegularExpression words(QStringLiteral(
        "(帮我|给我|替我|请|麻烦|一下|安排|预约|约个?|创建|新建|添加|加个|加一个|增加|订个?|开个|定个|建个|一个|提醒我|提醒|记得|待办|日程|活动|全天|"
        "^(?:在|于|要|去|把|的)|(?:的|吧|呀|哦|啊)$)"));
    // 英文：去掉开头的动词 / 冠词和结尾的介词
    static const QRegularExpression enHead(QStringLiteral(
        "^(?:please|can you|could you|schedule|add|create|book|set up|put|new|remind me to|remind me|todo:?|task:?|"
        "an? |the |event|for|to|on|at)\\b\\s*"), CI);
    static const QRegularExpression enTail(QStringLiteral("\\s*\\b(?:on|at|for|from|to|in|by|with)$"), CI);
    static const QRegularExpression punct(QStringLiteral("^[\\s，。,.!！：:、]+|[\\s，。,.!！：:、]+$"));
    for (int i = 0; i < 4; ++i) {   // 去掉前后缀后可能露出新的前后缀
        s.replace(words, QString());
        s.replace(enHead, QString());
        s.replace(enTail, QString());
        s.replace(punct, QString());
    }
    return s.simplified();
}

QList<QVariantMap> maps(const QVariantList &l)
{
    QList<QVariantMap> out;
    for (const QVariant &v : l) out << v.toMap();
    return out;
}

bool isTimed(const QVariantMap &e) { return !e["allDay"].toBool() && !e["multiDay"].toBool(); }

/// 工作时间（9:00–18:00）内的空闲时段
QList<QPair<QDateTime, QDateTime>> freeSlots(const QDate &d, const QDateTime &now, int minMinutes)
{
    QDateTime ws(d, QTime(9, 0)), we(d, QTime(18, 0));
    if (d == now.date() && now > ws) {
        const int m = now.time().hour() * 60 + now.time().minute();
        const int up = (m + 29) / 30 * 30;   // 向上取整到半点
        ws = QDateTime(d, QTime(0, 0)).addSecs(up * 60);
    }
    QList<QPair<QDateTime, QDateTime>> busy;
    for (const QVariantMap &e : maps(CalendarStore::instance()->occurrences(d.toString(Qt::ISODate), d.addDays(1).toString(Qt::ISODate))))
        if (isTimed(e))
            busy << qMakePair(QDateTime::fromMSecsSinceEpoch(qint64(e["startMs"].toDouble())), QDateTime::fromMSecsSinceEpoch(qint64(e["endMs"].toDouble())));
    std::sort(busy.begin(), busy.end());
    QList<QPair<QDateTime, QDateTime>> out;
    QDateTime cur = ws;
    for (const auto &b : busy) {
        if (b.first > cur && cur.secsTo(qMin(b.first, we)) >= minMinutes * 60) out << qMakePair(cur, qMin(b.first, we));
        cur = qMax(cur, b.second);
        if (cur >= we) break;
    }
    if (cur < we && cur.secsTo(we) >= minMinutes * 60) out << qMakePair(cur, we);
    return out;
}

QString slotText(const QPair<QDateTime, QDateTime> &s)
{
    return s.first.toString("HH:mm") + QStringLiteral("–") + s.second.toString("HH:mm");
}

QString greeting()
{
    return Assistant::tr("你好，我是日历小助手。可以问我「今天有什么安排」「明天下午有空吗」，"
                         "也可以直接说「明天下午3点 产品评审 1小时」或「提醒我周五交周报」。");
}

}  // namespace

Assistant *Assistant::instance()
{
    static Assistant *s = new Assistant;
    return s;
}

Assistant *Assistant::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

Assistant::Assistant()
{
    append({{"role", "assistant"}, {"text", greeting()}});
    // 切换界面语言时：还没聊过（只有欢迎语）就换成新语言的欢迎语
    connect(AppSettings::instance(), &AppSettings::languageChanged, this, [this] {
        if (m_messages.size() == 1 && m_messages[0].toMap()["role"] == "assistant") {
            m_messages.clear();
            append({{"role", "assistant"}, {"text", greeting()}});
        }
        emit suggestionsChanged();
    });
}

QStringList Assistant::suggestions() const
{
    return {tr("今天有什么安排？"), tr("下一个会议是什么？"), tr("明天下午有空吗"),
            tr("本周的待办"), tr("明天下午3点 需求评审 1小时"), tr("提醒我周五交周报")};
}

void Assistant::append(const QVariantMap &m)
{
    QVariantMap x = m;
    if (!x.contains("items")) x["items"] = QVariantList();
    if (!x.contains("action")) x["action"] = QVariantMap();
    x["done"] = false;
    m_messages << x;
    emit messagesChanged();
}

void Assistant::send(const QString &text)
{
    const QString t = text.trimmed();
    if (t.isEmpty() || m_thinking) return;
    append({{"role", "user"}, {"text", t}});
    m_thinking = true;
    emit thinkingChanged();
    // 稍作停顿，给「正在思考」一点反馈；接入真模型后这里换成异步请求
    QTimer::singleShot(350, this, [this, t] {
        QVariantMap r = respond(t);
        r["role"] = "assistant";
        append(r);
        m_thinking = false;
        emit thinkingChanged();
    });
}

void Assistant::clear()
{
    m_messages.clear();
    emit messagesChanged();
}

void Assistant::runAction(int index)
{
    if (index < 0 || index >= m_messages.size()) return;
    QVariantMap m = m_messages[index].toMap();
    const QVariantMap a = m["action"].toMap();
    if (a.isEmpty() || m["done"].toBool()) return;
    auto *cs = CalendarStore::instance();
    bool ok = false;
    if (a["kind"] == "deleteEvent") ok = cs->deleteEvent(a["uid"].toString());
    else if (a["kind"] == "deleteTodo") ok = cs->deleteTodo(a["uid"].toString());
    m["done"] = true;
    m_messages[index] = m;
    emit messagesChanged();
    append({{"role", "assistant"}, {"text", ok ? tr("已撤销。") : tr("这一项已经不存在了。")}});
}

// MARK: 解析

Assistant::When Assistant::parseWhen(const QString &input, const QDate &today)
{
    When w;
    QString s = input;
    s.replace(QStringLiteral("今晚"), QStringLiteral("今天晚上"));
    s.replace(QStringLiteral("明晚"), QStringLiteral("明天晚上"));
    s.replace(QRegularExpression(QStringLiteral("\\btonight\\b"), CI), QStringLiteral("today evening"));
    auto cut = [&](const QRegularExpressionMatch &m) { s.replace(m.capturedStart(), m.capturedLength(), QStringLiteral(" ")); };
    auto setDay = [&](const QDate &d) { w.from = d; w.to = d.addDays(1); w.singleDay = true; };
    auto weekdayDate = [&](int dow, const QString &pre) {
        QDate d = today.addDays(dow - today.dayOfWeek());
        if (pre == "下" || pre.compare("next", Qt::CaseInsensitive) == 0) d = d.addDays(d <= today ? 7 : (pre == "下" ? 7 : 0));
        else if (pre == "下下") d = d.addDays(14);
        else if (pre == "上" || pre.compare("last", Qt::CaseInsensitive) == 0) d = d.addDays(-7);
        else if ((pre.isEmpty() || pre.compare("this", Qt::CaseInsensitive) == 0) && d < today) d = d.addDays(7);   // 「周三」在周四说，指下周三
        return d;
    };

    // 周几（这周三 / 下周一 / 周五 / next monday / friday）
    static const QRegularExpression weekday(QStringLiteral("(下下|下|上|这|本)?个?(?:周|星期|礼拜)([一二三四五六日天1-7])"));
    static const QRegularExpression weekdayEn(QStringLiteral("\\b(?:(next|this|last)\\s+)?(mon|tue|wed|thu|fri|sat|sun)[a-z]*\\b"), CI);
    if (auto m = weekday.match(s); m.hasMatch()) {
        const QString c = m.captured(2);
        const int dow = c == "日" || c == "天" ? 7 : (c.at(0).isDigit() ? c.toInt() : cnDigit(c.at(0)));
        const QString pre = m.captured(1);
        QDate d = today.addDays(dow - today.dayOfWeek());
        if (pre == "下") d = d.addDays(7);
        else if (pre == "下下") d = d.addDays(14);
        else if (pre == "上") d = d.addDays(-7);
        else if (pre.isEmpty() && d < today) d = d.addDays(7);
        setDay(d);
        cut(m);
    } else if (auto me = weekdayEn.match(s); me.hasMatch()) {
        static const QStringList days{"mon", "tue", "wed", "thu", "fri", "sat", "sun"};
        setDay(weekdayDate(days.indexOf(me.captured(2).toLower()) + 1, me.captured(1)));
        cut(me);
    }
    // 范围
    static const QRegularExpression nextWeek(QStringLiteral("下周|下个?星期|下个?礼拜|\\bnext week\\b"), CI);
    static const QRegularExpression thisWeek(QStringLiteral("本周|这周|这个?星期|这个?礼拜|\\bthis week\\b"), CI);
    static const QRegularExpression soon(QStringLiteral("这几天|最近|未来几天|接下来几天|未来一周|一周内|\\b(?:next few days|coming days|upcoming|this coming week)\\b"), CI);
    if (!w.from.isValid()) {
        if (auto m = nextWeek.match(s); m.hasMatch()) {
            const QDate mon = today.addDays(8 - today.dayOfWeek());
            w.from = mon; w.to = mon.addDays(7); cut(m);
        } else if (auto m2 = thisWeek.match(s); m2.hasMatch()) {
            w.from = today; w.to = today.addDays(8 - today.dayOfWeek()); cut(m2);
        } else if (auto m3 = soon.match(s); m3.hasMatch()) {
            w.from = today; w.to = today.addDays(7); cut(m3);
        }
    }
    // 今天 / 明天 / today / tomorrow …
    static const QRegularExpression rel(QStringLiteral("大后天|后天|明天|明日|今天|今日|昨天|\\b(?:day after tomorrow|tomorrow|tmr|today|yesterday)\\b"), CI);
    if (auto m = rel.match(s); m.hasMatch()) {
        const QString r = m.captured(0).toLower();
        const int off = r == "大后天" ? 3 : (r == "后天" || r == "day after tomorrow") ? 2
                      : (r == "明天" || r == "明日" || r == "tomorrow" || r == "tmr") ? 1 : (r == "昨天" || r == "yesterday") ? -1 : 0;
        if (!w.from.isValid()) setDay(today.addDays(off));
        cut(m);
    }
    // 11月25日 / 25号 / Nov 25
    static const QRegularExpression md(QStringLiteral("(%1)月(%1)[日号]?").arg(kNum));
    static const QRegularExpression dOnly(QStringLiteral("(?<![\\d月])(%1)[日号]").arg(kNum));
    static const QRegularExpression mdEn(QStringLiteral("\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b"), CI);
    auto setMd = [&](int month, int day) {
        QDate d(today.year(), month, day);
        if (d.isValid() && d < today.addDays(-30)) d = d.addYears(1);
        if (d.isValid() && !w.from.isValid()) setDay(d);
    };
    if (auto m = md.match(s); m.hasMatch()) {
        setMd(cnNum(m.captured(1)), cnNum(m.captured(2)));
        cut(m);
    } else if (auto me = mdEn.match(s); me.hasMatch()) {
        static const QStringList months{"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"};
        setMd(months.indexOf(me.captured(1).toLower()) + 1, me.captured(2).toInt());
        cut(me);
    } else if (auto m2 = dOnly.match(s); m2.hasMatch()) {
        QDate d(today.year(), today.month(), qBound(1, cnNum(m2.captured(1)), 31));
        if (d.isValid() && d < today) d = d.addMonths(1);
        if (d.isValid() && !w.from.isValid()) setDay(d);
        cut(m2);
    }

    // 时间（中文，可带「到」形成区间）
    const QString P = QStringLiteral("(凌晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里)?");
    const QString T = QStringLiteral("(?:(\\d{1,2})[:：](\\d{2})|(%1)\\s*[点时](?:\\s*(半|一刻|三刻|\\d{1,2}分?|%2分?))?)").arg(kNum, kCn);
    static const QRegularExpression timeRe(P + "\\s*" + T + "(?:\\s*(?:到|至|-|~|－|—|–)\\s*" + P + "\\s*" + T + ")?");
    // 英文：3pm / 3:30 pm / 15:00 / at 3 / 3-4pm / from 2 to 3:30pm
    static const QRegularExpression timeEn(QStringLiteral(
        "\\b(?:(at|from)\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?(?:\\s*(?:-|–|to|until|till)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?)?\\b"), CI);
    static const QRegularExpression periodEn(QStringLiteral("\\b(morning|afternoon|evening|night|noon)\\b"), CI);
    const QString enPeriod = periodEn.match(s).captured(1).toLower();
    auto toTime = [](const QString &period, const QString &hh, const QString &mm, const QString &hw, const QString &mw, const QString &fallbackPeriod) {
        int h = !hh.isEmpty() ? hh.toInt() : cnNum(hw);
        int mi = 0;
        if (!mm.isEmpty()) mi = mm.toInt();
        else if (mw == "半") mi = 30;
        else if (mw == "一刻") mi = 15;
        else if (mw == "三刻") mi = 45;
        else if (!mw.isEmpty()) mi = qMax(0, cnNum(mw));
        const QString p = period.isEmpty() ? fallbackPeriod : period;
        static const QStringList pm{"下午", "傍晚", "晚上", "夜里", "午后"};
        if (pm.contains(p) && h < 12) h += 12;
        else if (p == "中午" && h < 6) h += 12;
        else if (p.isEmpty() && h >= 1 && h <= 7 && hh.isEmpty()) h += 12;   // 「3点开会」默认下午
        return QTime(h % 24, qBound(0, mi, 59));
    };
    auto enTime = [&](const QString &hh, const QString &mm, QString ampm, const QString &fallbackAmpm) {
        int h = hh.toInt();
        const int mi = mm.isEmpty() ? 0 : mm.toInt();
        if (ampm.isEmpty()) ampm = fallbackAmpm;
        ampm = ampm.toLower();
        if (ampm == "pm" && h < 12) h += 12;
        else if (ampm == "am" && h == 12) h = 0;
        else if (ampm.isEmpty() && mm.isEmpty()) {
            if ((enPeriod == "afternoon" || enPeriod == "evening" || enPeriod == "night") && h < 12) h += 12;
            else if (enPeriod.isEmpty() && h >= 1 && h <= 7) h += 12;   // "at 3" 默认下午
        }
        return QTime(h % 24, qBound(0, mi, 59));
    };
    bool gotTime = false;
    // 英文时间必须带 am/pm、冒号、或 at/from 前缀，避免把「1 hour」里的数字当成时间
    auto tryEnglish = [&](bool requireAmPm) {
        auto it = timeEn.globalMatch(s);
        while (it.hasNext()) {
            const auto m = it.next();
            const bool marked = !m.captured(4).isEmpty() || !m.captured(3).isEmpty() || !m.captured(1).isEmpty() || !m.captured(7).isEmpty();
            if (!marked || (requireAmPm && m.captured(4).isEmpty() && m.captured(7).isEmpty())) continue;
            const QString after = s.mid(m.capturedEnd()).trimmed().toLower();
            if (after.startsWith("hour") || after.startsWith("hr") || after.startsWith("min")) continue;
            const bool hasEnd = !m.captured(5).isEmpty();
            w.start = enTime(m.captured(2), m.captured(3), m.captured(4), hasEnd ? m.captured(7) : QString());
            if (hasEnd) {
                QTime e = enTime(m.captured(5), m.captured(6), m.captured(7), m.captured(4));
                if (e <= w.start && e.hour() + 12 < 24) e = e.addSecs(12 * 3600);
                w.end = e;
            }
            cut(m);
            return true;
        }
        return false;
    };
    // 带 am/pm，或整句没有中文 → 按英文解析；否则先按中文（「下午3:30」里的「下午」决定上下午）
    static const QRegularExpression hasCjk(QStringLiteral("[\x{4e00}-\x{9fff}]"));
    const bool chinese = hasCjk.match(s).hasMatch();
    gotTime = tryEnglish(true) || (!chinese && tryEnglish(false));
    if (!gotTime) {
        if (auto m = timeRe.match(s); m.hasMatch()) {
            w.start = toTime(m.captured(1), m.captured(2), m.captured(3), m.captured(4), m.captured(5), QString());
            if (!m.captured(7).isEmpty() || !m.captured(9).isEmpty()) {
                QTime e = toTime(m.captured(6), m.captured(7), m.captured(8), m.captured(9), m.captured(10), m.captured(1));
                if (e <= w.start && e.hour() + 12 < 24) e = e.addSecs(12 * 3600);
                w.end = e;
            }
            cut(m);
            gotTime = true;
        } else {
            gotTime = tryEnglish(false);
        }
    }
    if (!gotTime) {
        // 只有时段（「明天下午有空吗」/ "tomorrow afternoon"）：给出时段范围，便于查空闲
        static const QRegularExpression periodOnly(QStringLiteral("上午|下午|晚上|\\b(?:morning|afternoon|evening)\\b"), CI);
        if (auto m2 = periodOnly.match(s); m2.hasMatch()) {
            const QString p = m2.captured(0).toLower();
            const bool am = p == "上午" || p == "morning", pmA = p == "下午" || p == "afternoon";
            w.start = am ? QTime(9, 0) : pmA ? QTime(13, 0) : QTime(18, 0);
            w.end = am ? QTime(12, 0) : pmA ? QTime(18, 0) : QTime(22, 0);
            w.durationMin = -1;   // 标记：时间来自时段词，不是具体时刻
            cut(m2);
        }
    } else if (!enPeriod.isEmpty()) {
        s.replace(periodEn, QStringLiteral(" "));
    }
    // 时长
    static const QRegularExpression dur(QStringLiteral("(?:(\\d+|[一两二三四五六七八九十]+)\\s*个?\\s*(半)?\\s*(?:小时|钟头)|(半)\\s*个?\\s*(?:小时|钟头)|(\\d+|[一二两三四五六七八九十]+)\\s*分钟)"));
    static const QRegularExpression durEn(QStringLiteral("\\b(?:for\\s+)?(?:(\\d+(?:\\.\\d+)?|an|one|two)\\s*(?:hours?|hrs?)|(half an hour|half hour)|(\\d+)\\s*(?:minutes?|mins?))\\b"), CI);
    if (auto m = dur.match(s); m.hasMatch()) {
        if (!m.captured(1).isEmpty()) w.durationMin = cnNum(m.captured(1)) * 60 + (m.captured(2).isEmpty() ? 0 : 30);
        else if (!m.captured(3).isEmpty()) w.durationMin = 30;
        else w.durationMin = cnNum(m.captured(4));
        cut(m);
    } else if (auto me = durEn.match(s); me.hasMatch()) {
        const QString h = me.captured(1).toLower();
        if (!h.isEmpty()) w.durationMin = int((h == "an" || h == "one") ? 60 : h == "two" ? 120 : h.toDouble() * 60);
        else if (!me.captured(2).isEmpty()) w.durationMin = 30;
        else w.durationMin = me.captured(3).toInt();
        cut(me);
    }
    w.rest = s.simplified();
    return w;
}

// MARK: 回复

QVariantMap Assistant::respond(const QString &text, const QDateTime &now)
{
    QVariantMap r = respondImpl(text, now);
    // 英文回复可能以「today (…)」这类小写开头（中文模板里它在句中），句首大写
    QString t = r["text"].toString();
    if (en() && !t.isEmpty()) r["text"] = t.left(1).toUpper() + t.mid(1);
    return r;
}

QVariantMap Assistant::respondImpl(const QString &text, const QDateTime &now)
{
    auto *cs = CalendarStore::instance();
    const QDate today = now.date();
    const QString t = text.trimmed();
    const QString low = t.toLower();
    When w = parseWhen(t, today);
    const bool periodOnly = w.durationMin == -1;
    if (periodOnly) w.durationMin = 0;
    auto has = [&](const char *re) { return QRegularExpression(QString::fromUtf8(re), CI).match(low).hasMatch(); };
    const bool isQuestion = has("(有什么|有哪些|有没有|几个|什么|吗|么|？|\\?|查一?下|看看|列出|多少|\\b(?:what|whats|any|do i|am i|show|list|how many|when)\\b)");
    QVariantMap r;
    auto items = [](const QList<QVariantMap> &l, int max = 8) {
        QVariantList out;
        for (int i = 0; i < l.size() && i < max; ++i) out << l[i];
        return out;
    };

    // 1. 帮助
    if (has("^(你好|hi\\b|hello|hey\\b|嗨|在吗)") || has("(帮助|\\bhelp\\b|能做什么|会做什么|怎么用|what can you do)")) {
        r["text"] = tr("我可以帮你：\n• 查日程：「明天有什么安排」「下周的会议」\n• 找空闲：「周三下午有空吗」\n"
                       "• 下一个会议、今日概览\n• 新建活动：「周五上午10点 和设计对齐 半小时」\n• 新建待办：「提醒我明天交报告」");
        return r;
    }

    // 2. 新建待办
    if (has("(提醒我|记得|添加待办|新建待办|加个?待办|创建待办|^待办[:：]|^todo[:：]|\\bremind me\\b|\\badd (?:a )?(?:todo|task)\\b|\\bnew (?:todo|task)\\b|^task:)")) {
        QString title = cleanTitle(w.rest);
        if (title.isEmpty()) { r["text"] = tr("要提醒你做什么呢？比如「提醒我明天交周报」。"); return r; }
        QDate due = w.from.isValid() && w.singleDay ? w.from : QDate();
        QString dueTime;
        if (w.start.isValid() && !periodOnly) {
            if (!due.isValid()) due = w.start > now.time() ? today : today.addDays(1);
            dueTime = w.start.toString("HH:mm");
        }
        const QString uid = cs->createTodo({{"title", title}, {"calendarId", cs->defaultTodoList()},
                                           {"dueIso", due.isValid() ? due.toString(Qt::ISODate) : QString()}, {"dueTime", dueTime}});
        r["text"] = due.isValid() ? tr("已添加待办「%1」，截止 %2。").arg(title, dayLabel(due, today) + (dueTime.isEmpty() ? QString() : QStringLiteral(" ") + dueTime))
                                  : tr("已添加待办「%1」（无截止日期）。").arg(title);
        r["items"] = QVariantList{cs->todo(uid)};
        r["action"] = QVariantMap{{"label", tr("撤销")}, {"kind", "deleteTodo"}, {"uid", uid}};
        return r;
    }

    // 3. 新建活动（需要具体时间，或明确「全天」）
    const bool createVerb = has("(安排|约|预约|创建|新建|添加|加个|加一个|订|开个|定个|建个|\\b(?:schedule|add|create|book|set up|put)\\b)");
    const bool allDay = has("(全天|\\ball[- ]day\\b)");
    const bool looksLikeEvent = (w.start.isValid() && !periodOnly && !isQuestion && !has("(有空|空闲|空档|\\bfree\\b|\\bavailab)"));
    if ((createVerb && !isQuestion && (w.start.isValid() || allDay)) || looksLikeEvent) {
        if (periodOnly && !allDay) { r["text"] = tr("具体几点开始呢？比如「明天下午3点 需求评审」。"); return r; }
        QString title = cleanTitle(w.rest);
        if (title.isEmpty()) title = tr("新活动");
        QDate day = w.from.isValid() ? w.from : (w.start.isValid() && w.start < now.time() ? today.addDays(1) : today);
        QVariantMap m{{"title", title}, {"calendarId", cs->defaultCalendar()}, {"reminder", 10}};
        QDateTime s, e;
        if (allDay && !w.start.isValid()) {
            s = QDateTime(day, QTime(0, 0));
            m["allDay"] = true; m["startMs"] = double(s.toMSecsSinceEpoch()); m["endMs"] = double(s.toMSecsSinceEpoch());
        } else {
            s = QDateTime(day, w.start);
            e = w.end.isValid() ? QDateTime(day, w.end) : s.addSecs(60 * (w.durationMin > 0 ? w.durationMin : 60));
            m["startMs"] = double(s.toMSecsSinceEpoch()); m["endMs"] = double(e.toMSecsSinceEpoch());
        }
        // 冲突检查
        QStringList conflicts;
        if (e.isValid())
            for (const QVariantMap &x : maps(cs->occurrences(day.toString(Qt::ISODate), day.addDays(1).toString(Qt::ISODate))))
                if (isTimed(x) && x["startMs"].toDouble() < e.toMSecsSinceEpoch() && x["endMs"].toDouble() > s.toMSecsSinceEpoch())
                    conflicts << tr("「%1」").arg(x["title"].toString());
        const QString uid = cs->createEvent(m);
        const QVariantMap ev = cs->event(uid);
        QString txt = tr("已在「%1」创建「%2」：%3 %4。").arg(ev["calendarName"].toString(), title, dayLabel(day, today),
                                                          allDay && !w.start.isValid() ? tr("全天") : s.toString("HH:mm") + QStringLiteral("–") + e.toString("HH:mm"));
        if (!conflicts.isEmpty()) txt += QStringLiteral("\n") + tr("⚠ 与 %1 时间重叠。").arg(conflicts.join(tr("、")));
        r["text"] = txt;
        r["items"] = QVariantList{ev};
        r["action"] = QVariantMap{{"label", tr("撤销")}, {"kind", "deleteEvent"}, {"uid", uid}};
        return r;
    }

    // 4. 空闲时间
    if (has("(有空|空闲|空档|空余|没事|闲|\\bfree\\b|\\bavailab|open slot)")) {
        const QDate from = w.from.isValid() ? w.from : today;
        const QDate to = w.from.isValid() ? w.to : today.addDays(1);
        const int need = w.durationMin > 0 ? w.durationMin : 30;
        QStringList lines;
        int days = 0;
        for (QDate d = from; d < to && days < 7; d = d.addDays(1), ++days) {
            if (d < today) continue;
            QList<QPair<QDateTime, QDateTime>> daySlots = freeSlots(d, now, need);
            if (w.start.isValid()) {   // 限定在问到的时段内
                QList<QPair<QDateTime, QDateTime>> clipped;
                const QDateTime a(d, w.start), b(d, w.end.isValid() ? w.end : w.start.addSecs(3600 * 2));
                for (auto sl : daySlots) {
                    sl.first = qMax(sl.first, a); sl.second = qMin(sl.second, b);
                    if (sl.first.secsTo(sl.second) >= need * 60) clipped << sl;
                }
                daySlots = clipped;
            }
            QStringList ss;
            for (const auto &sl : daySlots) ss << slotText(sl);
            lines << tr("%1：%2").arg(dayShort(d, today), ss.isEmpty() ? tr("没有空档") : ss.join(tr("、")));
        }
        QString txt = lines.size() == 1 ? tr("工作时间（9:00–18:00）内，%1").arg(lines[0])
                                        : tr("工作时间（9:00–18:00）内的空闲时段：") + QStringLiteral("\n• ") + lines.join(QStringLiteral("\n• "));
        if (w.durationMin > 0) txt += QStringLiteral("\n") + tr("（已按至少 %1 分钟筛选）").arg(w.durationMin);
        r["text"] = txt;
        return r;
    }

    // 5. 下一个会议
    if (has("((下一个|下个|接下来|最近的).{0,4}(会|安排|日程|活动)|\\bnext (?:meeting|event|one)\\b|what'?s next|up next)")) {
        for (const QVariantMap &e : maps(cs->occurrences(today.toString(Qt::ISODate), today.addDays(15).toString(Qt::ISODate)))) {
            if (!isTimed(e) || e["endMs"].toDouble() <= now.toMSecsSinceEpoch()) continue;
            const qint64 mins = now.secsTo(QDateTime::fromMSecsSinceEpoch(qint64(e["startMs"].toDouble()))) / 60;
            const QString when = mins <= 0 ? tr("正在进行中") : mins < 60 ? tr("还有 %n 分钟", "", int(mins))
                               : mins < 24 * 60 ? tr("还有 %1 小时 %2 分钟").arg(mins / 60).arg(mins % 60) : QString();
            QString txt = tr("下一个是「%1」，%2 %3 开始").arg(e["title"].toString(),
                              dayShort(QDate::fromString(e["startIso"].toString(), Qt::ISODate), today), hm(e["startMs"].toDouble()));
            if (!when.isEmpty()) txt += tr("（%1）").arg(when);
            if (!e["location"].toString().isEmpty()) txt += tr("，地点：%1").arg(e["location"].toString());
            r["text"] = txt + tr("。");
            r["items"] = QVariantList{e};
            return r;
        }
        r["text"] = tr("未来两周没有会议，可以专心干活了。");
        return r;
    }

    // 6. 今日概览
    if (has("(总结|概览|简报|日报|怎么样|情况|overview|summary|briefing|\\bbrief\\b|my day)") && !w.from.isValid()) {
        const QList<QVariantMap> evs = maps(cs->occurrences(today.toString(Qt::ISODate), today.addDays(1).toString(Qt::ISODate)));
        int timed = 0, left = 0;
        QVariantMap next;
        for (const QVariantMap &e : evs)
            if (isTimed(e)) {
                ++timed;
                if (e["endMs"].toDouble() > now.toMSecsSinceEpoch()) { ++left; if (next.isEmpty()) next = e; }
            }
        const QList<QVariantMap> todos = maps(cs->todos("today"));
        int overdue = 0;
        for (const QVariantMap &x : todos) overdue += x["overdue"].toBool() ? 1 : 0;
        int freeMin = 0;
        for (const auto &sl : freeSlots(today, now, 15)) freeMin += sl.first.secsTo(sl.second) / 60;
        QString txt = tr("今天（%1）共 %2 个会议，还剩 %3 个").arg(dateText(today)).arg(timed).arg(left);
        if (!next.isEmpty()) txt += tr("，下一个是 %1「%2」").arg(hm(next["startMs"].toDouble()), next["title"].toString());
        txt += tr("。") + QStringLiteral("\n") + tr("待办 %n 项", "", int(todos.size()));
        if (overdue) txt += tr("（%n 项已逾期）", "", overdue);
        txt += tr("；工作时间内还有约 %1 小时 %2 分钟空闲。").arg(freeMin / 60).arg(freeMin % 60);
        r["text"] = txt;
        QList<QVariantMap> show;
        for (const QVariantMap &e : evs) if (e["endMs"].toDouble() > now.toMSecsSinceEpoch()) show << e;
        r["items"] = items(show, 5);
        return r;
    }

    // 7. 待办查询
    if (has("(待办|任务|todo|要做|没做完|未完成|提醒事项|\\btasks?\\b|to-?dos?|to do)")) {
        QList<QVariantMap> list;
        QString scope;
        if (w.from.isValid()) {
            for (const QVariantMap &x : maps(cs->todosInRange(w.from.toString(Qt::ISODate), w.to.toString(Qt::ISODate))))
                if (!x["done"].toBool()) list << x;
            scope = rangeLabel(w, today);
        } else {
            list = maps(cs->todos("today"));
            scope = tr("今天（含逾期）");
        }
        if (list.isEmpty()) {
            r["text"] = w.from.isValid() ? tr("%1没有未完成的待办 🎉").arg(scope)
                                         : tr("%1没有未完成的待办 🎉，全部列表里还有 %2 项。").arg(scope).arg(cs->todos("all").size());
            return r;
        }
        QStringList lines;
        for (const QVariantMap &x : list)
            lines << QStringLiteral("• ") + x["title"].toString()
                         + (x["overdue"].toBool() ? tr("（已逾期）") : x["dueTime"].toString().isEmpty() ? QString() : tr("（%1 截止）").arg(x["dueTime"].toString()));
        r["text"] = tr("%1有 %n 项待办：", "", int(list.size())).arg(scope) + QStringLiteral("\n") + lines.mid(0, 8).join('\n');
        r["items"] = items(list);
        return r;
    }

    // 8. 日程查询（提到了日期，或问安排 / 会议）
    if (w.from.isValid() || has("(安排|日程|会议|开会|会|忙|活动|行程|calendar|schedule|agenda|meetings?|events?|\\bbusy\\b|\\bplans?\\b)")) {
        if (!w.from.isValid()) { w.from = today; w.to = today.addDays(1); w.singleDay = true; }
        const bool meetingsOnly = has("(会议|开会|会$|meeting)");
        QList<QVariantMap> list;
        for (const QVariantMap &e : maps(cs->occurrences(w.from.toString(Qt::ISODate), w.to.toString(Qt::ISODate)))) {
            if (meetingsOnly && !isTimed(e)) continue;
            if (w.start.isValid() && isTimed(e)) {   // 「明天下午有什么会」
                const QTime st = QDateTime::fromMSecsSinceEpoch(qint64(e["startMs"].toDouble())).time();
                if (st < w.start || (w.end.isValid() && st >= w.end)) continue;
            }
            list << e;
        }
        if (list.isEmpty()) {
            r["text"] = (meetingsOnly ? tr("%1没有会议。") : tr("%1没有安排。")).arg(rangeLabel(w, today));
            return r;
        }
        QStringList lines;
        for (const QVariantMap &e : list) lines << eventLine(e, !w.singleDay, today);
        const QString head = meetingsOnly ? tr("%1有 %n 个会议：", "", int(list.size())) : tr("%1有 %n 个安排：", "", int(list.size()));
        r["text"] = head.arg(rangeLabel(w, today)) + QStringLiteral("\n") + lines.mid(0, 10).join('\n')
                    + (lines.size() > 10 ? QStringLiteral("\n……") : QString());
        r["items"] = items(list);
        return r;
    }

    r["text"] = tr("我还不太明白。可以试试：「明天有什么安排」「周三下午有空吗」「明天下午3点 需求评审」「提醒我周五交周报」。");
    return r;
}
