#include "ical.h"

#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>
#include <QTimeZone>
#include <algorithm>

namespace ical {
namespace {

// MARK: 行与属性

struct Prop {
    QString name;
    QHash<QString, QString> params;
    QString value;
};

/// 折行还原（RFC 5545 §3.1：CRLF 后跟空格/Tab 表示续行）
QStringList unfold(const QByteArray &data)
{
    const QString text = QString::fromUtf8(data);
    QStringList out;
    for (QString line : text.split(QLatin1Char('\n'))) {
        if (line.endsWith(QLatin1Char('\r'))) line.chop(1);
        if ((line.startsWith(QLatin1Char(' ')) || line.startsWith(QLatin1Char('\t'))) && !out.isEmpty())
            out.last() += line.mid(1);
        else if (!line.isEmpty())
            out << line;
    }
    return out;
}

Prop parseLine(const QString &line)
{
    Prop p;
    // 名字和参数里可能有带引号的冒号，找第一个不在引号里的冒号
    bool quoted = false;
    int colon = -1;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (c == QLatin1Char('"')) quoted = !quoted;
        else if (c == QLatin1Char(':') && !quoted) { colon = i; break; }
    }
    if (colon < 0) return p;
    p.value = line.mid(colon + 1);
    const QStringList head = line.left(colon).split(QLatin1Char(';'));
    p.name = head.value(0).toUpper();
    for (int i = 1; i < head.size(); ++i) {
        const int eq = head[i].indexOf(QLatin1Char('='));
        if (eq < 0) continue;
        QString v = head[i].mid(eq + 1);
        if (v.startsWith(QLatin1Char('"')) && v.endsWith(QLatin1Char('"')) && v.size() >= 2) v = v.mid(1, v.size() - 2);
        p.params.insert(head[i].left(eq).toUpper(), v);
    }
    return p;
}

QString unescape(const QString &s)
{
    QString out;
    out.reserve(s.size());
    for (int i = 0; i < s.size(); ++i) {
        const QChar c = s.at(i);
        if (c == QLatin1Char('\\') && i + 1 < s.size()) {
            const QChar n = s.at(++i);
            if (n == QLatin1Char('n') || n == QLatin1Char('N')) out += QLatin1Char('\n');
            else out += n;   // 转义的逗号、分号、反斜杠原样保留
        } else {
            out += c;
        }
    }
    return out;
}

QString escape(const QString &s)
{
    QString out = s;
    out.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
    out.replace(QLatin1Char(';'), QLatin1String("\\;"));
    out.replace(QLatin1Char(','), QLatin1String("\\,"));
    out.replace(QLatin1Char('\n'), QLatin1String("\\n"));
    return out;
}

/// 每行最多 75 字节，超出折行（按字符折，避免把 UTF-8 多字节字符切开）
QByteArray fold(const QString &line)
{
    QByteArray out;
    QByteArray cur;
    for (const QChar c : line) {
        const QByteArray b = QString(c).toUtf8();
        if (cur.size() + b.size() > 74) {
            out += cur + "\r\n ";
            cur.clear();
        }
        cur += b;
    }
    return out + cur + "\r\n";
}

QTimeZone zoneFor(const QString &tzid)
{
    if (tzid.isEmpty()) return {};
    QTimeZone z(tzid.toUtf8());
    if (z.isValid()) return z;
    // Outlook 导出的 Windows 时区名
    const QByteArray iana = QTimeZone::windowsIdToDefaultIanaId(tzid.toUtf8());
    if (!iana.isEmpty()) return QTimeZone(iana);
    return {};
}

/// 返回本地时间；*isDate 表示 VALUE=DATE（全天）
QDateTime parseDateTime(const QString &value, const QHash<QString, QString> &params, bool *isDate = nullptr)
{
    const QString v = value.trimmed();
    const bool dateOnly = params.value(QStringLiteral("VALUE")).compare(QLatin1String("DATE"), Qt::CaseInsensitive) == 0
                          || (v.size() == 8 && !v.contains(QLatin1Char('T')));
    if (isDate) *isDate = dateOnly;
    if (dateOnly) {
        const QDate d = QDate::fromString(v.left(8), QStringLiteral("yyyyMMdd"));
        return d.isValid() ? QDateTime(d, QTime(0, 0)) : QDateTime();
    }
    const bool utc = v.endsWith(QLatin1Char('Z'));
    const QString core = v.left(15);
    const QDate d = QDate::fromString(core.left(8), QStringLiteral("yyyyMMdd"));
    const QTime t = QTime::fromString(core.mid(9, 6), QStringLiteral("HHmmss"));
    if (!d.isValid() || !t.isValid()) return {};
    if (utc) return QDateTime(d, t, Qt::UTC).toLocalTime();
    const QTimeZone z = zoneFor(params.value(QStringLiteral("TZID")));
    if (z.isValid()) return QDateTime(d, t, z).toLocalTime();
    return QDateTime(d, t);   // 浮动时间 = 本地
}

/// P1D / PT1H30M / -PT15M / P1W → 秒
qint64 parseDuration(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^([+-])?P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$"));
    const auto m = re.match(s.trimmed().toUpper());
    if (!m.hasMatch()) return 0;
    qint64 secs = m.captured(2).toLongLong() * 7 * 86400 + m.captured(3).toLongLong() * 86400
                  + m.captured(4).toLongLong() * 3600 + m.captured(5).toLongLong() * 60 + m.captured(6).toLongLong();
    return m.captured(1) == QLatin1String("-") ? -secs : secs;
}

QString fmtDate(const QDate &d) { return d.toString(QStringLiteral("yyyyMMdd")); }
QString fmtDateTime(const QDateTime &dt) { return dt.toString(QStringLiteral("yyyyMMdd'T'HHmmss")); }
QString fmtUtc(const QDateTime &dt) { return dt.toUTC().toString(QStringLiteral("yyyyMMdd'T'HHmmss'Z'")); }

// MARK: RRULE

struct ByDay { int ordinal = 0; int weekday = 1; };   // weekday: 1 = 周一 … 7 = 周日（Qt 约定）

struct Rule {
    QString freq;
    int interval = 1;
    int count = 0;
    QDateTime until;
    QList<ByDay> byDay;
    QList<int> byMonthDay, byMonth, bySetPos;
};

int weekdayOf(const QString &code)
{
    static const QStringList codes{QStringLiteral("MO"), QStringLiteral("TU"), QStringLiteral("WE"), QStringLiteral("TH"),
                                   QStringLiteral("FR"), QStringLiteral("SA"), QStringLiteral("SU")};
    return codes.indexOf(code.toUpper()) + 1;   // 0 = 无效
}

QList<int> intList(const QString &v)
{
    QList<int> out;
    for (const QString &s : v.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        bool ok = false;
        const int n = s.toInt(&ok);
        if (ok && n != 0) out << n;
    }
    return out;
}

Rule parseRule(const QString &rrule)
{
    Rule r;
    for (const QString &part : rrule.split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
        const int eq = part.indexOf(QLatin1Char('='));
        if (eq < 0) continue;
        const QString k = part.left(eq).toUpper(), v = part.mid(eq + 1);
        if (k == QLatin1String("FREQ")) r.freq = v.toUpper();
        else if (k == QLatin1String("INTERVAL")) r.interval = qMax(1, v.toInt());
        else if (k == QLatin1String("COUNT")) r.count = qMax(0, v.toInt());
        else if (k == QLatin1String("UNTIL")) {
            bool isDate = false;
            r.until = parseDateTime(v, {}, &isDate);
            if (isDate) r.until = r.until.addDays(1).addSecs(-1);   // 日期形式的 UNTIL 包含当天
        } else if (k == QLatin1String("BYDAY")) {
            static const QRegularExpression re(QStringLiteral("^([+-]?\\d{1,2})?([A-Za-z]{2})$"));
            for (const QString &d : v.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                const auto m = re.match(d.trimmed());
                if (!m.hasMatch()) continue;
                const int wd = weekdayOf(m.captured(2));
                if (wd) r.byDay << ByDay{m.captured(1).toInt(), wd};
            }
        } else if (k == QLatin1String("BYMONTHDAY")) r.byMonthDay = intList(v);
        else if (k == QLatin1String("BYMONTH")) r.byMonth = intList(v);
        else if (k == QLatin1String("BYSETPOS")) r.bySetPos = intList(v);
    }
    return r;
}

/// 某月里符合 BYDAY 的日期（ordinal=0 表示该月所有这个星期几；负数从月末数）
QList<QDate> byDayInMonth(int y, int m, const QList<ByDay> &days)
{
    QList<QDate> out;
    const QDate first(y, m, 1);
    const int dim = first.daysInMonth();
    for (const ByDay &bd : days) {
        QList<QDate> all;
        for (int d = 1; d <= dim; ++d) {
            const QDate x(y, m, d);
            if (x.dayOfWeek() == bd.weekday) all << x;
        }
        if (bd.ordinal == 0) out += all;
        else if (bd.ordinal > 0 && bd.ordinal <= all.size()) out << all[bd.ordinal - 1];
        else if (bd.ordinal < 0 && -bd.ordinal <= all.size()) out << all[all.size() + bd.ordinal];
    }
    return out;
}

QList<QDate> byMonthDayIn(int y, int m, const QList<int> &days)
{
    QList<QDate> out;
    const int dim = QDate(y, m, 1).daysInMonth();
    for (int d : days) {
        const int day = d > 0 ? d : dim + d + 1;
        if (day >= 1 && day <= dim) out << QDate(y, m, day);
    }
    return out;
}

QList<QDate> applySetPos(QList<QDate> c, const QList<int> &pos)
{
    std::sort(c.begin(), c.end());
    c.erase(std::unique(c.begin(), c.end()), c.end());
    if (pos.isEmpty()) return c;
    QList<QDate> out;
    for (int p : pos) {
        const int i = p > 0 ? p - 1 : c.size() + p;
        if (i >= 0 && i < c.size()) out << c[i];
    }
    std::sort(out.begin(), out.end());
    return out;
}

/// 第 k 个周期内的候选日期（已排序，未过滤 DTSTART 之前的日期）
QList<QDate> candidates(const Rule &r, const QDate &start, int k)
{
    QList<QDate> c;
    if (r.freq == QLatin1String("DAILY")) {
        const QDate d = start.addDays(qint64(k) * r.interval);
        bool ok = r.byMonth.isEmpty() || r.byMonth.contains(d.month());
        if (ok && !r.byDay.isEmpty())
            ok = std::any_of(r.byDay.begin(), r.byDay.end(), [&](const ByDay &b) { return b.weekday == d.dayOfWeek(); });
        if (ok && !r.byMonthDay.isEmpty())
            ok = byMonthDayIn(d.year(), d.month(), r.byMonthDay).contains(d);
        if (ok) c << d;
        return c;
    }
    if (r.freq == QLatin1String("WEEKLY")) {
        const QDate weekStart = start.addDays(1 - start.dayOfWeek()).addDays(qint64(k) * 7 * r.interval);   // WKST=MO
        if (r.byDay.isEmpty()) c << weekStart.addDays(start.dayOfWeek() - 1);
        for (const ByDay &b : r.byDay) c << weekStart.addDays(b.weekday - 1);
        if (!r.byMonth.isEmpty())
            c.erase(std::remove_if(c.begin(), c.end(), [&](const QDate &d) { return !r.byMonth.contains(d.month()); }), c.end());
        return applySetPos(c, r.bySetPos);
    }
    if (r.freq == QLatin1String("MONTHLY")) {
        const QDate m = QDate(start.year(), start.month(), 1).addMonths(k * r.interval);
        if (!r.byMonth.isEmpty() && !r.byMonth.contains(m.month())) return c;
        if (!r.byMonthDay.isEmpty()) {
            c = byMonthDayIn(m.year(), m.month(), r.byMonthDay);
            if (!r.byDay.isEmpty())   // 两者同时出现时取交集（如「13 号且是周五」）
                c.erase(std::remove_if(c.begin(), c.end(), [&](const QDate &d) {
                            return std::none_of(r.byDay.begin(), r.byDay.end(), [&](const ByDay &b) { return b.weekday == d.dayOfWeek(); });
                        }), c.end());
        } else if (!r.byDay.isEmpty()) {
            c = byDayInMonth(m.year(), m.month(), r.byDay);
        } else if (start.day() <= m.daysInMonth()) {
            c << QDate(m.year(), m.month(), start.day());   // 31 号的月重复在小月跳过（RFC 行为）
        }
        return applySetPos(c, r.bySetPos);
    }
    if (r.freq == QLatin1String("YEARLY")) {
        const int y = start.year() + k * r.interval;
        const QList<int> months = r.byMonth.isEmpty() ? QList<int>{start.month()} : r.byMonth;
        for (int mo : months) {
            if (!r.byMonthDay.isEmpty()) c += byMonthDayIn(y, mo, r.byMonthDay);
            else if (!r.byDay.isEmpty()) c += byDayInMonth(y, mo, r.byDay);
            else if (QDate(y, mo, 1).daysInMonth() >= start.day()) c << QDate(y, mo, start.day());   // 2/29 只在闰年
        }
        return applySetPos(c, r.bySetPos);
    }
    return c;
}

QDate periodStart(const Rule &r, const QDate &start, int k)
{
    if (r.freq == QLatin1String("DAILY")) return start.addDays(qint64(k) * r.interval);
    if (r.freq == QLatin1String("WEEKLY")) return start.addDays(1 - start.dayOfWeek()).addDays(qint64(k) * 7 * r.interval);
    if (r.freq == QLatin1String("MONTHLY")) return QDate(start.year(), start.month(), 1).addMonths(k * r.interval);
    return QDate(start.year() + k * r.interval, 1, 1);
}

}  // namespace

