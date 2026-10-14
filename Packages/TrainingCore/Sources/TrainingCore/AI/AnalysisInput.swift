import Foundation

// 对应原型 utils/analysis.ts：不论走 API 还是“导出 → 外部 AI → 粘贴回来”，
// 都使用同一份输入（buildAnalysisInput）、同一套提示词（buildPrompt）和同一份输出格式。

// MARK: 本地安全规则（不依赖 AI，离线也生效）

public let painRisk = 7
public let painWarn = 5

/// 最近 7 天的本地风险检测
public func detectAlerts(records: [ExecutionRecord], wellness: [DailyWellness], today: LocalDate) -> [Finding] {
    let from = today.adding(days: -6)
    let recent = records.filter { $0.date >= from && $0.date <= today }.sortedStable { $0.date < $1.date }
    var findings: [Finding] = []

    let maxPain = recent.map { $0.painScore ?? -1 }.max() ?? -1
    if maxPain >= painRisk {
        findings.append(Finding(level: .risk, text: "近 7 天出现疼痛 \(maxPain)/10，建议暂停相关动作，疼痛持续请就医"))
    } else {
        let lastTwo = recent.filter { $0.painScore != nil }.suffix(2)
        if lastTwo.count == 2 && lastTwo.allSatisfy({ $0.painScore! >= painWarn }) {
            findings.append(Finding(level: .warn, text: "最近两次训练疼痛都在 \(painWarn) 分以上，建议降低强度"))
        }
    }

    let painSkips = recent.filter { $0.status == .skipped && $0.skipReason == .pain }.count
    if painSkips >= 2 { findings.append(Finding(level: .warn, text: "近 7 天有 \(painSkips) 次因疼痛跳过训练")) }

    let skips = recent.filter { $0.status == .skipped }.count
    if skips >= 3 { findings.append(Finding(level: .warn, text: "近 7 天跳过 \(skips) 次任务，计划可能偏重")) }

    let lastFatigue = wellness.filter { $0.date >= today.adding(days: -2) && $0.date <= today }.map(\.fatigueScore)
    if lastFatigue.count >= 2 && lastFatigue.allSatisfy({ $0 >= 7 }) {
        findings.append(Finding(level: .warn, text: "连续多日疲劳 7 分以上，注意恢复和睡眠"))
    }
    return findings
}

// MARK: 分析输入

public func defaultRange(kind: AnalysisKind, plan: PlanVersion?, today: LocalDate) -> DateRange {
    if kind == .planAdjustment, let plan {
        let from = max(plan.startDate, today.adding(days: -27))
        return DateRange(from: min(from, today), to: today)
    }
    return DateRange(from: today.adding(days: -6), to: today)
}

/// 发给 AI 的计划快照：不含 parent_version_id / analysis_id，附当前周与总周数
public struct AnalysisPlanSnapshot: Encodable, Sendable {
    public var schemaVersion: String
    public var id: String
    public var version: Int
    public var planName: String
    public var createdAt: String
    public var timezone: String
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var source: PlanSource
    public var changeNote: String?
    public var aiSummary: String?
    public var tasks: [PlanTask]
    public var currentWeek: Int
    public var totalWeeks: Int

    enum CodingKeys: String, CodingKey {
        case id, version, timezone, source, tasks
        case schemaVersion = "schema_version"
        case planName = "plan_name"
        case createdAt = "created_at"
        case startDate = "start_date"
        case endDate = "end_date"
        case changeNote = "change_note"
        case aiSummary = "ai_summary"
        case currentWeek = "current_week"
        case totalWeeks = "total_weeks"
    }
}

public struct AnalysisRecord: Encodable, Sendable {
    public struct SetItem: Encodable, Sendable {
        public var name: String
        public var sets: Int
        public var reps: Int?
        public var durationSec: Int?
        public var weightKg: Double?
        enum CodingKeys: String, CodingKey {
            case name, sets, reps
            case durationSec = "duration_sec"
            case weightKg = "weight_kg"
        }
    }
    public var date: LocalDate
    public var taskId: String
    public var taskTitle: String
    public var status: RecordStatus
    public var skipReason: SkipReason?
    public var sets: [SetItem]?
    public var painScore: Int?
    public var fatigueScore: Int?
    public var notes: String?
    public var source: RecordSource

