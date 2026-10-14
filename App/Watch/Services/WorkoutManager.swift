import Foundation
import HealthKit
import WatchKit

/// 第 3 层：训练中用 HKWorkoutSession 保持 App 在后台运行，组间休息结束时震动。
/// 没有健康权限时仍可训练，只是抬腕离开 App 后可能被系统挂起。
@MainActor
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var restTask: Task<Void, Never>?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        try? await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
    }

    func start() async {
        guard isAvailable, session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            s.delegate = self
            session = s
            builder = b
            let start = Date()
            s.startActivity(with: start)
            try await b.beginCollection(at: start)
        } catch {
            session = nil
            builder = nil
        }
    }

    /// 结束训练并保存到健康；返回 HKWorkout 的 UUID
    func end() async -> UUID? {
        cancelRestHaptic()
        guard let s = session, let b = builder else { return nil }
        session = nil
        builder = nil
        let end = Date()
        s.end()
        do {
            try await b.endCollection(at: end)
            return try await b.finishWorkout()?.uuid
        } catch {
            return nil
        }
    }

    /// 一组都没做就退出：不保存到健康
    func discard() {
        cancelRestHaptic()
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }

    /// 休息结束时震动并回调
    func scheduleRestHaptic(at until: Date, onEnd: @escaping @MainActor () -> Void) {
        restTask?.cancel()
        restTask = Task { @MainActor in
            let wait = until.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
            onEnd()
        }
    }

    func cancelRestHaptic() {
        restTask?.cancel()
        restTask = nil
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
