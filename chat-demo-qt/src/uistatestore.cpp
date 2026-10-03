#include "uistatestore.h"

#include "appdata.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QUuid>

UIStateStore *UIStateStore::instance()
{
    static UIStateStore *s = new UIStateStore;
    return s;
}

UIStateStore *UIStateStore::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

UIStateStore::UIStateStore()
{
    QFile f(dataDir() + QStringLiteral("/drafts.json"));
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        QVariantMap s = defaults();
        const QJsonObject o = it.value().toObject();
        s[QStringLiteral("draftText")] = o.value(QStringLiteral("draftText")).toString();
        s[QStringLiteral("draftSelStart")] = o.value(QStringLiteral("draftSelStart")).toInt();
        s[QStringLiteral("draftSelEnd")] = o.value(QStringLiteral("draftSelEnd")).toInt();
        s[QStringLiteral("replyToMsgId")] = o.value(QStringLiteral("replyToMsgId")).toString();
        m_states.insert(it.key(), s);
    }
}

QVariantMap UIStateStore::defaults()
{
    return {
        {QStringLiteral("draftText"), QString()},
        {QStringLiteral("draftSelStart"), 0},
        {QStringLiteral("draftSelEnd"), 0},
        {QStringLiteral("replyToMsgId"), QString()},
        {QStringLiteral("scrollAnchorMsgId"), QString()},
        {QStringLiteral("atBottom"), true},
        {QStringLiteral("unreadDividerMsgId"), QString()},
    };
}

QVariantMap UIStateStore::state(const QString &convId) const
{
    return m_states.value(convId, defaults());
}

bool UIStateStore::atBottom(const QString &convId) const
{
    return state(convId).value(QStringLiteral("atBottom")).toBool();
}

QString UIStateStore::acquireLease(const QString &convId)
{
    const QString token = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_leases[convId] = token;   // 同时使上一个持有者的租约失效
    return token;
}

void UIStateStore::releaseLease(const QString &convId, const QString &token)
{
    if (m_leases.value(convId) == token)
        m_leases.remove(convId);
}

bool UIStateStore::update(const QString &convId, const QVariantMap &patch, const QString &token)
{
    if (token.isEmpty() || m_leases.value(convId) != token)
        return false;
    QVariantMap s = state(convId);
    bool dirty = false, persistNeeded = false;
    static const QStringList persistKeys{QStringLiteral("draftText"), QStringLiteral("draftSelStart"),
                                         QStringLiteral("draftSelEnd"), QStringLiteral("replyToMsgId")};
    for (auto it = patch.begin(); it != patch.end(); ++it) {
        if (s.value(it.key()) != it.value()) {
            s[it.key()] = it.value();
            dirty = true;
            persistNeeded = persistNeeded || persistKeys.contains(it.key());
        }
    }
    if (!dirty)
        return true;
    m_states[convId] = s;
    if (persistNeeded)
        persist();
    emit changed(convId);
    return true;
}

void UIStateStore::flush(const QString &convId)
{
    emit flushRequested(convId);
}

void UIStateStore::setDivider(const QString &convId, const QString &msgId)
{
    QVariantMap s = state(convId);
    if (s.value(QStringLiteral("unreadDividerMsgId")).toString() == msgId)
        return;
    s[QStringLiteral("unreadDividerMsgId")] = msgId;
    m_states[convId] = s;
    emit changed(convId);
}

void UIStateStore::persist() const
{
    QJsonObject root;
    for (auto it = m_states.begin(); it != m_states.end(); ++it) {
        const QVariantMap &s = it.value();
        if (s.value(QStringLiteral("draftText")).toString().isEmpty()
            && s.value(QStringLiteral("replyToMsgId")).toString().isEmpty())
            continue;
        root[it.key()] = QJsonObject{
            {QStringLiteral("draftText"), s.value(QStringLiteral("draftText")).toString()},
            {QStringLiteral("draftSelStart"), s.value(QStringLiteral("draftSelStart")).toInt()},
            {QStringLiteral("draftSelEnd"), s.value(QStringLiteral("draftSelEnd")).toInt()},
            {QStringLiteral("replyToMsgId"), s.value(QStringLiteral("replyToMsgId")).toString()},
        };
    }
    QFile f(dataDir() + QStringLiteral("/drafts.json"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}
