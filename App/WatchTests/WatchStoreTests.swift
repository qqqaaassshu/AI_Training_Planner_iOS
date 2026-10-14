import Foundation
import UserNotifications
import Testing
import TrainingCore
@testable import AITrainingPlannerWatch

@MainActor
@Suite("WatchStore：手表数据")
struct WatchStoreTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).json")

    func plan() throws -> PlanVersion {
        let text = samplePlanText(mode: .json, today: LocalDate.today())
        let preview = try #require(previewPlanImport(text, mode: .json, today: LocalDate.today(), current: nil).value)
        return preview.makeVersion(existing: [], current: nil)
    }

    @Test("应用手机快照、记录、稍后提醒与训练进度在重新打开后仍在")
    func roundTrip() throws {
        let store = WatchStore(fileURL: url)
        let p = try plan()
        store.apply(WatchSnapshot(plan: p, records: []))
        let today = store.today
        let task = try #require(p.tasks.first { $0.type == .habit })
        let r = try #require(store.submit(RecordDraft(taskId: task.id, status: .snoozed), date: today))
        #expect(r.source == .watch)
        store.addSnooze(ReminderSnooze(taskId: task.id, date: today, until: Date().addingTimeInterval(600)))
        let workoutTask = try #require(p.tasks.first { $0.type == .workout })
        store.startWorkout(WorkoutProgress(taskId: workoutTask.id, date: today, exercises: workoutTask.exercises ?? []))
        store.updateWorkout { $0.completeSet() }

        let reopened = WatchStore(fileURL: url)
        #expect(reopened.plan?.id == p.id)
        #expect(reopened.records.count == 1)
        #expect(reopened.data.snoozes.count == 1)
        #expect(reopened.data.workout?.completedSets == 1)
    }

    @Test("完成后清除当天的稍后提醒；训练记录带健康 id")
    func completeClearsSnooze() throws {
        let store = WatchStore(fileURL: url)
        let p = try plan()
        store.apply(WatchSnapshot(plan: p, records: []))
        let today = store.today
        store.addSnooze(ReminderSnooze(taskId: "t1", date: today, until: Date().addingTimeInterval(600)))
        let id = UUID()
        let r = store.submit(RecordDraft(taskId: "t1", status: .completed), date: today, healthWorkoutId: id)
        #expect(store.data.snoozes.isEmpty)
        #expect(r?.healthWorkoutId == id.uuidString)
    }

    @Test("通知内容：时效性、指纹、按时触发")
    func notificationRequest() throws {
        let p = try plan()
        let now = p.startDate.date(atHour: 6, minute: 0, in: p.timeZone)!
        let schedule = ReminderScheduler.schedule(plan: p, records: [], now: now)
        let first = try #require(schedule.notifications.first)
        let request = ReminderService.request(for: first)
        #expect(request.identifier == first.id)
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(request.content.userInfo[ReminderRequest.fingerprintKey] as? String == first.fingerprint)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.nextTriggerDate() == first.fireDate)
    }
}
