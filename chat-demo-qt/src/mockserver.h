#pragma once
#include <QObject>
#include <QTimer>

// 每 3～8 秒随机给某个会话推一条消息。CHATDEMO_FAST=1 时加快（自测用）。
class MockServer : public QObject
{
    Q_OBJECT
public:
    explicit MockServer(QObject *parent = nullptr);
    void start();

private:
    void push();
    QTimer m_timer;
};