// MARK: 公开接口

qint64 durationSecs(const Event &e)
{
    const qint64 d = e.start.secsTo(e.end);
    if (e.allDay) return qMax<qint64>(d, 86400);
    return qMax<qint64>(d, 0);
}

QList<QDateTime> expand(const Event &e, const QDateTime &from, const QDateTime &to, int maxResults)
{
    QList<QDateTime> out;
    if (!e.start.isValid()) return out;
    const qint64 dur = durationSecs(e);
    auto overlaps = [&](const QDateTime &s) {
        return s < to && (dur > 0 ? s.addSecs(dur) > from : s >= from);
    };
    const Rule r = e.rrule.isEmpty() ? Rule{} : parseRule(e.rrule);
    if (r.freq.isEmpty()) {
        if (overlaps(e.start)) out << e.start;
        return out;
    }
    QSet<qint64> excluded;
    for (const QDateTime &x : e.exdates)
        excluded.insert(e.allDay ? QDateTime(x.date(), QTime(0, 0)).toSecsSinceEpoch() : x.toSecsSinceEpoch());

    int produced = 0;
    for (int k = 0; k < 50000; ++k) {
        const QList<QDate> cand = candidates(r, e.start.date(), k);
        bool past = false;
        for (const QDate &d : cand) {
            const QDateTime s(d, e.start.time());
            if (s < e.start) continue;
            if (r.until.isValid() && s > r.until) { past = true; break; }
            if (r.count && produced >= r.count) { past = true; break; }
            ++produced;   // 被 EXDATE 排除的实例也计入 COUNT（RFC 5545）
            if (s >= to) { past = true; break; }
            if (excluded.contains(s.toSecsSinceEpoch())) continue;
            if (overlaps(s)) {
                out << s;
                if (out.size() >= maxResults) return out;
            }
        }
        if (past || periodStart(r, e.start.date(), k) > to.date()) break;   // 周期起点已越过区间：之后不会再有实例
    }
    return out;
}

