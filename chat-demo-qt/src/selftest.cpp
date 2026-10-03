#include "selftest.h"

#include "chatstore.h"
#include "uistatestore.h"
#include "windowmanager.h"

#include <QEventLoop>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>

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
        wm->mainWindow()->grabWindow().save(shot);   // 可选：截图便于肉眼检查布局
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

    // 合并回主窗口
    wm->windowFor(c)->showNormal();
    wait(200);
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
}  // namespace

void SelfTest::schedule(int phase)
{
    QTimer::singleShot(1000, [phase] { phase == 1 ? phase1() : phase2(); });
}
