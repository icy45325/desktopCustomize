#include "selftest.h"

#include "appsettings.h"
#include "assistant.h"
#include "calendarstore.h"
#include "chatstore.h"
#include "ical.h"
#include "uistatestore.h"
#include "windowmanager.h"
#include "appdata.h"

#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <functional>
#include <QFile>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QRegularExpression>
#include <QUrl>

namespace {
int g_fail = 0;

void wait(int ms)
{
    QEventLoop l;
    QTimer::singleShot(ms, &l, &QEventLoop::quit);
    l.exec();
}

void check(bool ok, const char *what)
{
    qInfo("%s  %s", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++g_fail;
}

QQuickItem *draftInput(QQuickWindow *w)
{
    if (!w) return nullptr;
    // QML 子项的 QObject 父子关系不一定等于视觉层级，所以按 objectName 遍历整个视觉树
    QList<QQuickItem *> stack{w->contentItem()};
    while (!stack.isEmpty()) {
        QQuickItem *it = stack.takeLast();
        if (it->objectName() == "draftInput") return it;
        stack += it->childItems();
    }
    return nullptr;
}

QQuickItem *findItem(QQuickWindow *w, const char *name)
{
    if (!w) return nullptr;
    QList<QQuickItem *> stack{w->contentItem()};
    while (!stack.isEmpty()) {
        QQuickItem *it = stack.takeLast();
        if (it->objectName() == name) return it;
        stack += it->childItems();
    }
    return nullptr;
}

void finish()
{
    qInfo("%s (%d failed)", g_fail ? "SELFTEST FAILED" : "SELFTEST OK", g_fail);
    WindowManager::instance()->quitApp(g_fail ? 1 : 0);
}

void phase1()
{
    auto *wm = WindowManager::instance();
    auto *ui = UIStateStore::instance();
    auto *chat = ChatStore::instance();
    const QString c = QStringLiteral("c1");

    wm->select(c);
    wait(300);
    check(wm->placementOf(c) == "main" && wm->mainSelection() == c, "select: 会话在主窗口打开");

    if (const QString shot = qEnvironmentVariable("CHATDEMO_SHOT"); !shot.isEmpty()) {
        wm->mainWindow()->grabWindow().save(shot + ".main.light.png");
        wm->setDarkMode(true);
        wait(600);
        wm->mainWindow()->grabWindow().save(shot + ".main.dark.png");
        wm->setDarkMode(false);
        wait(600);   // 可选：截图便于肉眼检查布局
    }
    // 用例 1：草稿 + 光标
    QQuickItem *in = draftInput(wm->mainWindow());
    check(in != nullptr, "主窗口找到输入框");
    if (!in) return finish();
    in->setProperty("text", QStringLiteral("草稿 hello 你好"));
    in->setProperty("cursorPosition", 4);
    wait(450);   // 防抖 300ms
    check(ui->state(c).value("draftText").toString() == "草稿 hello 你好", "草稿防抖后写入 UIStateStore");
    check(ui->state(c).value("draftSelEnd").toInt() == 4, "光标位置写入 UIStateStore");

    // 用例 5：输入法组合中不迁移
    wm->setComposing(c, true);
    wm->detach(c);
    wait(250);
    check(wm->detachedWindowCount() == 0 && wm->placementOf(c) == "main", "输入法组合中：不拆出");
    wm->setComposing(c, false);
    wait(400);
    check(wm->detachedWindowCount() == 1 && wm->placementOf(c) == "detached", "组合结束后：拆出且只有一个窗口");
    check(wm->mainSelection().isEmpty() && wm->ghost() == c, "拆出后主窗口回到空态，ghost 指向该会话");

    // 用例 1：新窗口恢复草稿 + 光标
    QQuickItem *in2 = draftInput(wm->windowFor(c));
    check(in2 && in2->property("text").toString() == "草稿 hello 你好", "独立窗口草稿完整");
    check(in2 && in2->property("cursorPosition").toInt() == 4, "独立窗口光标位置一致");

    // 用例 4：再次打开 → 单实例
    wm->select(c);
    wm->detach(c);
    wait(200);
    check(wm->detachedWindowCount() == 1, "单实例：再次打开不新开窗口");

    // 租约：无效 token 的写入被丢弃
    check(!ui->update(c, {{"draftText", "STALE"}}, "bogus-token"), "无租约写入返回 false");
    check(ui->state(c).value("draftText").toString() == "草稿 hello 你好", "无租约写入被丢弃，状态不变");

    // 用例 3：设置引用回复（通过视图持有的租约写入），合并回主窗口后仍在
    auto *cv = findItem(wm->windowFor(c), "chatView");
    QVariantMap patch{{"replyToMsgId", "c1-seed-3"}};
    QMetaObject::invokeMethod(cv, "write", Q_ARG(QVariant, patch));
    check(ui->state(c).value("replyToMsgId").toString() == "c1-seed-3", "独立窗口内设置引用回复");

    // 用例 6：后台独立窗口收到新消息 → 未读 +1、发通知、不自动已读
    wm->windowFor(c)->showMinimized();
    wait(300);
    int notified = 0;
    auto conn = QObject::connect(chat, &ChatStore::notificationRequested, [&](auto &&...) { ++notified; });
    const int before = chat->unread(c);
    chat->receive({"selftest-1", c, "测试", "后台新消息", QDateTime::currentDateTime(), false, {}});
    check(chat->unread(c) == before + 1, "最小化的独立窗口收到新消息：未读 +1（用例 9）");
    check(notified == 1, "发出系统通知请求");
    check(!ui->state(c).value("unreadDividerMsgId").toString().isEmpty(), "写入「新消息」分隔线");
    QObject::disconnect(conn);
    if (const QString shot = qEnvironmentVariable("CHATDEMO_SHOT"); !shot.isEmpty()) {
        wm->mainWindow()->grabWindow().save(shot + ".ghost.light.png");      // 主窗口：空态 + 侧栏未读角标
    }

    // 窗口恢复可见后：自动滚到「新消息」分隔线
    wm->windowFor(c)->showNormal();
    wm->windowFor(c)->requestActivate();
    wait(500);
    {
        QQuickItem *lv = findItem(wm->windowFor(c), "messageList");
        QQuickItem *cv1 = findItem(wm->windowFor(c), "chatView");
        QVariant divIdx;
        QMetaObject::invokeMethod(cv1, "dividerIndex", Q_RETURN_ARG(QVariant, divIdx));
        QVariant first;
        QMetaObject::invokeMethod(lv, "indexAt", Q_RETURN_ARG(QVariant, first),
                                  Q_ARG(QVariant, 10.0), Q_ARG(QVariant, lv->property("contentY").toReal() + 4));
        const int d = divIdx.toInt(), f = first.toInt();
        const bool visible = lv->property("atYEnd").toBool() || (f >= 0 && d >= f && d <= f + 3);
        check(d >= 0 && visible, "窗口恢复后自动滚到「新消息」分隔线");
        if (const QString shot = qEnvironmentVariable("CHATDEMO_SHOT"); !shot.isEmpty()) {
            wm->windowFor(c)->grabWindow().save(shot + ".detached.light.png");   // 独立窗口：草稿 + 引用 + 新消息分隔线
            wm->setDarkMode(true);
            wait(600);
            wm->windowFor(c)->grabWindow().save(shot + ".detached.dark.png");
            wm->mainWindow()->grabWindow().save(shot + ".ghost.dark.png");
            wm->setDarkMode(false);
            wait(400);
        }
    }
    wm->attach(c);
    wait(400);
    check(wm->detachedWindowCount() == 0 && wm->placementOf(c) == "main" && wm->mainSelection() == c, "合并：窗口关闭，会话回到主窗口");
    QQuickItem *in3 = draftInput(wm->mainWindow());
    check(in3 && in3->property("text").toString() == "草稿 hello 你好", "合并后草稿完整");
    check(in3 && in3->property("cursorPosition").toInt() == 4, "合并后光标位置一致");
    auto *cv2 = findItem(wm->mainWindow(), "chatView");
    check(cv2 && cv2->property("st").toMap().value("replyToMsgId").toString() == "c1-seed-3", "合并后引用回复仍在");

    // 用例 10 / 12：拆出两个窗口后退出，留给 phase 2 恢复；⌘W 只关一个
    in3->setProperty("text", QStringLiteral("保存到磁盘"));
    wait(450);
    wm->detach("c1");
    wm->detach("c2");
    wait(400);
    check(wm->detachedWindowCount() == 2, "拆出两个独立窗口");
    wm->closeDetached("c2");
    wait(200);
    check(wm->detachedWindowCount() == 1 && wm->placementOf("c2") == "closed", "closeDetached：只关闭一个窗口");
    wm->detach("c3");
    wait(400);
    check(wm->detachedWindowCount() == 2, "再拆出一个（c1 + c3）");
    finish();
}

void phase2()
{
    auto *wm = WindowManager::instance();
    wait(800);
    check(wm->detachedWindowCount() == 2, "重启后恢复两个独立窗口");
    check(wm->placementOf("c1") == "detached" && wm->placementOf("c3") == "detached", "恢复的 Placement 正确（c1、c3）");
    check(wm->placementOf("c2") == "closed", "已关闭的 c2 不恢复");
    QQuickItem *in = draftInput(wm->windowFor("c1"));
    check(in && in->property("text").toString() == "保存到磁盘", "重启后草稿还在");
    finish();
}

// MARK: 日历

QList<QDate> starts(const ical::Event &e, QDate from, QDate to)
{
    QList<QDate> out;
    for (const QDateTime &dt : ical::expand(e, QDateTime(from, QTime(0, 0)), QDateTime(to, QTime(0, 0)))) out << dt.date();
    return out;
}

ical::Event rule(const QString &rrule, QDate start, QTime t = QTime(9, 0))
{
    ical::Event e;
    e.uid = "t";
    e.start = QDateTime(start, t);
    e.end = e.start.addSecs(3600);
    e.rrule = rrule;
    return e;
}

void icalTests()
{
    QFile f(":/qt/qml/ChatDemo/data/team-sample.ics");
    check(f.open(QIODevice::ReadOnly), "ical: 读取内置示例 .ics");
    const ical::Calendar c = ical::parse(f.readAll());
    check(c.name == "团队公共日历", "ical: X-WR-CALNAME");
    check(c.events.size() == 7 && c.todos.size() == 3, "ical: 7 个 VEVENT（含 1 个 RECURRENCE-ID 覆盖）+ 3 个 VTODO");
    const auto find = [&](const QString &uid) { for (const auto &e : c.events) if (e.uid == uid) return e; return ical::Event{}; };
    const ical::Event allhands = find("allhands@team.example");
    check(allhands.notes.contains("风险, 依赖与求助") && allhands.notes.contains('\n'), "ical: 文本反转义（\\n、\\,）");
    check(find("offsite@team.example").notes.contains("会被折成多行"), "ical: 折行还原");
    check(find("offsite@team.example").allDay && find("offsite@team.example").end.date() == QDate(2026, 12, 14), "ical: 全天多日事件（DTEND 不含）");
    const ical::Event utc = find("global-sync@team.example");
    check(utc.start == QDateTime(QDate(2026, 11, 25), QTime(2, 0), Qt::UTC).toLocalTime(), "ical: UTC 时间换算为本地");
    const ical::Event sh = find("sprint-planning@team.example");
    check(sh.start.toUTC().time() == QTime(7, 0) && sh.reminderMinutes == 15, "ical: TZID=Asia/Shanghai 换算 + VALARM");
    check(find("monthly-review@team.example").end == find("monthly-review@team.example").start.addSecs(3600), "ical: DURATION");

    // 重复规则
    const QDate nov23(2026, 11, 23);
    const QList<QDate> ah = starts(allhands, nov23, nov23.addDays(14));
    check(!ah.isEmpty() && !ah.contains(QDate(2026, 11, 26)), "RRULE: RECURRENCE-ID 覆盖的实例被排除");
    check(starts(find("monthly-review@team.example"), QDate(2026, 11, 1), QDate(2026, 12, 1)) == QList<QDate>{QDate(2026, 11, 27)},
          "RRULE: MONTHLY;BYDAY=-1FR（最后一个周五）");
    const ical::Event sp = sh;
    QList<QDate> spDays;
    for (const QDateTime &x : ical::expand(sp, sp.start.addDays(320), sp.start.addDays(340))) spDays << x.toUTC().date();
    check(spDays.size() == 1 && spDays[0] == QDate(2026, 11, 23), "RRULE: WEEKLY;INTERVAL=2（双周）");
    check(ical::expand(sp, QDateTime(QDate(2026, 12, 6), QTime(0, 0)), QDateTime(QDate(2026, 12, 9), QTime(0, 0))).isEmpty(), "RRULE: EXDATE 排除");
    check(starts(rule("FREQ=DAILY;COUNT=3", nov23), nov23, nov23.addDays(30)).size() == 3, "RRULE: COUNT");
    check(starts(rule("FREQ=DAILY;UNTIL=20261125", nov23), nov23, nov23.addDays(30)).size() == 3, "RRULE: UNTIL（日期，含当天）");
    check(starts(rule("FREQ=WEEKLY;BYDAY=MO,WE,FR", nov23), nov23, nov23.addDays(7)).size() == 3, "RRULE: WEEKLY;BYDAY 多天");
    check(starts(rule("FREQ=MONTHLY", QDate(2026, 1, 31)), QDate(2026, 1, 1), QDate(2027, 1, 1)).size() == 7, "RRULE: 31 号按月重复跳过小月");
    check(starts(rule("FREQ=YEARLY", QDate(2024, 2, 29)), QDate(2024, 1, 1), QDate(2033, 1, 1)).size() == 3, "RRULE: 2/29 按年只在闰年");
    check(starts(rule("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", nov23), QDate(2026, 11, 1), QDate(2027, 1, 1))
              == QList<QDate>{QDate(2026, 11, 30), QDate(2026, 12, 31)}, "RRULE: BYSETPOS=-1（每月最后一个工作日）");
    check(starts(rule("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", QDate(2026, 11, 26)), QDate(2026, 1, 1), QDate(2028, 1, 1))
              == QList<QDate>{QDate(2026, 11, 26), QDate(2027, 11, 25)}, "RRULE: YEARLY;BYMONTH;BYDAY=4TH");

    // 序列化往返
    ical::Event e = rule("FREQ=WEEKLY;BYDAY=TU", nov23.addDays(1));
    e.uid = "rt@x"; e.title = "含,逗号;分号\n换行 和一段很长很长很长很长很长很长很长很长很长很长很长很长很长的中文"; e.location = "A"; e.reminderMinutes = 30;
    e.exdates << QDateTime(nov23.addDays(8), QTime(9, 0));
    ical::Todo t; t.uid = "todo@x"; t.title = "待办"; t.due = nov23; t.dueTime = QTime(18, 0); t.priority = 1; t.done = true;
    t.completed = QDateTime::currentDateTime();
    const QByteArray bytes = ical::serialize("往返", "#112233", {e}, {t});
    const ical::Calendar back = ical::parse(bytes);
    bool lineOk = true;
    for (const QByteArray &l : bytes.split('\n')) lineOk = lineOk && l.size() <= 76;
    check(lineOk, "serialize: 每行不超过 75 字节（折行）");
    check(back.name == "往返" && back.color == "#112233" && back.events.size() == 1 && back.events[0].title == e.title
              && back.events[0].rrule == e.rrule && back.events[0].reminderMinutes == 30 && back.events[0].exdates.size() == 1,
          "serialize → parse 往返：事件字段一致");
    check(back.todos.size() == 1 && back.todos[0].done && back.todos[0].dueTime == QTime(18, 0) && back.todos[0].priority == 1,
          "serialize → parse 往返：待办字段一致");
}


// MARK: AI 小助手 + 动态面板

void assistantTests()
{
    auto *as = Assistant::instance();
    auto *cs = CalendarStore::instance();
    const QDate mon(2026, 11, 23);   // 周一
    auto pw = [&](const char *t) { return Assistant::parseWhen(QString::fromUtf8(t), mon); };
    check(pw("明天下午3点 需求评审 1小时").from == mon.addDays(1) && pw("明天下午3点 需求评审 1小时").start == QTime(15, 0)
              && pw("明天下午3点 需求评审 1小时").durationMin == 60 && pw("明天下午3点 需求评审 1小时").rest.contains("需求评审"),
          "assistant: 解析「明天下午3点 … 1小时」");
    check(pw("周五上午十点半").from == QDate(2026, 11, 27) && pw("周五上午十点半").start == QTime(10, 30), "assistant: 中文数字「十点半」+ 周几");
    check(pw("下周三 14:00-15:30").from == QDate(2026, 12, 2) && pw("下周三 14:00-15:30").end == QTime(15, 30), "assistant: 下周三 + 时间区间");
    check(pw("3点到5点").start == QTime(15, 0) && pw("3点到5点").end == QTime(17, 0), "assistant: 无时段词的「3点」按下午");
    check(pw("12月5号").from == QDate(2026, 12, 5) && pw("本周").to == QDate(2026, 11, 30), "assistant: 月日 / 本周范围");
    check(pw("一个半小时").durationMin == 90 && pw("半小时").durationMin == 30 && pw("45分钟").durationMin == 45, "assistant: 时长");

    const QDateTime now(QDate::currentDate(), QTime(8, 0));
    QVariantMap r = as->respond("今天有什么安排？", now);
    check(r["text"].toString().contains("产品评审") && !r["items"].toList().isEmpty(), "assistant: 查今天的安排");
    r = as->respond("下一个会议是什么？", now);
    check(r["text"].toString().contains("下一个是") && r["items"].toList().size() == 1, "assistant: 下一个会议");
    r = as->respond("今天下午有空吗", now);
    check(r["text"].toString().contains("–") || r["text"].toString().contains("没有空档"), "assistant: 查空闲时段");
    r = as->respond("明天下午4点 架构讨论 半小时", now);
    const QString uid = r["action"].toMap()["uid"].toString();
    const QVariantMap ev = cs->event(uid);
    check(!uid.isEmpty() && ev["title"] == "架构讨论"
              && QDateTime::fromMSecsSinceEpoch(qint64(ev["startMs"].toDouble())) == QDateTime(QDate::currentDate().addDays(1), QTime(16, 0))
              && ev["endMs"].toDouble() - ev["startMs"].toDouble() == 30 * 60000.0, "assistant: 自然语言新建活动（标题 / 时间 / 时长）");
    cs->deleteEvent(uid);
    r = as->respond("提醒我周五交周报", now);
    const QString tid = r["action"].toMap()["uid"].toString();
    check(!tid.isEmpty() && cs->todo(tid)["title"] == "交周报" && !cs->todo(tid)["dueIso"].toString().isEmpty(), "assistant: 自然语言新建待办");
    cs->deleteTodo(tid);
    r = as->respond("本周的待办", now);
    check(r["text"].toString().contains("待办"), "assistant: 查待办");

    // 消息流 + 撤销
    as->clear();
    as->send("提醒我明天买咖啡豆");
    wait(600);
    const QVariantList msgs = as->messages();
    check(msgs.size() == 2 && msgs[1].toMap()["text"].toString().contains("咖啡豆"), "assistant: send → 回复");
    const QString t2 = msgs[1].toMap()["action"].toMap()["uid"].toString();
    as->runAction(1);
    check(cs->todo(t2).isEmpty() && as->messages()[1].toMap()["done"].toBool(), "assistant: 撤销");
}

void panelTests()
{
    auto *wm = WindowManager::instance();
    assistantTests();
    wm->setModule("calendar");
    wm->setPanelOpen(true);
    wm->setPanelTab("meetings");
    wait(500);
    check(findItem(wm->mainWindow(), "meetingPanel") && findItem(wm->mainWindow(), "meetingPanel")->isVisible(), "panel: 会议标签");
    wm->setPanelTab("assistant");
    wait(400);
    check(findItem(wm->mainWindow(), "assistantPanel") && findItem(wm->mainWindow(), "assistantPanel")->isVisible(), "panel: 助手标签");

    // 日历模块里在面板打开会话（Placement = panel，与主窗口互斥）
    wm->setModule("chat");
    wm->select("c2");
    wait(300);
    wm->setModule("calendar");
    wm->openInPanel("c2");
    wait(500);
    check(wm->placementOf("c2") == "panel" && wm->panelConv() == "c2" && wm->mainSelection().isEmpty(), "panel: 会话移到面板（主窗口让出）");
    QQuickItem *pin = draftInput(wm->mainWindow());
    QQuickItem *panelChat = findItem(wm->mainWindow(), "panelChat");
    check(panelChat && panelChat->isVisible() && pin && pin->isVisible(), "panel: 日历模块里显示聊天详情");
    if (pin) { pin->setProperty("text", QStringLiteral("面板草稿")); wait(450); }
    wm->select("c2");
    wait(400);
    check(wm->placementOf("c2") == "main" && wm->panelConv().isEmpty(), "panel: 在消息中打开 → 回到主窗口");
    wm->setModule("chat");
    wait(400);
    QQuickItem *in = draftInput(wm->mainWindow());
    check(in && in->property("text").toString() == "面板草稿", "panel: 草稿随会话迁移");

    // 消息模块：面板显示日历；拆成独立窗口再合并
    wm->setPanelTab("calendar");
    wait(400);
    check(findItem(wm->mainWindow(), "panelCalendar") && findItem(wm->mainWindow(), "panelCalendar")->isVisible(), "panel: 消息模块里显示日历");
    wm->detachPanel();
    wait(600);
    check(wm->panelWindow() && !findItem(wm->mainWindow(), "sidePanel") && findItem(wm->panelWindow(), "sidePanel"), "panel: 拆成独立窗口（主窗口里卸载）");
    if (const QString shot = qEnvironmentVariable("CHATDEMO_SHOT"); !shot.isEmpty() && wm->panelWindow())
        wm->panelWindow()->grabWindow().save(shot + ".panel.window.light.png");
    wm->attachPanel();
    wait(400);
    check(!wm->panelWindow() && findItem(wm->mainWindow(), "sidePanel"), "panel: 合并回主窗口");
    wm->setPanelTab("todo");
    wm->setModule("calendar");
    wait(300);
}


// MARK: 设置：主题模式 + 界面语言

QString textOf(QQuickWindow *w, const char *name) { QQuickItem *it = findItem(w, name); return it ? it->property("text").toString() : QString(); }

void settingsTests()
{
    auto *wm = WindowManager::instance();
    auto *st = AppSettings::instance();
    const QString shot = qEnvironmentVariable("CHATDEMO_SHOT");

    // 主题：浅色 / 深色 / 跟随系统
    st->setThemeMode("dark");
    check(st->dark() && wm->darkMode(), "settings: 深色模式");
    st->setThemeMode("light");
    check(!st->dark() && !wm->darkMode(), "settings: 浅色模式");
    st->setThemeMode("system");
    check(st->dark() == st->systemDark(), "settings: 跟随系统（生效值 = 系统外观）");
    st->toggleDark();
    check(st->themeMode() == (st->systemDark() ? "light" : "dark"), "settings: ⌘⇧D 从「跟随系统」切到固定模式");
    st->setThemeMode("light");

    // 语言：中文 → English（界面重建，草稿保留，设置对话框保持打开）
    wm->setModule("chat");
    wm->select("c3");
    wait(400);
    if (QQuickItem *in = draftInput(wm->mainWindow())) { in->setProperty("text", QStringLiteral("切换语言前的草稿")); wait(100); }   // 不等防抖：验证切换前的 flush
    QMetaObject::invokeMethod(wm, "openSettings");
    wait(300);
    QObject *dlg = findItem(wm->mainWindow(), "settingsDialog") ? nullptr : wm->mainWindow()->findChild<QObject *>("settingsDialog");
    check(dlg && dlg->property("opened").toBool(), "settings: ⌘, 打开设置");
    if (!shot.isEmpty()) wm->mainWindow()->grabWindow().save(shot + ".settings.zh.light.png");

    st->setLanguage("en");
    wait(700);
    check(dlg && dlg->property("opened").toBool(), "i18n: 切换语言时设置对话框保持打开");
    if (!shot.isEmpty()) wm->mainWindow()->grabWindow().save(shot + ".settings.en.light.png");
    if (dlg) QMetaObject::invokeMethod(dlg, "close");
    QQuickItem *in2 = draftInput(wm->mainWindow());
    check(in2 && in2->property("text").toString() == "切换语言前的草稿", "i18n: 界面重建后草稿保留（切换前已 flush）");
    check(findItem(wm->mainWindow(), "rail-chat") && QString(findItem(wm->mainWindow(), "rail-chat")->property("label").toString()) == "Messages", "i18n: 导航条文字为英文");

    wm->setModule("calendar");
    CalendarStore::instance()->setViewMode("month");
    wait(500);
    const QString title = textOf(wm->mainWindow(), "calendarTitle");
    check(QRegularExpression("^(January|February|March|April|May|June|July|August|September|October|November|December) \\d{4}$").match(title).hasMatch(),
          qPrintable("i18n: 月视图标题为英文格式（" + title + "）"));
    check(CalendarStore::instance()->describeRule("FREQ=WEEKLY;BYDAY=MO,WE") == "Weekly on Mon, Wed"
              && CalendarStore::instance()->describeRule("FREQ=MONTHLY;BYDAY=2TU") == "Monthly on the 2nd Tue", "i18n: 重复规则描述为英文");

    // 助手：英文输入 + 英文回复
    auto *as = Assistant::instance();
    const QDateTime now(QDate::currentDate(), QTime(8, 0));
    const auto w = Assistant::parseWhen("design sync tomorrow at 3:30pm for 45 minutes", QDate(2026, 11, 23));
    check(w.from == QDate(2026, 11, 24) && w.start == QTime(15, 30) && w.durationMin == 45 && w.rest.contains("design sync"), "i18n: 解析英文日期 / 时间 / 时长");
    const auto w2 = Assistant::parseWhen("next friday 2-4pm", QDate(2026, 11, 23));
    check(w2.from == QDate(2026, 11, 27) && w2.start == QTime(14, 0) && w2.end == QTime(16, 0), "i18n: next friday + 时间区间");
    QVariantMap r = as->respond("What's on today?", now);
    check(r["text"].toString().startsWith("Today") && !r["items"].toList().isEmpty(), qPrintable("i18n: 助手英文查日程（" + r["text"].toString().left(40) + "…）"));
    r = as->respond("Design sync tomorrow at 4pm for 30 min", now);
    const QString uid = r["action"].toMap()["uid"].toString();
    check(!uid.isEmpty() && CalendarStore::instance()->event(uid)["title"] == "Design sync" && r["text"].toString().startsWith("Created"), "i18n: 助手英文新建活动");
    CalendarStore::instance()->deleteEvent(uid);
    r = as->respond("remind me to send the invoice friday", now);
    const QString tid = r["action"].toMap()["uid"].toString();
    check(!tid.isEmpty() && CalendarStore::instance()->todo(tid)["title"] == "send the invoice", "i18n: 助手英文新建待办");
    CalendarStore::instance()->deleteTodo(tid);

    if (!shot.isEmpty()) {
        CalendarStore::instance()->setViewMode("week");
        wm->setPanelTab("meetings");
        wait(600);
        wm->mainWindow()->grabWindow().save(shot + ".en.calendar.week.light.png");
        st->setThemeMode("dark");
        wm->setPanelTab("assistant");
        as->send("What's my next meeting?");
        wait(900);
        wm->mainWindow()->grabWindow().save(shot + ".en.calendar.week.dark.png");
        st->setThemeMode("light");
        wm->setModule("chat");
        wm->setPanelTab("calendar");
        wait(600);
        wm->mainWindow()->grabWindow().save(shot + ".en.chat.light.png");
    }

    // 切回中文
    st->setLanguage("zh");
    wm->setModule("calendar");
    CalendarStore::instance()->setViewMode("month");
    wait(600);
    check(textOf(wm->mainWindow(), "calendarTitle").contains("年"), "i18n: 切回中文");
    CalendarStore::instance()->setViewMode("week");
    wm->setPanelTab("todo");
    wait(300);
}

QStringList titlesOn(const QDate &d)
{
    QStringList r;
    for (const QVariant &v : CalendarStore::instance()->occurrences(d.toString(Qt::ISODate), d.addDays(1).toString(Qt::ISODate)))
        r << v.toMap().value("title").toString();
    return r;
}

// 性能：切模块、切视图（首次创建 / 再次访问）、数据变化的耗时（含一次完整重绘）。--selftest --perf
void perfPhase()
{
    auto *wm = WindowManager::instance();
    auto measure = [&](const char *what, std::function<void()> f) {
        QElapsedTimer t; t.start();
        f();
        QCoreApplication::processEvents();
        wm->mainWindow()->grabWindow();
        qInfo("PERF %-28s %6lld ms", what, t.elapsed());
    };
    wm->setModule("chat"); wait(500);
    measure("chat 重绘基线", [] {});
    measure("首次切到日历", [&] { wm->setModule("calendar"); });
    wait(300);
    measure("切回消息", [&] { wm->setModule("chat"); });
    wait(300);
    measure("再次切到日历", [&] { wm->setModule("calendar"); });
    wait(300);
    measure("日历重绘基线（无变化）", [] {});
    for (int round = 1; round <= 2; ++round)
        for (const char *m : {"month", "day", "year", "agenda", "week"}) {
            wait(300);
            measure(qPrintable(QString("视图 → %1（第 %2 次）").arg(m).arg(round)), [&] { CalendarStore::instance()->setViewMode(m); });
        }
    wait(300);
    measure("数据变化（新建待办）", [&] { CalendarStore::instance()->createTodo({{"title", "perf"}}); });
    finish();
}

void calendarPhase()
{
    auto *wm = WindowManager::instance();
    auto *cs = CalendarStore::instance();
    icalTests();

    // 数据层
    const QDate today = QDate::currentDate();
    check(cs->calendars().size() == 4, "store: 首次启动生成 3 个本地日历 + 1 个示例订阅");
    QVariantMap sub;
    for (const QVariant &v : cs->calendars()) if (v.toMap()["kind"] == "subscription") sub = v.toMap();
    check(sub["lastError"].toString().isEmpty() && sub["eventCount"].toInt() == 7, "store: 示例订阅已同步（qrc:）");
    check(titlesOn(today).contains("产品评审") && titlesOn(today).contains("1:1 沟通"), "store: 今天的本地事件");
    check(QFile::exists(dataDir() + "/calendar/work.ics") && QFile::exists(dataDir() + "/calendar/calendars.json"), "store: 本地日历以 .ics 落盘");

    const QDateTime s(today.addDays(1), QTime(15, 0));
    const QString uid = cs->createEvent({{"title", "自测活动"}, {"calendarId", "personal"}, {"startMs", double(s.toMSecsSinceEpoch())},
                                         {"endMs", double(s.addSecs(5400).toMSecsSinceEpoch())}, {"rrule", "FREQ=DAILY;COUNT=5"}});
    check(!uid.isEmpty() && titlesOn(today.addDays(1)).contains("自测活动") && titlesOn(today.addDays(5)).contains("自测活动")
              && !titlesOn(today.addDays(6)).contains("自测活动"), "store: 新建重复活动（COUNT=5）");
    cs->deleteEvent(uid, "this", double(QDateTime(today.addDays(3), QTime(15, 0)).toMSecsSinceEpoch()));
    check(!titlesOn(today.addDays(3)).contains("自测活动") && titlesOn(today.addDays(4)).contains("自测活动"), "store: 删除单次实例（EXDATE）");
    cs->updateEvent(uid, {{"title", "自测活动（改）"}, {"calendarId", "work"}});
    check(titlesOn(today.addDays(2)).contains("自测活动（改）") && cs->event(uid)["calendarId"] == "work", "store: 编辑并移到其它日历");
    cs->deleteEvent(uid, "all");
    check(cs->event(uid).isEmpty(), "store: 删除整个系列");
    check(!cs->updateEvent("allhands@team.example", {{"title", "x"}}), "store: 订阅日历只读，不能修改");

    const int before = cs->todos("today").size();
    const QString tid = cs->createTodo({{"title", "自测待办"}, {"dueIso", today.toString(Qt::ISODate)}, {"dueTime", "23:59"}});
    check(cs->todos("today").size() == before + 1, "store: 新建今天的待办");
    cs->toggleTodo(tid);
    check(cs->todos("today").size() == before && cs->todo(tid)["done"].toBool(), "store: 勾选完成");
    bool inRange = false;
    cs->setShowCompleted(true);
    for (const QVariant &v : cs->todosInRange(today.toString(Qt::ISODate), today.addDays(1).toString(Qt::ISODate))) inRange |= v.toMap()["uid"] == tid;
    cs->setShowCompleted(false);
    check(inRange, "store: 待办按截止日期出现在日历区间里");
    cs->deleteTodo(tid);

    cs->setCalendarVisible("work", false);
    check(!titlesOn(today).contains("产品评审"), "store: 隐藏日历后不显示其事件");
    cs->setCalendarVisible("work", true);
    check(!cs->search("评审").isEmpty(), "store: 搜索");

    // 订阅：本地文件 + 错误地址
    const QString path = dataDir() + "/import-test.ics";
    {
        QFile out(path);
        out.open(QIODevice::WriteOnly);
        out.write(ical::serialize("外部日历", "#FF5A5F", {rule("FREQ=WEEKLY;BYDAY=MO", today)}, {}));
    }
    const QString sid = cs->subscribe(QUrl::fromLocalFile(path).toString(), "", "", 60);
    QVariantMap s2;
    for (const QVariant &v : cs->calendars()) if (v.toMap()["id"] == sid) s2 = v.toMap();
    check(s2["name"] == "外部日历" && s2["eventCount"] == 1 && s2["readOnly"].toBool(), "subscribe: file:// 订阅，名称取 X-WR-CALNAME");
    check(cs->subscribe(QUrl::fromLocalFile(path).toString(), "", "", 60) == sid, "subscribe: 同一地址不重复订阅");
    const QString bad = cs->subscribe("ftp://example.invalid/x.ics", "坏地址", "", 60);
    QVariantMap s3;
    for (const QVariant &v : cs->calendars()) if (v.toMap()["id"] == bad) s3 = v.toMap();
    check(!s3["lastError"].toString().isEmpty(), "subscribe: 不支持的地址给出错误");
    cs->removeCalendar(bad);
    cs->removeCalendar(sid);
    check(cs->calendars().size() == 4, "subscribe: 取消订阅");

    // 提醒 → 通知 → 点击路由到日历
    QString notifiedKey;
    auto conn = QObject::connect(cs, &CalendarStore::notificationRequested, [&](const QString &k, auto &&...) { notifiedKey = k; });
    const QDateTime soon = QDateTime::currentDateTime().addSecs(5 * 60);
    const QString rid = cs->createEvent({{"title", "提醒测试"}, {"startMs", double(soon.toMSecsSinceEpoch())},
                                         {"endMs", double(soon.addSecs(1800).toMSecsSinceEpoch())}, {"reminder", 10}});
    cs->checkReminders();
    check(notifiedKey.startsWith("cal:" + rid), "reminder: 到点发出系统通知");
    QObject::disconnect(conn);
    wm->setModule("chat");
    wm->route(notifiedKey);
    check(wm->module() == "calendar", "reminder: 点击通知切到日历模块");
    cs->deleteEvent(rid);

    // 视图
    wait(600);
    QQuickItem *cv = findItem(wm->mainWindow(), "calendarView");
    if (QQuickItem *b = findItem(wm->mainWindow(), "createButton")) {   // 强调色按钮上的文字是浅色（曾因属性名 onAccent 被当成信号处理器而变黑）
        auto *ci = b->property("contentItem").value<QQuickItem *>();
        check(ci && ci->property("color").value<QColor>().lightness() > 200, "UI: 强调色按钮文字为浅色");
    }
    check(cv != nullptr && cv->isVisible(), "UI: 日历模块已加载");
    if (!cv) return finish();
    const QString shot = qEnvironmentVariable("CHATDEMO_SHOT");
    const QStringList modes{"week", "month", "day", "year", "agenda"};
    const QHash<QString, QString> expect{{"week", "timeGrid"}, {"day", "timeGrid"}, {"month", "monthView"}, {"year", "yearView"}, {"agenda", "agendaView"}};
    for (const QString &m : modes) {
        cs->setViewMode(m);
        wait(500);
        QQuickItem *host = findItem(wm->mainWindow(), "viewHost");
        auto *item = host ? host->property("item").value<QQuickItem *>() : nullptr;
        check(item && item->objectName() == expect[m], qPrintable("UI: 切换到 " + m + " 视图"));
        if (!shot.isEmpty()) {
            wm->mainWindow()->grabWindow().save(shot + ".calendar." + m + ".light.png");
            if (m == "week" || m == "month") {
                wm->setDarkMode(true);
                wait(500);
                wm->mainWindow()->grabWindow().save(shot + ".calendar." + m + ".dark.png");
                wm->setDarkMode(false);
                wait(400);
            }
        }
    }
    cs->setViewMode("week");
    wait(400);
    int blocks = 0;
    QList<QQuickItem *> stack{wm->mainWindow()->contentItem()};
    while (!stack.isEmpty()) {
        QQuickItem *it = stack.takeLast();
        if (it->objectName() == "eventBlock" && it->isVisible()) ++blocks;
        stack += it->childItems();
    }
    check(blocks >= 5, "UI: 周视图渲染出事件块");
    QQuickItem *todoPanel = findItem(wm->mainWindow(), "todoPanel");
    check(todoPanel && todoPanel->isVisible(), "UI: 动态面板默认显示待办");
    panelTests();
    settingsTests();
    if (!shot.isEmpty()) {   // 面板各标签截图（日历模块）
        wm->setModule("calendar");
        for (const char *t : {"meetings", "assistant", "chat"}) {
            if (QString(t) == "chat") wm->openInPanel("c2");
            wm->setPanelTab(t);
            wait(600);
            wm->mainWindow()->grabWindow().save(shot + ".panel." + t + ".light.png");
        }
        wm->select("c2");   // 移回主窗口
        wm->setModule("chat");
        wm->setPanelTab("calendar");
        wait(600);
        wm->mainWindow()->grabWindow().save(shot + ".panel.calendar-in-chat.light.png");
        wm->setDarkMode(true);
        wait(600);
        wm->mainWindow()->grabWindow().save(shot + ".panel.calendar-in-chat.dark.png");
        wm->setDarkMode(false);
        wm->setPanelTab("todo");
        wm->setModule("calendar");
        wait(400);
    }

    // 编辑器截图
    if (!shot.isEmpty()) {
        QMetaObject::invokeMethod(cv, "createAt", Q_ARG(QVariant, QVariant()), Q_ARG(QVariant, QVariant()), Q_ARG(QVariant, false), Q_ARG(QVariant, "event"));
        wait(500);
        wm->mainWindow()->grabWindow().save(shot + ".calendar.editor.light.png");
        if (QObject *ed = cv->findChild<QObject *>("eventEditor")) QMetaObject::invokeMethod(ed, "close");
        QMetaObject::invokeMethod(cv, "openSubscribe", Q_ARG(QVariant, QString()));
        wait(500);
        wm->mainWindow()->grabWindow().save(shot + ".calendar.subscribe.light.png");
        if (QObject *sd = cv->findChild<QObject *>("subscribeDialog")) QMetaObject::invokeMethod(sd, "close");
        wait(300);
    }
    finish();
}
}  // namespace

void SelfTest::schedule(int phase)
{
    QTimer::singleShot(1000, [phase] { phase == 4 ? perfPhase() : phase == 3 ? calendarPhase() : phase == 1 ? phase1() : phase2(); });
}
