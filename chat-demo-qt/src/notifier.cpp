#include "notifier.h"

#include <QColor>
#include <QDebug>
#include <QIcon>
#include <QPixmap>
#include <QSystemTrayIcon>

Notifier::Notifier(QObject *parent) : QObject(parent)
{
    if (!QSystemTrayIcon::isSystemTrayAvailable())
        return;
    QPixmap px(32, 32);
    px.fill(QColor(0x2a7fff));
    m_tray = new QSystemTrayIcon(QIcon(px), this);
    m_tray->show();
    // QSystemTrayIcon 不告诉我们点的是哪条通知，Demo 里取最近一条。
    connect(m_tray, &QSystemTrayIcon::messageClicked, this, [this] { emit clicked(m_lastConv); });
}

void Notifier::notify(const QString &convId, const QString &title, const QString &body)
{
    m_lastConv = convId;
    if (m_tray)
        m_tray->showMessage(title, body, QSystemTrayIcon::Information, 5000);
    else
        qInfo().noquote() << "[notify]" << title << body;
}
