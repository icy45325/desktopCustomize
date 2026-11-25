#pragma once
#include "ical.h"

#include <QHash>
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class QQmlEngine;
class QJSEngine;

// 日历模块的唯一数据源（单例，所有窗口共享）。
//  - 日历：local（可编辑，.ics 落盘）/ subscription（URL 订阅，只读，定时刷新，缓存原始 .ics）
//  - 事件：支持全天、跨天、RRULE 重复、EXDATE、提醒（VALARM）
//  - 待办：VTODO，可设截止日期/时间、优先级，订阅日历里的 VTODO 也会展示（只读）
// QML 侧所有日期都用 "yyyy-MM-dd" 字符串或毫秒时间戳传递，避免 JS Date ↔ QDate 的时区换算问题。
class CalendarStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    /// 任意数据变化 +1；视图里的函数绑定读一下它即可自动重算。
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    Q_PROPERTY(QVariantList calendars READ calendars NOTIFY calendarsChanged)
    /// day | week | month | year | agenda
    Q_PROPERTY(QString viewMode READ viewMode WRITE setViewMode NOTIFY viewModeChanged)
    Q_PROPERTY(bool showTodos READ showTodos WRITE setShowTodos NOTIFY showTodosChanged)
    Q_PROPERTY(bool showCompleted READ showCompleted WRITE setShowCompleted NOTIFY showCompletedChanged)
    Q_PROPERTY(bool weekStartsMonday READ weekStartsMonday WRITE setWeekStartsMonday NOTIFY weekStartsMondayChanged)
    Q_PROPERTY(int openTodoCount READ openTodoCount NOTIFY changed)
    /// 周 / 月视图是否显示周末（默认不显示）；周末是哪两天："sat-sun"（阿联酋等）| "fri-sat"（沙特、卡塔尔、科威特等）
    Q_PROPERTY(bool showWeekends READ showWeekends WRITE setShowWeekends NOTIFY showWeekendsChanged)
    Q_PROPERTY(QString weekendDays READ weekendDays WRITE setWeekendDays NOTIFY weekendDaysChanged)
    /// 内置日历：阿联酋公共假日、伊斯兰节日（生成在内存里，只读，出现在侧栏「其他日历」）
    Q_PROPERTY(bool showUaeHolidays READ showUaeHolidays WRITE setShowUaeHolidays NOTIFY holidaysChanged)
    Q_PROPERTY(bool showIslamicHolidays READ showIslamicHolidays WRITE setShowIslamicHolidays NOTIFY holidaysChanged)
    /// 在日 / 周 / 月视图显示回历日期；hijriAdjust 为 -2～+2 天的校正（影响回历显示和伊斯兰节日日期）
    Q_PROPERTY(bool showHijri READ showHijri WRITE setShowHijri NOTIFY hijriChanged)
    Q_PROPERTY(int hijriAdjust READ hijriAdjust WRITE setHijriAdjust NOTIFY hijriChanged)
public:
    static CalendarStore *instance();
    static CalendarStore *create(QQmlEngine *, QJSEngine *);

    int revision() const { return m_revision; }
    QVariantList calendars() const;
    QString viewMode() const { return m_viewMode; }
    void setViewMode(const QString &v);
    bool showTodos() const { return m_showTodos; }
    void setShowTodos(bool v);
    bool showCompleted() const { return m_showCompleted; }
    void setShowCompleted(bool v);
    bool weekStartsMonday() const { return m_weekStartsMonday; }
    void setWeekStartsMonday(bool v);
    int openTodoCount() const;
    bool showWeekends() const { return m_showWeekends; }
    void setShowWeekends(bool v);
    QString weekendDays() const { return m_weekendDays; }
    void setWeekendDays(const QString &v);
    bool showUaeHolidays() const { return m_showUae; }
    void setShowUaeHolidays(bool v);
    bool showIslamicHolidays() const { return m_showIslamic; }
    void setShowIslamicHolidays(bool v);
    bool showHijri() const { return m_showHijri; }
    void setShowHijri(bool v);
    int hijriAdjust() const { return m_hijriAdjust; }
    void setHijriAdjust(int v);

    /// 从 fromIso 起连续 days 天的回历日期：[{y, m, d, label（格子里的短文字）, full}]
    Q_INVOKABLE QVariantList hijriRange(const QString &fromIso, int days) const;
    /// 完整回历日期文字：「回历 1448 年 主马达·阿色尼月 14 日」/「14 Jumada II 1448 AH」
    Q_INVOKABLE QString hijriText(const QString &iso) const;

    // MARK: 查询
    /// [fromIso, toIso) 内可见日历的所有事件实例，按「全天优先、开始时间」排序。
    Q_INVOKABLE QVariantList occurrences(const QString &fromIso, const QString &toIso) const;
    /// 截止日期落在 [fromIso, toIso) 的待办（showCompleted=false 时不含已完成）。
    Q_INVOKABLE QVariantList todosInRange(const QString &fromIso, const QString &toIso) const;
    /// filter: today | scheduled | all | completed
    Q_INVOKABLE QVariantList todos(const QString &filter) const;
    /// 标题/地点/备注包含 query 的事件实例（过去 90 天 ~ 未来 365 天）
    Q_INVOKABLE QVariantList search(const QString &query) const;
    Q_INVOKABLE QVariantMap event(const QString &uid) const;
    Q_INVOKABLE QVariantMap todo(const QString &uid) const;
    Q_INVOKABLE QString describeRule(const QString &rrule) const { return ical::describeRule(rrule); }
    /// 某天有没有事件（迷你月历的小圆点用）
    Q_INVOKABLE QVariantList busyDays(const QString &fromIso, const QString &toIso) const;

    // MARK: 日历
    Q_INVOKABLE QString addCalendar(const QString &name, const QString &color);
    Q_INVOKABLE void removeCalendar(const QString &id);
    Q_INVOKABLE void setCalendarVisible(const QString &id, bool visible);
    Q_INVOKABLE void setCalendarColor(const QString &id, const QString &color);
    Q_INVOKABLE void renameCalendar(const QString &id, const QString &name);
    Q_INVOKABLE QString defaultCalendar() const;
    Q_INVOKABLE QString defaultTodoList() const;
    Q_INVOKABLE QStringList palette() const;

    // MARK: 订阅
    /// 支持 http(s)://、webcal://（按 https 取）、file://、qrc:、本地路径。返回日历 id。
    Q_INVOKABLE QString subscribe(const QString &url, const QString &name, const QString &color, int refreshMinutes);
    Q_INVOKABLE void refresh(const QString &id);
    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void updateSubscription(const QString &id, const QString &url, int refreshMinutes);
    /// 把本地日历导出为 .ics（返回文件路径；空串 = 失败）
    Q_INVOKABLE QString exportCalendar(const QString &id, const QString &path = {});

    // MARK: 事件（map 字段：title calendarId allDay startMs endMs location notes rrule reminder）
    Q_INVOKABLE QString createEvent(const QVariantMap &m);
    Q_INVOKABLE bool updateEvent(const QString &uid, const QVariantMap &m);
    /// scope: "all" 删除整个系列；"this" 只删 occurrenceMs 这一次（写 EXDATE）
    Q_INVOKABLE bool deleteEvent(const QString &uid, const QString &scope = QStringLiteral("all"), double occurrenceMs = 0);
    /// 拖动改期：把（非重复）事件平移到新的开始时间，时长不变
    Q_INVOKABLE bool moveEvent(const QString &uid, double newStartMs);

    // MARK: 待办（map 字段：title calendarId dueIso dueTime("HH:mm" 或空) notes priority done）
    Q_INVOKABLE QString createTodo(const QVariantMap &m);
    Q_INVOKABLE bool updateTodo(const QString &uid, const QVariantMap &m);
    Q_INVOKABLE bool toggleTodo(const QString &uid);
    Q_INVOKABLE bool deleteTodo(const QString &uid);

    /// 面板等日历视图之外的地方请求「打开条目详情」/「新建」，由 CalendarView 响应
    Q_INVOKABLE void requestOpen(const QVariantMap &item) { emit openRequested(item); }
    Q_INVOKABLE void requestCreate(const QString &kind) { emit createRequested(kind); }
    /// 通知点击：跳到该事件所在日期
    void reveal(const QString &key);
    /// 自测用：立即检查一次提醒
    Q_INVOKABLE void checkReminders();

