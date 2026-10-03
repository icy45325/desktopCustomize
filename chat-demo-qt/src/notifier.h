#pragma once
#include <QObject>

class QSystemTrayIcon;

// 系统通知：Demo 用 QSystemTrayIcon::showMessage。无托盘（如 Linux 无头环境）时降级为日志。
class Notifier : public QObject
{
    Q_OBJECT
public:
    explicit Notifier(QObject *parent = nullptr);
    void notify(const QString &convId, const QString &title, const QString &body);

signals:
    void clicked(const QString &convId);

private:
    QSystemTrayIcon *m_tray = nullptr;
    QString m_lastConv;
};