    enum CodingKeys: String, CodingKey {
        case date, status, sets, notes, source
        case taskId = "task_id"
        case taskTitle = "task_title"
        case skipReason = "skip_reason"
        case painScore = "pain_score"
        case fatigueScore = "fatigue_score"
    }
}

public struct AnalysisWellness: Encodable, Sendable {
    public var date: LocalDate
    public var fatigueScore: Int
    public var sleepHours: Double?
    enum CodingKeys: String, CodingKey {
        case date
        case fatigueScore = "fatigue_score"
        case sleepHours = "sleep_hours"
    }
}

public struct PlanHistoryEntry: Encodable, Sendable {
    public struct Outcome: Encodable, Sendable {
        public var completionRate: Int
        public var scheduled: Int
        public var skipped: Int
        public var painAverage: Double
        public var painMax: Int
        public var fatigueAverage: Double
        enum CodingKeys: String, CodingKey {
            case scheduled, skipped
            case completionRate = "completion_rate"
            case painAverage = "pain_average"
            case painMax = "pain_max"
            case fatigueAverage = "fatigue_average"
        }
    }
    public var version: Int
    public var createdDate: LocalDate
    public var source: PlanSource
    public var changeNote: String?
    /// 相对上一版的具体变化
    public var changes: [String]
    /// 该版本使用期间（到下一版创建前一天）
    public var active: DateRange
    public var outcome: Outcome

    enum CodingKeys: String, CodingKey {
        case version, source, changes, active, outcome
        case createdDate = "created_date"
        case changeNote = "change_note"
    }
}

public struct AnalysisProfileChange: Encodable, Sendable {
    public var date: LocalDate?
    public var field: String
    public var from: String
    public var to: String
}

public struct AnalysisInput: Encodable, Sendable {
    public var schemaVersion: String
    public var kind: AnalysisKind
    public var today: LocalDate
    public var range: DateRange
    public var plan: AnalysisPlanSnapshot?
    public var summary: ExportSummary
    public var localAlerts: [Finding]
    public var records: [AnalysisRecord]
    public var dailyWellness: [AnalysisWellness]
    /// 历次计划版本：调整了什么，以及该版本使用期间的执行效果
    public var planHistory: [PlanHistoryEntry]
    /// 个人档案的变更记录（最近的在后）
    public var profileChanges: [AnalysisProfileChange]
    /// 用户为本次分析填写的补充说明（放在用户消息正文，不进数据 JSON）
    public var userNote: String?
    /// 写入系统提示词，不重复放进数据 JSON
    public var profile: UserProfile

    /// 不含 user_note 与 profile：这两项单独放进提示词
    enum CodingKeys: String, CodingKey {
        case kind, today, range, plan, summary, records
        case schemaVersion = "schema_version"
        case localAlerts = "local_alerts"
        case dailyWellness = "daily_wellness"
        case planHistory = "plan_history"
        case profileChanges = "profile_changes"
    }
}

let maxHistoryVersions = 5
let maxProfileChanges = 10

/// 最近几个版本的调整内容与执行效果，帮助 AI 判断上次调整是否有效
public func buildPlanHistory(versions: [PlanVersion], records: [ExecutionRecord], dailyWellness: [DailyWellness],
                             today: LocalDate, timeZone: TimeZone = .current) -> [PlanHistoryEntry] {
    let sorted = versions.sortedStable { $0.createdAt < $1.createdAt }
    let entries = sorted.enumerated().map { i, v -> PlanHistoryEntry in
        let created = Timestamp.localDate(of: v.createdAt, in: timeZone) ?? v.startDate
        let from = max(created, v.startDate)
        let to: LocalDate
        if i + 1 < sorted.count {
            to = (Timestamp.localDate(of: sorted[i + 1].createdAt, in: timeZone) ?? today).adding(days: -1)
        } else {
            to = today
        }
        var changes: [String] = []
        if let parent = versions.first(where: { $0.id == v.parentVersionId }) {
            let diff = comparePlanVersions(parent, v)
            changes = diff.added.map { "新增任务：\($0.taskTitle)" }
                + diff.removed.map { "删除任务：\($0.taskTitle)" }
                + diff.modified.flatMap { m in m.changes.map { "\(m.taskTitle) · \($0)" } }
        }
        let range = DateRange(from: from, to: to < from ? from : to)
        let s = buildExportSummary(plan: v, records: records, dailyWellness: dailyWellness, today: today, range: range)
        return PlanHistoryEntry(
            version: v.version, createdDate: created, source: v.source, changeNote: v.changeNote, changes: changes,
            active: range,
            outcome: .init(completionRate: s.completionRate, scheduled: s.scheduledCount, skipped: s.skippedCount,
                           painAverage: s.painAverage, painMax: s.painMax, fatigueAverage: s.fatigueAverage)
        )
    }
    return Array(entries.suffix(maxHistoryVersions))
}

