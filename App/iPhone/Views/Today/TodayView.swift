import SwiftUI
import TrainingCore

struct TodayView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.currentPlan {
                    TodayList(plan: plan)
                } else {
                    ContentUnavailableView {
                        Label("还没有训练计划", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("到「计划」页导入一份计划")
                    }
                }
            }
            .navigationTitle("今日")
            .navigationDestination(for: TaskRoute.self) { route in
                TaskDetailView(route: route)
            }
        }
    }
}

struct TaskRoute: Hashable {
    var taskId: String
    var date: LocalDate
}

private struct TodayList: View {
    @Environment(TrainingStore.self) private var store
    let plan: PlanVersion

    var body: some View {
        let today = store.today
        let tasks = plan.tasks(on: today)
        let done = tasks.filter { store.state.records.record(taskId: $0.id, date: today)?.isDone == true }.count
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(today.longText).font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text("第 \(plan.currentWeek(today: today)) / \(plan.totalWeeks) 周").font(.headline)
                        Spacer()
                        Text("\(done)").font(.title).bold().monospacedDigit().foregroundStyle(.tint)
                        Text("/\(tasks.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(done), total: Double(max(tasks.count, 1)))
                }
                .padding(.vertical, 4)
            }

            Section {
                ScoreSlider(title: "今日疲劳 (0-10)", value: store.state.dailyFatigue(on: today), minLabel: "精力充沛", maxLabel: "极度疲劳",
                            hint: "记录今天的整体疲劳感受") { store.setDailyFatigue($0) }
            }

            taskSection("今日训练", tasks.filter { $0.type == .workout }, today: today)
            taskSection("今日习惯", tasks.filter { $0.type == .habit }, today: today)

            if tasks.isEmpty {
                Section {
                    Label("今天没有任务，好好休息！", systemImage: "cup.and.saucer")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, _ tasks: [PlanTask], today: LocalDate) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { task in
                    NavigationLink(value: TaskRoute(taskId: task.id, date: today)) {
                        TaskRow(plan: plan, task: task, date: today,
                                record: store.state.records.record(taskId: task.id, date: today),
                                draft: store.draft(date: today, taskId: task.id))
                    }
                }
            }
        }
    }
}

/// 任务行：状态、时间、进度、已记录的组与备注
struct TaskRow: View {
    let plan: PlanVersion
    let task: PlanTask
    let date: LocalDate
    let record: ExecutionRecord?
    let draft: TaskDraft?

    var body: some View {
        let planned = plan.exercises(for: task, on: date)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record?.status.symbol ?? "circle")
                .font(.title3)
                .foregroundStyle(record?.status.color ?? .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .fontWeight(.medium)
                    .strikethrough(record?.status == .completed || record?.status == .skipped)
                    .foregroundStyle(record?.status == .completed || record?.status == .skipped ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let time = task.schedule.time {
                        Label(time, systemImage: "clock").labelStyle(.titleAndIcon)
                    }
                    if let status = statusText(planned: planned) { Text(status) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let sets = record?.sets, !sets.isEmpty, record?.status != .partial {
                    SetListView(sets: sets)
                }
                if let pain = record?.painScore {
                    Text("疼痛评分：\(pain)/10").font(.caption).foregroundStyle(pain >= painRisk ? Color.red : Color.secondary)
                }
                if let notes = record?.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func statusText(planned: [Exercise]) -> String? {
        switch record?.status {
        case .partial: return "部分完成，可继续"
        case .snoozed: return "已延后"
        case .skipped: return record?.skipReason.map { "跳过（\($0.label)）" } ?? "跳过"
        case .completed: return nil
        case nil:
            guard let draft, !planned.isEmpty else { return planned.isEmpty ? nil : "\(planned.count) 个动作" }
            let n = planned.filter { draft.doneIds.contains($0.id) }.count
            return "进行中 \(n)/\(planned.count)"
        }
    }
}
