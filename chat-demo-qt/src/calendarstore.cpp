#include "calendarstore.h"

#include "appdata.h"
#include "appsettings.h"
#include "hijri.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QLocale>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlEngine>
#include <QSaveFile>
#include <QUrl>
#include <QUuid>
#include <algorithm>

namespace {
QString newUid() { return QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral("@chatdemo"); }
QDate isoDate(const QString &s) { return QDate::fromString(s, Qt::ISODate); }
QString isoStr(const QDate &d) { return d.toString(Qt::ISODate); }
QDateTime fromMs(const QVariant &v) { return QDateTime::fromMSecsSinceEpoch(qint64(v.toDouble())); }
const QString kSample = QStringLiteral("qrc:/qt/qml/ChatDemo/data/team-sample.ics");
}  // namespace

CalendarStore *CalendarStore::instance()
{
    static CalendarStore *s = new CalendarStore;
    return s;
}

CalendarStore *CalendarStore::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

CalendarStore::CalendarStore()
{
    m_net = new QNetworkAccessManager(this);
    // 系统地区是阿联酋时，默认打开公共假日 / 伊斯兰节日 / 回历（其它地区默认关闭）
    if (QLocale::system().territory() == QLocale::UnitedArabEmirates) {
        m_showUae = m_showIslamic = m_showHijri = true;
    }
    load();
    rebuildBuiltins();
    connect(AppSettings::instance(), &AppSettings::languageChanged, this, &CalendarStore::rebuildBuiltins);   // 节日名称随语言
    m_tick.setInterval(30 * 1000);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        checkReminders();
        const QDateTime now = QDateTime::currentDateTime();
        for (const Cal &c : std::as_const(m_cals))
            if (c.kind == QLatin1String("subscription") && c.refreshMinutes > 0 && !c.syncing
                && (!c.lastSync.isValid() || c.lastSync.secsTo(now) >= c.refreshMinutes * 60))
                refresh(c.id);
    });
    m_tick.start();
    // 启动后刷新一次订阅（缓存先显示，网络回来再替换）
    QTimer::singleShot(0, this, &CalendarStore::refreshAll);
}

// MARK: 设置

void CalendarStore::setViewMode(const QString &v)
{
    static const QStringList modes{QStringLiteral("day"), QStringLiteral("week"), QStringLiteral("month"),
                                   QStringLiteral("year"), QStringLiteral("agenda")};
    if (m_viewMode == v || !modes.contains(v)) return;
    m_viewMode = v;
    saveMeta();
    emit viewModeChanged();
}
void CalendarStore::setShowTodos(bool v) { if (m_showTodos != v) { m_showTodos = v; saveMeta(); emit showTodosChanged(); bump(); } }
void CalendarStore::setShowCompleted(bool v) { if (m_showCompleted != v) { m_showCompleted = v; saveMeta(); emit showCompletedChanged(); bump(); } }
void CalendarStore::setWeekStartsMonday(bool v) { if (m_weekStartsMonday != v) { m_weekStartsMonday = v; saveMeta(); emit weekStartsMondayChanged(); bump(); } }

void CalendarStore::setShowWeekends(bool v) { if (m_showWeekends != v) { m_showWeekends = v; saveMeta(); emit showWeekendsChanged(); } }
void CalendarStore::setWeekendDays(const QString &v)
{
    if (m_weekendDays == v || (v != QLatin1String("sat-sun") && v != QLatin1String("fri-sat"))) return;
    m_weekendDays = v;
    saveMeta();
    emit weekendDaysChanged();
}
void CalendarStore::setShowUaeHolidays(bool v) { if (m_showUae != v) { m_showUae = v; saveMeta(); emit holidaysChanged(); rebuildBuiltins(); } }
void CalendarStore::setShowIslamicHolidays(bool v) { if (m_showIslamic != v) { m_showIslamic = v; saveMeta(); emit holidaysChanged(); rebuildBuiltins(); } }
void CalendarStore::setShowHijri(bool v) { if (m_showHijri != v) { m_showHijri = v; saveMeta(); emit hijriChanged(); } }
void CalendarStore::setHijriAdjust(int v)
{
    v = qBound(-2, v, 2);
    if (m_hijriAdjust == v) return;
    m_hijriAdjust = v;
    saveMeta();
    emit hijriChanged();
    rebuildBuiltins();   // 伊斯兰节日的公历日期随校正移动
}

void CalendarStore::bump() { ++m_revision; emit changed(); }
void CalendarStore::bumpCalendars() { emit calendarsChanged(); bump(); }

QStringList CalendarStore::palette() const
{
    return {QStringLiteral("#4C8DFF"), QStringLiteral("#2ECC8A"), QStringLiteral("#FF9F0A"), QStringLiteral("#FF5A5F"),
            QStringLiteral("#A66CFF"), QStringLiteral("#14B8A6"), QStringLiteral("#F472B6"), QStringLiteral("#8E8E93")};
}

// MARK: 日历

CalendarStore::Cal *CalendarStore::cal(const QString &id)
{
    for (Cal &c : m_cals) if (c.id == id) return &c;
    return nullptr;
}
const CalendarStore::Cal *CalendarStore::cal(const QString &id) const
{
    for (const Cal &c : m_cals) if (c.id == id) return &c;
    return nullptr;
}
CalendarStore::Cal *CalendarStore::calOfEvent(const QString &uid, int *index)
{
    for (Cal &c : m_cals)
        for (int i = 0; i < c.events.size(); ++i)
            if (c.events[i].uid == uid) { *index = i; return &c; }
    return nullptr;
}
CalendarStore::Cal *CalendarStore::calOfTodo(const QString &uid, int *index)
{
    for (Cal &c : m_cals)
        for (int i = 0; i < c.todos.size(); ++i)
            if (c.todos[i].uid == uid) { *index = i; return &c; }
    return nullptr;
}

