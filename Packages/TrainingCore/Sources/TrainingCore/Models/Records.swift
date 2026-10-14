import Foundation

public enum RecordStatus: String, Codable, Hashable, Sendable {
    case completed
    /// 实际组数少于计划组数时自动判定
    case partial
    case skipped
    /// 延后，当天仍可再完成
    case snoozed
}

public enum SkipReason: String, Codable, Hashable, Sendable, CaseIterable, CodingKeyRepresentable {
    case pain
    case noTime = "no_time"
    case sick
    case other
}

public enum RecordSource: String, Codable, Hashable, Sendable {
    case phone, watch
}

public struct SetLog: Codable, Hashable, Sendable {
    public var exerciseId: String
    /// 冗余保存动作名，计划变更或自定义动作时仍可读
    public var exerciseName: String
    /// 从 1 开始
    public var setIndex: Int
    public var reps: Int?
    public var durationSec: Int?
    public var weightKg: Double?
    public var completedAt: String

    public init(exerciseId: String, exerciseName: String, setIndex: Int, reps: Int? = nil,
                durationSec: Int? = nil, weightKg: Double? = nil, completedAt: String) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.reps = reps
        self.durationSec = durationSec
        self.weightKg = weightKg
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case reps
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case setIndex = "set_index"
        case durationSec = "duration_sec"
        case weightKg = "weight_kg"
        case completedAt = "completed_at"
    }
}

/// 每个任务每天最多一条记录，再次提交时覆盖原记录（保留原 id）
public struct ExecutionRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var planVersionId: String
    public var date: LocalDate
    public var status: RecordStatus
    public var skipReason: SkipReason?
    public var sets: [SetLog]?
    /// 0–10
    public var painScore: Int?
    /// 0–10
    public var fatigueScore: Int?
    public var notes: String
    public var source: RecordSource
    public var startedAt: String?
    public var completedAt: String?
    public var updatedAt: String
    /// 预留：对应 HealthKit HKWorkout 的 UUID
    public var healthWorkoutId: String?

    public init(id: String = newId(), taskId: String, planVersionId: String, date: LocalDate, status: RecordStatus,
                skipReason: SkipReason? = nil, sets: [SetLog]? = nil, painScore: Int? = nil, fatigueScore: Int? = nil,
                notes: String = "", source: RecordSource, startedAt: String? = nil, completedAt: String? = nil,
                updatedAt: String, healthWorkoutId: String? = nil) {
        self.id = id
        self.taskId = taskId
        self.planVersionId = planVersionId
        self.date = date
        self.status = status
        self.skipReason = skipReason
        self.sets = sets
        self.painScore = painScore
        self.fatigueScore = fatigueScore
        self.notes = notes
        self.source = source
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.healthWorkoutId = healthWorkoutId
    }

    enum CodingKeys: String, CodingKey {
        case id, date, status, sets, notes, source
        case taskId = "task_id"
        case planVersionId = "plan_version_id"
        case skipReason = "skip_reason"
        case painScore = "pain_score"
        case fatigueScore = "fatigue_score"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case healthWorkoutId = "health_workout_id"
    }
}

public struct DailyWellness: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var fatigueScore: Int
    public var sleepHours: Double?
    public var updatedAt: String

    public init(date: LocalDate, fatigueScore: Int, sleepHours: Double? = nil, updatedAt: String) {
        self.date = date
        self.fatigueScore = fatigueScore
        self.sleepHours = sleepHours
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case date
        case fatigueScore = "fatigue_score"
        case sleepHours = "sleep_hours"
        case updatedAt = "updated_at"
    }
}

/// 统计口径见 docs/data-model.md 与 `buildExportSummary`
public struct ExportSummary: Codable, Hashable, Sendable {
    /// 统计区间内应完成任务数（过去日期 + 今天已有记录的任务）
    public var scheduledCount: Int
    public var completedCount: Int
    public var partialCount: Int
    public var skippedCount: Int
    /// completed 计 1，partial 计 0.5，百分比取整
    public var completionRate: Int
    /// 过去日期中既没完成也没跳过的任务（“日期 · 标题”）
    public var missedTasks: [String]
    public var skipReasons: [SkipReason: Int]
    public var painAverage: Double
    public var painMax: Int
    public var fatigueAverage: Double

    enum CodingKeys: String, CodingKey {
        case scheduledCount = "scheduled_count"
        case completedCount = "completed_count"
        case partialCount = "partial_count"
        case skippedCount = "skipped_count"
        case completionRate = "completion_rate"
        case missedTasks = "missed_tasks"
        case skipReasons = "skip_reasons"
        case painAverage = "pain_average"
        case painMax = "pain_max"
        case fatigueAverage = "fatigue_average"
    }
}
