# 把英文译文填进 lupdate 生成的 .ts（源文本中文）。
# 改了界面文字后：
#   lupdate src qml -extensions cpp,h,qml,js -source-language zh_CN -target-language en_US -locations none -ts i18n/ChatDemo_en.ts
#   python3 i18n/fill_en.py i18n/ChatDemo_en.ts      # 输出 missing 的条目，补进下面的 T / OVERRIDE 后再跑一次
import sys
import xml.etree.ElementTree as ET

T = {
 '截止 %1': 'Due %1', '待办': 'To-do', '全天': 'All day', '%1 起': 'from %1', '再看 30 天': 'Show 30 more days',
 '没有找到与「%1」相关的日程': 'No events matching “%1”', '接下来 %1 天没有安排': 'Nothing scheduled in the next %1 days',
 '今天': 'Today', '明天': 'Tomorrow', '昨天': 'Yesterday', '后天': 'In 2 days',
 '%1（%2）': '%1 (%2)', '%1 – %2': '%1 – %2', '（%1）': ' (%1)',
 '你好，我是日历小助手。可以问我「今天有什么安排」「明天下午有空吗」，也可以直接说「明天下午3点 产品评审 1小时」或「提醒我周五交周报」。':
   'Hi, I’m your calendar assistant. Ask me “What’s on today?” or “Am I free tomorrow afternoon?”, or just say “Product review tomorrow at 3pm for 1 hour” or “Remind me to send the weekly report on Friday”.',
 '今天有什么安排？': 'What’s on today?', '下一个会议是什么？': 'What’s my next meeting?', '明天下午有空吗': 'Am I free tomorrow afternoon?',
 '本周的待办': 'To-dos this week', '明天下午3点 需求评审 1小时': 'Spec review tomorrow 3pm for 1 hour', '提醒我周五交周报': 'Remind me to send the weekly report Friday',
 '已撤销。': 'Undone.', '这一项已经不存在了。': 'That item no longer exists.',
 '我可以帮你：\n• 查日程：「明天有什么安排」「下周的会议」\n• 找空闲：「周三下午有空吗」\n• 下一个会议、今日概览\n• 新建活动：「周五上午10点 和设计对齐 半小时」\n• 新建待办：「提醒我明天交报告」':
   'I can help you:\n• Check your schedule: “What’s on tomorrow?” “Meetings next week”\n• Find free time: “Am I free Wednesday afternoon?”\n• Next meeting, today’s overview\n• Create events: “Design sync Friday 10am for 30 min”\n• Create to-dos: “Remind me to send the report tomorrow”',
 '要提醒你做什么呢？比如「提醒我明天交周报」。': 'What should I remind you about? For example: “Remind me to send the weekly report tomorrow”.',
 '已添加待办「%1」，截止 %2。': 'Added to-do “%1”, due %2.', '已添加待办「%1」（无截止日期）。': 'Added to-do “%1” (no due date).',
 '撤销': 'Undo', '具体几点开始呢？比如「明天下午3点 需求评审」。': 'What time should it start? For example: “Spec review tomorrow at 3pm”.',
 '新活动': 'New event', '「%1」': '“%1”', '已在「%1」创建「%2」：%3 %4。': 'Created “%2” in %1: %3 %4.',
 '⚠ 与 %1 时间重叠。': '⚠ Overlaps with %1.', '、': ', ', '%1：%2': '%1: %2', '没有空档': 'no free slots',
 '工作时间（9:00–18:00）内，%1': 'Within working hours (9:00–18:00), %1', '工作时间（9:00–18:00）内的空闲时段：': 'Free slots within working hours (9:00–18:00):',
 '（已按至少 %1 分钟筛选）': '(at least %1 minutes)', '正在进行中': 'in progress',
 '还有 %n 分钟': ('in %n minute', 'in %n minutes'), '还有 %1 小时 %2 分钟': 'in %1 h %2 min',
 '下一个是「%1」，%2 %3 开始': 'Next up: “%1”, %2 at %3', '，地点：%1': ', at %1', '。': '.',
 '未来两周没有会议，可以专心干活了。': 'No meetings in the next two weeks — time for deep work.',
 '今天（%1）共 %2 个会议，还剩 %3 个': 'Today (%1): %2 meetings, %3 remaining', '，下一个是 %1「%2」': ', next is “%2” at %1',
 '待办 %n 项': ('%n to-do', '%n to-dos'), '（%n 项已逾期）': (' (%n overdue)', ' (%n overdue)'),
 '；工作时间内还有约 %1 小时 %2 分钟空闲。': '; about %1 h %2 min free during working hours.',
 '今天（含逾期）': 'today (incl. overdue)', '%1没有未完成的待办 🎉': 'No open to-dos for %1 🎉',
 '%1没有未完成的待办 🎉，全部列表里还有 %2 项。': 'No open to-dos for %1 🎉 — %2 more in the full list.',
 '（已逾期）': ' (overdue)', '（%1 截止）': ' (due %1)', '%1有 %n 项待办：': ('%1 — %n to-do:', '%1 — %n to-dos:'),
 '%1没有会议。': 'No meetings %1.', '%1没有安排。': 'Nothing scheduled %1.',
 '%1有 %n 个会议：': ('%1 — %n meeting:', '%1 — %n meetings:'), '%1有 %n 个安排：': ('%1 — %n event:', '%1 — %n events:'),
 '我还不太明白。可以试试：「明天有什么安排」「周三下午有空吗」「明天下午3点 需求评审」「提醒我周五交周报」。':
   'Sorry, I didn’t get that. Try: “What’s on tomorrow?”, “Am I free Wednesday afternoon?”, “Spec review tomorrow at 3pm”, “Remind me to send the weekly report Friday”.',
 '日历小助手': 'Calendar Assistant', '正在思考…': 'Thinking…', '查日程 · 找空闲 · 建活动 / 待办': 'Schedule · Free time · Events / To-dos',
 '清空': 'Clear', '无截止日期': 'No due date', '已撤销': 'Undone', '问问日程，或说「明天3点 评审」': 'Ask about your schedule, or say “review tomorrow 3pm”',
 '日历': 'Calendar', '切换主题（⌘⇧D）': 'Toggle theme (⌘⇧D)', '＋  创建': '＋  Create', '活动（C）': 'Event (C)', '全天活动': 'All-day event',
 '新建日历…': 'New calendar…', '订阅日历…': 'Subscribe to calendar…', '＋': '＋', '刷新失败：%1': 'Refresh failed: %1', '上次同步 %1': 'Last synced %1',
 '尚未同步': 'Not synced yet', '\n只读 · 右键可刷新 / 修改': '\nRead-only · right-click to refresh / edit', '仅显示此日历': 'Show only this calendar',
 '立即刷新': 'Refresh now', '编辑订阅…': 'Edit subscription…', '重命名…': 'Rename…', '导出为 .ics': 'Export as .ics', '已导出到 %1': 'Exported to %1',
 '导出失败': 'Export failed', '颜色': 'Color', '当前': 'current', '取消订阅': 'Unsubscribe', '删除日历': 'Delete calendar', '我的日历': 'MY CALENDARS',
 '新建日历': 'New calendar', '订阅日历': 'SUBSCRIBED', '通过 URL 订阅（Google / iCloud / Outlook 的 .ics 链接）': 'Subscribe by URL (.ics links from Google / iCloud / Outlook)',
 '还没有订阅。点 ＋ 粘贴 .ics / webcal 链接': 'No subscriptions yet. Click ＋ and paste an .ics / webcal link', '选项': 'OPTIONS',
 '在日历中显示待办': 'Show to-dos in calendar', '显示已完成的待办': 'Show completed to-dos', '每周从周一开始': 'Week starts on Monday',
 '快捷键：T 今天 · D/W/M/Y/A 切换视图 · J/K 翻页 · C 新建 · / 搜索': 'Shortcuts: T today · D/W/M/Y/A views · J/K page · C create · / search',
 '日历名称': 'Calendar name', '取消': 'Cancel', '创建': 'Create', '重命名日历': 'Rename calendar', '保存': 'Save', '删除「%1」？': 'Delete “%1”?',
 '取消订阅后，该日历的活动将不再显示。可随时重新订阅。': 'Events from this calendar will no longer be shown. You can subscribe again at any time.',
 '日历中的所有活动和待办都会被删除，且无法恢复。': 'All events and to-dos in this calendar will be deleted. This can’t be undone.',
 '删除': 'Delete', '新日历': 'New calendar', '无法读取文件：%1': 'Can’t read file: %1',
 '不支持的地址，请使用 https://、webcal:// 或本地 .ics 文件': 'Unsupported address. Use https://, webcal:// or a local .ics file',
 '不是有效的 iCalendar（.ics）数据': 'Not valid iCalendar (.ics) data', '（无标题）': '(No title)', '现在开始': 'starting now',
 '%n 分钟后开始': ('starts in %n minute', 'starts in %n minutes'),
 '工作': 'Work', '站会': 'Stand-up', '线上': 'Online', '产品评审': 'Product review', '3F 会议室 A': 'Room 3A', '设计走查': 'Design walkthrough',
 '设计部': 'Design studio', '1:1 沟通': '1:1', '客户拜访': 'Customer visit', '科技园 B 座': 'Tech Park, Building B', '版本发布': 'Release',
 '上海出差': 'Trip to Shanghai', '准备评审材料': 'Prepare review deck', '提交周报': 'Send weekly report', '本周进展 + 下周计划': 'Progress this week + plan for next week',
 '个人': 'Personal', '健身': 'Workout', '健身房': 'Gym', '午餐 · 老同学': 'Lunch with an old friend', '公司楼下': 'Café downstairs',
 '妈妈生日 🎂': 'Mom’s birthday 🎂', '报销发票': 'Submit expense receipts', '预订上海机票': 'Book flight to Shanghai', '出差前确认航班': 'Confirm flight before the trip',
 '续费云服务器': 'Renew cloud server', '整理需求池': 'Groom the backlog', '更新简历': 'Update résumé', '团队公共日历（示例订阅）': 'Team calendar (sample subscription)',
 '搜索：%1': 'Search: %1', '日程': 'Agenda', '第 %1 周': 'Week %1', '自 %1 起': 'From %1', '回到今天（T）': 'Go to today (T)',
 '上一页（K / ←）': 'Previous (K / ←)', '下一页（J / →）': 'Next (J / →)', '搜索日程': 'Search events', '搜索（/ 或 ⌘F）': 'Search (/ or ⌘F)',
 '日': 'Day', '周': 'Week', '月': 'Month', '年': 'Year', '%1视图（%2）': '%1 view (%2)', '隐藏待办': 'Hide to-dos', '在右侧面板显示待办': 'Show to-dos in side panel',
 '%n 条消息': ('%n message', '%n messages'), '⇲ 合并到主窗口': '⇲ Merge into main window', '⧉ 拆出窗口': '⧉ Pop out',
 '%n 条新消息 ↓': ('%n new message ↓', '%n new messages ↓'), '引用回复': 'Quote reply', '回复': 'Reply', '输入消息…': 'Type a message…', '发送 ➤': 'Send ➤',
 '消息': 'Messages', '切换到浅色（⌘⇧D）': 'Switch to light (⌘⇧D)', '切换到深色（⌘⇧D）': 'Switch to dark (⌘⇧D)', '搜索会话': 'Search chats',
 '▥ 面板': '▥ Panel', '⧉ 独立窗口': '⧉ Window', '在新窗口打开': 'Open in new window', '在右侧面板打开': 'Open in side panel', '在线 · %1': 'Online · %1',
 '%n 条未读': ('%n unread', '%n unread'), '没有未读': 'all caught up', '选择日期': 'Pick a date', '优先级：%1': 'Priority: %1', '提醒：%1': 'Alert: %1',
 '提醒：提前 %1 分钟': 'Alert: %1 min before', ' · 订阅日历（只读）': ' · subscribed (read-only)', '编辑': 'Edit', '删除重复活动：': 'Delete recurring event:',
 '仅此次': 'This event', '所有': 'All events', '活动': 'Event', '编辑待办': 'Edit to-do', '编辑活动': 'Edit event', '待办事项': 'To-do',
 '添加标题': 'Add title', '至': 'to', '结束日期': 'End date', '%1（自定义）': '%1 (custom)', '添加地点': 'Add location', '截止': 'Due', '无时间': 'No time',
 '优先级': 'Priority', '添加备注': 'Add notes', '修改将应用到整个重复系列': 'Changes apply to the whole series', '正在打开日历…': 'Opening calendar…',
 '「%1」已在右侧面板打开': '“%1” is open in the side panel', '「%1」已在独立窗口打开': '“%1” is open in a separate window', '移回这里': 'Move back here',
 '前往该窗口': 'Go to window', '选择一个会话开始聊天': 'Select a chat to start messaging', '今天 · 已结束': 'Today · ended',
 '进行中 · 还剩 %n 分钟': ('In progress · %n minute left', 'In progress · %n minutes left'), '%1 小时 %2 分钟后开始': 'Starts in %1 h %2 min',
 '正在进行': 'Happening now', '下一个会议': 'Next meeting', '加入会议': 'Join', '今天 %n 个会议': ('%n meeting today', '%n meetings today'),
 '7 天': '7 days', '接下来没有会议 ☕': 'No upcoming meetings ☕', '今天没有其它会议了': 'No other meetings today', '没有其它会议': 'No other meetings',
 '还有 %n 项': ('+%n more', '+%n more'), '（⌘1）': ' (⌘1)', '（⌘2）': ' (⌘2)', '设置（⌘,）': 'Settings (⌘,)',
 '面板已在独立窗口，点击合并回来': 'Panel is in its own window — click to dock it', '隐藏动态面板': 'Hide side panel', '显示动态面板': 'Show side panel', '（⌘⇧P）': ' (⌘⇧P)',
 '在日历中打开 ›': 'Open in Calendar ›', '这一天没有安排': 'Nothing scheduled', '选择会话，在面板里聊天': 'Pick a chat to open it in the panel',
 '⧉ 已在独立窗口': '⧉ In a separate window', '正在主窗口中查看': 'Open in main window', '返回会话列表': 'Back to chats', '在消息中打开': 'Open in Messages',
 '拆出为独立窗口': 'Pop out to window', '动态面板': 'Side Panel', '设置': 'Settings', '外观': 'APPEARANCE', '浅色': 'Light', '深色': 'Dark', '跟随系统': 'System',
 '系统当前为%1模式，切换系统外观时会自动跟随。': 'Your system is currently in %1 mode; the app follows it automatically.', '语言': 'LANGUAGE',
 '快捷键：⌘, 打开设置 · ⌘⇧D 切换浅色 / 深色': 'Shortcuts: ⌘, settings · ⌘⇧D toggle light / dark',
 '会议': 'Meetings', '聊天': 'Chat', '助手': 'Assistant', '合并回主窗口': 'Dock into main window', '在独立窗口中打开': 'Open in separate window',
 '关闭面板（⌘⇧P）': 'Close panel (⌘⇧P)', '每 15 分钟': 'Every 15 minutes', '每小时': 'Hourly', '每 6 小时': 'Every 6 hours', '每天': 'Daily',
 '不自动刷新': 'Never', '示例：团队公共日历（内置）': 'Sample: team calendar (built-in)', '中国节假日（Google 公共日历）': 'Holidays in China (Google public calendar)',
 '正在订阅…': 'Subscribing…', '已添加，但首次同步失败：%1（可稍后在列表里右键「立即刷新」）': 'Added, but the first sync failed: %1 (right-click it in the list and choose “Refresh now” later)',
 '编辑订阅': 'Edit subscription',
 '粘贴日历的 iCal（.ics）地址：Google 日历 → 设置 → 某个日历 →「iCal 格式的公开 / 私密地址」；macOS / iCloud 日历 → 共享 →「公开日历」；Outlook → 发布日历 → ICS。也支持 webcal:// 和本地 .ics 文件路径。':
   'Paste the calendar’s iCal (.ics) address: Google Calendar → Settings → a calendar → “Public / Secret address in iCal format”; macOS / iCloud Calendar → Share → “Public Calendar”; Outlook → Publish calendar → ICS. webcal:// links and local .ics file paths also work.',
 'https://… 或 webcal://… 或 /path/to/calendar.ics': 'https://… or webcal://… or /path/to/calendar.ics', '名称': 'Name',
 '留空则使用日历自带的名称': 'Leave empty to use the calendar’s own name', '自动刷新': 'Auto refresh', '关闭': 'Close', '订阅': 'Subscribe',
 '已完成': 'Completed', '无日期': 'No date', '已逾期': 'Overdue', '以后': 'Later', '计划': 'Scheduled', '全部': 'All',
 '添加今天的待办，回车保存': 'Add a to-do for today, press Return', '添加待办，回车保存': 'Add a to-do, press Return',
 '更多选项（截止时间、优先级、备注）': 'More options (due time, priority, notes)', ' · 只读': ' · read-only', '今天没有待办 🎉': 'Nothing due today 🎉',
 '还没有完成的待办': 'No completed to-dos yet', '没有待办': 'No to-dos',
 '每 %1 天': 'Every %1 days', '每个工作日': 'Every weekday', '每 %1 周': 'Every %1 weeks', '每周': 'Weekly', '每 %1 个月': 'Every %1 months', '每月': 'Monthly',
 '（第 %1 个%2）': ' on the %1th %2', '（最后一个%1）': ' on the last %1', '（%1 日）': ' on day %1', '（最后一天）': ' on the last day',
 '每 %1 年': 'Every %1 years', '每年': 'Yearly', '自定义重复': 'Custom recurrence', '，共 %n 次': (', %n time', ', %n times'), '，至 %1': ', until %1',
}
# 同一个中文在不同界面里意思不同：按 (上下文, 源文本) 覆盖
OVERRIDE = {
 ('Assistant', '今天'): 'today', ('Assistant', '明天'): 'tomorrow', ('Assistant', '昨天'): 'yesterday', ('Assistant', '全天'): 'all day',
 ('SidePanel', '待办'): 'To-dos', ('CalendarStore', '待办'): 'To-dos', ('EventEditor', '待办'): 'To-do',
 ('SidePanel', '日历'): 'Calendar', ('CalSidebar', '日历'): 'Calendar',
 ('ical', '每周'): 'Weekly', ('ical', '每天'): 'Daily', ('ical', '每月'): 'Monthly', ('ical', '每年'): 'Yearly',
 ('ical', '（%1）'): ' on %1', ('ical', '（第 %1 个%2）'): ' on the %1 %2',
}

path = sys.argv[1]
tree = ET.parse(path)
missing = []
for ctx in tree.getroot().iter('context'):
    cname = ctx.find('name').text
    for m in ctx.iter('message'):
        src = m.find('source').text
        tr = m.find('translation')
        val = OVERRIDE.get((cname, src), T.get(src))
        if val is None:
            missing.append((cname, src))
            continue
        for c in list(tr):
            tr.remove(c)
        tr.text = None
        tr.attrib.pop('type', None)
        if m.get('numerus') == 'yes':
            forms = val if isinstance(val, tuple) else (val, val)
            for f in forms:
                e = ET.SubElement(tr, 'numerusform')
                e.text = f
        else:
            tr.text = val[0] if isinstance(val, tuple) else val
ET.indent(tree, space='    ')
with open(path, 'wb') as f:
    f.write(b'<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n')
    tree.write(f, encoding='utf-8')
print('missing:', len(missing))
for c, s in missing:
    print(' ', c, repr(s))
