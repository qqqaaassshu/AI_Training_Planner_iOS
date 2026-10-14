import SwiftUI
import TrainingCore
import UserNotifications

struct WatchTodayView: View {
    @Environment(WatchAppModel.self) private var model

    var body: some View {
        let today = model.store.today
        List {
            if model.reminders.authorization == .denied {
                NavigationLink {
                    ReminderStatusView()
                } label: {
                    Label("通知已关闭，到点不会提醒", systemImage: "bell.slash.fill").foregroundStyle(.red)
                }
            }
            if let plan = model.store.plan {
                let tasks = plan.tasks(on: today)
                if tasks.isEmpty {
                    Text("今天没有任务，好好休息").foregroundStyle(.secondary)
                }
                ForEach(tasks) { task in
                    let record = model.store.record(taskId: task.id, date: today)
                    if task.type == .workout {
                        Button {
                            model.startWorkout(task)
                        } label: {
                            WatchTaskRow(task: task, record: record, exercises: plan.exercises(for: task, on: today).count)
                        }
                        .disabled(record?.status == .completed || record?.status == .skipped)
                    } else {
                        NavigationLink {
                            HabitActionView(task: task)
                        } label: {
                            WatchTaskRow(task: task, record: record, exercises: 0)
                        }
                    }
                }
            } else {
                Text("在 iPhone 上导入训练计划后，会自动同步到手表").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReminderStatusView()
                } label: {
                    Image(systemName: "bell.badge")
                }
            }
        }
    }
}

private struct WatchTaskRow: View {
    let task: PlanTask
    let record: ExecutionRecord?
    let exercises: Int

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(task.title).lineLimit(2)
                HStack(spacing: 4) {
                    if let t = task.schedule.time { Text(t) }
                    if exercises > 0 { Text("· \(exercises) 个动作") }
                    if let s = record?.status, s != .completed { Text("· \(s.label)") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch record?.status {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "circle.dashed"
        case .skipped: return "forward.circle"
        case .snoozed: return "clock"
        case nil: return task.type == .workout ? "figure.strengthtraining.traditional" : "circle"
        }
    }

    private var color: Color {
        switch record?.status {
        case .completed, .partial: return .green
        case .snoozed: return .orange
        default: return .secondary
        }
    }
}

/// 习惯：完成 / 稍后 / 跳过
struct HabitActionView: View {
    @Environment(WatchAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let task: PlanTask

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(task.title).font(.headline).multilineTextAlignment(.center)
                Button("完成") {
                    model.complete(task)
                    dismiss()
                }
                .tint(.green)
                Button("稍后 10 分钟") {
                    model.snooze(taskId: task.id, date: model.store.today)
                    dismiss()
                }
                ForEach(SkipReason.allCases, id: \.self) { reason in
                    Button("跳过 · \(reason.label)") {
                        model.skip(task, reason: reason)
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 提醒状态与系统限制说明
struct ReminderStatusView: View {
    @Environment(WatchAppModel.self) private var model

    var body: some View {
        List {
            Section("提醒") {
                LabeledContent("通知", value: authorizationText)
                LabeledContent("时效性通知", value: model.reminders.timeSensitive == .enabled ? "已开启" : "未开启")
                LabeledContent("待发提醒", value: "\(model.reminders.pendingCount) 条")
                if let a = model.store.data.alarm {
                    LabeledContent("强提醒", value: "\(a.title) \(a.fireDate.formatted(date: .omitted, time: .shortened))")
                } else {
                    LabeledContent("强提醒", value: "无")
                }
            }
            if model.reminders.authorization == .denied {
                Section {
                    Text("通知已关闭。请在 iPhone 的 Watch App →「通知」里允许本 App 的通知，并开启时效性通知")
                        .font(.footnote)
                }
            } else if model.reminders.authorization == .notDetermined {
                Button("允许通知") { Task { await model.reminders.requestAuthorization() } }
            }
            Section("这些情况下不会震动") {
                Text("手表没有佩戴或没有解锁")
                Text("勿扰、影院模式、睡眠专注会压制普通通知（时效性通知可穿透普通专注模式）")
                Text("通知权限被关闭")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("提醒")
        .task { await model.reminders.refreshSettings() }
    }

    private var authorizationText: String {
        switch model.reminders.authorization {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "已关闭"
        case .notDetermined: return "未设置"
        @unknown default: return "未知"
        }
    }
}
