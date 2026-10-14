import Foundation
import Observation
import TrainingCore
import WatchKit

/// 手表端的协调者：数据、同步、三层提醒、训练
@MainActor
@Observable
final class WatchAppModel {
    static let shared = WatchAppModel()

    let store: WatchStore
    @ObservationIgnored let reminders = ReminderService()
    @ObservationIgnored let alarm = AlarmService()
    @ObservationIgnored let workout = WorkoutManager()
    @ObservationIgnored private let connectivity = WatchConnectivityService()

    /// 让界面跟着提醒权限、强提醒状态刷新
    private(set) var revision = 0

    init(store: WatchStore? = nil) {
        self.store = store ?? WatchStore()
        alarm.shouldRing = { [weak self] in self?.alarmStillNeeded() ?? false }
        alarm.onChange = { [weak self] in
            guard let self else { return }
            self.isAlarmRinging = self.alarm.ringing
        }
        connectivity.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.store.apply(snapshot)
            Task { await self.rescheduleAll(foreground: WKApplication.shared().applicationState == .active) }
        }
    }

    /// 强提醒正在响
    private(set) var isAlarmRinging = false

    func launch() async {
        connectivity.activate()
        store.publishToWidgets()
        await reminders.requestAuthorization()
        await workout.requestAuthorization()
        await becameActive()
    }

    func becameActive() async {
        store.refreshToday()
        await reminders.refreshSettings()
        await rescheduleAll(foreground: true)
    }

    /// 重排通知；在前台时同时重排强提醒（智能闹钟只能在前台安排）
    func rescheduleAll(foreground: Bool) async {
        let schedule = await reminders.reschedule(data: store.data)
        if foreground, !alarm.ringing {
            store.setAlarm(alarm.schedule(schedule.strongAlarm, current: store.data.alarm))
        }
        revision += 1
    }

    /// 后台刷新（WKApplicationRefreshBackgroundTask）
    func backgroundRefresh() async {
        store.refreshToday()
        await rescheduleAll(foreground: false)
    }

    private func alarmStillNeeded() -> Bool {
        guard let a = store.data.alarm else { return true }
        let r = store.record(taskId: a.taskId, date: a.date)
        return !(r?.status == .completed || r?.status == .partial || r?.status == .skipped)
    }

    // MARK: 强提醒的操作

    func startFromAlarm() {
        alarm.stop()
        if let a = store.data.alarm, let task = store.plan?.tasks.first(where: { $0.id == a.taskId }) {
            startWorkout(task, date: a.date)
        }
        store.setAlarm(nil)
    }

    func snoozeFromAlarm() {
        alarm.stop()
        if let a = store.data.alarm { snooze(taskId: a.taskId, date: a.date) }
        store.setAlarm(nil)
    }

    // MARK: 通知操作

    func handleNotificationAction(_ action: ReminderAction, taskId: String, date: LocalDate) {
        switch action {
        case .complete:
            save(RecordDraft(taskId: taskId, status: .completed), date: date)
        case .snooze:
            snooze(taskId: taskId, date: date)
        case .start:
            if let task = store.plan?.tasks.first(where: { $0.id == taskId }), store.data.workout == nil {
                startWorkout(task, date: date)
            }
        }
    }

    // MARK: 任务

    func complete(_ task: PlanTask) {
        save(RecordDraft(taskId: task.id, status: .completed), date: store.today)
    }

    func skip(_ task: PlanTask, reason: SkipReason) {
        save(RecordDraft(taskId: task.id, status: .skipped, skipReason: reason), date: store.today)
    }

    /// 稍后提醒：记为延后，并安排一条稍后提醒
    func snooze(taskId: String, date: LocalDate) {
        store.addSnooze(ReminderScheduler.snooze(taskId: taskId, date: date, now: Date()))
        save(RecordDraft(taskId: taskId, status: .snoozed), date: date)
    }

    private func save(_ draft: RecordDraft, date: LocalDate, healthWorkoutId: UUID? = nil) {
        if let r = store.submit(draft, date: date, healthWorkoutId: healthWorkoutId) { connectivity.send(r) }
        Task { await rescheduleAll(foreground: WKApplication.shared().applicationState == .active) }
    }

    // MARK: 训练

    func startWorkout(_ task: PlanTask, date: LocalDate? = nil) {
        guard let plan = store.plan else { return }
        let day = date ?? store.today
        let exercises = plan.exercises(for: task, on: day)
        guard !exercises.isEmpty else {
            complete(task)
            return
        }
        store.startWorkout(WorkoutProgress(taskId: task.id, date: day, exercises: exercises))
        Task { await workout.start() }
    }

    /// App 被系统结束后恢复进行中的训练
    func resumeWorkoutIfNeeded() {
        guard let w = store.data.workout else { return }
        if case .rest(let until) = w.phase {
            store.updateWorkout { $0.endRestIfDue() }
            if until > Date() { workout.scheduleRestHaptic(at: until) { [weak self] in self?.restEnded() } }
        }
        Task { await workout.start() }
    }

    func setWorkoutValue(_ v: Int) { store.updateWorkout { $0.setValue(v) } }

    func adjustWorkout(steps: Int) { store.updateWorkout { $0.adjust(steps: steps) } }

    func completeSet() {
        var until: Date?
        store.updateWorkout { until = $0.completeSet() }
        if let until {
            workout.scheduleRestHaptic(at: until) { [weak self] in self?.restEnded() }
        } else if store.data.workout?.isFinished == true {
            WKInterfaceDevice.current().play(.success)
        }
    }

    func restEnded() { store.updateWorkout { $0.endRestIfDue() } }

    func skipRest() {
        workout.cancelRestHaptic()
        store.updateWorkout { $0.skipRest() }
    }

    /// 中途结束：有完成的组就保存为部分完成，否则直接退出
    func endWorkoutEarly() {
        var saved = false
        store.updateWorkout { saved = $0.finishEarly() }
        if !saved {
            workout.discard()
            store.clearWorkout()
        }
    }

    /// 训练结束（全部完成或中途结束）后保存记录
    func saveWorkout() async {
        guard let w = store.data.workout, w.isFinished else { return }
        let healthId = await workout.end()
        store.clearWorkout()
        save(w.recordDraft(), date: w.date, healthWorkoutId: healthId)
    }
}
