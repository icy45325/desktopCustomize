#include "chatstore.h"
#include "mockserver.h"
#include "notifier.h"
#include "selftest.h"
#include "windowmanager.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QTimer>

int main(int argc, char *argv[])
{
    // 用 QApplication 而不是 QGuiApplication：QSystemTrayIcon 属于 QtWidgets。
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("ChatDemo"));
    QApplication::setOrganizationName(QStringLiteral("ChatDemo"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // 单进程、单个 QQmlEngine；所有窗口共享同一组 C++ 单例 Store。
    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
    WindowManager::instance()->setEngine(&engine);

    Notifier notifier;
    QObject::connect(ChatStore::instance(), &ChatStore::notificationRequested, &notifier, &Notifier::notify);
    QObject::connect(&notifier, &Notifier::clicked, WindowManager::instance(), &WindowManager::route);
    // placement 变化时刷新会话列表里的「已拆出」标记
    // （WindowManager::setPlacement 已直接通知 ChatStore）

    MockServer mock;
    mock.start();

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/ChatDemo/qml/Main.qml")));

    const QStringList args = app.arguments();
    if (args.contains(QStringLiteral("--selftest")))
        SelfTest::schedule(args.contains(QStringLiteral("--phase2")) ? 2 : 1);

    return app.exec();
}