/// - Parameter includeNotes: 是否包含文字备注（隐私：默认不发送原始备注）
public func buildAnalysisInput(kind: AnalysisKind, plan: PlanVersion?, versions: [PlanVersion], records: [ExecutionRecord],
                               dailyWellness: [DailyWellness], today: LocalDate, range explicitRange: DateRange? = nil,
                               includeNotes: Bool = false, profile: UserProfile = UserProfile(),
                               profileHistory: [ProfileChange] = [], userNote: String? = nil,
                               timeZone: TimeZone = .current) -> AnalysisInput {
    let range = explicitRange ?? defaultRange(kind: kind, plan: plan, today: today)
    let byVersionDesc = versions.sortedStable { $0.version > $1.version }
    func titleOf(_ taskId: String) -> String {
        for v in [plan].compactMap({ $0 }) + byVersionDesc {
            if let t = v.tasks.first(where: { $0.id == taskId }) { return t.title }
        }
        return taskId
    }

    let snapshot = plan.map { p in
        AnalysisPlanSnapshot(schemaVersion: p.schemaVersion, id: p.id, version: p.version, planName: p.planName,
                             createdAt: p.createdAt, timezone: p.timezone, startDate: p.startDate, endDate: p.endDate,
                             source: p.source, changeNote: p.changeNote, aiSummary: p.aiSummary, tasks: p.tasks,
                             currentWeek: p.currentWeek(today: today), totalWeeks: p.totalWeeks)
    }

    let recs = records.filter { range.contains($0.date) }.sortedStable { $0.date < $1.date }.map { r in
        AnalysisRecord(
            date: r.date, taskId: r.taskId, taskTitle: titleOf(r.taskId), status: r.status, skipReason: r.skipReason,
            sets: (r.sets?.isEmpty ?? true) ? nil : summarizeSets(r.sets!).map {
                .init(name: $0.name, sets: $0.sets, reps: $0.reps, durationSec: $0.durationSec, weightKg: $0.weightKg)
            },
            painScore: r.painScore, fatigueScore: r.fatigueScore,
            notes: includeNotes && !r.notes.isEmpty ? r.notes : nil, source: r.source
        )
    }

    let note = userNote?.trimmed
    return AnalysisInput(
        schemaVersion: schemaVersion,
        kind: kind,
        today: today,
        range: range,
        plan: snapshot,
        summary: buildExportSummary(plan: plan, records: records, dailyWellness: dailyWellness, today: today, range: range),
        localAlerts: detectAlerts(records: records, wellness: dailyWellness, today: today),
        records: recs,
        dailyWellness: dailyWellness.filter { range.contains($0.date) }
            .map { AnalysisWellness(date: $0.date, fatigueScore: $0.fatigueScore, sleepHours: $0.sleepHours) },
        planHistory: buildPlanHistory(versions: versions, records: records, dailyWellness: dailyWellness, today: today, timeZone: timeZone),
        profileChanges: profileHistory.suffix(maxProfileChanges).map {
            AnalysisProfileChange(date: Timestamp.localDate(of: $0.at, in: timeZone), field: $0.field.label,
                                  from: displayValue($0.field, $0.from), to: displayValue($0.field, $0.to))
        },
        userNote: (note?.isEmpty ?? true) ? nil : note,
        profile: profile
    )
}

extension Sequence {
    /// 稳定排序（与 JS Array.prototype.sort 一致：相等元素保持原顺序）
    func sortedStable(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in less(a.element, b.element) || (!less(b.element, a.element) && a.offset < b.offset) }
            .map(\.element)
    }
}