signals:
    void changed();
    void calendarsChanged();
    // 每个设置单独通知：共用一个信号会让切视图时所有读「周起始日」的绑定（年视图 500+ 个日期格）全部重算
    void viewModeChanged();
    void showTodosChanged();
    void showCompletedChanged();
    void weekStartsMondayChanged();
    void showWeekendsChanged();
    void weekendDaysChanged();
    void holidaysChanged();
    void hijriChanged();
    void syncFinished(const QString &id, bool ok, const QString &error);
    void notificationRequested(const QString &key, const QString &title, const QString &body);
    void revealRequested(const QString &dateIso);
    void openRequested(const QVariantMap &item);
    void createRequested(const QString &kind);

private:
    CalendarStore();
    struct Cal {
        QString id, name, color, kind;      // kind: local | subscription
        bool visible = true;
        QString url;
        int refreshMinutes = 60;
        QDateTime lastSync;
        QString lastError;
        bool syncing = false;
        QList<ical::Event> events;
        QList<ical::Todo> todos;
    };
    Cal *cal(const QString &id);
    const Cal *cal(const QString &id) const;
    Cal *calOfEvent(const QString &uid, int *index);
    Cal *calOfTodo(const QString &uid, int *index);
    QVariantMap occurrenceMap(const Cal &c, const ical::Event &e, const QDateTime &start) const;
    QVariantMap todoMap(const Cal &c, const ical::Todo &t) const;
    static void applyEvent(ical::Event &e, const QVariantMap &m);
    static void applyTodo(ical::Todo &t, const QVariantMap &m);
    void loadFromIcs(Cal &c, const QByteArray &data, bool adoptMeta);
    void fetched(const QString &id, const QByteArray &data, const QString &error);

    void rebuildBuiltins();        // 按设置重新生成内置日历（节假日开关 / 回历校正 / 语言变化时）
    QList<ical::Event> uaeHolidays(int fromYear, int toYear) const;
    QList<ical::Event> islamicHolidays(int fromYear, int toYear, bool skipUaeOverlap) const;
    void load();
    void seed();
    void saveMeta();
    void saveCalendar(const Cal &c);
    QString calDir() const;
    void bump();
    void bumpCalendars();

    QList<Cal> m_cals;
    QNetworkAccessManager *m_net = nullptr;
    QTimer m_tick;                       // 每 30 秒：提醒 + 订阅定时刷新
    QSet<QString> m_fired;               // 已经提醒过的实例
    int m_revision = 0;
    QString m_viewMode = QStringLiteral("week");
    bool m_showTodos = true;
    bool m_showCompleted = false;
    bool m_weekStartsMonday = true;
    bool m_showWeekends = false;
    QString m_weekendDays = QStringLiteral("sat-sun");
    bool m_showUae = false;
    bool m_showIslamic = false;
    bool m_showHijri = false;
    int m_hijriAdjust = 0;
    QHash<QString, bool> m_builtinVisible;   // 内置日历在侧栏里的勾选状态
};
