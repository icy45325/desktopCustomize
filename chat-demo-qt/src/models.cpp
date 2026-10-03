#include "models.h"

int MessageModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QHash<int, QByteArray> MessageModel::roleNames() const
{
    return {
        {IdRole, "msgId"},         {SenderRole, "sender"},          {TextRole, "text"},
        {SentAtRole, "sentAt"},    {IsMineRole, "isMine"},          {ReplyIdRole, "replyToMsgId"},
        {ReplyTextRole, "replyText"},
    };
}

QVariant MessageModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Message &m = m_items.at(index.row());
    switch (role) {
    case IdRole: return m.id;
    case SenderRole: return m.sender;
    case TextRole: return m.text;
    case SentAtRole: return m.sentAt;
    case IsMineRole: return m.isMine;
    case ReplyIdRole: return m.replyToMsgId;
    case ReplyTextRole: return m.replyToMsgId.isEmpty() ? QString() : previewOf(m.replyToMsgId);
    }
    return {};
}

void MessageModel::append(const Message &m)
{
    beginInsertRows({}, m_items.size(), m_items.size());
    m_items.append(m);
    endInsertRows();
    emit countChanged();
}

void MessageModel::prependSeed(const QList<Message> &list)
{
    beginResetModel();
    m_items = list + m_items;
    endResetModel();
    emit countChanged();
}

QString MessageModel::idAt(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items.at(row).id : QString();
}

int MessageModel::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).id == id)
            return i;
    return -1;
}

QString MessageModel::previewOf(const QString &id) const
{
    const int i = indexOfId(id);
    return i < 0 ? QString() : m_items.at(i).sender + QStringLiteral("：") + m_items.at(i).text;
}

QDateTime MessageModel::sentAtAt(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items.at(row).sentAt : QDateTime();
}