Calendar parse(const QByteArray &data)
{
    Calendar cal;
    enum class In { None, Event, Todo, Alarm } in = In::None, parent = In::None;
    Event ev;
    Todo td;
    QDateTime dtEndTodo;
    qint64 duration = -1;
    bool startIsDate = false, hasEnd = false;

    for (const QString &line : unfold(data)) {
        const Prop p = parseLine(line);
        if (p.name.isEmpty()) continue;
        const QString val = p.value.trimmed().toUpper();

        if (p.name == QLatin1String("BEGIN")) {
            if (val == QLatin1String("VEVENT")) { in = In::Event; ev = Event{}; duration = -1; hasEnd = false; startIsDate = false; }
            else if (val == QLatin1String("VTODO")) { in = In::Todo; td = Todo{}; }
            else if (val == QLatin1String("VALARM")) { parent = in; in = In::Alarm; }
            continue;
        }
        if (p.name == QLatin1String("END")) {
            if (val == QLatin1String("VALARM")) { in = parent; continue; }
            if (val == QLatin1String("VEVENT") && in == In::Event) {
                if (ev.start.isValid()) {
                    ev.allDay = startIsDate;
                    if (!hasEnd)
                        ev.end = duration >= 0 ? ev.start.addSecs(duration) : (ev.allDay ? ev.start.addDays(1) : ev.start);
                    if (ev.end < ev.start) ev.end = ev.start;
                    if (ev.uid.isEmpty()) ev.uid = QStringLiteral("anon-%1-%2").arg(cal.events.size()).arg(ev.start.toSecsSinceEpoch());
                    cal.events << ev;
                }
            } else if (val == QLatin1String("VTODO") && in == In::Todo) {
                if (td.uid.isEmpty()) td.uid = QStringLiteral("anon-todo-%1").arg(cal.todos.size());
                cal.todos << td;
            }
            in = In::None;
            continue;
        }

        switch (in) {
        case In::None:
            if (p.name == QLatin1String("X-WR-CALNAME")) cal.name = unescape(p.value);
            else if (p.name == QLatin1String("X-APPLE-CALENDAR-COLOR")) cal.color = p.value.left(7);
            break;
        case In::Alarm:
            if (p.name == QLatin1String("TRIGGER") && parent == In::Event && ev.reminderMinutes < 0) {
                const qint64 s = parseDuration(p.value);
                if (s <= 0) ev.reminderMinutes = int(-s / 60);
            }
            break;
        case In::Event:
            if (p.name == QLatin1String("UID")) ev.uid = p.value.trimmed();
            else if (p.name == QLatin1String("SUMMARY")) ev.title = unescape(p.value);
            else if (p.name == QLatin1String("LOCATION")) ev.location = unescape(p.value);
            else if (p.name == QLatin1String("DESCRIPTION")) ev.notes = unescape(p.value);
            else if (p.name == QLatin1String("URL")) ev.url = p.value.trimmed();
            else if (p.name == QLatin1String("DTSTART")) ev.start = parseDateTime(p.value, p.params, &startIsDate);
            else if (p.name == QLatin1String("DTEND")) { ev.end = parseDateTime(p.value, p.params); hasEnd = ev.end.isValid(); }
            else if (p.name == QLatin1String("DURATION")) duration = parseDuration(p.value);
            else if (p.name == QLatin1String("RRULE")) ev.rrule = p.value.trimmed();
            else if (p.name == QLatin1String("RECURRENCE-ID")) ev.recurrenceId = parseDateTime(p.value, p.params);
            else if (p.name == QLatin1String("EXDATE"))
                for (const QString &x : p.value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                    const QDateTime dt = parseDateTime(x, p.params);
                    if (dt.isValid()) ev.exdates << dt;
                }
            break;
        case In::Todo:
            if (p.name == QLatin1String("UID")) td.uid = p.value.trimmed();
            else if (p.name == QLatin1String("SUMMARY")) td.title = unescape(p.value);
            else if (p.name == QLatin1String("DESCRIPTION")) td.notes = unescape(p.value);
            else if (p.name == QLatin1String("PRIORITY")) td.priority = qBound(0, p.value.toInt(), 9);
            else if (p.name == QLatin1String("STATUS")) td.done = td.done || val == QLatin1String("COMPLETED");
            else if (p.name == QLatin1String("PERCENT-COMPLETE")) td.done = td.done || p.value.toInt() >= 100;
            else if (p.name == QLatin1String("COMPLETED")) { td.completed = parseDateTime(p.value, p.params); td.done = true; }
            else if (p.name == QLatin1String("DUE")) {
                bool isDate = false;
                const QDateTime d = parseDateTime(p.value, p.params, &isDate);
                td.due = d.date();
                td.dueTime = isDate ? QTime() : d.time();
            }
            break;
        }
    }

    // RECURRENCE-ID：单次修改的实例从主事件里排除，自己作为独立事件显示
    QHash<QString, int> master;
    for (int i = 0; i < cal.events.size(); ++i)
        if (!cal.events[i].recurrenceId.isValid()) master.insert(cal.events[i].uid, i);
    for (Event &e : cal.events) {
        if (!e.recurrenceId.isValid()) continue;
        if (const auto it = master.constFind(e.uid); it != master.constEnd())
            cal.events[*it].exdates << e.recurrenceId;
        e.uid += QLatin1Char('@') + QString::number(e.recurrenceId.toSecsSinceEpoch());
    }
    return cal;
}

