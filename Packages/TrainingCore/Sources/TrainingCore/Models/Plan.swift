import Foundation

/// 数据格式版本（docs/data-model.md v2）
public let schemaVersion = "2.0"

public struct Exercise: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var sets: Int
    /// 每组次数。与 durationSec 二选一
    public var reps: Int?
    /// 每组时长（秒），用于平板支撑等计时动作。与 reps 二选一
    public var durationSec: Int?
    public var weightKg: Double?
    /// 组间休息（秒），手表倒计时用，未设置时按 60 秒
    public var restSec: Int?
    /// 动作要点
    public var cue: String?

    public init(id: String = newId(), name: String, sets: Int, reps: Int? = nil, durationSec: Int? = nil,
                weightKg: Double? = nil, restSec: Int? = nil, cue: String? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.durationSec = durationSec
        self.weightKg = weightKg
        self.restSec = restSec
        self.cue = cue
    }

    public static let defaultRestSec = 60

    enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, cue
        case durationSec = "duration_sec"
        case weightKg = "weight_kg"
        case restSec = "rest_sec"
    }
}

/// 按周渐进：weekFrom ~ weekTo（含）期间用 exercises 覆盖任务默认动作
public struct TaskPhase: Codable, Hashable, Sendable {
    public var weekFrom: Int
    public var weekTo: Int
    public var exercises: [Exercise]

    public init(weekFrom: Int, weekTo: Int, exercises: [Exercise]) {
        self.weekFrom = weekFrom
        self.weekTo = weekTo
        self.exercises = exercises
    }

    enum CodingKeys: String, CodingKey {
        case exercises
        case weekFrom = "week_from"
        case weekTo = "week_to"
    }
}

public struct TaskSchedule: Codable, Hashable, Sendable {
    public var daily: Bool?
    /// 0 = 周日 … 6 = 周六
    public var weekday: [Int]?
    /// HH:mm，本地时间（按计划的 timezone）
    public var time: String?

    public init(daily: Bool? = nil, weekday: [Int]? = nil, time: String? = nil) {
        self.daily = daily
        self.weekday = weekday
        self.time = time
    }

    public static func everyDay(at time: String? = nil) -> TaskSchedule { TaskSchedule(daily: true, time: time) }
    public static func weekdays(_ days: [Int], at time: String? = nil) -> TaskSchedule { TaskSchedule(weekday: days, time: time) }

    /// 解析 time 为 (时, 分)
    public var hourMinute: (hour: Int, minute: Int)? {
        guard let t = time, let groups = t.firstMatchGroups(jsRegex(#"^([01]\d|2[0-3]):([0-5]\d)$"#)),
              let h = groups[1].flatMap({ Int($0) }), let m = groups[2].flatMap({ Int($0) }) else { return nil }
        return (h, m)
    }
}

public enum TaskType: String, Codable, Hashable, Sendable {
    case workout, habit
}

public struct PlanTask: Codable, Hashable, Sendable, Identifiable {
    /// 跨版本保持不变，用于版本对比与历史统计
    public var id: String
    public var title: String
    public var type: TaskType
    public var schedule: TaskSchedule
    public var exercises: [Exercise]?
    public var phases: [TaskPhase]?
    public var reminder: Bool

    public init(id: String = newId(), title: String, type: TaskType, schedule: TaskSchedule,
                exercises: [Exercise]? = nil, phases: [TaskPhase]? = nil, reminder: Bool = true) {
        self.id = id
        self.title = title
        self.type = type
        self.schedule = schedule
        self.exercises = exercises
        self.phases = phases
        self.reminder = reminder
    }
}

public enum PlanSource: String, Codable, Hashable, Sendable {
    case jsonImport = "json_import"
    case nlImport = "nl_import"
    case aiAnalysis = "ai_analysis"
    case manual
}

public struct PlanVersion: Codable, Hashable, Sendable, Identifiable {
    public var schemaVersion: String
    public var id: String
    public var version: Int
    public var planName: String
    /// ISO 8601
    public var createdAt: String
    /// IANA 时区，如 "Asia/Shanghai"
    public var timezone: String
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var parentVersionId: String?
    public var source: PlanSource
    /// 由哪次 AI 分析生成
    public var analysisId: String?
    /// 本版本相对上一版的调整说明
    public var changeNote: String?
    public var aiSummary: String?
    public var tasks: [PlanTask]

    public init(schemaVersion: String = TrainingCore.schemaVersion, id: String = newId(), version: Int, planName: String,
                createdAt: String, timezone: String, startDate: LocalDate, endDate: LocalDate? = nil,
                parentVersionId: String? = nil, source: PlanSource, analysisId: String? = nil,
                changeNote: String? = nil, aiSummary: String? = nil, tasks: [PlanTask]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.planName = planName
        self.createdAt = createdAt
        self.timezone = timezone
        self.startDate = startDate
        self.endDate = endDate
        self.parentVersionId = parentVersionId
        self.source = source
        self.analysisId = analysisId
        self.changeNote = changeNote
        self.aiSummary = aiSummary
        self.tasks = tasks
    }

    /// 计划时区；无效时用设备时区
    public var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    enum CodingKeys: String, CodingKey {
        case id, version, timezone, source, tasks
        case schemaVersion = "schema_version"
        case planName = "plan_name"
        case createdAt = "created_at"
        case startDate = "start_date"
        case endDate = "end_date"
        case parentVersionId = "parent_version_id"
        case analysisId = "analysis_id"
        case changeNote = "change_note"
        case aiSummary = "ai_summary"
    }
}

/// 导入 / AI 输出的计划内容（不含由 App 分配的版本元数据），对应 plan.schema.json
public struct PlanInput: Codable, Hashable, Sendable {
    public var planName: String
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var timezone: String?
    public var aiSummary: String?
    public var changeNote: String?
    public var tasks: [PlanTask]

    public init(planName: String, startDate: LocalDate, endDate: LocalDate? = nil, timezone: String? = nil,
                aiSummary: String? = nil, changeNote: String? = nil, tasks: [PlanTask]) {
        self.planName = planName
        self.startDate = startDate
        self.endDate = endDate
        self.timezone = timezone
        self.aiSummary = aiSummary
        self.changeNote = changeNote
        self.tasks = tasks
    }

    enum CodingKeys: String, CodingKey {
        case timezone, tasks
        case planName = "plan_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case aiSummary = "ai_summary"
        case changeNote = "change_note"
    }
}
