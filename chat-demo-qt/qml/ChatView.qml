import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 纯视图：挂载时从 UIStateStore 恢复，变化时经租约写回。主窗口和独立窗口复用同一个实现。
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

    onActiveVisibleChanged: WindowManager.setActiveVisible(convId, activeVisible)
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

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            Label { text: ChatStore.title(root.convId); font.bold: true; font.pixelSize: 16 }
            Item { Layout.fillWidth: true }
            Button {
                objectName: "moveButton"
                text: root.detached ? "合并到主窗口" : "在新窗口打开"
                onClicked: root.detached ? WindowManager.attach(root.convId) : WindowManager.detach(root.convId)
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#d0d0d0" }

        ListView {
            id: list
            objectName: "messageList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            leftMargin: 12; rightMargin: 12; topMargin: 12; bottomMargin: 12
            model: root.msgs
            ScrollBar.vertical: ScrollBar {}

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
                required property string msgId
                required property string sender
                required property string text
                required property bool isMine
                required property string replyText

                width: ListView.view.width - 24
                spacing: 4

                // 打开会话时确定的「新消息」分隔线，之后不变
                RowLayout {
                    visible: row.msgId === root.st.unreadDividerMsgId
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#e53935" }
                    Label { text: "新消息"; color: "#e53935"; font.pixelSize: 12 }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#e53935" }
                }

                Item {
                    width: parent.width
                    implicitHeight: col.implicitHeight

                    Column {
                        id: col
                        spacing: 2
                        anchors.right: row.isMine ? parent.right : undefined
                        anchors.left: row.isMine ? undefined : parent.left

                        Label {
                            visible: !row.isMine
                            text: row.sender
                            color: "#808080"
                            font.pixelSize: 11
                        }
                        Label {
                            visible: row.replyText !== ""
                            text: "↩ " + row.replyText
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, row.width * 0.75)
                            font.pixelSize: 11
                            color: "#606060"
                        }
                        Rectangle {
                            radius: 8
                            color: row.isMine ? "#402a7fff" : "#20000000"
                            width: Math.min(bubbleText.implicitWidth, row.width * 0.75 - 16) + 16
                            height: bubbleText.height + 16
                            Text {
                                id: bubbleText
                                x: 8; y: 8
                                width: Math.min(implicitWidth, row.width * 0.75 - 16)
                                text: row.text
                                wrapMode: Text.Wrap
                                color: "#202020"
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

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#d0d0d0" }

        // 引用栏
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 6
            visible: root.st.replyToMsgId !== ""
            Label {
                Layout.fillWidth: true
                text: "引用 " + (root.msgs ? root.msgs.previewOf(root.st.replyToMsgId) : "")
                elide: Text.ElideRight
                color: "#808080"
                font.pixelSize: 12
            }
            ToolButton { text: "✕"; onClicked: root.write({ replyToMsgId: "" }) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 8

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                TextArea {
                    id: input
                    objectName: "draftInput"
                    wrapMode: TextArea.Wrap
                    placeholderText: "输入消息，↩ 发送，⇧↩ 换行"
                    background: Rectangle { color: "#08000000"; radius: 4 }
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
            Button {
                text: "发送"
                enabled: input.text.trim() !== ""
                onClicked: root.send()
            }
        }
    }
}
