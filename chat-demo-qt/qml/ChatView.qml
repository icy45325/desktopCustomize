import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ChatDemo

// 纯视图：挂载时从 UIStateStore 恢复，变化时经租约写回。主窗口和独立窗口复用同一个实现。
// 外观：方案 C 的结构（头像 + 气泡 + 胶囊输入条）叠加方案 B 的用色（单一强调色、按人着色的名字、dark 下发光）。
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
        sendPulse.restart()
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

        // 标题栏：头像 + 标题/成员 + 右侧胶囊按钮
        Item {
            Layout.fillWidth: true
            implicitHeight: 60
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18; anchors.rightMargin: 14
                spacing: 12
                Avatar { name: ChatStore.title(root.convId); size: 36 }
                ColumnLayout {
                    spacing: 1
                    Text {
                        text: ChatStore.title(root.convId)
                        font.pixelSize: Theme.fontTitle; font.bold: true
                        color: Theme.text
                        Behavior on color { ColorAnimation { duration: 260 } }
                    }
                    Text {
                        text: root.msgs ? root.msgs.count + " 条消息" : ""
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textTertiary
                    }
                }
                Item { Layout.fillWidth: true }
                MacButton {
                    objectName: "moveButton"
                    text: root.detached ? "⇲ 合并到主窗口" : "⧉ 拆出窗口"
                    onClicked: root.detached ? WindowManager.attach(root.convId) : WindowManager.detach(root.convId)
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18 }
                height: 1; color: Theme.surface
            }
        }

        ListView {
            id: list
            objectName: "messageList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            leftMargin: 18; rightMargin: 18; topMargin: 12; bottomMargin: 12
            model: root.msgs
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 6; radius: 3; color: Theme.textTertiary; opacity: parent.active ? 0.6 : 0.25 }
            }

            // 新消息上浮进入
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; from: list.contentY + list.height; duration: 380; easing.type: Easing.OutCubic }
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

                width: ListView.view.width - 36
                spacing: 4
                readonly property real maxBubble: Math.min(width * 0.68, 520)
                readonly property bool isNew: root.st.unreadDividerMsgId !== "" && index >= root.dividerIndex()

                // 打开会话时确定的「新消息」分隔线，之后不变：渐变胶囊（方案 C）+ dark 下虚线（方案 B）
                Item {
                    visible: row.msgId === root.st.unreadDividerMsgId
                    width: parent.width
                    height: visible ? 30 : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; radius: 1; color: Theme.surface }
                    Rectangle {
                        anchors.centerIn: parent
                        width: dividerText.implicitWidth + 24; height: 22; radius: 11
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.accent }
                            GradientStop { position: 1; color: Theme.accentSecondary }
                        }
                        Rectangle { anchors.fill: parent; anchors.margins: -3; radius: height / 2; color: Theme.accentGlow; opacity: 0.5; z: -1 }
                        Text {
                            id: dividerText
                            anchors.centerIn: parent
                            text: (root.msgs.count - root.dividerIndex()) + " 条新消息 ↓"
                            font.pixelSize: Theme.fontSmall; font.bold: true
                            color: Theme.onAccent
                        }
                    }
                }

                // 时间戳：与上一条相隔 ≥ 10 分钟时显示
                Item {
                    visible: {
                        if (row.index === 0) return true
                        var prev = root.msgs.sentAtAt(row.index - 1)
                        return (row.sentAt - prev) >= 10 * 60 * 1000
                    }
                    width: parent.width
                    height: visible ? 24 : 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: stamp.implicitWidth + 20; height: 20; radius: 10
                        color: Theme.surface
                        Text { id: stamp; anchors.centerIn: parent; text: Qt.formatTime(row.sentAt, "HH:mm"); font.pixelSize: Theme.fontSmall; color: Theme.textTertiary }
                    }
                }

                // 消息行：头像 + 名字 + 引用 + 气泡
                Item {
                    width: parent.width
                    implicitHeight: Math.max(col.implicitHeight, row.isMine ? 0 : 28)

                    Avatar {
                        id: av
                        visible: !row.isMine
                        name: row.sender
                        size: 28
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                    }

                    Column {
                        id: col
                        spacing: 3
                        anchors.right: row.isMine ? parent.right : undefined
                        anchors.left: row.isMine ? undefined : av.right
                        anchors.leftMargin: row.isMine ? 0 : 8

                        Text {
                            visible: !row.isMine
                            text: row.sender
                            color: Theme.senderColor(row.sender)
                            font.pixelSize: Theme.fontSmall; font.bold: true
                            leftPadding: 4
                            Behavior on color { ColorAnimation { duration: 260 } }
                        }
                        // 引用块
                        Rectangle {
                            visible: row.replyText !== ""
                            radius: 10
                            color: Theme.surface
                            width: Math.min(quote.implicitWidth, row.maxBubble - 22) + 22
                            height: quote.implicitHeight + 12
                            anchors.right: row.isMine ? parent.right : undefined
                            Rectangle { x: 0; y: 6; width: 3; height: parent.height - 12; radius: 1.5; color: Theme.accent }
                            Text {
                                id: quote
                                x: 12; y: 6
                                width: Math.min(implicitWidth, row.maxBubble - 22)
                                text: row.replyText
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                            }
                        }
                        // 气泡
                        Item {
                            width: bubble.width; height: bubble.height
                            anchors.right: row.isMine ? parent.right : undefined
                            // 我方气泡的光晕 / 投影
                            Rectangle {
                                visible: row.isMine
                                anchors.fill: bubble; anchors.topMargin: 6; anchors.bottomMargin: -6
                                radius: Theme.radiusBubble + 2
                                color: Theme.accentGlow
                                opacity: Theme.dark ? 0.55 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 260 } }
                            }
                            Rectangle {
                                id: bubble
                                radius: Theme.radiusBubble
                                color: row.isMine ? Theme.accent : Theme.accentSoft
                                border.width: row.isNew && !row.isMine ? 1.5 : 0
                                border.color: Theme.accent
                                width: Math.min(bubbleText.implicitWidth, row.maxBubble - 28) + 28
                                height: bubbleText.height + 19
                                Behavior on color { ColorAnimation { duration: 260 } }
                                Text {
                                    id: bubbleText
                                    x: 14; y: 9
                                    width: Math.min(implicitWidth, row.maxBubble - 28)
                                    text: row.text
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Theme.fontBody
                                    lineHeight: 1.18
                                    color: row.isMine ? Theme.onAccent : Theme.bubbleOtherText
                                    Behavior on color { ColorAnimation { duration: 260 } }
                                }
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
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 16; Layout.rightMargin: 16
            implicitHeight: visible ? 38 : 0
            visible: root.st.replyToMsgId !== ""
            Rectangle {
                anchors.fill: parent; anchors.bottomMargin: 6
                radius: 12
                color: Theme.surface
                Behavior on color { ColorAnimation { duration: 260 } }
                Rectangle { x: 0; y: 8; width: 3; height: parent.height - 16; radius: 1.5; color: Theme.accent }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8
                    spacing: 8
                    Text { text: "回复"; font.pixelSize: Theme.fontSmall; font.bold: true; color: Theme.accent }
                    Text {
                        Layout.fillWidth: true
                        text: root.msgs ? root.msgs.previewOf(root.st.replyToMsgId) : ""
                        elide: Text.ElideRight
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                    }
                    MouseArea {
                        id: closeReply
                        width: 22; height: 22
                        hoverEnabled: true
                        onClicked: root.write({ replyToMsgId: "" })
                        Rectangle { anchors.fill: parent; radius: 11; color: Theme.accentSoft; opacity: parent.containsMouse ? 1 : 0.6 }
                        Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 10; color: Theme.textSecondary }
                    }
                }
            }
        }

        // 输入区：胶囊输入条（方案 C），dark 下描边发光（方案 B）
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.bottomMargin: 14
            implicitHeight: inputFrame.implicitHeight

            Rectangle {   // 光晕
                anchors.fill: inputFrame; anchors.margins: -4
                radius: height / 2
                color: Theme.accentGlow
                opacity: input.activeFocus ? (Theme.dark ? 0.45 : 0.25) : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Rectangle {
                id: inputFrame
                anchors.left: parent.left; anchors.right: parent.right
                implicitHeight: Math.min(120, Math.max(44, input.implicitHeight + 10))
                radius: 22
                color: Theme.input
                border.width: input.activeFocus ? 1.5 : 1
                border.color: input.activeFocus ? Theme.accent : Theme.inputBorder
                Behavior on color { ColorAnimation { duration: 260 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 6
                    spacing: 6
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: input.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        TextArea {
                            id: input
                            objectName: "draftInput"
                            width: parent.width
                            wrapMode: TextArea.Wrap
                            placeholderText: "输入消息…"
                            placeholderTextColor: Theme.textTertiary
                            color: Theme.text
                            font.pixelSize: Theme.fontBody
                            leftPadding: 10; rightPadding: 6; topPadding: 12; bottomPadding: 12
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
                    MacButton {
                        id: sendBtn
                        Layout.alignment: Qt.AlignVCenter
                        primary: true
                        text: "发送 ➤"
                        enabled: input.text.trim() !== ""
                        onClicked: root.send()
                        SequentialAnimation {
                            id: sendPulse
                            NumberAnimation { target: sendBtn; property: "scale"; to: 0.88; duration: 90 }
                            NumberAnimation { target: sendBtn; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }
    }
}