QVariantList CalendarStore::calendars() const
{
    QVariantList out;
    for (const Cal &c : m_cals) {
        int open = 0;
        for (const ical::Todo &t : c.todos) open += t.done ? 0 : 1;
        out << QVariantMap{{"id", c.id}, {"name", c.name}, {"color", c.color}, {"kind", c.kind},
                           {"visible", c.visible}, {"url", c.url}, {"refreshMinutes", c.refreshMinutes},
                           {"lastSync", c.lastSync.isValid() ? c.lastSync.toString(QStringLiteral("MM-dd HH:mm")) : QString()},
                           {"lastError", c.lastError}, {"syncing", c.syncing}, {"readOnly", c.kind != QLatin1String("local")},
                           {"eventCount", int(c.events.size())}, {"openTodos", open}};
    }
    return out;
}

QString CalendarStore::addCalendar(const QString &name, const QString &color)
{
    Cal c;
    c.id = QStringLiteral("cal-") + QUuid::createUuid().toString(QUuid::Id128).left(8);
    c.name = name.trimmed().isEmpty() ? tr("新日历") : name.trimmed();
    c.color = color.isEmpty() ? palette().value(m_cals.size() % palette().size()) : color;
    c.kind = QStringLiteral("local");
    m_cals << c;
    saveCalendar(c);
    saveMeta();
    bumpCalendars();
    return c.id;
}

void CalendarStore::removeCalendar(const QString &id)
{
    if (id == QLatin1String("holiday-ae")) { setShowUaeHolidays(false); return; }
    if (id == QLatin1String("islamic")) { setShowIslamicHolidays(false); return; }
    for (int i = 0; i < m_cals.size(); ++i)
        if (m_cals[i].id == id) {
            m_cals.removeAt(i);
            QFile::remove(calDir() + QLatin1Char('/') + id + QStringLiteral(".ics"));
            saveMeta();
            bumpCalendars();
            return;
        }
}

void CalendarStore::setCalendarVisible(const QString &id, bool visible)
{
    if (Cal *c = cal(id); c && c->visible != visible) {
        c->visible = visible;
        if (c->kind == QLatin1String("builtin")) m_builtinVisible[id] = visible;
        saveMeta();
        bumpCalendars();
    }
}
void CalendarStore::setCalendarColor(const QString &id, const QString &color)
{
    if (Cal *c = cal(id); c && c->color != color) { c->color = color; saveMeta(); if (c->kind == QLatin1String("local")) saveCalendar(*c); bumpCalendars(); }
}
void CalendarStore::renameCalendar(const QString &id, const QString &name)
{
    if (Cal *c = cal(id); c && !name.trimmed().isEmpty()) { c->name = name.trimmed(); saveMeta(); if (c->kind == QLatin1String("local")) saveCalendar(*c); bumpCalendars(); }
}

QString CalendarStore::defaultCalendar() const
{
    for (const Cal &c : m_cals) if (c.kind == QLatin1String("local") && c.visible && c.id != QLatin1String("todo")) return c.id;
    for (const Cal &c : m_cals) if (c.kind == QLatin1String("local")) return c.id;
    return {};
}
QString CalendarStore::defaultTodoList() const
{
    if (const Cal *c = cal(QStringLiteral("todo")); c) return c->id;
    return defaultCalendar();
}

// MARK: 订阅

QString CalendarStore::subscribe(const QString &url, const QString &name, const QString &color, int refreshMinutes)
{
    const QString u = url.trimmed();
    if (u.isEmpty()) return {};
    for (const Cal &c : std::as_const(m_cals))
        if (c.kind == QLatin1String("subscription") && c.url == u) return c.id;   // 同一地址不重复订阅
    Cal c;
    c.id = QStringLiteral("sub-") + QUuid::createUuid().toString(QUuid::Id128).left(8);
    c.name = name.trimmed();
    c.color = color.isEmpty() ? palette().value((m_cals.size() + 3) % palette().size()) : color;
    c.kind = QStringLiteral("subscription");
    c.url = u;
    c.refreshMinutes = refreshMinutes;
    m_cals << c;
    saveMeta();
    bumpCalendars();
    refresh(c.id);
    return c.id;
}

void CalendarStore::updateSubscription(const QString &id, const QString &url, int refreshMinutes)
{
    Cal *c = cal(id);
    if (!c || c->kind != QLatin1String("subscription")) return;
    const bool urlChanged = c->url != url.trimmed();
    c->url = url.trimmed();
    c->refreshMinutes = refreshMinutes;
    saveMeta();
    bumpCalendars();
    if (urlChanged) refresh(id);
}

void CalendarStore::refreshAll()
{
    QStringList ids;
    for (const Cal &c : std::as_const(m_cals)) if (c.kind == QLatin1String("subscription")) ids << c.id;
    for (const QString &id : ids) refresh(id);
}

void CalendarStore::refresh(const QString &id)
{
    Cal *c = cal(id);
    if (!c || c->kind != QLatin1String("subscription") || c->syncing) return;
    QString u = c->url;
    if (u.startsWith(QLatin1String("webcal://"), Qt::CaseInsensitive)) u = QStringLiteral("https://") + u.mid(9);
    if (u.startsWith(QLatin1String("webcals://"), Qt::CaseInsensitive)) u = QStringLiteral("https://") + u.mid(10);
    const QUrl url(u);

    // 本地文件 / 资源：同步读取
    QString path;
    if (url.scheme() == QLatin1String("qrc")) path = QLatin1Char(':') + url.path();
    else if (url.isLocalFile()) path = url.toLocalFile();
    else if (QFileInfo::exists(u)) path = u;
    if (!path.isEmpty()) {
        QFile f(path);
        if (f.open(QIODevice::ReadOnly)) fetched(id, f.readAll(), {});
        else fetched(id, {}, tr("无法读取文件：%1").arg(path));
        return;
    }
    if (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https")) {
        fetched(id, {}, tr("不支持的地址，请使用 https://、webcal:// 或本地 .ics 文件"));
        return;
    }
    c->syncing = true;
    emit calendarsChanged();
    QNetworkRequest req(url);
    req.setTransferTimeout(20000);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ChatDemo-Calendar/1.0"));
    QNetworkReply *reply = m_net->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, id, reply] {
        reply->deleteLater();
        const QString err = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
        fetched(id, reply->readAll(), err);
    });
}

