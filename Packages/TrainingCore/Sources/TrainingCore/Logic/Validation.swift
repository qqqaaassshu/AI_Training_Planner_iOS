import Foundation

/// 导入数据校验与归一化，规则与 Resources/*.schema.json 保持一致（对应原型 utils/validate.ts）。
/// 校验失败时返回全部错误（带字段路径），而不是悄悄丢弃数据。
public enum ValidationResult<T: Sendable>: Sendable {
    case ok(T)
    case failure([String])

    public var value: T? { if case .ok(let v) = self { return v }; return nil }
    public var errors: [String] { if case .failure(let e) = self { return e }; return [] }
    public var isOK: Bool { value != nil }
}

private func isPosInt(_ v: JSONValue?) -> Bool { (v?.intValue ?? 0) >= 1 }
private func isNonNegInt(_ v: JSONValue?) -> Bool { (v?.intValue ?? -1) >= 0 }
private func isNonEmptyStr(_ v: JSONValue?) -> Bool { !(v?.stringValue?.trimmed.isEmpty ?? true) }
private func optStr(_ o: [String: JSONValue], _ key: String) -> String? {
    guard let s = o[key]?.stringValue?.trimmed, !s.isEmpty else { return nil }
    return s
}
nonisolated(unsafe) private let timeRegex = jsRegex(#"^([01]\d|2[0-3]):[0-5]\d$"#)

private func checkExercise(_ raw: JSONValue, _ path: String, _ errors: inout [String]) -> Exercise? {
    guard let o = raw.objectValue else {
        errors.append("\(path)：应为对象")
        return nil
    }
    let start = errors.count
    if !isNonEmptyStr(o["name"]) { errors.append("\(path).name：缺少动作名称") }
    if !isPosInt(o["sets"]) { errors.append("\(path).sets：应为 ≥1 的整数") }
    let hasReps = o["reps"] != nil, hasDur = o["duration_sec"] != nil
    if !hasReps && !hasDur { errors.append("\(path)：reps 与 duration_sec 至少填一个") }
    if hasReps && !isPosInt(o["reps"]) { errors.append("\(path).reps：应为 ≥1 的整数") }
    if hasDur && !isPosInt(o["duration_sec"]) { errors.append("\(path).duration_sec：应为 ≥1 的整数（秒）") }
    if let w = o["weight_kg"], !((w.numberValue ?? -1) >= 0) { errors.append("\(path).weight_kg：应为 ≥0 的数字") }
    if o["rest_sec"] != nil && !isNonNegInt(o["rest_sec"]) { errors.append("\(path).rest_sec：应为 ≥0 的整数（秒）") }
    guard errors.count == start else { return nil }

    return Exercise(
        id: optStr(o, "id") ?? newId(),
        name: o["name"]!.stringValue!.trimmed,
        sets: o["sets"]!.intValue!,
        reps: hasReps ? o["reps"]!.intValue : nil,
        durationSec: hasDur ? o["duration_sec"]!.intValue : nil,
        weightKg: o["weight_kg"]?.numberValue,
        restSec: o["rest_sec"]?.intValue,
        cue: optStr(o, "cue")
    )
}

private func checkExercises(_ raw: JSONValue?, _ path: String, _ errors: inout [String]) -> [Exercise]? {
    guard let raw else { return nil }
    guard let arr = raw.arrayValue else {
        errors.append("\(path)：应为数组")
        return nil
    }
    return arr.enumerated().compactMap { i, e in checkExercise(e, "\(path)[\(i)]", &errors) }
}

private func checkTask(_ raw: JSONValue, _ path: String, _ errors: inout [String]) -> PlanTask? {
    guard let o = raw.objectValue else {
        errors.append("\(path)：应为对象")
        return nil
    }
    let start = errors.count
    if !isNonEmptyStr(o["title"]) { errors.append("\(path).title：缺少任务名称") }
    let type = o["type"]?.stringValue.flatMap(TaskType.init(rawValue:))
    if type == nil { errors.append("\(path).type：应为 \"workout\" 或 \"habit\"") }

    var schedule = TaskSchedule()
    if let sched = o["schedule"]?.objectValue {
        let weekday = sched["weekday"]
        let days = weekday?.arrayValue?.map { $0.intValue }
        let weekdayOK = days.map { !$0.isEmpty && $0.allSatisfy { ($0 ?? -1) >= 0 && ($0 ?? 7) <= 6 } } ?? false
        if weekday != nil && !weekdayOK { errors.append("\(path).schedule.weekday：应为 0-6 的整数数组（0=周日）") }
        let daily = sched["daily"]?.boolValue == true
        if !daily && !weekdayOK { errors.append("\(path).schedule：需设置 daily: true 或 weekday") }
        if let t = sched["time"], !(t.stringValue?.matches(timeRegex) ?? false) {
            errors.append("\(path).schedule.time：格式应为 HH:mm")
        }
        schedule = daily ? TaskSchedule(daily: true) : TaskSchedule(weekday: weekdayOK ? Array(Set(days!.map { $0! })).sorted() : [])
        schedule.time = sched["time"]?.stringValue
    } else {
        errors.append("\(path).schedule：缺少日程")
    }

    let exercises = checkExercises(o["exercises"], "\(path).exercises", &errors)

    var phases: [TaskPhase]?
    if let rawPhases = o["phases"] {
        if let arr = rawPhases.arrayValue {
            phases = []
            for (i, p) in arr.enumerated() {
                let pp = "\(path).phases[\(i)]"
                guard let po = p.objectValue else {
                    errors.append("\(pp)：应为对象")
                    continue
                }
                guard isPosInt(po["week_from"]), isPosInt(po["week_to"]), po["week_to"]!.intValue! >= po["week_from"]!.intValue! else {
                    errors.append("\(pp)：week_from / week_to 应为 ≥1 的整数且 week_from ≤ week_to")
                    continue
                }
                let exs = checkExercises(po["exercises"], "\(pp).exercises", &errors) ?? []
                phases!.append(TaskPhase(weekFrom: po["week_from"]!.intValue!, weekTo: po["week_to"]!.intValue!, exercises: exs))
            }
        } else {
            errors.append("\(path).phases：应为数组")
        }
    }

    guard errors.count == start, let type else { return nil }
    return PlanTask(
        id: optStr(o, "id") ?? newId(),
        title: o["title"]!.stringValue!.trimmed,
        type: type,
        schedule: schedule,
        exercises: (exercises?.isEmpty ?? true) ? nil : exercises,
        phases: (phases?.isEmpty ?? true) ? nil : phases,
        reminder: o["reminder"] == nil ? true : o["reminder"]?.boolValue == true
    )
}

public func validatePlanInput(_ raw: JSONValue) -> ValidationResult<PlanInput> {
    guard let o = raw.objectValue else { return .failure(["计划应为 JSON 对象"]) }
    var errors: [String] = []

    if !isNonEmptyStr(o["plan_name"]) { errors.append("plan_name：缺少计划名称") }
    let start = o["start_date"]?.stringValue.flatMap(LocalDate.init)
    if start == nil { errors.append("start_date：应为有效日期 YYYY-MM-DD") }
    let end = o["end_date"]?.stringValue.flatMap(LocalDate.init)
    if o["end_date"] != nil && end == nil { errors.append("end_date：应为有效日期 YYYY-MM-DD") }
    if let s = start, let e = end, e < s { errors.append("end_date：不能早于 start_date") }

    var tasks: [PlanTask] = []
    if let arr = o["tasks"]?.arrayValue, !arr.isEmpty {
        tasks = arr.enumerated().compactMap { i, t in checkTask(t, "tasks[\(i)]", &errors) }
        var seen = Set<String>()
        if let dup = tasks.map(\.id).first(where: { !seen.insert($0).inserted }) {
            errors.append("tasks：任务 id \"\(dup)\" 重复")
        }
    } else {
        errors.append("tasks：至少需要一个任务")
    }

    guard errors.isEmpty, let start else { return .failure(errors) }
    return .ok(PlanInput(
        planName: o["plan_name"]!.stringValue!.trimmed,
        startDate: start,
        endDate: end,
        timezone: optStr(o, "timezone"),
        aiSummary: optStr(o, "ai_summary"),
        changeNote: optStr(o, "change_note"),
        tasks: tasks
    ))
}

/// 从 JSON 文本校验计划（文本不是合法 JSON 时也返回错误而不是抛出）
public func validatePlanInput(json text: String) -> ValidationResult<PlanInput> {
    guard let raw = try? JSONValue.parse(text) else { return .failure(["不是有效的 JSON"]) }
    return validatePlanInput(raw)
}

public func validateAIAnalysisOutput(_ raw: JSONValue) -> ValidationResult<AIAnalysisOutput> {
    guard let o = raw.objectValue else { return .failure(["分析结果应为 JSON 对象"]) }
    var errors: [String] = []
    if !isNonEmptyStr(o["summary"]) { errors.append("summary：缺少总结") }

    var findings: [Finding] = []
    if let arr = o["findings"]?.arrayValue {
        for (i, f) in arr.enumerated() {
            if let level = f["level"]?.stringValue.flatMap(FindingLevel.init(rawValue:)), isNonEmptyStr(f["text"]) {
                findings.append(Finding(level: level, text: f["text"]!.stringValue!.trimmed))
            } else {
                errors.append("findings[\(i)]：需要 level（info/warn/risk）与 text")
            }
        }
    } else {
        errors.append("findings：应为数组")
    }

    var suggested: PlanInput?
    if let sp = o["suggested_plan"], sp != .null {
        switch validatePlanInput(sp) {
        case .ok(let p): suggested = p
        case .failure(let e): errors += e.map { "suggested_plan.\($0)" }
        }
    }

    guard errors.isEmpty else { return .failure(errors) }
    return .ok(AIAnalysisOutput(summary: o["summary"]!.stringValue!.trimmed, findings: findings, suggestedPlan: suggested))
}

public struct JSONExtractionError: Error, LocalizedError, Equatable {
    public var errorDescription: String? { "未找到有效的 JSON" }
}

nonisolated(unsafe) private let fencedRegex = jsRegex(#"```(?:json)?\s*([\s\S]*?)```"#)

/// 从 AI 回复文本中提取 JSON（兼容 ```json 代码块与前后说明文字）
public func extractJSON(_ text: String) throws -> JSONValue {
    let candidate = text.firstMatchGroups(fencedRegex)?[1] ?? text
    if let v = try? JSONValue.parse(candidate) { return v }
    if let first = candidate.firstIndex(of: "{"), let last = candidate.lastIndex(of: "}"), first < last,
       let v = try? JSONValue.parse(String(candidate[first...last])) {
        return v
    }
    throw JSONExtractionError()
}
