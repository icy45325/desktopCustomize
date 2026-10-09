#include "windowmanager.h"

#include "appdata.h"
#include "chatstore.h"
#include "uistatestore.h"

#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

static const QSize kDefaultSize(480, 640);

WindowManager *WindowManager::instance()
{
    static WindowManager *s = new WindowManager;
    return s;
}

WindowManager *WindowManager::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

WindowManager::WindowManager()
{
    m_dark = layoutSettings().value(QStringLiteral("ui/dark"), false).toBool();
    if (qEnvironmentVariableIsSet("CHATDEMO_DARK"))
        m_dark = qEnvironmentVariableIntValue("CHATDEMO_DARK") != 0;
    qApp->installEventFilter(this);
    connect(qApp, &QCoreApplication::aboutToQuit, this, [this] {
        m_terminating = true;
        saveAllGeometry();
    });
}

void WindowManager::setEngine(QQmlEngine *engine) { m_engine = engine; }

void WindowManager::setDarkMode(bool v)
{
    if (m_dark == v)
        return;
    m_dark = v;
    layoutSettings().setValue(QStringLiteral("ui/dark"), v);
    emit darkModeChanged();
}

// 系统 Quit（macOS ⌘Q 等）会先关闭所有窗口再 aboutToQuit，要在第一时间标记「退出中」，
// 否则各独立窗口的 closing 会把 Placement 改成 closed，布局就丢了。
bool WindowManager::eventFilter(QObject *obj, QEvent *e)
{
    if (e->type() == QEvent::Quit)
        m_terminating = true;
    return QObject::eventFilter(obj, e);
}

QString WindowManager::placementOf(const QString &convId) const
{
    return m_placements.value(convId, QStringLiteral("closed"));
}

void WindowManager::setPlacement(const QString &id, const QString &p)
{
    if (placementOf(id) == p)
        return;
    m_placements[id] = p;
    emit placementChanged(id);
    ChatStore::instance()->placementChanged(id);
}

void WindowManager::setMainSelection(const QString &id)
{
    if (m_mainSelection == id)
        return;
    m_mainSelection = id;
    emit mainSelectionChanged();
}

void WindowManager::setGhost(const QString &id)
{
    if (m_ghost == id)
        return;
    m_ghost = id;
    emit ghostChanged();
}

void WindowManager::setActiveVisible(const QString &convId, bool v)
{
    if (v)
        m_activeVisible.insert(convId);
    else
        m_activeVisible.remove(convId);
}

void WindowManager::setComposing(const QString &convId, bool v)
{
    if (v)
        m_composing.insert(convId);
    else
        m_composing.remove(convId);
}

int WindowManager::detachedWindowCount() const
{
    int n = 0;
    for (const auto &w : m_windows)
        n += w ? 1 : 0;
    return n;
}

// MARK: - 打开

void WindowManager::select(const QString &convId)
{
    if (convId.isEmpty()) {
        if (!m_mainSelection.isEmpty())
            release(m_mainSelection);
        setMainSelection(QString());
        saveLayout();
        return;
    }
    if (placementOf(convId) == QLatin1String("detached")) {
        raiseWindow(m_windows.value(convId));   // 单实例：前置已有窗口
        return;
    }
    if (!m_mainSelection.isEmpty() && m_mainSelection != convId)
        release(m_mainSelection);
    setMainSelection(convId);
    setGhost(QString());
    setPlacement(convId, QStringLiteral("main"));
    saveLayout();
}

void WindowManager::release(const QString &id)
{
    UIStateStore::instance()->flush(id);
    if (placementOf(id) == QLatin1String("main"))
        setPlacement(id, QStringLiteral("closed"));
}

// MARK: - 拆出 / 合并（状态迁移：flush → 释放租约 → 更新 Placement → 新容器挂载并获取租约）

void WindowManager::detach(const QString &convId) { detachImpl(convId, std::nullopt); }

