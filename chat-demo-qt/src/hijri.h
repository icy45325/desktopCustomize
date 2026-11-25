#pragma once
#include <QDate>
#include <cmath>

// 伊斯兰历（回历）与公历互换：表格法（tabular Islamic calendar，民用纪元 622-07-16，
// 30 年周期内第 2、5、7、10、13、16、18、21、24、26、29 年为闰年）。
// 与阿联酋 / 沙特官方（按新月观测或 Umm al-Qura）相比通常相差 0～1 天，偶尔 2 天，
// 所以对外提供 adjust（-2～+2 天，同 Windows / Outlook 的「回历日期调整」）。
// 已用 2025 / 2026 年已知日期核对：如 1447-09-01（斋月首日）= 2026-02-18。
namespace hijri {

struct Date {
    int year = 0, month = 0, day = 0;
};

/// 回历日期 → 儒略日（Qt 的 QDate::toJulianDay 同样以正午为界的整数儒略日）
inline qint64 toJulianDay(int y, int m, int d)
{
    return d + qint64(std::ceil(29.5 * (m - 1))) + qint64(y - 1) * 354 + (3 + 11 * qint64(y)) / 30 + 1948439;
}

/// 公历 → 回历。adjust > 0 表示回历日期往后推（今天显示为回历的「明天」）
inline Date fromGregorian(const QDate &g, int adjust = 0)
{
    const qint64 jd = g.toJulianDay() + adjust;
    Date h;
    h.year = int((30 * (jd - 1948440) + 10646) / 10631);
    h.month = qMin(12, int(std::ceil(double(jd - (29 + toJulianDay(h.year, 1, 1))) / 29.5)) + 1);
    h.day = int(jd - toJulianDay(h.year, h.month, 1)) + 1;
    return h;
}

/// 回历 → 公历（与 fromGregorian 互逆，含同样的 adjust）
inline QDate toGregorian(int y, int m, int d, int adjust = 0)
{
    return QDate::fromJulianDay(toJulianDay(y, m, d) - adjust);
}

}  // namespace hijri
