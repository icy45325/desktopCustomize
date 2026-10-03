import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 纯视图：挂载时从 UIStateStore 恢复，变化时经租约写回。主窗口和独立窗口复用同一个实现。
// 外观参考 macOS Messages：蓝色/浅灰气泡、圆角输入框、圆形发送键。
Item {
    id: root
    objectName: "chatView"
    property string convId
    property bool detached: false

    property string token: ""
    property var st: UIStateStore.state(convId)
    property var msgs: ChatStore.messages(convId)
    property bool restored: false

    // 已读条件：前台 + key 窗口 + 未最小化 + 停在底部。
    readonly property bool activeVisible: Window.window !== null && Window.active
                                          && Window.visibility !== Window.Minimized
                                          && Qt.application.state === Qt.ApplicationActive
    readonly property bool canMarkRead: activeVisible && st.atBottom

    onActiveVisibleChanged: {
        WindowManager.setActiveVisible(convId, activeVisible)
        // 窗口从后台/最小化恢复：有未读分隔线且列表不在底部时，自动滚到分隔线
        if (activeVisible && restored) scrollToDividerIfNeeded()
    }
    onCanMarkReadChanged: if (canMarkRead) ChatStore.markRead(convId)

    Connections {
        target: UIStateStore
        function onChanged(id) { if (id === root.convId) root.st = UIStateStore.state(root.convId) }
        // 迁移前，WindowManager 要求立即写回尚未落盘的草稿和滚动锚点
        function onFlushRequested(id) { if (id === root.convId) root.flushNow() }
    }

    // MARK: 生命周期

    Component.onCompleted: {
        token = UIStateStore.acquireLease(convId)
        // 打开会话时确定未读分隔线
        var unread = ChatStore.unread(convId)
        var s = UIStateStore.state(convId)
        if (unread > 0 && s.unreadDividerMsgId === "" && msgs.count >= unread)
            UIStateStore.setDivider(convId, msgs.idAt(msgs.count - unread))
        else if (unread === 0)
            UIStateStore.setDivider(convId, "")
        st = UIStateStore.state(convId)

        // 恢复草稿与光标
        input.text = st.draftText
        var len = input.text.length
        var a = Math.min(st.draftSelStart, len), b = Math.min(st.draftSelEnd, len)
        if (a !== b) input.select(a, b); else input.cursorPosition = b

        WindowManager.setActiveVisible(convId, activeVisible)
        if (canMarkRead) ChatStore.markRead(convId)
        Qt.callLater(restoreScroll)
    }

    Component.onDestruction: {
        flushNow()
        WindowManager.setActiveVisible(convId, false)
        WindowManager.setComposing(convId, false)
        if (ChatStore.unread(convId) === 0) UIStateStore.setDivider(convId, "")
        UIStateStore.releaseLease(convId, token)
    }

    function write(patch) { return UIStateStore.update(convId, patch, token) }

    function currentAnchor() {
        var i = list.indexAt(10, list.contentY + 4)
        return i >= 0 ? msgs.idAt(i) : ""
    }

    function dividerIndex() {
        var d = st.unreadDividerMsgId
        return d === "" ? -1 : msgs.indexOfId(d)
    }

    /// 窗口恢复可见时：若未读分隔线存在且不在视口内，把它滚到顶部。
    function scrollToDividerIfNeeded() {
        var i = dividerIndex()
        if (i < 0 || list.atYEnd) return
        var first = list.indexAt(10, list.contentY + 4)
        var last = list.indexAt(10, list.contentY + list.height - 4)
        if (first >= 0 && last >= 0 && i >= first && i <= last) return   // 已经可见
        list.positionViewAtIndex(i, ListView.Beginning)
        scrollTimer.restart()
    }

    /// 立即写入防抖队列中尚未写回的草稿和滚动锚点。
    function flushNow() {
        draftTimer.stop()
        scrollTimer.stop()
        var patch = { draftText: input.text, draftSelStart: input.selectionStart, draftSelEnd: input.selectionEnd }
        if (restored) patch.scrollAnchorMsgId = currentAnchor()
        write(patch)
    }

    function restoreScroll() {
        var s = UIStateStore.state(convId)
        var i = s.atBottom ? -1 : msgs.indexOfId(s.scrollAnchorMsgId)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Beginning)
        else list.positionViewAtEnd()
        restoreTimer.restart()
    }

    function send() {
        var text = input.text.trim()
        if (text === "") return
        ChatStore.send(convId, text, st.replyToMsgId)
        draftTimer.stop()
        input.text = ""
        write({ draftText: "", draftSelStart: 0, draftSelEnd: 0, replyToMsgId: "", atBottom: true })
        Qt.callLater(list.positionViewAtEnd)
    }

    // 恢复完成前不写回滚动状态，避免恢复过程中的位置抖动覆盖已保存的锚点
    Timer {
        id: restoreTimer
        interval: 250
        onTriggered: {
            var s = UIStateStore.state(root.convId)
            if (s.atBottom || s.scrollAnchorMsgId === "") list.positionViewAtEnd()
            root.restored = true
            root.write({ atBottom: list.atYEnd })
        }
    }
    Timer { id: draftTimer; interval: 300; onTriggered: root.flushDraft() }   // 草稿写回防抖 300ms
    Timer { id: scrollTimer; interval: 300; onTriggered: root.write({ scrollAnchorMsgId: root.currentAnchor() }) }  // 滚动停止后写回
    function flushDraft() {
        write({ draftText: input.text, draftSelStart: input.selectionStart, draftSelEnd: input.selectionEnd })
    }

    // MARK: 视图

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 标题栏：居中标题 + 右侧工具按钮（macOS 工具栏样式）
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: "#FAFAFA"
            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    text: ChatStore.title(root.convId)
                    font.pixelSize: Theme.fontTitle; font.bold: true
                    color: Theme.textPrimary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: root.msgs ? root.msgs.count + " 条消息" : ""
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
            MacButton {
                objectName: "moveButton"
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: root.detached ? "⇲ 合并到主窗口" : "⧉ 新窗口"
                onClicked: root.detached ? WindowManager.attach(root.convId) : WindowManager.detach(root.convId)
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separatorLight }
        }

        ListView {
            id: list
            objectName: "messageList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            leftMargin: 16; rightMargin: 16; topMargin: 12; bottomMargin: 12
            model: root.msgs
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 6; radius: 3; color: "#60000000"; opacity: parent.active ? 1 : 0.4 }
            }

            property bool wasAtEnd: false

            onAtYEndChanged: if (root.restored) root.write({ atBottom: atYEnd })
            onContentYChanged: if (root.restored && (dragging || flicking || moving)) scrollTimer.restart()
            onMovementEnded: if (root.restored) scrollTimer.restart()

            // 到达新消息前记下是否在底部（追加后 atYEnd 会短暂变 false）
            Connections {
                target: root.msgs
                function onRowsAboutToBeInserted() { list.wasAtEnd = list.atYEnd }
                function onRowsInserted() { if (list.wasAtEnd) Qt.callLater(list.positionViewAtEnd) }
            }

            delegate: Column {
                id: row
                required property int index
                required property string msgId
                required property string sender
                required property string text
                required property bool isMine
                required property string replyText
                required property date sentAt

                width: ListView.view.width - 32
                spacing: 4
                readonly property real maxBubble: Math.min(width * 0.68, 520)

                // 打开会话时确定的「新消息」分隔线，之后不变
                Item {
                    visible: row.msgId === root.st.unreadDividerMsgId
                    width: parent.width
                    height: visible ? 28 : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Theme.separatorLight }
                    Rectangle {
                        anchors.centerIn: parent
                        width: dividerText.implicitWidth + 20; height: 20; radius: 10
                        color: Theme.windowBg; border.color: Theme.separatorLight
                        Text { id: dividerText; anchors.centerIn: parent; text: "新消息"; font.pixelSize: Theme.fontSmall; color: Theme.accent }
                    }
                }

                // 时间戳：与上一条相隔 ≥ 10 分钟时显示（Messages 风格）
                Text {
                    visible: {
                        if (row.index === 0) return true
                        var prev = root.msgs.sentAtAt(row.index - 1)
                        return (row.sentAt - prev) >= 10 * 60 * 1000
                    }
                    width: parent.width
                    height: visible ? implicitHeight + 6 : 0
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatTime(row.sentAt, "HH:mm")
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                }

                Item {
                    width: parent.width
                    implicitHeight: col.implicitHeight

                    Column {
                        id: col
                        spacing: 3
                        anchors.right: row.isMine ? parent.right : undefined
                        anchors.left: row.isMine ? undefined : parent.left

                        Text {
                            visible: !row.isMine
                            text: row.sender
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSmall
                            leftPadding: 12
                        }
                        // 引用块
                        Rectangle {
                            visible: row.replyText !== ""
                            radius: 10
                            color: Theme.quoteBg
                            width: Math.min(quote.implicitWidth, row.maxBubble - 20) + 20
                            height: quote.implicitHeight + 12
                            anchors.right: row.isMine ? parent.right : undefined
                            Rectangle { x: 0; y: 6; width: 3; height: parent.height - 12; radius: 1.5; color: Theme.accent }
                            Text {
                                id: quote
                                x: 10; y: 6
                                width: Math.min(implicitWidth, row.maxBubble - 20)
                                text: row.replyText
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                            }
                        }
                        // 气泡
                        Rectangle {
                            radius: Theme.radiusBubble
                            color: row.isMine ? Theme.bubbleMine : Theme.bubbleOther
                            width: Math.min(bubbleText.implicitWidth, row.maxBubble - 28) + 28
                            height: bubbleText.height + 18
                            anchors.right: row.isMine ? parent.right : undefined
                            Text {
                                id: bubbleText
                                x: 14; y: 9
                                width: Math.min(implicitWidth, row.maxBubble - 28)
                                text: row.text
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontBody
                                lineHeight: 1.15
                                color: row.isMine ? Theme.textOnAccent : Theme.bubbleOtherText
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: col
                        acceptedButtons: Qt.RightButton
                        onClicked: replyMenu.popup()
                    }
                    Menu {
                        id: replyMenu
                        MenuItem { text: "引用回复"; onTriggered: root.write({ replyToMsgId: row.msgId }) }
                    }
                }
            }
        }

        // 引用栏
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: visible ? 36 : 0
            visible: root.st.replyToMsgId !== ""
            color: "#FAFAFA"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.separatorLight }
            Rectangle { x: 16; y: 9; width: 3; height: 18; radius: 1.5; color: Theme.accent }
            Text {
                anchors { left: parent.left; leftMargin: 26; right: closeReply.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: "回复 " + (root.msgs ? root.msgs.previewOf(root.st.replyToMsgId) : "")
                elide: Text.ElideRight
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
            }
            MouseArea {
                id: closeReply
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: 22; height: 22
                hoverEnabled: true
                onClicked: root.write({ replyToMsgId: "" })
                Rectangle { anchors.fill: parent; radius: 11; color: parent.containsMouse ? Theme.sidebarHover : "transparent" }
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 11; color: Theme.textSecondary }
            }
        }

        // 输入区：圆角输入框 + 圆形发送键
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(56, inputFrame.implicitHeight + 20)
            color: "#FAFAFA"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.separatorLight }

            Rectangle {
                id: inputFrame
                anchors { left: parent.left; right: sendBtn.left; leftMargin: 16; rightMargin: 10; verticalCenter: parent.verticalCenter }
                implicitHeight: Math.min(120, Math.max(36, input.implicitHeight + 4))
                radius: 18
                color: Theme.inputBg
                border.width: 1
                border.color: input.activeFocus ? Theme.accent : Theme.controlBorder

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 2
                    contentHeight: input.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    TextArea {
                        id: input
                        objectName: "draftInput"
                        width: parent.width
                        wrapMode: TextArea.Wrap
                        placeholderText: "输入消息"
                        placeholderTextColor: Theme.textSecondary
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontBody
                        leftPadding: 12; rightPadding: 12; topPadding: 7; bottomPadding: 7
                        background: null
                        onTextChanged: draftTimer.restart()
                        onCursorPositionChanged: draftTimer.restart()
                        // 输入法组合中（中文尚未上屏）不触发迁移
                        onInputMethodComposingChanged: WindowManager.setComposing(root.convId, inputMethodComposing)
                        Keys.onPressed: (e) => {
                            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                                    && !(e.modifiers & Qt.ShiftModifier) && !inputMethodComposing) {
                                root.send()
                                e.accepted = true
                            }
                        }
                    }
                }
            }
            MacButton {
                id: sendBtn
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                primary: true
                circular: true
                text: "↑"
                font.bold: true
                font.pixelSize: 15
                enabled: input.text.trim() !== ""
                onClicked: root.send()
            }
        }
    }
}
