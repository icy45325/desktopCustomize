#pragma once
#include <QDate>
#include <QObject>
#include <QTime>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// 日历 AI 小助手（本地规则引擎，离线可用）。
// 理解中文和英文自然语言：查日程 / 会议、查待办、找空闲时间、下一个会议、今日概览、新建活动、新建待办。
// respond() 是唯一的「大脑」入口：以后接入真正的大模型时，只需替换它（把 CalendarStore 的查询/写入作为工具暴露给模型）。
class Assistant : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    /// [{role: "user"|"assistant", text, items: [事件/待办], action: {label, kind, uid} | {}, done}]
    Q_PROPERTY(QVariantList messages READ messages NOTIFY messagesChanged)
    Q_PROPERTY(bool thinking READ thinking NOTIFY thinkingChanged)
    Q_PROPERTY(QStringList suggestions READ suggestions NOTIFY suggestionsChanged)
public:
    static Assistant *instance();
    static Assistant *create(QQmlEngine *, QJSEngine *);

    QVariantList messages() const { return m_messages; }
    bool thinking() const { return m_thinking; }
    QStringList suggestions() const;

    Q_INVOKABLE void send(const QString &text);
    Q_INVOKABLE void clear();
    /// 执行消息上的操作（如「撤销」），执行后按钮变灰
    Q_INVOKABLE void runAction(int index);

    /// 同步生成回复（自测直接调用）。now 用于测试固定「现在」。
    QVariantMap respond(const QString &text, const QDateTime &now = QDateTime::currentDateTime());

    // 解析结果（供自测）
    struct When {
        QDate from, to;            // [from, to)；无效 = 未提及日期
        bool singleDay = false;
        QTime start, end;          // 无效 = 未提及时间
        int durationMin = 0;       // 0 = 未提及
        QString rest;              // 去掉日期/时间/时长后的剩余文本
    };
    static When parseWhen(const QString &text, const QDate &today);

signals:
    void messagesChanged();
    void thinkingChanged();
    void suggestionsChanged();

private:
    Assistant();
    QVariantMap respondImpl(const QString &text, const QDateTime &now);
    void append(const QVariantMap &m);
    QVariantList m_messages;
    bool m_thinking = false;
};