void CalendarStore::fetched(const QString &id, const QByteArray &data, const QString &error)
{
    Cal *c = cal(id);
    if (!c) return;   // 拉取期间被取消订阅
    c->syncing = false;
    QString err = error;
    if (err.isEmpty() && !data.contains("BEGIN:VCALENDAR")) err = tr("不是有效的 iCalendar（.ics）数据");
    if (err.isEmpty()) {
        loadFromIcs(*c, data, true);
        c->lastSync = QDateTime::currentDateTime();
        c->lastError.clear();
        QDir().mkpath(calDir());
        QSaveFile f(calDir() + QLatin1Char('/') + id + QStringLiteral(".ics"));
        if (f.open(QIODevice::WriteOnly)) { f.write(data); f.commit(); }
    } else {
        c->lastError = err;   // 保留上次缓存的数据
        qWarning().noquote() << "[calendar] 订阅刷新失败" << c->url << err;
    }
    if (c->name.isEmpty()) c->name = tr("订阅日历");
    saveMeta();
    bumpCalendars();
    emit syncFinished(id, err.isEmpty(), err);
}

void CalendarStore::loadFromIcs(Cal &c, const QByteArray &data, bool adoptMeta)
{
    ical::Calendar parsed = ical::parse(data);
    c.events = parsed.events;
    c.todos = parsed.todos;
    if (adoptMeta && c.name.isEmpty() && !parsed.name.isEmpty()) c.name = parsed.name;
}

QString CalendarStore::exportCalendar(const QString &id, const QString &path)
{
    const Cal *c = cal(id);
    if (!c) return {};
    const QString out = path.isEmpty() ? dataDir() + QStringLiteral("/export-") + c->id + QStringLiteral(".ics") : path;
    QSaveFile f(out);
    if (!f.open(QIODevice::WriteOnly)) return {};
    f.write(ical::serialize(c->name, c->color, c->events, c->todos));
    return f.commit() ? out : QString();
}

// MARK: 查询

QVariantMap CalendarStore::occurrenceMap(const Cal &c, const ical::Event &e, const QDateTime &start) const
{
    const QDateTime end = start.addSecs(ical::durationSecs(e));
    // 最后覆盖的那一天：结束时间恰好是 0 点时不算那一天
    QDate last = end.date();
    if (end > start && end.time() == QTime(0, 0)) last = last.addDays(-1);
    if (last < start.date()) last = start.date();
    return {{"key", e.uid + QLatin1Char('|') + QString::number(start.toSecsSinceEpoch())},
            {"uid", e.uid}, {"type", "event"},
            {"calendarId", c.id}, {"calendarName", c.name}, {"calendarKind", c.kind}, {"color", c.color},
            {"title", e.title.isEmpty() ? tr("（无标题）") : e.title},
            {"location", e.location}, {"notes", e.notes}, {"url", e.url},
            {"allDay", e.allDay}, {"startMs", double(start.toMSecsSinceEpoch())}, {"endMs", double(end.toMSecsSinceEpoch())},
            {"startIso", isoStr(start.date())}, {"lastIso", isoStr(last)},
            {"multiDay", last > start.date()},
            {"readOnly", c.kind != QLatin1String("local")}, {"recurring", !e.rrule.isEmpty()},
            {"rrule", e.rrule}, {"reminder", e.reminderMinutes}};
}

QVariantList CalendarStore::occurrences(const QString &fromIso, const QString &toIso) const
{
    const QDateTime from(isoDate(fromIso), QTime(0, 0)), to(isoDate(toIso), QTime(0, 0));
    if (!from.isValid() || !to.isValid()) return {};
    struct Item { QVariantMap m; bool allDay; qint64 start, len; };
    QList<Item> items;
    for (const Cal &c : m_cals) {
        if (!c.visible) continue;
        for (const ical::Event &e : c.events)
            for (const QDateTime &s : ical::expand(e, from, to)) {
                const bool longish = e.allDay || ical::durationSecs(e) >= 86400;
                items << Item{occurrenceMap(c, e, s), longish, s.toSecsSinceEpoch(), ical::durationSecs(e)};
            }
    }
    std::stable_sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
        if (a.allDay != b.allDay) return a.allDay;
        if (a.start != b.start) return a.start < b.start;
        return a.len > b.len;
    });
    QVariantList out;
    for (const Item &i : items) out << i.m;
    return out;
}

QVariantList CalendarStore::busyDays(const QString &fromIso, const QString &toIso) const
{
    QSet<QString> days;
    for (const QVariant &v : occurrences(fromIso, toIso)) {
        const QVariantMap m = v.toMap();
        for (QDate d = isoDate(m["startIso"].toString()); d <= isoDate(m["lastIso"].toString()); d = d.addDays(1))
            days.insert(isoStr(d));
    }
    QVariantList out;
    for (const QString &d : days) out << d;
    return out;
}

QVariantList CalendarStore::search(const QString &query) const
{
    const QString q = query.trimmed();
    if (q.isEmpty()) return {};
    const QDate today = QDate::currentDate();
    QVariantList out;
    for (const QVariant &v : occurrences(isoStr(today.addDays(-90)), isoStr(today.addDays(366)))) {
        const QVariantMap m = v.toMap();
        if (m["title"].toString().contains(q, Qt::CaseInsensitive) || m["location"].toString().contains(q, Qt::CaseInsensitive)
            || m["notes"].toString().contains(q, Qt::CaseInsensitive))
            out << m;
    }
    std::stable_sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["startMs"].toDouble() < b.toMap()["startMs"].toDouble();
    });
    return out;
}

