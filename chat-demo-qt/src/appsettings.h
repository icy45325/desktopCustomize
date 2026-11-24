#pragma once
#include <QObject>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;
class QTranslator;

// 应用级设置（QML 中为 Settings 单例），持久化到 layout.ini：
//  - language: "zh" | "en"。切换时换 QTranslator 并通知各窗口重建界面（状态都在 C++ Store 里，不会丢）
//  - themeMode: "light" | "dark" | "system"。system 跟随操作系统外观，系统切换时实时更新
//  - dark: 生效的深浅色（Theme.dark 绑定它）
class AppSettings : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Settings)
    QML_SINGLETON
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(bool systemDark READ systemDark NOTIFY darkChanged)
public:
    static AppSettings *instance();
    static AppSettings *create(QQmlEngine *, QJSEngine *);

    QString language() const { return m_language; }
    void setLanguage(const QString &lang);
    QString themeMode() const { return m_themeMode; }
    void setThemeMode(const QString &mode);
    bool dark() const { return m_dark; }
    bool systemDark() const { return m_systemDark; }

    /// 启动时调用一次：装上当前语言的翻译。需要 engine 以便 retranslate。
    void install(QQmlEngine *engine);
    /// ⌘⇧D：在浅色 / 深色之间切换（离开「跟随系统」）
    Q_INVOKABLE void toggleDark();

signals:
    void languageChanged();
    void themeModeChanged();
    void darkChanged();

protected:
    bool eventFilter(QObject *obj, QEvent *e) override;

private:
    AppSettings();
    void applyTranslator();
    void updateDark();
    static bool detectSystemDark();

    QString m_language;
    QString m_themeMode;
    bool m_dark = false;
    bool m_systemDark = false;
    bool m_forced = false;          // CHATDEMO_DARK 环境变量强制（自测 / 截图）
    QQmlEngine *m_engine = nullptr;
    QTranslator *m_translator = nullptr;
};
