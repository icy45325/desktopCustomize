#include "appsettings.h"

#include "appdata.h"
#include "uistatestore.h"

#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QLocale>
#include <QPalette>
#include <QQmlEngine>
#include <QStyleHints>
#include <QTranslator>

AppSettings *AppSettings::instance()
{
    static AppSettings *s = new AppSettings;
    return s;
}

AppSettings *AppSettings::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

AppSettings::AppSettings()
{
    QSettings s = layoutSettings();
    // 语言：首次启动按系统语言（中文系统 → 中文，其它 → 英文）
    const QString sysLang = QLocale::system().language() == QLocale::Chinese ? QStringLiteral("zh") : QStringLiteral("en");
    m_language = s.value(QStringLiteral("ui/language"), sysLang).toString();
    if (qEnvironmentVariableIsSet("CHATDEMO_LANG"))
        m_language = qEnvironmentVariable("CHATDEMO_LANG");
    if (m_language != QLatin1String("en")) m_language = QStringLiteral("zh");

    // 主题：兼容旧版本的 ui/dark 布尔值
    QString mode = s.value(QStringLiteral("ui/themeMode")).toString();
    if (mode.isEmpty())
        mode = s.contains(QStringLiteral("ui/dark")) ? (s.value(QStringLiteral("ui/dark")).toBool() ? QStringLiteral("dark") : QStringLiteral("light"))
                                                    : QStringLiteral("system");
    m_themeMode = mode;
    if (qEnvironmentVariableIsSet("CHATDEMO_DARK")) {
        m_forced = true;
        m_themeMode = qEnvironmentVariableIntValue("CHATDEMO_DARK") ? QStringLiteral("dark") : QStringLiteral("light");
    }

    m_systemDark = detectSystemDark();
    m_dark = m_themeMode == QLatin1String("system") ? m_systemDark : m_themeMode == QLatin1String("dark");

    // 跟随系统外观
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this, [this] { updateDark(); });
#endif
    qApp->installEventFilter(this);   // Qt 6.4：系统外观切换时调色板会变
}

bool AppSettings::detectSystemDark()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    const Qt::ColorScheme cs = QGuiApplication::styleHints()->colorScheme();
    if (cs != Qt::ColorScheme::Unknown)
        return cs == Qt::ColorScheme::Dark;
#endif
    // 回退：系统调色板的窗口底色偏暗即视为深色模式（macOS / Windows / 大多数 Linux 桌面都会同步调色板）
    const QColor w = QGuiApplication::palette().color(QPalette::Window);
    return w.lightness() < 128;
}

bool AppSettings::eventFilter(QObject *obj, QEvent *e)
{
    if (obj == qApp && (e->type() == QEvent::ApplicationPaletteChange || e->type() == QEvent::ThemeChange))
        updateDark();
    return QObject::eventFilter(obj, e);
}

void AppSettings::updateDark()
{
    const bool sys = detectSystemDark();
    const bool d = m_themeMode == QLatin1String("system") ? sys : m_themeMode == QLatin1String("dark");
    if (sys == m_systemDark && d == m_dark)
        return;
    m_systemDark = sys;
    m_dark = d;
    emit darkChanged();
}

void AppSettings::setThemeMode(const QString &mode)
{
    if (mode != QLatin1String("light") && mode != QLatin1String("dark") && mode != QLatin1String("system"))
        return;
    if (m_themeMode == mode)
        return;
    m_themeMode = mode;
    if (!m_forced)
        layoutSettings().setValue(QStringLiteral("ui/themeMode"), mode);
    emit themeModeChanged();
    updateDark();
}

void AppSettings::toggleDark() { setThemeMode(m_dark ? QStringLiteral("light") : QStringLiteral("dark")); }

void AppSettings::setLanguage(const QString &lang)
{
    const QString l = lang == QLatin1String("en") ? QStringLiteral("en") : QStringLiteral("zh");
    if (m_language == l)
        return;
    m_language = l;
    layoutSettings().setValue(QStringLiteral("ui/language"), l);
    UIStateStore::instance()->flushAll();   // 界面即将重建：先把各会话未写回的草稿 / 光标写进 Store
    applyTranslator();
    emit languageChanged();
}

void AppSettings::install(QQmlEngine *engine)
{
    m_engine = engine;
    applyTranslator();
}

void AppSettings::applyTranslator()
{
    // 源文本是中文；英文界面加载 ChatDemo_en.qm
    if (m_translator) {
        QCoreApplication::removeTranslator(m_translator);
        delete m_translator;
        m_translator = nullptr;
    }
    QLocale::setDefault(QLocale(m_language == QLatin1String("en") ? QLocale::English : QLocale::Chinese,
                                m_language == QLatin1String("en") ? QLocale::UnitedStates : QLocale::China));
    if (m_language == QLatin1String("en")) {
        m_translator = new QTranslator(this);
        if (m_translator->load(QStringLiteral(":/i18n/ChatDemo_en.qm")))
            QCoreApplication::installTranslator(m_translator);
        else
            qWarning() << "[i18n] 找不到英文翻译 :/i18n/ChatDemo_en.qm";
    }
    if (m_engine)
        m_engine->retranslate();
}
