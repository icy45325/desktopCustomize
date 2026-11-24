#pragma once
#include <QHash>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// 会话级 UI 状态（草稿、光标、滚动锚点、引用、未读分隔线）+ 写入租约。
// 租约保证：迁移后旧视图迟到的异步写入会被丢弃（token 不匹配）。
class UIStateStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    static UIStateStore *instance();
    static UIStateStore *create(QQmlEngine *, QJSEngine *);

    Q_INVOKABLE QVariantMap state(const QString &convId) const;
    Q_INVOKABLE QString acquireLease(const QString &convId);
    Q_INVOKABLE void releaseLease(const QString &convId, const QString &token);
    /// token 不匹配 → 直接丢弃，返回 false。
    Q_INVOKABLE bool update(const QString &convId, const QVariantMap &patch, const QString &token);
    /// 迁移前调用：通知旧视图把防抖队列里尚未写回的内容立即写入。
    Q_INVOKABLE void flush(const QString &convId);
    /// 所有持有租约的会话都 flush（切换界面语言、整体重建界面前调用）
    void flushAll();
    /// 视图销毁时用：租约仍是自己的才清理「可见 / 输入法」等标记（被新视图接手后就不要再动了）
    Q_INVOKABLE bool holdsLease(const QString &convId, const QString &token) const { return !token.isEmpty() && m_leases.value(convId) == token; }
    /// 由 ChatStore 在新未读到来时写入分隔线，不经过租约。
    Q_INVOKABLE void setDivider(const QString &convId, const QString &msgId);

    bool atBottom(const QString &convId) const;

signals:
    void changed(const QString &convId);
    void flushRequested(const QString &convId);

private:
    UIStateStore();
    static QVariantMap defaults();
    void persist() const;

    QHash<QString, QVariantMap> m_states;
    QHash<QString, QString> m_leases;
};