QByteArray serialize(const QString &name, const QString &color, const QList<Event> &events, const QList<Todo> &todos)
{
    QByteArray out;
    auto put = [&](const QString &l) { out += fold(l); };
    const QString stamp = fmtUtc(QDateTime::currentDateTimeUtc());
    put(QStringLiteral("BEGIN:VCALENDAR"));
    put(QStringLiteral("VERSION:2.0"));
    put(QStringLiteral("PRODID:-//ChatDemo//Calendar 1.0//ZH"));
    put(QStringLiteral("CALSCALE:GREGORIAN"));
    if (!name.isEmpty()) put(QStringLiteral("X-WR-CALNAME:") + escape(name));
    if (!color.isEmpty()) put(QStringLiteral("X-APPLE-CALENDAR-COLOR:") + color);

    for (const Event &e : events) {
        put(QStringLiteral("BEGIN:VEVENT"));
        put(QStringLiteral("UID:") + e.uid);
        put(QStringLiteral("DTSTAMP:") + stamp);
        if (e.allDay) {
            put(QStringLiteral("DTSTART;VALUE=DATE:") + fmtDate(e.start.date()));
            put(QStringLiteral("DTEND;VALUE=DATE:") + fmtDate(qMax(e.end.date(), e.start.date().addDays(1))));
        } else {
            put(QStringLiteral("DTSTART:") + fmtDateTime(e.start));   // 浮动时间：按本地时间解释
            put(QStringLiteral("DTEND:") + fmtDateTime(e.end));
        }
        put(QStringLiteral("SUMMARY:") + escape(e.title));
        if (!e.location.isEmpty()) put(QStringLiteral("LOCATION:") + escape(e.location));
        if (!e.notes.isEmpty()) put(QStringLiteral("DESCRIPTION:") + escape(e.notes));
        if (!e.url.isEmpty()) put(QStringLiteral("URL:") + e.url);
        if (!e.rrule.isEmpty()) put(QStringLiteral("RRULE:") + e.rrule);
        for (const QDateTime &x : e.exdates)
            put(e.allDay ? QStringLiteral("EXDATE;VALUE=DATE:") + fmtDate(x.date()) : QStringLiteral("EXDATE:") + fmtDateTime(x));
        if (e.reminderMinutes >= 0) {
            put(QStringLiteral("BEGIN:VALARM"));
            put(QStringLiteral("ACTION:DISPLAY"));
            put(QStringLiteral("DESCRIPTION:") + escape(e.title));
            put(QStringLiteral("TRIGGER:-PT%1M").arg(e.reminderMinutes));
            put(QStringLiteral("END:VALARM"));
        }
        put(QStringLiteral("END:VEVENT"));
    }
    for (const Todo &t : todos) {
        put(QStringLiteral("BEGIN:VTODO"));
        put(QStringLiteral("UID:") + t.uid);
        put(QStringLiteral("DTSTAMP:") + stamp);
        put(QStringLiteral("SUMMARY:") + escape(t.title));
        if (!t.notes.isEmpty()) put(QStringLiteral("DESCRIPTION:") + escape(t.notes));
        if (t.due.isValid())
            put(t.dueTime.isValid() ? QStringLiteral("DUE:") + fmtDateTime(QDateTime(t.due, t.dueTime))
                                    : QStringLiteral("DUE;VALUE=DATE:") + fmtDate(t.due));
        if (t.priority > 0) put(QStringLiteral("PRIORITY:%1").arg(t.priority));
        put(t.done ? QStringLiteral("STATUS:COMPLETED") : QStringLiteral("STATUS:NEEDS-ACTION"));
        if (t.done && t.completed.isValid()) put(QStringLiteral("COMPLETED:") + fmtUtc(t.completed));
        put(QStringLiteral("END:VTODO"));
    }
    put(QStringLiteral("END:VCALENDAR"));
    return out;
}

