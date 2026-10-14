import Foundation

// 今日任务的打勾与提交（对应原型 TodayView 的 TaskCard 与 SetEditor），iPhone 与 Watch 共用。

/// 计划动作 → 可编辑的实际值（计时动作不带次数）
public func summaries(fromPlan exercises: [Exercise]) -> [SetSummary] {
    exercises.map {
        SetSummary(exerciseId: $0.id, name: $0.name, sets: $0.sets, reps: $0.durationSec == nil ? $0.reps : nil,
                   durationSec: $0.durationSec, weightKg: $0.weightKg)
    }
}

/// 一个任务当天的进度：每个动作的实际值，以及已打勾的动作
public struct TaskProgress: Codable, Hashable, Sendable {
    public var items: [SetSummary]
    public var doneIds: [String]

    public init(items: [SetSummary], doneIds: [String] = []) {
        self.items = items
        self.doneIds = doneIds
    }

    /// 初始进度：部分完成的记录 > 本地草稿 > 计划默认值
    public static func initial(planned: [Exercise], record: ExecutionRecord?, draft: TaskDraft?) -> TaskProgress {
        let base = summaries(fromPlan: planned)
        if record?.status == .partial, let sets = record?.sets, !sets.isEmpty {
            let logged = summarizeSets(sets)
            return TaskProgress(items: base.map { b in logged.first { $0.exerciseId == b.exerciseId } ?? b },
                                doneIds: logged.map(\.exerciseId))
        }
        if let draft {
            return TaskProgress(items: base.map { b in draft.items.first { $0.exerciseId == b.exerciseId } ?? b },
                                doneIds: draft.doneIds)
        }
        return TaskProgress(items: base)
    }

    public func isDone(_ exerciseId: String) -> Bool { doneIds.contains(exerciseId) }

    public mutating func toggle(_ exerciseId: String) {
        if let i = doneIds.firstIndex(of: exerciseId) { doneIds.remove(at: i) } else { doneIds.append(exerciseId) }
    }

    /// 已打勾的计划动作数
    public func doneCount(planned: [Exercise]) -> Int { planned.filter { doneIds.contains($0.id) }.count }

    public func allDone(planned: [Exercise]) -> Bool { !planned.isEmpty && doneCount(planned: planned) == planned.count }

    /// 要保存的草稿；一个都没勾时不保存
    public var draft: TaskDraft? { doneIds.isEmpty ? nil : TaskDraft(doneIds: doneIds, items: items) }
}

/// 用户在任务上的操作
public enum TaskOutcome: Hashable, Sendable {
    /// 完成（或保存进度：勾选数少于计划时记为部分完成）
    case done
    case snoozed
    case skipped(SkipReason)
}

/// 提交时由界面给出的内容；id、日期、版本、时间戳由 `PersistedState.record` 补全
public struct RecordDraft: Hashable, Sendable {
    public var taskId: String
    public var status: RecordStatus
    public var skipReason: SkipReason?
    public var sets: [SetLog]?
    public var notes: String
    public var painScore: Int?
    public var fatigueScore: Int?
    public var startedAt: String?

    public init(taskId: String, status: RecordStatus, skipReason: SkipReason? = nil, sets: [SetLog]? = nil, notes: String = "",
                painScore: Int? = nil, fatigueScore: Int? = nil, startedAt: String? = nil) {
        self.taskId = taskId
        self.status = status
        self.skipReason = skipReason
        self.sets = sets
        self.notes = notes
        self.painScore = painScore
        self.fatigueScore = fatigueScore
        self.startedAt = startedAt
    }

    /// 由今日任务的操作生成记录内容。
    /// 完成时：勾选过动作就只记录勾选的；一个都没勾时视为按计划全部完成。
    public static func make(task: PlanTask, planned: [Exercise], progress: TaskProgress, outcome: TaskOutcome,
                            notes: String, painScore: Int?, now: Date = Date()) -> RecordDraft {
        switch outcome {
        case .done:
            let at = Timestamp.string(from: now)
            let chosen = progress.doneIds.isEmpty ? progress.items : progress.items.filter { progress.doneIds.contains($0.exerciseId) }
            let sets = planned.isEmpty ? nil : expandSets(chosen.filter { $0.sets > 0 }, completedAt: at)
            return RecordDraft(taskId: task.id, status: sets.map { statusForSets(planned: planned, sets: $0) } ?? .completed,
                               sets: sets, notes: notes, painScore: task.type == .workout ? painScore : nil)
        case .snoozed:
            return RecordDraft(taskId: task.id, status: .snoozed, notes: notes)
        case .skipped(let reason):
            return RecordDraft(taskId: task.id, status: .skipped, skipReason: reason, notes: notes)
        }
    }
}

extension SkipReason {
    public var label: String {
        switch self {
        case .pain: return "疼痛"
        case .noTime: return "没时间"
        case .sick: return "生病"
        case .other: return "其他"
        }
    }
}

extension RecordStatus {
    public var label: String {
        switch self {
        case .completed: return "完成"
        case .partial: return "部分完成"
        case .skipped: return "跳过"
        case .snoozed: return "延后"
        }
    }
}
