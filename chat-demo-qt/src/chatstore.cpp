#include "chatstore.h"

#include "uistatestore.h"
#include "windowmanager.h"

#include <QQmlEngine>
#include <QUuid>
#include <algorithm>

ChatStore *ChatStore::instance()
{
    static ChatStore *s = new ChatStore;
    return s;
}

ChatStore *ChatStore::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

ChatStore::ChatStore()
{
    struct Def { const char *id; const char *title; QStringList people; };
    const QList<Def> defs = {
        {"c1", "产品群", {"小李", "小张", "Amy"}},
        {"c2", "设计评审", {"Bob", "Cindy"}},
        {"c3", "小王", {"小王"}},
        {"c4", "周报小组", {"老陈", "Dora", "Evan"}},
    };
    const QDateTime now = QDateTime::currentDateTime();
    int n = 0;
    for (const Def &d : defs) {
        const QString id = QString::fromUtf8(d.id);
        auto *model = new MessageModel(this);
        QList<Message> list;
        for (int k = 0; k < 40; ++k) {
            const bool mine = k % 5 == 4;
            list.append({QStringLiteral("%1-seed-%2").arg(id).arg(k), id,
                         mine ? QStringLiteral("我") : d.people.at(k % d.people.size()),
                         QStringLiteral("这是第 %1 条历史消息：").arg(k + 1)
                             + QStringLiteral("内容").repeated(1 + k % 6),
                         now.addSecs((k - 60) * 60 - n * 10), mine, QString()});
        }
        model->prependSeed(list);
        m_msgs.insert(id, model);
        m_convs.append({id, QString::fromUtf8(d.title), list.last().sentAt, 0});
        ++n;
    }
    resort();
}

int ChatStore::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_convs.size(); }

QHash<int, QByteArray> ChatStore::roleNames() const
{
    return {{ConvIdRole, "convId"}, {TitleRole, "title"}, {LastTextRole, "lastText"},
            {UnreadRole, "unread"}, {PlacementRole, "placement"}};
}

QVariant ChatStore::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_convs.size())
        return {};
    const Conv &c = m_convs.at(index.row());
    switch (role) {
    case ConvIdRole: return c.id;
    case TitleRole: return c.title;
    case UnreadRole: return c.unread;
    case PlacementRole: return WindowManager::instance()->placementOf(c.id);
    case LastTextRole: {
        MessageModel *m = m_msgs.value(c.id);
        return m && m->count() ? m->previewOf(m->idAt(m->count() - 1)) : QString();
    }
    }
    return {};
}

int ChatStore::totalUnread() const
{
    int n = 0;
    for (const Conv &c : m_convs)
        n += c.unread;
    return n;
}

QStringList ChatStore::conversationIds() const
{
    QStringList l;
    for (const Conv &c : m_convs)
        l << c.id;
    return l;
}

QObject *ChatStore::messages(const QString &convId)
{
    MessageModel *m = m_msgs.value(convId);
    if (m)
        QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}

QString ChatStore::title(const QString &convId) const
{
    const int i = indexOfConv(convId);
    return i < 0 ? convId : m_convs.at(i).title;
}

int ChatStore::unread(const QString &convId) const
{
    const int i = indexOfConv(convId);
    return i < 0 ? 0 : m_convs.at(i).unread;
}

int ChatStore::indexOfConv(const QString &id) const
{
    for (int i = 0; i < m_convs.size(); ++i)
        if (m_convs.at(i).id == id)
            return i;
    return -1;
}

void ChatStore::send(const QString &convId, const QString &text, const QString &replyTo)
{
    append({QUuid::createUuid().toString(QUuid::WithoutBraces), convId, QStringLiteral("我"), text,
            QDateTime::currentDateTime(), true, replyTo});
}

void ChatStore::receive(const Message &m)
{
    if (indexOfConv(m.conversationId) < 0)
        return;
    const QString id = m.conversationId;
    auto *wm = WindowManager::instance();
    auto *ui = UIStateStore::instance();

    // 是否已读 / 通知必须在追加之前判断（追加会改变底部状态）。
    const bool visibleInKeyWindow = wm->isActiveVisible(id);
    const bool canRead = visibleInKeyWindow && ui->atBottom(id);

    append(m);

    if (!canRead) {
        const int i = indexOfConv(id);
        const bool wasZero = m_convs[i].unread == 0;
        m_convs[i].unread++;
        if (wasZero)
            ui->setDivider(id, m.id);
        emit dataChanged(index(i), index(i), {UnreadRole});
        emit totalUnreadChanged();
    }
    if (!visibleInKeyWindow)
        emit notificationRequested(id, title(id), m.sender + QStringLiteral("：") + m.text);
}

void ChatStore::markRead(const QString &convId)
{
    const int i = indexOfConv(convId);
    if (i < 0 || m_convs[i].unread == 0)
        return;
    m_convs[i].unread = 0;
    emit dataChanged(index(i), index(i), {UnreadRole});
    emit totalUnreadChanged();
}

void ChatStore::placementChanged(const QString &convId)
{
    const int i = indexOfConv(convId);
    if (i >= 0)
        emit dataChanged(index(i), index(i), {PlacementRole});
}

void ChatStore::append(const Message &m)
{
    m_msgs.value(m.conversationId)->append(m);
    const int i = indexOfConv(m.conversationId);
    m_convs[i].lastAt = m.sentAt;
    emit dataChanged(index(i), index(i), {LastTextRole});
    resort();
}

void ChatStore::resort()
{
    QList<Conv> sorted = m_convs;
    std::stable_sort(sorted.begin(), sorted.end(), [](const Conv &a, const Conv &b) { return a.lastAt > b.lastAt; });
    bool same = true;
    for (int i = 0; i < sorted.size(); ++i)
        same = same && sorted.at(i).id == m_convs.at(i).id;
    if (same)
        return;
    beginResetModel();
    m_convs = sorted;
    endResetModel();
}