void WindowManager::detachAt(const QString &convId, qreal x, qreal y) { detachImpl(convId, QPointF(x, y)); }

void WindowManager::detachImpl(const QString &id, std::optional<QPointF> origin)
{
    if (id.isEmpty())
        return;
    if (placementOf(id) == QLatin1String("detached") && m_windows.value(id)) {
        raiseWindow(m_windows.value(id));
        return;
    }
    if (deferIfComposing(id, [this, id, origin] { detachImpl(id, origin); }))
        return;
    UIStateStore::instance()->flush(id);                 // 1. 旧视图 flush（2. 租约在旧视图销毁/新视图获取时交接）
    setPlacement(id, QStringLiteral("detached"));        // 3. 更新 Placement
    if (m_mainSelection == id) {
        setMainSelection(QString());
        setGhost(id);
    }
    saveLayout();
    createWindow(id, origin);                            // 4. 新容器挂载
}

void WindowManager::attach(const QString &convId)
{
    if (placementOf(convId) != QLatin1String("detached"))
        return;
    if (deferIfComposing(convId, [this, convId] { attach(convId); }))
        return;
    UIStateStore::instance()->flush(convId);
    if (!m_mainSelection.isEmpty() && m_mainSelection != convId)
        release(m_mainSelection);
    setPlacement(convId, QStringLiteral("main"));        // 先改 Placement，窗口 closing 回调就是 no-op
    setMainSelection(convId);
    setGhost(QString());
    saveLayout();
    destroyWindow(convId);
    raiseWindow(m_mainWindow);
}

void WindowManager::closeDetached(const QString &convId)
{
    UIStateStore::instance()->flush(convId);
    setPlacement(convId, QStringLiteral("closed"));
    saveLayout();
    destroyWindow(convId);
}

void WindowManager::detachedClosed(const QString &convId)
{
    if (m_terminating)
        return;
    if (placementOf(convId) == QLatin1String("detached")) {
        setPlacement(convId, QStringLiteral("closed"));
        saveLayout();
    }
    m_windows.remove(convId);
}

void WindowManager::route(const QString &convId)
{
    if (placementOf(convId) == QLatin1String("detached")) {
        raiseWindow(m_windows.value(convId));
    } else {
        select(convId);
        raiseWindow(m_mainWindow);
    }
}

// MARK: - 输入法组合：组合中不迁移，等组合结束后再执行

bool WindowManager::deferIfComposing(const QString &id, std::function<void()> retry)
{
    if (!m_composing.contains(id))
        return false;
    QTimer::singleShot(100, this, std::move(retry));
    return true;
}

// MARK: - 窗口

QQuickWindow *WindowManager::createWindow(const QString &id, std::optional<QPointF> origin)
{
    if (!m_engine)
        return nullptr;
    if (!m_component)
        m_component = new QQmlComponent(
            m_engine, QUrl(QStringLiteral("qrc:/qt/qml/ChatDemo/qml/DetachedWindow.qml")), this);
    if (m_component->isError()) {
        qWarning() << m_component->errors();
        return nullptr;
    }
    QObject *obj = m_component->createWithInitialProperties({{QStringLiteral("convId"), id}});
    auto *w = qobject_cast<QQuickWindow *>(obj);
    if (!w) {
        qWarning() << "DetachedWindow.qml did not create a window" << m_component->errors();
        delete obj;
        return nullptr;
    }
    QRect geo(QPoint(), kDefaultSize);
    const QVariantMap saved = savedGeometry(id);
    if (origin) {
        // 拖出：放到光标位置
        geo.moveTopLeft(origin->toPoint() - QPoint(40, 20));
        if (saved.value(QStringLiteral("valid")).toBool())
            geo.setSize(QSize(saved.value(QStringLiteral("width")).toInt(), saved.value(QStringLiteral("height")).toInt()));
    } else if (saved.value(QStringLiteral("valid")).toBool()) {
        geo = QRect(saved.value(QStringLiteral("x")).toInt(), saved.value(QStringLiteral("y")).toInt(),
                    saved.value(QStringLiteral("width")).toInt(), saved.value(QStringLiteral("height")).toInt());
    } else {
        const QPoint base = m_mainWindow ? m_mainWindow->position() + QPoint(60, 60) : QPoint(100, 100);
        geo.moveTopLeft(base + QPoint(30, 30) * int(m_windows.size()));
    }
    w->setGeometry(onScreen(geo));
    m_windows.insert(id, w);
    w->show();
    raiseWindow(w);
    return w;
}

