import Foundation

// 对应原型 utils/plan.ts「动作 / 组记录」部分

extension Exercise {
    /// "3×10"、"3×30秒"、"4×10 @10kg"
    public var targetText: String { formatExerciseTarget(sets: sets, reps: reps, durationSec: durationSec, weightKg: weightKg) }
}

public func formatExerciseTarget(sets: Int, reps: Int?, durationSec: Int?, weightKg: Double?) -> String {
    let per = durationSec.map(formatDuration) ?? "\(reps ?? 0)"
    let weight = weightKg.flatMap { $0 != 0 ? " @\(jsNumber($0))kg" : nil } ?? ""
    return "\(sets)×\(per)\(weight)"
}

/// 一个动作的汇总（展示、手动补录、训练草稿）
public struct SetSummary: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var name: String
    public var sets: Int
    public var reps: Int?
    public var durationSec: Int?
    public var weightKg: Double?

    public init(exerciseId: String, name: String, sets: Int, reps: Int? = nil, durationSec: Int? = nil, weightKg: Double? = nil) {
        self.exerciseId = exerciseId
        self.name = name
        self.sets = sets
        self.reps = reps
        self.durationSec = durationSec
        self.weightKg = weightKg
    }

    enum CodingKeys: String, CodingKey {
        case name, sets, reps
        case exerciseId = "exercise_id"
        case durationSec = "duration_sec"
        case weightKg = "weight_kg"
    }
}

/// 把组记录按动作汇总（取每个动作最后一组的数值），保持动作首次出现的顺序
public func summarizeSets(_ sets: [SetLog]) -> [SetSummary] {
    var order: [String] = []
    var map: [String: SetSummary] = [:]
    for s in sets {
        let prev = map[s.exerciseId]
        if prev == nil { order.append(s.exerciseId) }
        map[s.exerciseId] = SetSummary(exerciseId: s.exerciseId, name: s.exerciseName, sets: (prev?.sets ?? 0) + 1,
                                       reps: s.reps, durationSec: s.durationSec, weightKg: s.weightKg)
    }
    return order.compactMap { map[$0] }
}

/// 由汇总值生成每组记录（手动补录时使用）
public func expandSets(_ items: [SetSummary], completedAt: String) -> [SetLog] {
    items.flatMap { it in
        (0..<max(0, it.sets)).map { i in
            var log = SetLog(exerciseId: it.exerciseId, exerciseName: it.name, setIndex: i + 1, completedAt: completedAt)
            if let d = it.durationSec { log.durationSec = d } else { log.reps = it.reps ?? 0 }
            if let w = it.weightKg, w != 0 { log.weightKg = w }
            return log
        }
    }
}

/// 实际完成组数少于计划时视为 partial
public func statusForSets(planned: [Exercise], sets: [SetLog]) -> RecordStatus {
    let plannedSets = planned.reduce(0) { $0 + $1.sets }
    return plannedSets > 0 && sets.count < plannedSets ? .partial : .completed
}