QString describeRule(const QString &rrule)
{
    if (rrule.isEmpty()) return {};
    const Rule r = parseRule(rrule);
    static const QStringList wd{QString(), QStringLiteral("一"), QStringLiteral("二"), QStringLiteral("三"), QStringLiteral("四"),
                                QStringLiteral("五"), QStringLiteral("六"), QStringLiteral("日")};
    const QString every = r.interval > 1 ? QStringLiteral("每 %1 ").arg(r.interval) : QStringLiteral("每");
    QString s;
    if (r.freq == QLatin1String("DAILY")) s = r.interval > 1 ? every + QStringLiteral("天") : QStringLiteral("每天");
    else if (r.freq == QLatin1String("WEEKLY")) {
        QStringList days;
        for (const ByDay &b : r.byDay) days << QStringLiteral("周") + wd[b.weekday];
        if (days.size() == 5 && std::none_of(r.byDay.begin(), r.byDay.end(), [](const ByDay &b) { return b.weekday > 5; }))
            s = QStringLiteral("每个工作日");
        else
            s = (r.interval > 1 ? every + QStringLiteral("周") : QStringLiteral("每周")) + (days.isEmpty() ? QString() : QStringLiteral(" ") + days.join(QStringLiteral("、")));
    } else if (r.freq == QLatin1String("MONTHLY")) {
        s = r.interval > 1 ? every + QStringLiteral("个月") : QStringLiteral("每月");
        if (!r.byDay.isEmpty() && r.byDay[0].ordinal != 0)
            s += r.byDay[0].ordinal > 0 ? QStringLiteral(" 第 %1 个周%2").arg(r.byDay[0].ordinal).arg(wd[r.byDay[0].weekday])
                                        : QStringLiteral(" 最后一个周%1").arg(wd[r.byDay[0].weekday]);
        else if (!r.byMonthDay.isEmpty())
            s += r.byMonthDay[0] > 0 ? QStringLiteral(" %1 日").arg(r.byMonthDay[0]) : QStringLiteral(" 最后一天");
    } else if (r.freq == QLatin1String("YEARLY")) s = r.interval > 1 ? every + QStringLiteral("年") : QStringLiteral("每年");
    else return QStringLiteral("自定义重复");
    if (r.count) s += QStringLiteral("，共 %1 次").arg(r.count);
    else if (r.until.isValid()) s += QStringLiteral("，至 ") + r.until.date().toString(QStringLiteral("yyyy-MM-dd"));
    return s;
}

}  // namespace ical
