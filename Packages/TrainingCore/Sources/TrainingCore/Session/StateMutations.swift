import Foundation

// 对 App 状态的修改（对应原型 App.tsx 中的 handleImport / handleRecord 等），iPhone 与 Watch 共用。

extension PersistedState {
    /// 导入新版本并设为当前计划
    public mutating func addPlanVersion(_ version: PlanVersion) {
        planVersions.append(version)
        currentPlanId = version.id
    }

    /// 切换当前版本（查看或回退到历史版本）
    public mutating func selectPlanVersion(id: String) {
        guard planVersions.contains(where: { $0.id == id }) else { return }
        currentPlanId = id
    }

    /// 写入当天记录：每个任务每天最多一条，再次提交时覆盖（保留原 id）
    @discardableResult
    public mutating func record(_ draft: RecordDraft, date: LocalDate, source: RecordSource = .phone, now: Date = Date()) -> ExecutionRecord? {
        guard let plan = currentPlan else { return nil }
        let at = Timestamp.string(from: now)
        let existing = records.firstIndex { $0.taskId == draft.taskId && $0.date == date }
        let record = ExecutionRecord(
            id: existing.map { records[$0].id } ?? newId(),
            taskId: draft.taskId,
            planVersionId: plan.id,
            date: date,
            status: draft.status,
            skipReason: draft.skipReason,
            sets: draft.sets,
            painScore: draft.painScore,
            fatigueScore: draft.fatigueScore,
            notes: draft.notes,
            source: source,
            startedAt: draft.startedAt,
            completedAt: draft.status == .completed || draft.status == .partial ? at : nil,
            updatedAt: at
        )
        if let i = existing { records.remove(at: i) }
        records.append(record)
        return record
    }

    /// 修改历史记录（补录动作、备注等）
    public mutating func updateRecord(id: String, now: Date = Date(), _ change: (inout ExecutionRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[i])
        records[i].updatedAt = Timestamp.string(from: now)
    }

    public mutating func deleteRecord(id: String) {
        records.removeAll { $0.id == id }
    }

    /// 当天的整体疲劳（每天一条）
    public mutating func setDailyFatigue(_ score: Int, date: LocalDate, now: Date = Date()) {
        let old = dailyWellness.first { $0.date == date }
        dailyWellness.removeAll { $0.date == date }
        dailyWellness.append(DailyWellness(date: date, fatigueScore: score, sleepHours: old?.sleepHours, updatedAt: Timestamp.string(from: now)))
    }

    public func dailyFatigue(on date: LocalDate) -> Int? {
        dailyWellness.first { $0.date == date }?.fatigueScore
    }
}

/// 记录对应的任务：优先查记录所属版本，其次版本号从新到旧（任务 id 跨版本稳定）
public func findTask(for record: ExecutionRecord, in versions: [PlanVersion]) -> (plan: PlanVersion, task: PlanTask)? {
    let ordered = versions.filter { $0.id == record.planVersionId } + versions.filter { $0.id != record.planVersionId }.sorted { $0.version > $1.version }
    for plan in ordered {
        if let task = plan.tasks.first(where: { $0.id == record.taskId }) { return (plan, task) }
    }
    return nil
}

/// 历史页的一天
public struct HistoryDay: Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var records: [ExecutionRecord]
    public var fatigue: Int?
    public var id: LocalDate { date }
}

/// 按日期从新到旧分组；只有疲劳评分的日期也列出
public func historyDays(records: [ExecutionRecord], wellness: [DailyWellness]) -> [HistoryDay] {
    let dates = Set(records.map(\.date)).union(wellness.map(\.date))
    return dates.sorted(by: >).map { date in
        HistoryDay(date: date, records: records.filter { $0.date == date }.sortedStable { $0.updatedAt < $1.updatedAt },
                   fatigue: wellness.first { $0.date == date }?.fatigueScore)
    }
}

/// 历史页顶部统计：按记录条数（与原型一致）
public struct HistoryStats: Hashable, Sendable {
    public var done: Int
    public var skipped: Int
    public var rate: Int

    public init(records: [ExecutionRecord]) {
        done = records.filter(\.isDone).count
        skipped = records.filter { $0.status == .skipped }.count
        rate = records.isEmpty ? 0 : Int(jsRound(Double(done) / Double(records.count) * 100))
    }
}

/// 补录编辑器的初始值：已有组记录 > 当天计划动作
public func editorItems(for record: ExecutionRecord, versions: [PlanVersion]) -> [SetSummary] {
    if let sets = record.sets, !sets.isEmpty { return summarizeSets(sets) }
    guard let found = findTask(for: record, in: versions) else { return [] }
    return summaries(fromPlan: found.plan.exercises(for: found.task, on: record.date))
}
