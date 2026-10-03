#include "mockserver.h"

#include "chatstore.h"

#include <QRandomGenerator>
#include <QUuid>

MockServer::MockServer(QObject *parent) : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, [this] {
        push();
        start();
    });
}

void MockServer::start()
{
    const bool fast = qEnvironmentVariableIntValue("CHATDEMO_FAST") != 0;
    const int lo = fast ? 300 : 3000, hi = fast ? 600 : 8000;
    m_timer.start(QRandomGenerator::global()->bounded(lo, hi));
}

void MockServer::push()
{
    static const QStringList lines = {
        QStringLiteral("在吗？"), QStringLiteral("看下这个方案"), QStringLiteral("今天下午三点开会"),
        QStringLiteral("收到，我来处理"), QStringLiteral("这个需求有变化"), QStringLiteral("辛苦了～"),
        QStringLiteral("能再确认一下吗"), QStringLiteral("OK 没问题"), QStringLiteral("晚点同步一下进度"),
        QStringLiteral("我把文档发你了")};
    static const QStringList people = {QStringLiteral("小李"), QStringLiteral("小张"), QStringLiteral("Amy"),
                                       QStringLiteral("Bob")};
    auto *chat = ChatStore::instance();
    const QStringList ids = chat->conversationIds();
    auto *rng = QRandomGenerator::global();
    const QString conv = ids.at(rng->bounded(ids.size()));
    chat->receive({QUuid::createUuid().toString(QUuid::WithoutBraces), conv,
                   conv == QLatin1String("c3") ? QStringLiteral("小王") : people.at(rng->bounded(people.size())),
                   lines.at(rng->bounded(lines.size())), QDateTime::currentDateTime(), false, QString()});
}
