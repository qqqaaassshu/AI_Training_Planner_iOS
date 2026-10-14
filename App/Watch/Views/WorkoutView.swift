import SwiftUI
import TrainingCore

/// 逐组训练：完成一组 → 组间休息倒计时（结束时震动）→ 下一组。表冠调整次数或时长
struct WorkoutView: View {
    @Environment(WatchAppModel.self) private var model
    let progress: WorkoutProgress

    var body: some View {
        switch progress.phase {
        case .set: SetView(progress: progress)
        case .rest(let until): RestView(progress: progress, until: until)
        case .done: DoneView(progress: progress)
        }
    }
}

private struct SetView: View {
    @Environment(WatchAppModel.self) private var model
    let progress: WorkoutProgress
    @State private var crown = 0.0

    var body: some View {
        let ex = progress.current
        VStack(spacing: 4) {
            HStack {
                Text("动作 \(progress.exerciseIndex + 1)/\(progress.exercises.count)")
                Spacer()
                Text("组 \(progress.setIndex)/\(ex?.sets ?? 0)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(ex?.name ?? "").font(.headline).lineLimit(2).multilineTextAlignment(.center)
            HStack {
                Button { model.adjustWorkout(steps: -1) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered).frame(width: 36)
                Text(progress.valueText)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 64)
                    .focusable()
                    .digitalCrownRotation($crown, from: 0, through: 3600, by: Double(progress.step),
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                Button { model.adjustWorkout(steps: 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered).frame(width: 36)
            }
            if let w = ex?.weightKg, w > 0 {
                Text("@\(w.formatted())kg").font(.caption2).foregroundStyle(.secondary)
            }
            Button("完成本组") { model.completeSet() }
                .tint(.green)
            Button(progress.logs.isEmpty ? "退出" : "结束并保存") { model.endWorkoutEarly() }
                .font(.footnote)
        }
        .onAppear { crown = Double(progress.value) }
        .onChange(of: progress.value) { _, v in if Int(crown) != v { crown = Double(v) } }
        .onChange(of: crown) { _, c in model.setWorkoutValue(Int(c.rounded())) }
    }
}

private struct RestView: View {
    @Environment(WatchAppModel.self) private var model
    let progress: WorkoutProgress
    let until: Date

    var body: some View {
        VStack(spacing: 6) {
            Text("组间休息").font(.footnote).foregroundStyle(.secondary)
            Text(timerInterval: Date()...max(until, Date()), countsDown: true)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.green)
            if let ex = progress.current {
                Text("下一组：\(ex.name) 第 \(progress.setIndex)/\(ex.sets) 组")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("跳过休息") { model.skipRest() }
        }
    }
}

private struct DoneView: View {
    @Environment(WatchAppModel.self) private var model
    let progress: WorkoutProgress
    @State private var saving = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text(progress.completedSets < progress.totalSets ? "已保存进度" : "训练完成").font(.headline)
            Text("\(progress.completedSets)/\(progress.totalSets) 组 · \(progress.minutes()) 分钟")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("好") {
                saving = true
                Task { await model.saveWorkout() }
            }
            .disabled(saving)
        }
    }
}
