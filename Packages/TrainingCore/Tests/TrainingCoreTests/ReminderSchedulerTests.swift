import Foundation
import Testing
@testable import TrainingCore

/// 示例计划（Asia/Shanghai，2026-06-15 周一开始）：
/// t1 训练 周一三五 07:30；t2 散步 每天 18:00；t3 睡觉 每天 22:30
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func at(_ date: String, _ time: String, _ tz: TimeZone = shanghai) -> Date {
    let hm = time.split(separator: ":").map { Int($0)! }
    return d(date).date(atHour: hm[0], minute: hm[1], in: tz)!
}

@Suite("提醒排程") struct ReminderSchedulerTests {
    let plan = makePlan()

    @Test("7 天窗口内的提醒按时间排序，第一条是今天的训练") func basic() throws {
        let s = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-06-15", "07:00"))
        #expect(s.notifications.count == 3 + 7 * 2) // t1 三次 + t2/t3 各七次
        #expect(!s.truncated)
        let first = s.notifications[0]
        #expect(first.id == "atp.reminder.t1.2026-06-15")
        #expect(first.fireDate == Date(timeIntervalSince1970: 1_781_479_800)) // 2026-06-14T23:30:00Z
        #expect(first.title == "身体维护训练A")
        #expect(first.body == "深蹲 3×10、臀桥 3×12、平板支撑 3×30秒")
        #expect(s.notifications.map(\.fireDate) == s.notifications.map(\.fireDate).sorted())
        #expect(s.notifications.last?.id == "atp.reminder.t3.2026-06-21")
        #expect(s.strongAlarm?.id == first.id)
        #expect(s.refreshBy == at("2026-06-15", "07:00").addingTimeInterval(24 * 3600))
    }

    @Test("已过的时间、已完成/部分完成/跳过的任务不再提醒") func excludes() {
        let records = [rec("t3", "2026-06-15", .completed), rec("t2", "2026-06-16", .partial), rec("t3", "2026-06-16", .skipped, skipReason: .sick)]
        let s = ReminderScheduler.schedule(plan: plan, records: records, now: at("2026-06-15", "19:00"))
        let ids = Set(s.notifications.map(\.id))
        #expect(!ids.contains("atp.reminder.t1.2026-06-15")) // 07:30 已过
        #expect(!ids.contains("atp.reminder.t2.2026-06-15")) // 18:00 已过
        #expect(!ids.contains("atp.reminder.t3.2026-06-15"))
        #expect(!ids.contains("atp.reminder.t2.2026-06-16"))
        #expect(!ids.contains("atp.reminder.t3.2026-06-16"))
        #expect(s.notifications.first?.id == "atp.reminder.t1.2026-06-17")
    }

    @Test("延后（snoozed）的记录仍会提醒") func snoozedStillReminds() {
        let s = ReminderScheduler.schedule(plan: plan, records: [rec("t2", "2026-06-15", .snoozed)], now: at("2026-06-15", "12:00"))
        #expect(s.notifications.contains { $0.id == "atp.reminder.t2.2026-06-15" })
    }

    @Test("计划开始前、结束后，以及关闭提醒或没有时间的任务不排") func filters() {
        var p = plan
        p.tasks[1].reminder = false
        p.tasks[2].schedule.time = nil
        p.endDate = d("2026-06-17")
        let s = ReminderScheduler.schedule(plan: p, records: [], now: at("2026-06-12", "12:00"))
        #expect(s.notifications.map(\.id) == ["atp.reminder.t1.2026-06-15", "atp.reminder.t1.2026-06-17"])
        #expect(ReminderScheduler.schedule(plan: nil, records: [], now: Date()).notifications.isEmpty)
    }

    @Test("强提醒只给训练，且不超过可提前安排的 36 小时") func strongAlarm() {
        // 周一训练已完成，下一次是周三 07:30，距现在 48.5 小时
        let s = ReminderScheduler.schedule(plan: plan, records: [rec("t1", "2026-06-15", .completed)], now: at("2026-06-15", "07:00"))
        #expect(s.strongAlarm == nil)
        #expect(s.notifications.first?.taskType == .habit)
        // 周二晚上：周三训练在 36 小时内
        let s2 = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-06-16", "20:00"))
        #expect(s2.strongAlarm?.id == "atp.reminder.t1.2026-06-17")
        #expect(s2.notifications.first?.taskType == .habit) // 22:30 睡觉在前，但强提醒只看训练
    }

