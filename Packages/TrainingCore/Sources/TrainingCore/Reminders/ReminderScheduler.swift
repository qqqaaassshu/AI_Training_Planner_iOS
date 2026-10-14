import Foundation

// 提醒排程逻辑（docs/ios-plan.md「硬性要求：到点手表必须自动震动提醒」）。
//
// 这里只做纯计算：要提醒哪些任务、什么时候、64 条上限下排哪些、下一次强提醒是哪个、
// 最晚什么时候需要重排。Watch App 把结果翻译成：
// - 第 1 层：`UNNotificationRequest`（`UNCalendarNotificationTrigger`，`interruptionLevel = .timeSensitive`）
// - 第 2 层：`WKExtendedRuntimeSession.start(at:)`（只排 `strongAlarm`，须在前台安排）
// - 重排：打开 App、`WKApplicationRefreshBackgroundTask`（不晚于 `refreshBy`）、收到手机同步的新计划时
//
// 提醒由手表安排，手机不重复安排同一提醒。

/// 一条要安排的提醒
public struct ReminderRequest: Hashable, Sendable, Identifiable {
    /// 稳定标识：同一任务同一天始终相同，便于增量更新（`atp.reminder.<taskId>.<date>`）
    public var id: String
    public var taskId: String
    /// 任务所属日期（计划时区）
    public var date: LocalDate
    public var fireDate: Date
    public var taskType: TaskType
    public var title: String
    public var body: String
    /// 来自“稍后提醒”
    public var isSnooze: Bool

    /// 内容指纹：时间或文字变了就需要重新安排。App 把它存进通知的 userInfo，下次对比用
    public var fingerprint: String {
        "\(Int64(fireDate.timeIntervalSince1970.rounded()))|\(title)|\(body)"
    }

    public static let fingerprintKey = "atp.fingerprint"
}

/// “稍后提醒”：用户在通知上点了稍后，或在 App 里选了延后
public struct ReminderSnooze: Codable, Hashable, Sendable {
    public var taskId: String
    public var date: LocalDate
    public var until: Date

    public init(taskId: String, date: LocalDate, until: Date) {
        self.taskId = taskId
        self.date = date
        self.until = until
    }

    enum CodingKeys: String, CodingKey {
        case date, until
        case taskId = "task_id"
    }
}

public struct ReminderPolicy: Hashable, Sendable {
    /// 每个 App 最多 64 条待发本地通知（系统限制）
    public var capacity: Int = 64
    /// 留给其他通知（组间休息、通知操作里新加的“稍后”等）的名额
    public var reservedSlots: Int = 4
    /// 只排未来若干天（含今天）
    public var horizonDays: Int = 7
    /// 智能闹钟会话（WKExtendedRuntimeSession）最多可提前多久安排
    public var strongAlarmMaxLead: TimeInterval = 36 * 3600
    /// 即使名额充足，也至少这么久重排一次（让新的一天进入窗口、纠正时区变化）
    public var maxRefreshInterval: TimeInterval = 24 * 3600
    /// 默认稍后提醒的时长
    public var snoozeInterval: TimeInterval = 10 * 60

    public init() {}

    public var notificationLimit: Int { max(0, capacity - reservedSlots) }
}

public struct ReminderSchedule: Hashable, Sendable {
    /// 应处于待发状态的通知，按时间排序，数量不超过 `policy.notificationLimit`
    public var notifications: [ReminderRequest]
    /// 下一次训练（workout）的闹钟式强提醒；超出可提前安排的范围时为 nil
    public var strongAlarm: ReminderRequest?
    /// 窗口内还有更多提醒因名额被截断
    public var truncated: Bool
    /// 最晚在这个时间之前重排（安排后台刷新用）
    public var refreshBy: Date
}

/// 增量更新：只动有变化的通知，避免每次全部删除重建
public struct ReminderDiff: Hashable, Sendable {
    /// 需要移除的待发通知 id（已不需要的）
    public var toRemove: [String]
    /// 需要新增或替换的通知（相同 id 再次添加会覆盖原通知）
    public var toAdd: [ReminderRequest]
}

/// 系统里已有的待发通知（从 `pendingNotificationRequests()` 读取）
public struct PendingReminder: Hashable, Sendable {
    public var identifier: String
    public var fingerprint: String?
    public init(identifier: String, fingerprint: String?) {
        self.identifier = identifier
        self.fingerprint = fingerprint
    }
}

public enum ReminderScheduler {
    public static let identifierPrefix = "atp.reminder."

    public static func identifier(taskId: String, date: LocalDate) -> String { "\(identifierPrefix)\(taskId).\(date)" }

    /// 该任务当天是否已经处理（完成、部分完成或跳过）——处理过的不再提醒；延后（snoozed）仍要提醒
    static func isClosed(_ r: ExecutionRecord?) -> Bool {
        guard let r else { return false }
        return r.status == .completed || r.status == .partial || r.status == .skipped
    }

