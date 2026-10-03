#pragma once
#include "models.h"

#include <QAbstractListModel>
#include <QHash>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// 会话列表模型（按最后消息时间倒序）+ 所有消息。单例，所有窗口共享。
class ChatStore : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int totalUnread READ totalUnread NOTIFY totalUnreadChanged)
public:
    enum Roles { ConvIdRole = Qt::UserRole + 1, TitleRole, LastTextRole, UnreadRole, PlacementRole };

    static ChatStore *instance();
    static ChatStore *create(QQmlEngine *, QJSEngine *);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int totalUnread() const;
    QStringList conversationIds() const;

    Q_INVOKABLE QObject *messages(const QString &convId);
    Q_INVOKABLE QString title(const QString &convId) const;
    Q_INVOKABLE int unread(const QString &convId) const;
    Q_INVOKABLE void send(const QString &convId, const QString &text, const QString &replyTo);
    Q_INVOKABLE void markRead(const QString &convId);

    /// MockServer 推来的消息。是否计未读 / 发通知在这里决定。
    void receive(const Message &m);
    void placementChanged(const QString &convId);

signals:
    void totalUnreadChanged();
    void notificationRequested(const QString &convId, const QString &title, const QString &body);

private:
    ChatStore();
    struct Conv {
        QString id, title;
        QDateTime lastAt;
        int unread = 0;
    };
    int indexOfConv(const QString &id) const;
    void append(const Message &m);
    void resort();

    QList<Conv> m_convs;
    QHash<QString, MessageModel *> m_msgs;
};
