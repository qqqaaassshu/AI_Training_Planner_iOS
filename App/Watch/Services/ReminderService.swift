import Foundation
import Observation
import TrainingCore
import UserNotifications
import WatchKit

/// 第 1 层：手表自己安排本地通知（不依赖 iPhone 转发）。
/// 按 TrainingCore 的排程结果增量更新待发通知，并按 `refreshBy` 安排后台刷新续排。
@MainActor
@Observable
final class ReminderService {
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var timeSensitive: UNNotificationSetting = .notSupported
    private(set) var pendingCount = 0
    private(set) var lastSchedule: ReminderSchedule?

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshSettings()
    }

    func refreshSettings() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        timeSensitive = settings.timeSensitiveSetting
    }

    /// 重新计算并增量更新待发通知；返回排程结果（其中的 strongAlarm 交给 AlarmService）
    @discardableResult
    func reschedule(data: WatchData, now: Date = Date()) async -> ReminderSchedule {
        let schedule = ReminderScheduler.schedule(plan: data.state.currentPlan, records: data.state.records,
                                                  snoozes: data.snoozes, now: now)
        let pending = await center.pendingNotificationRequests().map {
            PendingReminder(identifier: $0.identifier, fingerprint: $0.content.userInfo[ReminderRequest.fingerprintKey] as? String)
        }
        let diff = ReminderScheduler.diff(desired: schedule.notifications, pending: pending)
        if !diff.toRemove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: diff.toRemove) }
        for r in diff.toAdd {
            try? await center.add(Self.request(for: r))
        }
        pendingCount = schedule.notifications.count
        lastSchedule = schedule
        scheduleBackgroundRefresh(at: schedule.refreshBy)
        return schedule
    }

    static func request(for r: ReminderRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.body = r.body
        content.sound = .default
        content.threadIdentifier = r.taskId
        // 时效性通知可穿透普通专注模式（需开启 Time Sensitive Notifications 能力，且用户允许）
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            ReminderRequest.fingerprintKey: r.fingerprint,
            "task_id": r.taskId,
            "date": r.date.description,
        ]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: r.id, content: content, trigger: trigger)
    }

    private func scheduleBackgroundRefresh(at date: Date) {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: nil) { _ in }
    }
}