QVariantMap CalendarStore::todoMap(const Cal &c, const ical::Todo &t) const
{
    const QDateTime now = QDateTime::currentDateTime();
    const bool overdue = !t.done && t.due.isValid()
                         && (t.due < now.date() || (t.due == now.date() && t.dueTime.isValid() && t.dueTime < now.time()));
    const QDateTime dueAt(t.due, t.dueTime.isValid() ? t.dueTime : QTime(0, 0));
    return {{"uid", t.uid}, {"type", "todo"}, {"key", QStringLiteral("todo|") + t.uid},
            {"calendarId", c.id}, {"calendarName", c.name}, {"color", c.color},
            {"title", t.title.isEmpty() ? tr("（无标题）") : t.title}, {"notes", t.notes},
            {"dueIso", t.due.isValid() ? isoStr(t.due) : QString()},
            {"dueTime", t.dueTime.isValid() ? t.dueTime.toString(QStringLiteral("HH:mm")) : QString()},
            {"dueMs", t.due.isValid() ? double(dueAt.toMSecsSinceEpoch()) : 0.0},
            {"done", t.done}, {"priority", t.priority}, {"overdue", overdue},
            {"readOnly", c.kind != QLatin1String("local")}};
}

QVariantList CalendarStore::todosInRange(const QString &fromIso, const QString &toIso) const
{
    const QDate from = isoDate(fromIso), to = isoDate(toIso);
    QList<QVariantMap> list;
    for (const Cal &c : m_cals) {
        if (!c.visible) continue;
        for (const ical::Todo &t : c.todos)
            if (t.due.isValid() && t.due >= from && t.due < to && (m_showCompleted || !t.done)) list << todoMap(c, t);
    }
    std::stable_sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        if (a["done"].toBool() != b["done"].toBool()) return !a["done"].toBool();
        return a["dueMs"].toDouble() < b["dueMs"].toDouble();
    });
    QVariantList out;
    for (const QVariantMap &m : list) out << m;
    return out;
}

QVariantList CalendarStore::todos(const QString &filter) const
{
    const QDate today = QDate::currentDate();
    QList<QVariantMap> list;
    for (const Cal &c : m_cals) {
        if (!c.visible) continue;
        for (const ical::Todo &t : c.todos) {
            bool ok = false;
            if (filter == QLatin1String("today")) ok = !t.done && t.due.isValid() && t.due <= today;
            else if (filter == QLatin1String("scheduled")) ok = !t.done && t.due.isValid();
            else if (filter == QLatin1String("completed")) ok = t.done;
            else ok = !t.done;
            if (ok) list << todoMap(c, t);
        }
    }
    const bool completed = filter == QLatin1String("completed");
    std::stable_sort(list.begin(), list.end(), [completed](const QVariantMap &a, const QVariantMap &b) {
        const bool ad = !a["dueIso"].toString().isEmpty(), bd = !b["dueIso"].toString().isEmpty();
        if (ad != bd) return completed ? !ad : ad;           // 有截止日期的排前面
        if (a["dueMs"].toDouble() != b["dueMs"].toDouble()) return completed ? a["dueMs"].toDouble() > b["dueMs"].toDouble()
                                                                             : a["dueMs"].toDouble() < b["dueMs"].toDouble();
        const int ap = a["priority"].toInt() > 0 ? a["priority"].toInt() : 10;   // 0 = 未设置，排最后
        const int bp = b["priority"].toInt() > 0 ? b["priority"].toInt() : 10;
        return ap < bp;
    });
    QVariantList out;
    for (const QVariantMap &m : list) out << m;
    return out;
}

int CalendarStore::openTodoCount() const
{
    const QDate today = QDate::currentDate();
    int n = 0;
    for (const Cal &c : m_cals)
        if (c.visible)
            for (const ical::Todo &t : c.todos) n += (!t.done && t.due.isValid() && t.due <= today) ? 1 : 0;
    return n;
}

QVariantMap CalendarStore::event(const QString &uid) const
{
    for (const Cal &c : m_cals)
        for (const ical::Event &e : c.events)
            if (e.uid == uid) return occurrenceMap(c, e, e.start);
    return {};
}

QVariantMap CalendarStore::todo(const QString &uid) const
{
    for (const Cal &c : m_cals)
        for (const ical::Todo &t : c.todos)
            if (t.uid == uid) return todoMap(c, t);
    return {};
}

// MARK: 事件写入

void CalendarStore::applyEvent(ical::Event &e, const QVariantMap &m)
{
    if (m.contains("title")) e.title = m["title"].toString().trimmed();
    if (m.contains("location")) e.location = m["location"].toString().trimmed();
    if (m.contains("notes")) e.notes = m["notes"].toString();
    if (m.contains("rrule")) e.rrule = m["rrule"].toString();
    if (m.contains("reminder")) e.reminderMinutes = m["reminder"].toInt();
    if (m.contains("allDay")) e.allDay = m["allDay"].toBool();
    QDateTime s = m.contains("startMs") ? fromMs(m["startMs"]) : e.start;
    QDateTime en = m.contains("endMs") ? fromMs(m["endMs"]) : e.end;
    if (e.allDay) {
        // 全天：startMs / endMs 是第一天 / 最后一天（含）里的任意时刻
        const QDate first = s.date();
        QDate last = m.contains("endMs") ? en.date() : en.addSecs(-1).date();
        if (last < first) last = first;
        s = QDateTime(first, QTime(0, 0));
        en = QDateTime(last.addDays(1), QTime(0, 0));
    } else if (en < s) {
        en = s.addSecs(3600);
    }
    e.start = s;
    e.end = en;
}

