import Foundation

/// 通知上的操作（手表）：训练可“开始”或“稍后”，习惯可“完成”或“稍后”
public enum ReminderCategory: String, CaseIterable, Sendable {
    case workout = "atp.reminder.workout"
    case habit = "atp.reminder.habit"

    public init(taskType: TaskType) { self = taskType == .workout ? .workout : .habit }

    public var actions: [ReminderAction] {
        switch self {
        case .workout: return [.start, .snooze]
        case .habit: return [.complete, .snooze]
        }
    }
}

public enum ReminderAction: String, CaseIterable, Sendable {
    /// 打开 App 开始训练
    case start = "atp.action.start"
    /// 直接记为完成（不打开 App）
    case complete = "atp.action.complete"
    /// 稍后再提醒
    case snooze = "atp.action.snooze"

    public var title: String {
        switch self {
        case .start: return "开始训练"
        case .complete: return "完成"
        case .snooze: return "稍后 10 分钟"
        }
    }

    /// 是否需要打开 App
    public var opensApp: Bool { self == .start }
}

extension ReminderRequest {
    public var category: ReminderCategory { ReminderCategory(taskType: taskType) }

    /// 通知 userInfo 里的任务与日期
    public static let taskIdKey = "task_id"
    public static let dateKey = "date"
}

// MARK: 表盘复杂功能

/// 表盘上显示的今日进度与下一个任务
public struct ComplicationSummary: Codable, Hashable, Sendable {
    public var done: Int
    public var total: Int
    /// 下一个未完成、且有提醒时间的任务
    public var nextTitle: String?
    public var nextTime: Date?
    public var nextIsWorkout: Bool

    public init(done: Int, total: Int, nextTitle: String? = nil, nextTime: Date? = nil, nextIsWorkout: Bool = false) {
        self.done = done
        self.total = total
        self.nextTitle = nextTitle
        self.nextTime = nextTime
        self.nextIsWorkout = nextIsWorkout
    }

    public static let empty = ComplicationSummary(done: 0, total: 0)

    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// 某个时刻表盘应显示的内容
public func complicationSummary(plan: PlanVersion?, records: [ExecutionRecord], now: Date) -> ComplicationSummary {
    guard let plan else { return .empty }
    let tz = plan.timeZone
    let today = LocalDate(now, in: tz)
    let tasks = plan.tasks(on: today)
    let done = tasks.filter { records.record(taskId: $0.id, date: today)?.isDone == true }.count
    let upcoming = tasks.compactMap { task -> (PlanTask, Date)? in
        let r = records.record(taskId: task.id, date: today)
        guard !(r?.isDone ?? false), r?.status != .skipped, let hm = task.schedule.hourMinute,
              let at = today.date(atHour: hm.hour, minute: hm.minute, in: tz), at >= now.addingTimeInterval(-30 * 60) else { return nil }
        return (task, at)
    }
    .sorted { $0.1 < $1.1 }
    .first
    return ComplicationSummary(done: done, total: tasks.count, nextTitle: upcoming?.0.title, nextTime: upcoming?.1,
                               nextIsWorkout: upcoming?.0.type == .workout)
}

/// 表盘时间线：现在一条，之后每个任务时间点再各一条（到点后切换到下一个任务）
public func complicationTimeline(plan: PlanVersion?, records: [ExecutionRecord], now: Date, hours: Int = 24) -> [(date: Date, summary: ComplicationSummary)] {
    var dates = [now]
    if let plan {
        let tz = plan.timeZone
        let today = LocalDate(now, in: tz)
        for d in [today, today.adding(days: 1)] {
            for task in plan.tasks(on: d) {
                guard let hm = task.schedule.hourMinute, let at = d.date(atHour: hm.hour, minute: hm.minute, in: tz) else { continue }
                // 任务时间过去 30 分钟后不再显示为“下一个”
                let switchAt = at.addingTimeInterval(30 * 60 + 1)
                if switchAt > now && switchAt < now.addingTimeInterval(TimeInterval(hours) * 3600) { dates.append(switchAt) }
            }
        }
        // 午夜换天
        if let midnight = today.adding(days: 1).date(atHour: 0, minute: 0, in: tz), midnight > now { dates.append(midnight) }
    }
    return Array(Set(dates)).sorted().map { ($0, complicationSummary(plan: plan, records: records, now: $0)) }
}
