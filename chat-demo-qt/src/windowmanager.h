#pragma once
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QRect>
#include <QSet>
#include <QVariantMap>
#include <functional>
#include <optional>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QQmlComponent;
class QQuickWindow;
class QJSEngine;

// 会话 → 容器 的映射、拆出/合并流程、输入法组合延迟、布局持久化、通知路由。
// placement: "main" | "detached" | "closed"
class WindowManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    /// 主窗口右侧当前显示的会话（空 = 无）。
    Q_PROPERTY(QString mainSelection READ mainSelection NOTIFY mainSelectionChanged)
    /// 刚被拆出的会话，主窗口右侧显示「已在独立窗口打开」。
    Q_PROPERTY(QString ghost READ ghost NOTIFY ghostChanged)
    /// 生效的深色模式（兼容旧接口；实际由 AppSettings.themeMode 决定）。写入 = 切到浅色 / 深色固定模式。
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    /// 主窗口当前模块："chat" | "calendar"，持久化到 layout.ini。
    Q_PROPERTY(QString module READ module WRITE setModule NOTIFY moduleChanged)
    /// 右侧动态面板（全局，消息 / 日历两个模块共用）：是否打开、当前标签、是否拆成独立窗口、面板里打开的会话
    Q_PROPERTY(bool panelOpen READ panelOpen WRITE setPanelOpen NOTIFY panelChanged)
    Q_PROPERTY(QString panelTab READ panelTab WRITE setPanelTab NOTIFY panelChanged)
    Q_PROPERTY(bool panelDetached READ panelDetached NOTIFY panelChanged)
    Q_PROPERTY(QString panelConv READ panelConv NOTIFY panelChanged)
public:
    bool panelOpen() const { return m_panelOpen; }
    void setPanelOpen(bool v);
    QString panelTab() const { return m_panelTab; }
    void setPanelTab(const QString &t);
    bool panelDetached() const { return m_panelDetached; }
    QString panelConv() const { return m_panelConv; }
    /// 把面板拆成独立窗口 / 合并回主窗口
    Q_INVOKABLE void detachPanel();
    Q_INVOKABLE void attachPanel();
    Q_INVOKABLE void panelWindowClosed();
    /// 在面板里打开会话（Placement = panel）；已在独立窗口时只前置该窗口
    Q_INVOKABLE void openInPanel(const QString &convId);
    Q_INVOKABLE void closePanelConv();
    /// 面板里点了日历条目 / 「在日历中打开」：切到日历模块并前置主窗口
    Q_INVOKABLE void focusCalendar();
    /// 任意窗口按 ⌘,：前置主窗口并打开设置
    Q_INVOKABLE void openSettings(const QString &page = QString());
    QQuickWindow *panelWindow() const { return m_panelWindow; }

    QString module() const { return m_module; }
    void setModule(const QString &m);

    bool darkMode() const;
    void setDarkMode(bool v);

    static WindowManager *instance();
    static WindowManager *create(QQmlEngine *, QJSEngine *);

    void setEngine(QQmlEngine *engine);

    QString mainSelection() const { return m_mainSelection; }
    QString ghost() const { return m_ghost; }

    Q_INVOKABLE QString placementOf(const QString &convId) const;
    /// 会话列表点击。已在独立窗口 → 前置；否则在主窗口右侧打开。空串 = 关闭右侧会话。
    Q_INVOKABLE void select(const QString &convId);
    Q_INVOKABLE void detach(const QString &convId);
    Q_INVOKABLE void detachAt(const QString &convId, qreal globalX, qreal globalY);
    Q_INVOKABLE void attach(const QString &convId);
    /// Ctrl+W / 关闭：会话状态保留，Placement 变为 closed。
    Q_INVOKABLE void closeDetached(const QString &convId);
    /// 独立窗口 onClosing 调用：仍是 detached 说明用户直接点了关闭按钮。
    Q_INVOKABLE void detachedClosed(const QString &convId);
    Q_INVOKABLE void route(const QString &convId);

    Q_INVOKABLE bool isActiveVisible(const QString &convId) const { return m_activeVisible.contains(convId); }
    Q_INVOKABLE void setActiveVisible(const QString &convId, bool v);
    Q_INVOKABLE void setComposing(const QString &convId, bool v);

    Q_INVOKABLE void registerMainWindow(QQuickWindow *w);
    Q_INVOKABLE void saveGeometry(const QString &key, int x, int y, int w, int h);
    /// 返回已纠正到屏幕内的几何；{valid:false} 表示没有保存过。
    Q_INVOKABLE QVariantMap savedGeometry(const QString &key) const;
    Q_INVOKABLE void restoreLayout();
    Q_INVOKABLE void quitApp(int code = 0);

    // 供自测使用
    QQuickWindow *windowFor(const QString &convId) const { return m_windows.value(convId); }
    QQuickWindow *mainWindow() const { return m_mainWindow; }
    int detachedWindowCount() const;

signals:
    void darkModeChanged();
    void moduleChanged();
    void panelChanged();
    void settingsRequested(const QString &page);
    void mainSelectionChanged();
    void ghostChanged();
    void placementChanged(const QString &convId);

protected:
    bool eventFilter(QObject *obj, QEvent *e) override;

private:
    WindowManager();
    void setPlacement(const QString &id, const QString &p);
    void setMainSelection(const QString &id);
    void setGhost(const QString &id);
    void release(const QString &id);
    void detachImpl(const QString &id, std::optional<QPointF> origin);
    QQuickWindow *createWindow(const QString &id, std::optional<QPointF> origin);
    void destroyWindow(const QString &id);
    void raiseWindow(QQuickWindow *w);
    bool deferIfComposing(const QString &id, std::function<void()> retry);
    void saveLayout();
    void saveAllGeometry();
    static QRect onScreen(QRect r);

    QQmlEngine *m_engine = nullptr;
    QQmlComponent *m_component = nullptr;
    QPointer<QQuickWindow> m_mainWindow;
    QHash<QString, QString> m_placements;
    QHash<QString, QPointer<QQuickWindow>> m_windows;
    QSet<QString> m_activeVisible;
    QSet<QString> m_composing;
    QString m_mainSelection;
    QString m_ghost;
    QString m_module = QStringLiteral("chat");
    bool m_panelOpen = true;
    QString m_panelTab = QStringLiteral("todo");
    bool m_panelDetached = false;
    QString m_panelConv;
    QPointer<QQuickWindow> m_panelWindow;
    void setPanelConv(const QString &id);
    void savePanel();
    void createPanelWindow();
    bool m_terminating = false;
    bool m_restored = false;
};
