import Foundation

/// 手表逐组训练（对应原型 WatchTrainingMode）：完成一组 → 组间休息倒计时 → 下一组。
/// 次数 / 时长在完成前可用表冠调整；中途结束时，已完成的组作为“部分完成”保存。
/// 可编码，App 被系统结束后能恢复到原来的进度。
public struct WorkoutProgress: Codable, Hashable, Sendable {
    public enum Phase: Codable, Hashable, Sendable {
        /// 正在做 `exerciseIndex` 的第 `setIndex` 组
        case set
        /// 组间休息到 `until`
        case rest(until: Date)
        case done
    }

    public let taskId: String
    public let date: LocalDate
    public let exercises: [Exercise]
    public let startedAt: Date
    public private(set) var exerciseIndex = 0
    /// 从 1 开始
    public private(set) var setIndex = 1
    public private(set) var phase: Phase = .set
    public private(set) var logs: [SetLog] = []
    /// 当前组的次数（或计时动作的秒数），可调整
    public private(set) var value: Int

    public init(taskId: String, date: LocalDate, exercises: [Exercise], startedAt: Date = Date()) {
        self.taskId = taskId
        self.date = date
        self.exercises = exercises
        self.startedAt = startedAt
        self.value = exercises.first.map(Self.defaultValue) ?? 0
        if exercises.isEmpty { phase = .done }
    }

    static func defaultValue(_ e: Exercise) -> Int { e.durationSec ?? e.reps ?? 0 }

    public var current: Exercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    public var isTimed: Bool { current?.durationSec != nil }
    /// 表冠每格：计时动作 5 秒，次数 1 次
    public var step: Int { isTimed ? 5 : 1 }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    public var completedSets: Int { logs.count }
    public var isFinished: Bool { phase == .done }

    /// 显示用：“12” 或 “45秒”
    public var valueText: String { isTimed ? formatDuration(value) : "\(value)" }

    public mutating func setValue(_ v: Int) {
        guard phase == .set else { return }
        value = max(0, v)
    }

    public mutating func adjust(steps: Int) { setValue(value + steps * step) }

    /// 完成当前组；返回休息结束时间（最后一组完成时返回 nil，训练结束）
    @discardableResult
    public mutating func completeSet(now: Date = Date()) -> Date? {
        guard phase == .set, let ex = current else { return nil }
        logs.append(SetLog(exerciseId: ex.id, exerciseName: ex.name, setIndex: setIndex,
                           reps: isTimed ? nil : value, durationSec: isTimed ? value : nil,
                           weightKg: (ex.weightKg ?? 0) > 0 ? ex.weightKg : nil, completedAt: Timestamp.string(from: now)))
        if setIndex < ex.sets {
            setIndex += 1
        } else if exerciseIndex + 1 < exercises.count {
            exerciseIndex += 1
            setIndex = 1
            value = Self.defaultValue(exercises[exerciseIndex])
        } else {
            phase = .done
            return nil
        }
        let until = now.addingTimeInterval(TimeInterval(ex.restSec ?? Exercise.defaultRestSec))
        phase = .rest(until: until)
        return until
    }

    /// 休息时间到了就回到下一组
    public mutating func endRestIfDue(now: Date = Date()) {
        if case .rest(let until) = phase, now >= until { phase = .set }
    }

    public mutating func skipRest() {
        if case .rest = phase { phase = .set }
    }

    /// 中途结束：有完成的组就结束并保存（返回 true），一组都没做则返回 false（直接退出）
    public mutating func finishEarly() -> Bool {
        guard !logs.isEmpty else { return false }
        phase = .done
        return true
    }

    /// 已用时长（分钟，至少 1）
    public func minutes(now: Date = Date()) -> Int { max(1, Int((now.timeIntervalSince(startedAt) / 60).rounded())) }

    /// 生成记录：组数不足为部分完成
    public func recordDraft() -> RecordDraft {
        RecordDraft(taskId: taskId, status: statusForSets(planned: exercises, sets: logs), sets: logs,
                    startedAt: Timestamp.string(from: startedAt))
    }
}
