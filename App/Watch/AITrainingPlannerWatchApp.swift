import SwiftUI
import TrainingCore
import UserNotifications
import WatchKit

@main
struct AITrainingPlannerWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var model = WatchAppModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        // 必须在启动时设置，才能收到通知操作
        UNUserNotificationCenter.current().delegate = self
        ReminderService.registerCategories()
    }

    /// App 在前台时也显示提醒
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// 通知上点了“完成 / 稍后 / 开始训练”
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let taskId = info[ReminderRequest.taskIdKey] as? String
        let date = (info[ReminderRequest.dateKey] as? String).flatMap(LocalDate.init)
        let action = ReminderAction(rawValue: response.actionIdentifier)
        Task { @MainActor in
            if let taskId, let date, let action {
                WatchAppModel.shared.handleNotificationAction(action, taskId: taskId, date: date)
            }
            completionHandler()
        }
    }

    /// 智能闹钟会话到点时，系统重新启动 App 并交回会话
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in WatchAppModel.shared.alarm.adopt(extendedRuntimeSession) }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await WatchAppModel.shared.backgroundRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            case let connectivity as WKWatchConnectivityRefreshBackgroundTask:
                // 手机发来的数据由 WCSession 代理处理；留一点时间再结束
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    connectivity.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