    /// 计算当前应安排的提醒
    public static func schedule(plan: PlanVersion?, records: [ExecutionRecord], snoozes: [ReminderSnooze] = [],
                                now: Date, policy: ReminderPolicy = ReminderPolicy()) -> ReminderSchedule {
        let candidates = plan.map { upcoming(plan: $0, records: records, snoozes: snoozes, now: now, policy: policy) } ?? []
        let limit = policy.notificationLimit
        let notifications = Array(candidates.prefix(limit))
        let truncated = candidates.count > notifications.count

        let alarm = candidates.first { $0.taskType == .workout && $0.fireDate.timeIntervalSince(now) <= policy.strongAlarmMaxLead }

        var refreshBy = now.addingTimeInterval(policy.maxRefreshInterval)
        if truncated, !notifications.isEmpty {
            // 用掉一半名额时续排，留出后台刷新被系统推迟的余量
            refreshBy = min(refreshBy, notifications[notifications.count / 2].fireDate)
        }
        return ReminderSchedule(notifications: notifications, strongAlarm: alarm, truncated: truncated, refreshBy: refreshBy)
    }

    /// 窗口内所有未来的提醒，按时间排序（未截断）
    static func upcoming(plan: PlanVersion, records: [ExecutionRecord], snoozes: [ReminderSnooze], now: Date,
                         policy: ReminderPolicy) -> [ReminderRequest] {
        let tz = plan.timeZone
        let today = LocalDate(now, in: tz)
        // 智能闹钟可提前 36 小时安排，窗口至少要覆盖到明天
        let horizon = max(policy.horizonDays, 2)
        let lastDay = today.adding(days: horizon - 1)
        let tasksById = Dictionary(plan.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var byId: [String: ReminderRequest] = [:]

        // 按日程的提醒（从昨天开始：昨天的任务可能被延后到今天）
        var d = today.adding(days: -1)
        while d <= lastDay {
            for task in plan.tasks(on: d) where task.reminder {
                guard let hm = task.schedule.hourMinute, !isClosed(records.record(taskId: task.id, date: d)),
                      let fire = d.date(atHour: hm.hour, minute: hm.minute, in: tz), fire > now else { continue }
                let r = request(plan: plan, task: task, date: d, fire: fire, snooze: false)
                byId[r.id] = r
            }
            d = d.adding(days: 1)
        }

        // 稍后提醒覆盖同一任务同一天的原提醒（同一个 id）；每个任务每天只取最晚的一次稍后
        for s in snoozes.sortedStable(by: { $0.until < $1.until }) {
            guard let task = tasksById[s.taskId], s.until > now, s.date <= lastDay,
                  !isClosed(records.record(taskId: s.taskId, date: s.date)) else { continue }
            let r = request(plan: plan, task: task, date: s.date, fire: s.until, snooze: true)
            byId[r.id] = r
        }

        return byId.values.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    static func request(plan: PlanVersion, task: PlanTask, date: LocalDate, fire: Date, snooze: Bool) -> ReminderRequest {
        ReminderRequest(
            id: identifier(taskId: task.id, date: date),
            taskId: task.id,
            date: date,
            fireDate: fire,
            taskType: task.type,
            title: task.title,
            body: body(plan: plan, task: task, date: date, snooze: snooze),
            isSnooze: snooze
        )
    }

    /// 通知正文：训练列出当天的动作（按周渐进后的），习惯给一句提示
    static func body(plan: PlanVersion, task: PlanTask, date: LocalDate, snooze: Bool) -> String {
        let prefix = snooze ? "稍后提醒 · " : ""
        guard task.type == .workout else { return prefix + "到时间了，完成后点按打勾" }
        let exercises = plan.exercises(for: task, on: date)
        if exercises.isEmpty { return prefix + "该训练了" }
        let shown = exercises.prefix(3).map { "\($0.name) \($0.targetText)" }.joined(separator: "、")
        let more = exercises.count > 3 ? " 等 \(exercises.count) 个动作" : ""
        return prefix + shown + more
    }

    /// 对比系统里已有的待发通知，得出增量操作。只处理本模块生成的 id（`identifierPrefix`）
    public static func diff(desired: [ReminderRequest], pending: [PendingReminder]) -> ReminderDiff {
        let ours = pending.filter { $0.identifier.hasPrefix(identifierPrefix) }
        let pendingById = Dictionary(ours.map { ($0.identifier, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
        let desiredIds = Set(desired.map(\.id))
        return ReminderDiff(
            toRemove: ours.map(\.identifier).filter { !desiredIds.contains($0) },
            toAdd: desired.filter { r in
                guard let fp = pendingById[r.id] else { return true }
                return fp != r.fingerprint
            }
        )
    }

    /// 用户点了“稍后”：生成一条稍后提醒
    public static func snooze(taskId: String, date: LocalDate, now: Date, policy: ReminderPolicy = ReminderPolicy()) -> ReminderSnooze {
        ReminderSnooze(taskId: taskId, date: date, until: now.addingTimeInterval(policy.snoozeInterval))
    }
}
