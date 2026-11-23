#pragma once
#include <QDateTime>
#include <QList>
#include <QString>

// 精简版 iCalendar（RFC 5545）：解析 / 序列化 VEVENT、VTODO，展开 RRULE。
// 本地日历也用 .ics 落盘，订阅日历缓存原始 .ics —— 与 Google Calendar / macOS 日历互通。
namespace ical {

struct Event {
    QString uid, title, location, notes, url;
    QDateTime start, end;            // 已转换为本地时间；全天事件 end 为「次日 0 点」（不含）
    bool allDay = false;
    QString rrule;                   // 原始 RRULE 值，如 "FREQ=WEEKLY;BYDAY=MO,WE"
    QList<QDateTime> exdates;        // 被排除的实例（含被 RECURRENCE-ID 覆盖的实例）
    QDateTime recurrenceId;          // 非空 = 这是某个重复事件的单次修改
    int reminderMinutes = -1;        // VALARM TRIGGER，-1 = 无
};

struct Todo {
    QString uid, title, notes;
    QDate due;
    QTime dueTime;                   // 无效 = 只有日期
    bool done = false;
    QDateTime completed;
    int priority = 0;                // RFC：0 未设置，1 最高 … 9 最低
};

struct Calendar {
    QString name;                    // X-WR-CALNAME
    QString color;                   // X-APPLE-CALENDAR-COLOR（#RRGGBB）
    QList<Event> events;
    QList<Todo> todos;
};

Calendar parse(const QByteArray &data);
QByteArray serialize(const QString &name, const QString &color, const QList<Event> &events, const QList<Todo> &todos);

/// 与 [from, to) 有交集的所有实例起点（本地时间，升序）。非重复事件最多返回一个。
QList<QDateTime> expand(const Event &e, const QDateTime &from, const QDateTime &to, int maxResults = 2000);

/// 事件时长（秒）；全天事件至少一天，非全天至少 0。
qint64 durationSecs(const Event &e);

/// 「每周一、三」「每月」这类简短描述，供详情面板显示。
QString describeRule(const QString &rrule);

}  // namespace ical
