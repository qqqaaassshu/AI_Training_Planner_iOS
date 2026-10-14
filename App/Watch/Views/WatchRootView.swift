import SwiftUI
import TrainingCore

struct WatchRootView: View {
    @Environment(WatchAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var launched = false

    var body: some View {
        Group {
            if model.isAlarmRinging {
                AlarmView()
            } else if let workout = model.store.data.workout {
                WorkoutView(progress: workout)
            } else {
                NavigationStack { WatchTodayView() }
            }
        }
        .task {
            guard !launched else { return }
            launched = true
            model.resumeWorkoutIfNeeded()
            await model.launch()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, launched { Task { await model.becameActive() } }
        }
    }
}

/// 到点的强提醒：持续震动，直到点开始或稍后
struct AlarmView: View {
    @Environment(WatchAppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "alarm.fill").font(.title).foregroundStyle(.orange)
            Text("该训练了").font(.headline)
            Text(model.store.data.alarm?.title ?? "").font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("开始") { model.startFromAlarm() }
                .tint(.green)
            Button("稍后 10 分钟") { model.snoozeFromAlarm() }
        }
        .padding(.horizontal)
    }
}
