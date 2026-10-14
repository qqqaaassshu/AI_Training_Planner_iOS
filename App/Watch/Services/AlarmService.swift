import Foundation
import TrainingCore
import WatchKit

/// 第 2 层：训练任务的闹钟式强提醒（智能闹钟会话 WKExtendedRuntimeSession）。
/// 到点后反复震动，直到用户点“开始”或“稍后”。系统同一时间只允许一个，且必须在 App 前台时安排，
/// 所以只用于“下一次训练”，每次打开 App 或完成训练后重排。
@MainActor
final class AlarmService: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    /// 正在响的强提醒
    private(set) var ringing = false
    /// 会话开始时调用：返回 false 表示该任务已不需要提醒（例如已完成），直接结束会话
    var shouldRing: (() -> Bool)?
    var onChange: (() -> Void)?

    /// 按排程结果安排下一次强提醒（只能在前台调用）。返回实际安排的提醒
    func schedule(_ alarm: ReminderRequest?, current: ScheduledAlarm?, now: Date = Date()) -> ScheduledAlarm? {
        if let alarm, let current, current.reminderId == alarm.id, current.fireDate == alarm.fireDate,
           session?.state == .scheduled {
            return current
        }
        // 上次启动时安排的会话在 App 重启后拿不到引用；新的会话会替代它（失败时旧会话到点仍会开始，届时由 shouldRing 判断）
        session?.invalidate()
        session = nil
        guard let alarm, alarm.fireDate > now.addingTimeInterval(60) else { return nil }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: alarm.fireDate)
        session = s
        return ScheduledAlarm(reminderId: alarm.id, taskId: alarm.taskId, date: alarm.date, title: alarm.title, fireDate: alarm.fireDate)
    }

    /// 系统在会话到点时重新启动 App，并通过 WKApplicationDelegate 交回会话
    func adopt(_ s: WKExtendedRuntimeSession) {
        s.delegate = self
        session = s
    }

    /// 用户点了开始或稍后
    func stop() {
        session?.invalidate()
        session = nil
        if ringing {
            ringing = false
            onChange?()
        }
    }

    private func didStart(_ s: WKExtendedRuntimeSession) {
        guard shouldRing?() ?? true else {
            s.invalidate()
            return
        }
        ringing = true
        onChange?()
        s.notifyUser(hapticType: .notification) { next in
            next.pointee = .notification
            return 2.0
        }
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.didStart(extendedRuntimeSession) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in
            if self.session === extendedRuntimeSession { self.session = nil }
            if self.ringing {
                self.ringing = false
                self.onChange?()
            }
        }
    }
}