    @Test("64 条上限：截断到上限减预留，并在用掉一半时续排") func capacity() {
        var policy = ReminderPolicy()
        policy.horizonDays = 60
        let s = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-06-15", "07:00"), policy: policy)
        #expect(s.notifications.count == 60)
        #expect(s.truncated)

        policy.capacity = 10
        policy.reservedSlots = 0
        policy.maxRefreshInterval = 30 * 24 * 3600
        let small = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-06-15", "07:00"), policy: policy)
        #expect(small.notifications.count == 10)
        #expect(small.refreshBy == small.notifications[5].fireDate)
        #expect(small.refreshBy < small.notifications.last!.fireDate)
    }

    @Test("稍后提醒：覆盖同一任务同一天的提醒，任务完成后作废") func snooze() {
        let now = at("2026-06-15", "07:35")
        let sn = ReminderScheduler.snooze(taskId: "t1", date: d("2026-06-15"), now: now)
        #expect(sn.until == now.addingTimeInterval(600))
        let s = ReminderScheduler.schedule(plan: plan, records: [rec("t1", "2026-06-15", .snoozed)], snoozes: [sn], now: now)
        let r = s.notifications.first { $0.id == "atp.reminder.t1.2026-06-15" }
        #expect(r?.fireDate == sn.until)
        #expect(r?.isSnooze == true)
        #expect(r?.body.hasPrefix("稍后提醒 · ") == true)
        #expect(s.strongAlarm?.id == r?.id)

        let done = ReminderScheduler.schedule(plan: plan, records: [rec("t1", "2026-06-15", .completed)], snoozes: [sn], now: now)
        #expect(!done.notifications.contains { $0.id == "atp.reminder.t1.2026-06-15" })
    }

    @Test("昨天的任务延后到今天凌晨也会提醒") func snoozeAcrossMidnight() {
        let sn = ReminderSnooze(taskId: "t3", date: d("2026-06-15"), until: at("2026-06-16", "00:10"))
        let s = ReminderScheduler.schedule(plan: plan, records: [], snoozes: [sn], now: at("2026-06-16", "00:05"))
        #expect(s.notifications.first?.id == "atp.reminder.t3.2026-06-15")
    }

    @Test("按周渐进：通知正文用当周的动作；动作多时省略") func phaseBody() {
        let s = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-07-13", "07:00"))
        #expect(s.notifications[0].body == "深蹲 4×10 @10kg、臀桥 4×12、平板支撑 3×45秒")
        var p = plan
        p.tasks[0].phases = nil
        p.tasks[0].exercises!.append(Exercise(name: "俯卧撑", sets: 3, reps: 8))
        let s2 = ReminderScheduler.schedule(plan: p, records: [], now: at("2026-06-15", "07:00"))
        #expect(s2.notifications[0].body.hasSuffix(" 等 4 个动作"))
        #expect(s2.notifications.first { $0.taskType == .habit }?.body == "到时间了，完成后点按打勾")
    }

    @Test("按计划时区计算时刻") func timeZones() {
        var p = plan
        p.timezone = "America/New_York"
        let ny = TimeZone(identifier: "America/New_York")!
        let s = ReminderScheduler.schedule(plan: p, records: [], now: at("2026-06-15", "00:00", ny))
        #expect(s.notifications[0].fireDate == Date(timeIntervalSince1970: 1_781_523_000)) // 2026-06-15T11:30:00Z
    }

    @Test("增量更新：只移除不需要的，只添加新增或变化的，不碰其他通知") func diff() {
        let s = ReminderScheduler.schedule(plan: plan, records: [], now: at("2026-06-15", "07:00"))
        let a = s.notifications[0], b = s.notifications[1]
        var changed = s.notifications[2]
        changed.title = "旧标题"
        let pending = [
            PendingReminder(identifier: a.id, fingerprint: a.fingerprint),
            PendingReminder(identifier: b.id, fingerprint: b.fingerprint),
            PendingReminder(identifier: changed.id, fingerprint: changed.fingerprint),
            PendingReminder(identifier: "atp.reminder.t9.2026-06-15", fingerprint: "x"),
            PendingReminder(identifier: "rest-timer", fingerprint: nil),
        ]
        let diff = ReminderScheduler.diff(desired: s.notifications, pending: pending)
        #expect(diff.toRemove == ["atp.reminder.t9.2026-06-15"])
        #expect(diff.toAdd.count == s.notifications.count - 2)
        #expect(diff.toAdd.first?.id == s.notifications[2].id)
        #expect(!diff.toAdd.contains { $0.id == a.id || $0.id == b.id })
    }
}
