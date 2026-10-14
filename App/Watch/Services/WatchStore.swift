import Foundation
import Observation
import TrainingCore

/// 手表上保存的数据（JSON 文件）：从手机同步来的当前计划与近期记录、稍后提醒、进行中的训练、已安排的强提醒
struct WatchData: Codable, Equatable {
    var state = PersistedState()
    var snoozes: [ReminderSnooze] = []
    var workout: WorkoutProgress?
    var alarm: ScheduledAlarm?
}

/// 已安排的智能闹钟会话（WKExtendedRuntimeSession）对应的任务
struct ScheduledAlarm: Codable, Equatable {
    var reminderId: String
    var taskId: String
    var date: LocalDate
    var title: String
    var fireDate: Date
}

@MainActor
@Observable
final class WatchStore {
    private(set) var data: WatchData
    private(set) var today = LocalDate.today()
    var lastError: String?

    @ObservationIgnored private let fileURL: URL

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("watch-data.json")
    }

    init(fileURL: URL = WatchStore.defaultURL) {
        self.fileURL = fileURL
        if let raw = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(WatchData.self, from: raw) {
            data = decoded
        } else {
            data = WatchData()
        }
    }

    var plan: PlanVersion? { data.state.currentPlan }
    var records: [ExecutionRecord] { data.state.records }

    func record(taskId: String, date: LocalDate) -> ExecutionRecord? { records.record(taskId: taskId, date: date) }

    func refreshToday(now: Date = Date()) {
        let t = LocalDate.today(now: now)
        if t != today { today = t }
        // 过期的稍后提醒清掉
        let before = data.snoozes.count
        data.snoozes.removeAll { $0.until < now.addingTimeInterval(-3600) }
        if data.snoozes.count != before { save() }
    }

    // MARK: 同步

    func apply(_ snapshot: WatchSnapshot) {
        update { $0.state.apply(snapshot) }
    }

    // MARK: 记录

    /// 写入记录（来源为手表），返回需要发给手机的记录
    @discardableResult
    func submit(_ draft: RecordDraft, date: LocalDate, healthWorkoutId: UUID? = nil) -> ExecutionRecord? {
        var result: ExecutionRecord?
        update { d in
            result = d.state.record(draft, date: date, source: .watch)
            if let id = healthWorkoutId, let r = result {
                d.state.updateRecord(id: r.id) { $0.healthWorkoutId = id.uuidString }
                result = d.state.records.first { $0.id == r.id }
            }
            // 完成或跳过后，这个任务当天的稍后提醒作废
            if draft.status != .snoozed { d.snoozes.removeAll { $0.taskId == draft.taskId && $0.date == date } }
        }
        return result
    }

    func addSnooze(_ snooze: ReminderSnooze) {
        update { d in
            d.snoozes.removeAll { $0.taskId == snooze.taskId && $0.date == snooze.date }
            d.snoozes.append(snooze)
        }
    }

    // MARK: 训练

    func startWorkout(_ progress: WorkoutProgress) {
        update { $0.workout = progress }
    }

    func updateWorkout(_ change: (inout WorkoutProgress) -> Void) {
        guard data.workout != nil else { return }
        update { d in
            if var w = d.workout {
                change(&w)
                d.workout = w
            }
        }
    }

    func clearWorkout() {
        update { $0.workout = nil }
    }

    // MARK: 强提醒

    func setAlarm(_ alarm: ScheduledAlarm?) {
        guard data.alarm != alarm else { return }
        update { $0.alarm = alarm }
    }

    // MARK: 文件

    private func update(_ change: (inout WatchData) -> Void) {
        var next = data
        change(&next)
        guard next != data else { return }
        data = next
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }
}
