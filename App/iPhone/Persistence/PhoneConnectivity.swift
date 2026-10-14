import Foundation
import TrainingCore
import WatchConnectivity

/// iPhone 端的手表同步：计划与近期记录变化时发给手表（applicationContext，只保留最新一份）；
/// 接收手表排队发来的记录（transferUserInfo）并合并。提醒由手表自己安排，手机不重复安排。
@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    private let store: TrainingStore

    init(store: TrainingStore) {
        self.store = store
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 把当前计划与近期记录发给手表
    func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let data = try store.state.watchSnapshot(today: store.today).encoded()
            try session.updateApplicationContext([WatchSnapshot.contextKey: data])
        } catch {
            store.lastError = "同步到手表失败：\(error.localizedDescription)"
        }
    }

    private func receive(_ data: Data) {
        guard let record = try? ExecutionRecord.decode(data) else { return }
        store.mergeFromWatch(record)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 切换配对的手表后重新激活
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchSnapshot.recordKey] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
