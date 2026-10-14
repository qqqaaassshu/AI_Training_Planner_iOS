import Foundation

// 对应原型 utils/nlImport.ts：把“深蹲3组10次”这类文字解析成计划

private let weekdayMap: [(String, Int)] = [
    ("星期一", 1), ("星期二", 2), ("星期三", 3), ("星期四", 4), ("星期五", 5), ("星期六", 6), ("星期日", 0), ("星期天", 0),
    ("周一", 1), ("周二", 2), ("周三", 3), ("周四", 4), ("周五", 5), ("周六", 6), ("周日", 0), ("周天", 0),
]

private let num = #"(\d+)"#
private let unitSec = #"(秒|s|sec|分钟|分|min)"#
private let weight = #"(?:\s*[@，,]?\s*(\d+(?:\.\d+)?)\s*(?:kg|公斤|KG|Kg))?"#

private enum PatternKind { case reps, duration, singleDuration }

/// 依次尝试的动作格式
nonisolated(unsafe) private let exercisePatterns: [(Regex<AnyRegexOutput>, PatternKind)] = [
    // 深蹲3组10次 / 深蹲 3组 x 10次 / 深蹲3组每组10个
    (jsRegex(#"^(.+?)\s*"# + num + #"\s*组\s*(?:[x×X*]|每组)?\s*"# + num + #"\s*(?:次|个|下)"# + weight), .reps),
    // 平板支撑3组30秒 / 3组x1分钟
    (jsRegex(#"^(.+?)\s*"# + num + #"\s*组\s*(?:[x×X*]|每组)?\s*"# + num + #"\s*"# + unitSec + weight), .duration),
    // 平板支撑 3x30秒（必须先于次数格式，避免把 30 拆成 3 + 0）
    (jsRegex(#"^(.+?)\s*"# + num + #"\s*[x×X*]\s*"# + num + #"\s*"# + unitSec + weight), .duration),
    // 深蹲 3x10 / 深蹲3×10 20kg
    (jsRegex(#"^(.+?)\s*"# + num + #"\s*[x×X*]\s*"# + num + #"(?![\d.])"# + weight), .reps),
    // 深蹲 3组 10
    (jsRegex(#"^(.+?)\s+"# + num + #"\s*组\s*"# + num + #"\s*$"#), .reps),
    // 平板支撑60秒（单组计时）
    (jsRegex(#"^(.+?)\s*"# + num + #"\s*"# + unitSec + #"$"#), .singleDuration),
]

/// 列表符号：- • * · 或 “1.” “2、” “3)”
nonisolated(unsafe) private let listMarker = jsRegex(#"^(?:[-•*·]|\d+[.、)）])\s*"#)
nonisolated(unsafe) private let habitHint = jsRegex("散步|走路|睡|起床|水果|喝水|冥想|拉伸|习惯|步|蔬菜|早餐|午餐|晚餐|戒")
nonisolated(unsafe) private let minuteUnit = jsRegex("分|min")
nonisolated(unsafe) private let trailingPunct = jsRegex("[：:，,]$")
nonisolated(unsafe) private let timeRegex = jsRegex(#"\b([01]?\d|2[0-3])[:：]([0-5]\d)\b"#)
nonisolated(unsafe) private let timeAnywhere = jsRegex(#"([01]?\d|2[0-3])[:：][0-5]\d"#)
nonisolated(unsafe) private let compactWeekdays = jsRegex("(?:周|星期)([一二三四五六日天](?:[、,，/和及]?[一二三四五六日天])+)")
nonisolated(unsafe) private let dateRegex = jsRegex(#"\d{4}-\d{2}-\d{2}"#)
nonisolated(unsafe) private let planNameRegex = jsRegex(#"^(?:计划名称|计划)[：:]\s*(.+)$"#)

private func stripListMarker(_ s: String) -> String { s.replacing(listMarker, with: "", maxReplacements: 1) }

private func toSeconds(_ n: Int, _ unit: String) -> Int { unit.matches(minuteUnit) ? n * 60 : n }

/// 解析一行动作；不是动作时返回 nil
public func parseExerciseLine(_ line: String) -> Exercise? {
    let text = stripListMarker(line.trimmed).trimmed
    guard !text.isEmpty else { return nil }

    for (re, kind) in exercisePatterns {
        guard let m = text.firstMatchGroups(re) else { continue }
        let name = m[1]!.trimmed.replacing(trailingPunct, with: "")
        guard !name.isEmpty else { continue }
        var ex = Exercise(name: name, sets: 1)
        func int(_ i: Int) -> Int { Int(m[i] ?? "") ?? 0 }
        switch kind {
        case .singleDuration:
            ex.durationSec = toSeconds(int(2), m[3]!)
        case .duration:
            ex.sets = int(2)
            ex.durationSec = toSeconds(int(3), m[4]!)
            if let w = m[5] { ex.weightKg = Double(w) }
        case .reps:
            ex.sets = int(2)
            ex.reps = int(3)
            if m.count > 4, let w = m[4] { ex.weightKg = Double(w) }
        }
        if ex.sets < 1 || (ex.reps.map { $0 < 1 } ?? false) || (ex.durationSec.map { $0 < 1 } ?? false) { return nil }
        return ex
    }
    return nil
}

private func parseWeekdays(_ text: String) -> [Int]? {
    var days = Set<Int>()
    var rest = text
    for (label, n) in weekdayMap where rest.contains(label) {
        days.insert(n)
        rest = rest.replacingOccurrences(of: label, with: "")
    }
    // 周一三五 / 周二、四
    if let g = text.firstMatchGroups(compactWeekdays), let chars = g[1] {
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 0, "天": 0]
        for ch in chars { if let n = map[ch] { days.insert(n) } }
    }
    return days.isEmpty ? nil : days.sorted()
}

private func parseTime(_ text: String) -> String? {
    guard let g = text.firstMatchGroups(timeRegex), let h = g[1], let m = g[2] else { return nil }
    return "\(h.leftPadded(to: 2)):\(m)"
}

private func isHeader(_ line: String) -> Bool {
    if line.matches(jsRegex("[：:]$")) { return true }
    if line.matches(jsRegex("(训练|习惯|日常)$")) { return true }
    return line.matches(jsRegex("^(周[一二三四五六日天]|星期|每日|每天)")) && parseExerciseLine(line) == nil
}

public struct NLParseResult: Sendable {
    public var plan: PlanInput
    /// 未能识别的行，导入前展示给用户确认
    public var warnings: [String]
}

public struct NLParseError: Error, LocalizedError, Equatable {
    public var errorDescription: String? { "未能识别训练内容，请检查格式（例如：深蹲3组10次、平板支撑3组30秒）" }
}

public func parseNaturalLanguagePlan(_ text: String, today: LocalDate = .today()) throws -> NLParseResult {
    let lines = text.components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty }
    var tasks: [PlanTask] = []
    var warnings: [String] = []
    var planName = "自然语言导入计划"
    var startDate = today
    var endDate: LocalDate?
    var current: PlanTask?
    var habitSchedule: TaskSchedule?

    func flush() {
        if let t = current {
            if !(t.exercises ?? []).isEmpty { tasks.append(t) } else { warnings.append("「\(t.title)」下没有识别到动作，已忽略") }
        }
        current = nil
    }

    func makeHabit(_ line: String, base: TaskSchedule?) -> PlanTask {
        let title = stripListMarker(line).trimmed
        var schedule: TaskSchedule
        if let w = parseWeekdays(title) { schedule = TaskSchedule(weekday: w) }
        else if let b = base { schedule = b }
        else { schedule = TaskSchedule(daily: true) }
        if let t = parseTime(title) { schedule.time = t }
        return PlanTask(title: title, type: .habit, schedule: schedule, reminder: true)
    }

    for (idx, line) in lines.enumerated() {
        // 元信息
        if let g = line.firstMatchGroups(planNameRegex), let n = g[1] {
            planName = n.trimmed
            continue
        }
        if line.matches(jsRegex("开始|起始")), let g = line.firstMatchGroups(dateRegex) {
            if let d = LocalDate(g[0]!) { startDate = d }
            continue
        }
        if line.matches(jsRegex("结束|截止")), let g = line.firstMatchGroups(dateRegex) {
            if let d = LocalDate(g[0]!) { endDate = d }
            continue
        }
        if idx == 0 && line.matches(jsRegex("计划$")) && parseExerciseLine(line) == nil {
            planName = line
            continue
        }

        if isHeader(line) {
            flush()
            let header = line.replacing(jsRegex("[：:]$"), with: "").trimmed
            var title = header.replacing(timeAnywhere, with: "", maxReplacements: 1)
                .replacing(jsRegex(#"\s+"#), with: " ").trimmed
            if title.isEmpty { title = header }
            let weekday = parseWeekdays(title)
            let daily = title.matches(jsRegex("每日|每天")) || weekday == nil
            var schedule = daily ? TaskSchedule(daily: true) : TaskSchedule(weekday: weekday)
            if let t = parseTime(header) { schedule.time = t }

            if title.matches(jsRegex("习惯|日常")) {
                habitSchedule = schedule
            } else {
                habitSchedule = nil
                current = PlanTask(title: title, type: .workout, schedule: schedule, exercises: [], reminder: true)
            }
            continue
        }

        if let hs = habitSchedule {
            tasks.append(makeHabit(line, base: hs))
            continue
        }

        if current == nil && line.matches(habitHint) {
            tasks.append(makeHabit(line, base: nil))
            continue
        }

        if let ex = parseExerciseLine(line) {
            if current == nil {
                current = PlanTask(title: "训练", type: .workout, schedule: TaskSchedule(daily: true), exercises: [], reminder: true)
            }
            current!.exercises!.append(ex)
            continue
        }

        if line.matches(habitHint) {
            tasks.append(makeHabit(line, base: nil))
            continue
        }

        warnings.append("未识别：\(line)")
    }
    flush()

    guard !tasks.isEmpty else { throw NLParseError() }
    return NLParseResult(plan: PlanInput(planName: planName, startDate: startDate, endDate: endDate, tasks: tasks), warnings: warnings)
}
