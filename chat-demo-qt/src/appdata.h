#pragma once
#include <QDir>
#include <QSettings>
#include <QStandardPaths>
#include <QString>

// 数据目录：草稿 JSON 和布局 ini 都放这里。CHATDEMO_DATA_DIR 用于自测隔离。
inline QString dataDir()
{
    static const QString dir = [] {
        QString p = qEnvironmentVariable("CHATDEMO_DATA_DIR");
        if (p.isEmpty())
            p = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir().mkpath(p);
        return p;
    }();
    return dir;
}

inline QSettings layoutSettings()
{
    return QSettings(dataDir() + QStringLiteral("/layout.ini"), QSettings::IniFormat);
}
