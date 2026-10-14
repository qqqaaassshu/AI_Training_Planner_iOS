import Foundation

// 对应原型 utils/plan.ts「统计」部分

func average(_ xs: [Double]) -> Double {
    xs.isEmpty ? 0 : jsRound(xs.reduce(0, +) / Double(xs.count) * 10) / 10
}

/// 统计口径：
/// - 过去的日期：所有排期任务都计入
/// - 今天：只有已有记录（完成/部分/跳过）的任务才计入，还没做的不算遗漏
/// - completed 计 1，partial 计 0.5，skipped 计 0
public func buildExportSummary(plan: PlanVersion?, records: [ExecutionRecord], dailyWellness: [DailyWellness],
                               today: LocalDate, range: DateRange? = nil) -> ExportSummary {
    let inRange = { (d: LocalDate) in range?.contains(d) ?? true }
    let scoped = records.filter { inRange($0.date) }

    var scheduledCount = 0, completed = 0, partial = 0, skipped = 0
    var missed: [String] = []
    var reasons: [SkipReason: Int] = [:]

    if let plan {
        let to = range.map { Swift.min($0.to, today) } ?? today
        for s in plan.scheduledTasks(from: range?.from ?? plan.startDate, to: to) {
            let r = records.record(taskId: s.task.id, date: s.date)
            if s.date == today && (r == nil || r?.status == .snoozed) { continue }
            scheduledCount += 1
            switch r?.status {
            case .completed: completed += 1
            case .partial: partial += 1
            case .skipped:
                skipped += 1
                reasons[r?.skipReason ?? .other, default: 0] += 1
            default: missed.append("\(s.date) · \(s.task.title)")
            }
        }
    }

    let pain = scoped.compactMap(\.painScore)
    let fatigue = scoped.compactMap(\.fatigueScore).map(Double.init)
        + dailyWellness.filter { inRange($0.date) }.map { Double($0.fatigueScore) }

    return ExportSummary(
        scheduledCount: scheduledCount,
        completedCount: completed,
        partialCount: partial,
        skippedCount: skipped,
        completionRate: scheduledCount > 0
            ? Int(jsRound((Double(completed) + Double(partial) * 0.5) / Double(scheduledCount) * 100)) : 0,
        missedTasks: missed,
        skipReasons: reasons,
        painAverage: average(pain.map(Double.init)),
        painMax: pain.max() ?? 0,
        fatigueAverage: average(fatigue)
    )
}
