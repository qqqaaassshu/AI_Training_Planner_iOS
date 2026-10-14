import Foundation

// 对应原型 utils/plan.ts「日程」部分

extension PlanTask {
    public func isScheduled(on date: LocalDate) -> Bool {
        if schedule.daily == true { return true }
        return schedule.weekday?.contains(date.weekday) ?? false
    }
}

public struct ScheduledTask: Hashable, Sendable {
    public var date: LocalDate
    public var task: PlanTask
}

extension PlanVersion {
    public func contains(_ date: LocalDate) -> Bool {
        date >= startDate && (endDate.map { date <= $0 } ?? true)
    }

    public func tasks(on date: LocalDate) -> [PlanTask] {
        guard contains(date) else { return [] }
        return tasks.filter { $0.isScheduled(on: date) }
    }

    /// 没有结束日期时按 12 周
    public var totalWeeks: Int {
        guard let end = endDate else { return 12 }
        return max(1, Int((Double(startDate.days(to: end) + 1) / 7).rounded(.up)))
    }

    /// date 位于计划第几周（从 1 开始，计划开始前视为第 1 周）
    public func week(of date: LocalDate) -> Int {
        let days = startDate.days(to: date)
        if days < 0 { return 1 }
        return days / 7 + 1
    }

    public func currentWeek(today: LocalDate) -> Int {
        min(totalWeeks, week(of: today))
    }

    /// 按周渐进：若当周有 phase 覆盖则用 phase 的动作
    public func exercises(for task: PlanTask, on date: LocalDate) -> [Exercise] {
        let w = week(of: date)
        if let phase = task.phases?.first(where: { w >= $0.weekFrom && w <= $0.weekTo }) { return phase.exercises }
        return task.exercises ?? []
    }

    /// 区间内（截断到计划起止日期）每天的排期任务
    public func scheduledTasks(from: LocalDate, to: LocalDate) -> [ScheduledTask] {
        var result: [ScheduledTask] = []
        let start = Swift.max(from, startDate)
        let end = endDate.map { Swift.min($0, to) } ?? to
        var d = start
        while d <= end {
            for task in tasks where task.isScheduled(on: d) { result.append(ScheduledTask(date: d, task: task)) }
            d = d.adding(days: 1)
        }
        return result
    }
}

extension Array where Element == ExecutionRecord {
    public func record(taskId: String, date: LocalDate) -> ExecutionRecord? {
        first { $0.taskId == taskId && $0.date == date }
    }
}

extension ExecutionRecord {
    /// 完成或部分完成
    public var isDone: Bool { status == .completed || status == .partial }
}