void WindowManager::destroyWindow(const QString &id)
{
    QQuickWindow *w = m_windows.take(id);
    if (!w)
        return;
    w->close();
    w->deleteLater();
}

void WindowManager::raiseWindow(QQuickWindow *w)
{
    if (!w)
        return;
    if (w->visibility() == QWindow::Minimized)
        w->showNormal();
    w->show();
    w->raise();
    w->requestActivate();
}

void WindowManager::registerMainWindow(QQuickWindow *w) { m_mainWindow = w; }

// MARK: - 布局持久化

QRect WindowManager::onScreen(QRect r)
{
    for (QScreen *s : QGuiApplication::screens())
        if (s->availableGeometry().intersects(r))
            return r;
    // 完全不在任何屏幕上（例如断开外接屏）→ 主屏居中
    if (QScreen *p = QGuiApplication::primaryScreen())
        r.moveCenter(p->availableGeometry().center());
    return r;
}

void WindowManager::saveGeometry(const QString &key, int x, int y, int w, int h)
{
    if (m_terminating)
        return;
    QSettings s = layoutSettings();
    s.setValue(QStringLiteral("geom/") + key, QRect(x, y, w, h));
}

QVariantMap WindowManager::savedGeometry(const QString &key) const
{
    QSettings s = layoutSettings();
    const QVariant v = s.value(QStringLiteral("geom/") + key);
    if (!v.isValid())
        return {{QStringLiteral("valid"), false}};
    const QRect r = onScreen(v.toRect());
    return {{QStringLiteral("valid"), true}, {QStringLiteral("x"), r.x()}, {QStringLiteral("y"), r.y()},
            {QStringLiteral("width"), r.width()}, {QStringLiteral("height"), r.height()}};
}

void WindowManager::saveAllGeometry()
{
    QSettings s = layoutSettings();
    for (auto it = m_windows.begin(); it != m_windows.end(); ++it)
        if (it.value())
            s.setValue(QStringLiteral("geom/") + it.key(), it.value()->geometry());
    if (m_mainWindow)
        s.setValue(QStringLiteral("geom/main"), m_mainWindow->geometry());
}

void WindowManager::saveLayout()
{
    if (m_terminating)
        return;
    QSettings s = layoutSettings();
    QStringList ids;
    for (auto it = m_placements.begin(); it != m_placements.end(); ++it)
        if (it.value() == QLatin1String("detached"))
            ids << it.key();
    ids.sort();
    s.setValue(QStringLiteral("layout/detached"), ids);
    s.setValue(QStringLiteral("layout/mainSelection"), m_mainSelection);
}

void WindowManager::restoreLayout()
{
    if (m_restored)
        return;
    m_restored = true;
    QSettings s = layoutSettings();
    const QString sel = s.value(QStringLiteral("layout/mainSelection")).toString();
    if (!sel.isEmpty())
        select(sel);
    const QStringList ids = s.value(QStringLiteral("layout/detached")).toStringList();
    for (const QString &id : ids)
        detachImpl(id, std::nullopt);
    if (!ids.isEmpty())
        raiseWindow(m_mainWindow);
}

void WindowManager::quitApp(int code)
{
    m_terminating = true;
    saveAllGeometry();
    QCoreApplication::exit(code);
}