QString CalendarStore::createEvent(const QVariantMap &m)
{
    Cal *c = cal(m.value("calendarId").toString());
    if (!c || c->kind != QLatin1String("local")) c = cal(defaultCalendar());
    if (!c) return {};
    ical::Event e;
    e.uid = newUid();
    applyEvent(e, m);
    if (!e.start.isValid()) return {};
    c->events << e;
    saveCalendar(*c);
    bumpCalendars();
    return e.uid;
}

bool CalendarStore::updateEvent(const QString &uid, const QVariantMap &m)
{
    int i = -1;
    Cal *c = calOfEvent(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    ical::Event e = c->events[i];
    applyEvent(e, m);
    const QString target = m.value("calendarId").toString();
    Cal *dst = target.isEmpty() ? c : cal(target);
    if (dst && dst != c && dst->kind == QLatin1String("local")) {   // 换日历
        c->events.removeAt(i);
        dst->events << e;
        saveCalendar(*c);
        saveCalendar(*dst);
    } else {
        c->events[i] = e;
        saveCalendar(*c);
    }
    bumpCalendars();
    return true;
}

bool CalendarStore::deleteEvent(const QString &uid, const QString &scope, double occurrenceMs)
{
    int i = -1;
    Cal *c = calOfEvent(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    if (scope == QLatin1String("this") && !c->events[i].rrule.isEmpty())
        c->events[i].exdates << QDateTime::fromMSecsSinceEpoch(qint64(occurrenceMs));
    else
        c->events.removeAt(i);
    saveCalendar(*c);
    bumpCalendars();
    return true;
}

bool CalendarStore::moveEvent(const QString &uid, double newStartMs)
{
    int i = -1;
    Cal *c = calOfEvent(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    ical::Event &e = c->events[i];
    const qint64 delta = e.start.msecsTo(QDateTime::fromMSecsSinceEpoch(qint64(newStartMs)));
    if (delta == 0) return true;
    e.start = e.start.addMSecs(delta);
    e.end = e.end.addMSecs(delta);
    saveCalendar(*c);
    bump();
    return true;
}

// MARK: 待办写入

void CalendarStore::applyTodo(ical::Todo &t, const QVariantMap &m)
{
    if (m.contains("title")) t.title = m["title"].toString().trimmed();
    if (m.contains("notes")) t.notes = m["notes"].toString();
    if (m.contains("priority")) t.priority = qBound(0, m["priority"].toInt(), 9);
    if (m.contains("dueIso")) t.due = isoDate(m["dueIso"].toString());
    if (m.contains("dueTime")) t.dueTime = QTime::fromString(m["dueTime"].toString(), QStringLiteral("HH:mm"));
    if (!t.due.isValid()) t.dueTime = QTime();
    if (m.contains("done")) {
        const bool d = m["done"].toBool();
        if (d && !t.done) t.completed = QDateTime::currentDateTime();
        if (!d) t.completed = QDateTime();
        t.done = d;
    }
}

QString CalendarStore::createTodo(const QVariantMap &m)
{
    Cal *c = cal(m.value("calendarId").toString());
    if (!c || c->kind != QLatin1String("local")) c = cal(defaultTodoList());
    if (!c || m.value("title").toString().trimmed().isEmpty()) return {};
    ical::Todo t;
    t.uid = newUid();
    applyTodo(t, m);
    c->todos << t;
    saveCalendar(*c);
    bumpCalendars();
    return t.uid;
}

bool CalendarStore::updateTodo(const QString &uid, const QVariantMap &m)
{
    int i = -1;
    Cal *c = calOfTodo(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    ical::Todo t = c->todos[i];
    applyTodo(t, m);
    const QString target = m.value("calendarId").toString();
    Cal *dst = target.isEmpty() ? c : cal(target);
    if (dst && dst != c && dst->kind == QLatin1String("local")) {
        c->todos.removeAt(i);
        dst->todos << t;
        saveCalendar(*dst);
    } else {
        c->todos[i] = t;
    }
    saveCalendar(*c);
    bumpCalendars();
    return true;
}

bool CalendarStore::toggleTodo(const QString &uid)
{
    int i = -1;
    Cal *c = calOfTodo(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    return updateTodo(uid, {{"done", !c->todos[i].done}});
}

bool CalendarStore::deleteTodo(const QString &uid)
{
    int i = -1;
    Cal *c = calOfTodo(uid, &i);
    if (!c || c->kind != QLatin1String("local")) return false;
    c->todos.removeAt(i);
    saveCalendar(*c);
    bumpCalendars();
    return true;
}

// MARK: 提醒

void CalendarStore::checkReminders()
{
    const QDateTime now = QDateTime::currentDateTime();
    for (const Cal &c : std::as_const(m_cals)) {
        if (!c.visible) continue;
        for (const ical::Event &e : c.events) {
            if (e.reminderMinutes < 0) continue;
            for (const QDateTime &s : ical::expand(e, now, now.addSecs(e.reminderMinutes * 60 + 3600))) {
                const QDateTime fireAt = s.addSecs(-e.reminderMinutes * 60);
                const QString key = e.uid + QLatin1Char('|') + QString::number(s.toSecsSinceEpoch());
                // 只提醒「刚到点」的（10 分钟内），避免启动时把过去的提醒一次性全弹出来
                if (fireAt > now || fireAt.secsTo(now) > 600 || s < now || m_fired.contains(key)) continue;
                m_fired.insert(key);
                const QString when = e.allDay ? tr("全天")
                                              : s.toString(QStringLiteral("HH:mm")) + QStringLiteral(" – ")
                                                    + s.addSecs(ical::durationSecs(e)).toString(QStringLiteral("HH:mm"));
                QString body = when;
                const qint64 mins = (now.secsTo(s) + 59) / 60;
                body += QStringLiteral(" · ") + (mins <= 0 ? tr("现在开始") : tr("%n 分钟后开始", "", int(mins)));
                if (!e.location.isEmpty()) body += QStringLiteral(" · ") + e.location;
                emit notificationRequested(QStringLiteral("cal:") + key, e.title, body);
            }
        }
    }
}

void CalendarStore::reveal(const QString &key)
{
    const qint64 secs = key.section(QLatin1Char('|'), 1).toLongLong();
    if (secs > 0) emit revealRequested(isoStr(QDateTime::fromSecsSinceEpoch(secs).date()));
}

// MARK: 回历与内置节假日日历

namespace {
bool isEnglish() { return AppSettings::instance()->language() == QLatin1String("en"); }
const char *const kHijriEn[] = {"Muharram", "Safar", "Rabiʻ I", "Rabiʻ II", "Jumada I", "Jumada II",
                                "Rajab", "Shaʻban", "Ramadan", "Shawwal", "Dhuʻl-Qiʻdah", "Dhuʻl-Hijjah"};
const char *const kHijriEnShort[] = {"Muh.", "Saf.", "Rab. I", "Rab. II", "Jum. I", "Jum. II",
                                     "Raj.", "Sha.", "Ram.", "Shaw.", "Dhu Q.", "Dhu H."};
const char16_t *const kHijriZh[] = {u"穆哈兰姆月", u"色法尔月", u"赖比尔·敖外鲁月", u"赖比尔·阿色尼月", u"主马达·敖外鲁月", u"主马达·阿色尼月",
                                    u"赖哲卜月", u"舍尔邦月", u"赖买丹月（斋月）", u"闪瓦鲁月", u"都尔喀尔德月", u"都尔黑哲月"};
const char16_t *const kHijriZhShort[] = {u"穆哈兰姆", u"色法尔", u"赖比一", u"赖比二", u"主马一", u"主马二",
                                         u"赖哲卜", u"舍尔邦", u"斋月", u"闪瓦鲁", u"都尔喀", u"都尔黑"};
}  // namespace

QVariantList CalendarStore::hijriRange(const QString &fromIso, int days) const
{
    QVariantList out;
    QDate d = isoDate(fromIso);
    const bool en = isEnglish();
    for (int i = 0; i < days && d.isValid(); ++i, d = d.addDays(1)) {
        const hijri::Date h = hijri::fromGregorian(d, m_hijriAdjust);
        const QString monthShort = en ? QString::fromLatin1(kHijriEnShort[h.month - 1]) : QString::fromUtf16(kHijriZhShort[h.month - 1]);
        // 格子里：每月 1 日显示「1 斋月」，其余只显示日数
        const QString label = h.day == 1 ? QString::number(h.day) + QLatin1Char(' ') + monthShort : QString::number(h.day);
        out << QVariantMap{{"y", h.year}, {"m", h.month}, {"d", h.day}, {"label", label}, {"monthShort", monthShort}, {"first", h.day == 1}};
    }
    return out;
}

QString CalendarStore::hijriText(const QString &iso) const
{
    const QDate d = isoDate(iso);
    if (!d.isValid()) return {};
    const hijri::Date h = hijri::fromGregorian(d, m_hijriAdjust);
    if (isEnglish())
        return QStringLiteral("%1 %2 %3 AH").arg(h.day).arg(QString::fromUtf8(kHijriEn[h.month - 1])).arg(h.year);
    return QStringLiteral("回历 %1 年%2 %3 日").arg(h.year).arg(QString::fromUtf16(kHijriZh[h.month - 1])).arg(h.day);
}

QList<ical::Event> CalendarStore::uaeHolidays(int fromYear, int toYear) const
{
    QList<ical::Event> out;
    auto add = [&](const QString &key, const QString &title, const QDate &d, int days, bool estimated) {
        if (!d.isValid()) return;
        ical::Event e;
        e.uid = QStringLiteral("builtin-ae-%1-%2").arg(key, d.toString(Qt::ISODate));
        e.title = title;
        e.allDay = true;
        e.start = QDateTime(d, QTime(0, 0));
        e.end = QDateTime(d.addDays(days), QTime(0, 0));
        e.notes = estimated ? tr("伊斯兰节日按回历推算，实际日期以阿联酋官方根据新月观测公布的为准（可在设置里调整 ±2 天）。")
                            : tr("阿联酋联邦公共假日。");
        out << e;
    };
    for (int y = fromYear; y <= toYear; ++y) {
        add(QStringLiteral("newyear"), tr("元旦"), QDate(y, 1, 1), 1, false);
        add(QStringLiteral("commemoration"), tr("纪念日"), QDate(y, 12, 1), 1, false);
        add(QStringLiteral("national"), tr("国庆节"), QDate(y, 12, 2), 2, false);
    }
    // 伊斯兰节日：覆盖这几个公历年的所有回历年
    const int hFrom = hijri::fromGregorian(QDate(fromYear, 1, 1), m_hijriAdjust).year;
    const int hTo = hijri::fromGregorian(QDate(toYear, 12, 31), m_hijriAdjust).year;
    const QDate lo(fromYear, 1, 1), hi(toYear, 12, 31);
    for (int h = hFrom; h <= hTo; ++h) {
        auto g = [&](int m, int d) { const QDate x = hijri::toGregorian(h, m, d, m_hijriAdjust); return x >= lo && x <= hi ? x : QDate(); };
        add(QStringLiteral("hijri-newyear"), tr("伊斯兰新年"), g(1, 1), 1, true);
        add(QStringLiteral("mawlid"), tr("先知诞辰"), g(3, 12), 1, true);
        add(QStringLiteral("eid-fitr"), tr("开斋节"), g(10, 1), 3, true);
        add(QStringLiteral("arafat"), tr("阿拉法特日"), g(12, 9), 1, true);
        add(QStringLiteral("eid-adha"), tr("宰牲节"), g(12, 10), 3, true);
    }
    return out;
}

QList<ical::Event> CalendarStore::islamicHolidays(int fromYear, int toYear, bool skipUaeOverlap) const
{
    QList<ical::Event> out;
    const QDate lo(fromYear, 1, 1), hi(toYear, 12, 31);
    const int hFrom = hijri::fromGregorian(lo, m_hijriAdjust).year;
    const int hTo = hijri::fromGregorian(hi, m_hijriAdjust).year;
    for (int h = hFrom; h <= hTo; ++h) {
        auto add = [&](const QString &key, const QString &title, int m, int d, int days) {
            const QDate x = hijri::toGregorian(h, m, d, m_hijriAdjust);
            if (x < lo || x > hi) return;
            ical::Event e;
            e.uid = QStringLiteral("builtin-islamic-%1-%2").arg(key).arg(h);
            e.title = title;
            e.allDay = true;
            e.start = QDateTime(x, QTime(0, 0));
            e.end = QDateTime(x.addDays(days), QTime(0, 0));
            e.notes = tr("按回历推算，实际日期取决于新月观测（可在设置里调整 ±2 天）。");
            out << e;
        };
        add(QStringLiteral("ashura"), tr("阿舒拉日"), 1, 10, 1);
        add(QStringLiteral("isra"), tr("登霄节"), 7, 27, 1);
        add(QStringLiteral("shaban"), tr("拜拉特夜"), 8, 15, 1);
        add(QStringLiteral("ramadan"), tr("斋月开始"), 9, 1, 1);
        add(QStringLiteral("qadr"), tr("盖德尔夜"), 9, 27, 1);
        if (!skipUaeOverlap) {   // 阿联酋假日日历已包含这些，避免重复
            add(QStringLiteral("newyear"), tr("伊斯兰新年"), 1, 1, 1);
            add(QStringLiteral("mawlid"), tr("先知诞辰"), 3, 12, 1);
            add(QStringLiteral("eid-fitr"), tr("开斋节"), 10, 1, 3);
            add(QStringLiteral("arafat"), tr("阿拉法特日"), 12, 9, 1);
            add(QStringLiteral("eid-adha"), tr("宰牲节"), 12, 10, 3);
        }
    }
    return out;
}

void CalendarStore::rebuildBuiltins()
{
    m_cals.erase(std::remove_if(m_cals.begin(), m_cals.end(), [](const Cal &c) { return c.kind == QLatin1String("builtin"); }), m_cals.end());
    const int y = QDate::currentDate().year();
    auto make = [&](const QString &id, const QString &name, const QString &color, const QList<ical::Event> &events) {
        Cal c;
        c.id = id;
        c.name = name;
        c.color = color;
        c.kind = QStringLiteral("builtin");
        c.visible = m_builtinVisible.value(id, true);
        c.events = events;
        m_cals << c;
    };
    if (m_showUae)
        make(QStringLiteral("holiday-ae"), tr("阿联酋公共假日"), QStringLiteral("#E0533D"), uaeHolidays(y - 1, y + 2));
    if (m_showIslamic)
        make(QStringLiteral("islamic"), tr("伊斯兰节日"), QStringLiteral("#14A37F"), islamicHolidays(y - 1, y + 2, m_showUae));
    bumpCalendars();
}

// MARK: 持久化

QString CalendarStore::calDir() const { return dataDir() + QStringLiteral("/calendar"); }

void CalendarStore::saveCalendar(const Cal &c)
{
    if (c.kind != QLatin1String("local")) return;   // 订阅日历只保存拉取到的原始数据
    QDir().mkpath(calDir());
    QSaveFile f(calDir() + QLatin1Char('/') + c.id + QStringLiteral(".ics"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(ical::serialize(c.name, c.color, c.events, c.todos));
        f.commit();
    }
}

void CalendarStore::saveMeta()
{
    QJsonArray cals;
    QJsonObject builtinVis;
    for (auto it = m_builtinVisible.constBegin(); it != m_builtinVisible.constEnd(); ++it) builtinVis[it.key()] = it.value();
    for (const Cal &c : std::as_const(m_cals))
        if (c.kind != QLatin1String("builtin"))   // 内置日历每次启动按设置重新生成
        cals << QJsonObject{{"id", c.id}, {"name", c.name}, {"color", c.color}, {"kind", c.kind}, {"visible", c.visible},
                            {"url", c.url}, {"refreshMinutes", c.refreshMinutes},
                            {"lastSync", c.lastSync.toString(Qt::ISODate)}, {"lastError", c.lastError}};
    const QJsonObject root{{"calendars", cals},
                           {"settings", QJsonObject{{"viewMode", m_viewMode}, {"showTodos", m_showTodos},
                                                    {"showCompleted", m_showCompleted}, {"weekStartsMonday", m_weekStartsMonday},
                                                    {"showWeekends", m_showWeekends}, {"weekendDays", m_weekendDays},
                                                    {"showUaeHolidays", m_showUae}, {"showIslamicHolidays", m_showIslamic},
                                                    {"showHijri", m_showHijri}, {"hijriAdjust", m_hijriAdjust},
                                                    {"builtinVisible", builtinVis}}}};
    QDir().mkpath(calDir());
    QSaveFile f(calDir() + QStringLiteral("/calendars.json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(root).toJson());
        f.commit();
    }
}

void CalendarStore::load()
{
    QFile f(calDir() + QStringLiteral("/calendars.json"));
    if (!f.open(QIODevice::ReadOnly)) {
        seed();
        return;
    }
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    const QJsonObject s = root["settings"].toObject();
    m_viewMode = s["viewMode"].toString(m_viewMode);
    m_showTodos = s["showTodos"].toBool(m_showTodos);
    m_showCompleted = s["showCompleted"].toBool(m_showCompleted);
    m_weekStartsMonday = s["weekStartsMonday"].toBool(m_weekStartsMonday);
    m_showWeekends = s["showWeekends"].toBool(m_showWeekends);
    m_weekendDays = s["weekendDays"].toString(m_weekendDays);
    m_showUae = s["showUaeHolidays"].toBool(m_showUae);
    m_showIslamic = s["showIslamicHolidays"].toBool(m_showIslamic);
    m_showHijri = s["showHijri"].toBool(m_showHijri);
    m_hijriAdjust = qBound(-2, s["hijriAdjust"].toInt(m_hijriAdjust), 2);
    const QJsonObject bv = s["builtinVisible"].toObject();
    for (auto it = bv.begin(); it != bv.end(); ++it) m_builtinVisible[it.key()] = it.value().toBool(true);
    for (const QJsonValue &v : root["calendars"].toArray()) {
        const QJsonObject o = v.toObject();
        Cal c;
        c.id = o["id"].toString();
        c.name = o["name"].toString();
        c.color = o["color"].toString(QStringLiteral("#4C8DFF"));
        c.kind = o["kind"].toString(QStringLiteral("local"));
        c.visible = o["visible"].toBool(true);
        c.url = o["url"].toString();
        c.refreshMinutes = o["refreshMinutes"].toInt(60);
        c.lastSync = QDateTime::fromString(o["lastSync"].toString(), Qt::ISODate);
        c.lastError = o["lastError"].toString();
        QFile ics(calDir() + QLatin1Char('/') + c.id + QStringLiteral(".ics"));
        if (ics.open(QIODevice::ReadOnly)) loadFromIcs(c, ics.readAll(), false);
        m_cals << c;
    }
}

void CalendarStore::seed()
{
    const QDate d = QDate::currentDate();
    auto at = [&](int dayOffset, int h, int m) { return QDateTime(d.addDays(dayOffset), QTime(h, m)); };
    auto ev = [&](const QString &title, const QDateTime &s, const QDateTime &e, const QString &loc = {}, int remind = -1,
                  const QString &rrule = {}) {
        ical::Event x;
        x.uid = newUid();
        x.title = title; x.start = s; x.end = e; x.location = loc; x.reminderMinutes = remind; x.rrule = rrule;
        return x;
    };
    auto allDay = [&](const QString &title, int from, int days, const QString &rrule = {}) {
        ical::Event x = ev(title, QDateTime(d.addDays(from), QTime(0, 0)), QDateTime(d.addDays(from + days), QTime(0, 0)), {}, -1, rrule);
        x.allDay = true;
        return x;
    };
    auto todo = [&](const QString &title, int dueOffset, QTime t, int prio, bool done = false, const QString &notes = {}) {
        ical::Todo x;
        x.uid = newUid();
        x.title = title; x.priority = prio; x.done = done; x.notes = notes;
        if (dueOffset != INT_MIN) { x.due = d.addDays(dueOffset); x.dueTime = t; }
        if (done) x.completed = QDateTime::currentDateTime();
        return x;
    };
    const int mondayOffset = 1 - d.dayOfWeek();

    Cal work{QStringLiteral("work"), tr("工作"), QStringLiteral("#4C8DFF"), QStringLiteral("local")};
    work.events << ev(tr("站会"), at(mondayOffset - 14, 9, 30), at(mondayOffset - 14, 9, 45), tr("线上"), 5,
                      QStringLiteral("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"))
                << ev(tr("产品评审"), at(0, 10, 0), at(0, 11, 0), tr("3F 会议室 A"), 10)
                << ev(tr("设计走查"), at(0, 14, 0), at(0, 15, 30), tr("设计部"), 15)
                << ev(tr("1:1 沟通"), at(0, 14, 30), at(0, 15, 0), {}, 5)
                << ev(tr("客户拜访"), at(2, 13, 0), at(2, 17, 0), tr("科技园 B 座"), 30)
                << ev(tr("版本发布"), at(-2, 16, 0), at(-2, 17, 30), {}, 10)
                << allDay(tr("上海出差"), 3, 2);
    // 示例会议链接（「加入会议」按钮用）
    work.events[0].url = QStringLiteral("https://meet.example.com/standup");
    work.events[1].url = QStringLiteral("https://meet.example.com/product-review");
    work.events[3].url = QStringLiteral("https://meet.example.com/one-on-one");
    work.todos << todo(tr("准备评审材料"), 0, QTime(9, 0), 1, true)
               << todo(tr("提交周报"), 0, QTime(18, 0), 5, false, tr("本周进展 + 下周计划"));

    Cal personal{QStringLiteral("personal"), tr("个人"), QStringLiteral("#2ECC8A"), QStringLiteral("local")};
    personal.events << ev(tr("健身"), at(mondayOffset - 7 + 1, 19, 0), at(mondayOffset - 7 + 1, 20, 30), tr("健身房"), -1,
                          QStringLiteral("FREQ=WEEKLY;BYDAY=TU,TH"))
                    << ev(tr("午餐 · 老同学"), at(-1, 12, 0), at(-1, 13, 0), tr("公司楼下"))
                    << allDay(tr("妈妈生日 🎂"), 5, 1, QStringLiteral("FREQ=YEARLY"));

    Cal todos{QStringLiteral("todo"), tr("待办"), QStringLiteral("#FF9F0A"), QStringLiteral("local")};
    todos.todos << todo(tr("报销发票"), -1, QTime(), 5)
                << todo(tr("预订上海机票"), 1, QTime(), 1, false, tr("出差前确认航班"))
                << todo(tr("续费云服务器"), 6, QTime(10, 0), 0)
                << todo(tr("整理需求池"), INT_MIN, QTime(), 0)
                << todo(tr("更新简历"), -3, QTime(), 0, true);

    m_cals << work << personal << todos;
    for (const Cal &c : std::as_const(m_cals)) saveCalendar(c);

    // 示例订阅：内置的 .ics（含时区、RECURRENCE-ID、VTODO），展示订阅日历的解析与只读效果
    Cal sub;
    sub.id = QStringLiteral("sub-team");
    sub.name = tr("团队公共日历（示例订阅）");
    sub.color = QStringLiteral("#A66CFF");
    sub.kind = QStringLiteral("subscription");
    sub.url = kSample;
    sub.refreshMinutes = 60;
    m_cals << sub;
    saveMeta();
    refresh(sub.id);
}
