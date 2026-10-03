#pragma once
#include <QAbstractListModel>
#include <QDateTime>
#include <QList>
#include <QString>

struct Message {
    QString id;
    QString conversationId;
    QString sender;
    QString text;
    QDateTime sentAt;
    bool isMine = false;
    QString replyToMsgId;
};

// 一个会话的消息列表。
class MessageModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        SenderRole,
        TextRole,
        SentAtRole,
        IsMineRole,
        ReplyIdRole,
        ReplyTextRole,
    };

    explicit MessageModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_items.size(); }
    void append(const Message &m);
    void prependSeed(const QList<Message> &list);  // 种子数据，不触发动画/信号洪水

    Q_INVOKABLE QString idAt(int row) const;
    Q_INVOKABLE int indexOfId(const QString &id) const;
    Q_INVOKABLE QString previewOf(const QString &id) const;
    Q_INVOKABLE QDateTime sentAtAt(int row) const;

signals:
    void countChanged();

private:
    QList<Message> m_items;
};
