import Foundation

// 对应原型 utils/plan.ts「版本」部分

/// 让新计划沿用上一版的任务 / 动作 id：
/// - 已存在于上一版的 id 保持不变
/// - 否则按任务标题（动作名称）匹配上一版，沿用其 id
/// 这样自然语言导入或 AI 未带 id 时，版本对比和历史统计仍然连续。
public func reconcileIds(_ tasks: [PlanTask], previous prev: PlanVersion?) -> [PlanTask] {
    guard let prev else { return tasks }
    let prevById = Dictionary(prev.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var claimed = Set(tasks.filter { prevById[$0.id] != nil }.map(\.id))

    return tasks.map { task in
        var prevTask = prevById[task.id]
        if prevTask == nil {
            prevTask = prev.tasks.first { !claimed.contains($0.id) && $0.title == task.title }
            if let p = prevTask { claimed.insert(p.id) }
        }
        guard let prevTask else { return task }

        let prevExercises = (prevTask.exercises ?? []) + (prevTask.phases?.flatMap(\.exercises) ?? [])
        func match(_ ex: Exercise) -> Exercise {
            guard let same = prevExercises.first(where: { $0.name == ex.name }) else { return ex }
            var e = ex
            e.id = same.id
            return e
        }
        var t = task
        t.id = prevTask.id
        t.exercises = task.exercises?.map(match)
        t.phases = task.phases?.map { p in
            var q = p
            q.exercises = p.exercises.map(match)
            return q
        }
        return t
    }
}

/// 生成新版本：version 依次 +1，parent 默认为当前最新版本
public func createPlanVersion(_ input: PlanInput, existing: [PlanVersion], source: PlanSource,
                              parent explicitParent: PlanVersion? = nil, analysisId: String? = nil,
                              now: Date = Date()) -> PlanVersion {
    let latest = existing.reduce(nil as PlanVersion?) { max, v in max == nil || v.version > max!.version ? v : max }
    let parent = explicitParent ?? latest
    return PlanVersion(
        version: (latest?.version ?? 0) + 1,
        planName: input.planName,
        createdAt: Timestamp.string(from: now),
        timezone: input.timezone ?? parent?.timezone ?? TimeZone.current.identifier,
        startDate: input.startDate,
        endDate: input.endDate,
        parentVersionId: parent?.id,
        source: source,
        analysisId: analysisId,
        changeNote: input.changeNote.flatMap { $0.isEmpty ? nil : $0 },
        aiSummary: input.aiSummary.flatMap { $0.isEmpty ? nil : $0 },
        tasks: reconcileIds(input.tasks, previous: parent)
    )
}

public struct PlanDiff: Hashable, Sendable {
    public struct TaskSummary: Hashable, Sendable {
        public var taskTitle: String
        public var exercises: [String]
    }
    public struct TaskChanges: Hashable, Sendable {
        public var taskTitle: String
        public var changes: [String]
    }
    public var added: [TaskSummary]
    public var removed: [TaskSummary]
    public var modified: [TaskChanges]

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }
}

let weekdayLabels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

func describeSchedule(_ s: TaskSchedule) -> String {
    let days = s.daily == true ? "每天" : (s.weekday ?? []).map { (0...6).contains($0) ? weekdayLabels[$0] : "\($0)" }.joined(separator: "、")
    return s.time.map { "\(days) \($0)" } ?? days
}

/// 按名称对比动作（顺序与原型 Map 一致：先按 b 的顺序列出新增/修改，再列出删除）
func diffExercises(_ a: [Exercise], _ b: [Exercise]) -> [String] {
    func byName(_ xs: [Exercise]) -> (order: [String], map: [String: Exercise]) {
        var order: [String] = [], map: [String: Exercise] = [:]
        for e in xs {
            if map[e.name] == nil { order.append(e.name) }
            map[e.name] = e
        }
        return (order, map)
    }
    let mA = byName(a), mB = byName(b)
    var changes: [String] = []
    for name in mB.order {
        let ex = mB.map[name]!
        if let prev = mA.map[name] {
            if prev.targetText != ex.targetText { changes.append("\(name)：\(prev.targetText) → \(ex.targetText)") }
        } else {
            changes.append("新增动作：\(name) \(ex.targetText)")
        }
    }
    for name in mA.order where mB.map[name] == nil { changes.append("删除动作：\(name)") }
    return changes
}

private func stripIds(_ phases: [TaskPhase]?) -> [TaskPhase]? {
    phases?.map { p in
        var q = p
        q.exercises = p.exercises.map { e in
            var x = e
            x.id = ""
            return x
        }
        return q
    }
}

/// 版本对比：任务按 id 匹配，找不到时按标题匹配
public func comparePlanVersions(_ a: PlanVersion, _ b: PlanVersion) -> PlanDiff {
    let aById = Dictionary(a.tasks.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
    var matched = Set<String>()
    var added: [PlanDiff.TaskSummary] = []
    var modified: [PlanDiff.TaskChanges] = []

    for taskB in b.tasks {
        guard let taskA = aById[taskB.id] ?? a.tasks.first(where: { !matched.contains($0.id) && $0.title == taskB.title }) else {
            added.append(.init(taskTitle: taskB.title, exercises: taskB.exercises?.map(\.name) ?? []))
            continue
        }
        matched.insert(taskA.id)

        var changes: [String] = []
        if taskA.title != taskB.title { changes.append("名称：\(taskA.title) → \(taskB.title)") }
        let sa = describeSchedule(taskA.schedule), sb = describeSchedule(taskB.schedule)
        if sa != sb { changes.append("日程：\(sa) → \(sb)") }
        changes += diffExercises(taskA.exercises ?? [], taskB.exercises ?? [])
        if stripIds(taskA.phases) != stripIds(taskB.phases) { changes.append("分阶段安排调整") }
        if !changes.isEmpty { modified.append(.init(taskTitle: taskB.title, changes: changes)) }
    }

    let removed = a.tasks.filter { !matched.contains($0.id) }
        .map { PlanDiff.TaskSummary(taskTitle: $0.title, exercises: $0.exercises?.map(\.name) ?? []) }
    return PlanDiff(added: added, removed: removed, modified: modified)
}

extension TaskSchedule {
    /// “周一、周三、周五 07:30” / “每天 18:00”
    public var summary: String { describeSchedule(self) }
}

extension PlanSource {
    public var label: String {
        switch self {
        case .jsonImport: return "JSON 导入"
        case .nlImport: return "自然语言导入"
        case .aiAnalysis: return "AI 建议"
        case .manual: return "手动"
        }
    }
}
