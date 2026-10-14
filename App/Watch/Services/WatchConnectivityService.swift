import Foundation
import TrainingCore
import WatchConnectivity

/// 手表端同步：接收手机的计划与记录（applicationContext），把手表上的记录排队发回手机（transferUserInfo，不丢失）
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    /// 收到手机快照时调用（主线程）
    var onSnapshot: ((WatchSnapshot) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ record: ExecutionRecord) {
        guard WCSession.isSupported(), let data = try? record.encoded() else { return }
        WCSession.default.transferUserInfo([WatchSnapshot.recordKey: data])
    }

    private func deliver(_ context: [String: Any]) {
        guard let data = context[WatchSnapshot.contextKey] as? Data, let snapshot = try? WatchSnapshot.decode(data) else { return }
        DispatchQueue.main.async { self.onSnapshot?(snapshot) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { deliver(session.receivedApplicationContext) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }
}
