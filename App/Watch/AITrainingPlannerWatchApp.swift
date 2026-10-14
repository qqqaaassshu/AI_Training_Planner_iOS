import SwiftUI
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

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
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
