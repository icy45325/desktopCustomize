#pragma once

// 无头自测：用真实的 QML 视图 + WindowManager 走一遍核心验收用例。
//   CHATDEMO_DATA_DIR=/tmp/x QT_QPA_PLATFORM=offscreen ChatDemo --selftest           # phase 1，结束时留一个独立窗口
//   CHATDEMO_DATA_DIR=/tmp/x QT_QPA_PLATFORM=offscreen ChatDemo --selftest --phase2  # phase 2，验证重启恢复
namespace SelfTest {
void schedule(int phase);
}
