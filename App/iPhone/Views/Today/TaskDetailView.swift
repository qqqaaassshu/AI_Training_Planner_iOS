import SwiftUI
import TrainingCore

/// 今日任务详情：逐个动作打勾、调整实际值、记录疼痛与备注，然后完成 / 延后 / 跳过
struct TaskDetailView: View {
    @Environment(TrainingStore.self) private var store
    let route: TaskRoute

    var body: some View {
        if let plan = store.currentPlan, let task = plan.tasks.first(where: { $0.id == route.taskId }) {
            let record = store.state.records.record(taskId: task.id, date: route.date)
            let open = record == nil || record?.status == .snoozed || record?.status == .partial
            if open {
                TaskEditor(plan: plan, task: task, date: route.date, record: record,
                           draft: store.draft(date: route.date, taskId: task.id))
                    .id("\(route.date)|\(task.id)|\(record?.updatedAt ?? "")")
            } else {
                ClosedTaskView(plan: plan, task: task, record: record!)
            }
        } else {
            ContentUnavailableView("任务不在当前计划中", systemImage: "questionmark.circle")
        }
    }
}

private struct ClosedTaskView: View {
    let plan: PlanVersion
    let task: PlanTask
    let record: ExecutionRecord

    var body: some View {
        List {
            Section {
                Label(record.status.label + (record.skipReason.map { "（\($0.label)）" } ?? ""), systemImage: record.status.symbol)
                    .foregroundStyle(record.status.color)
                if let sets = record.sets, !sets.isEmpty { SetListView(sets: sets) }
                if let pain = record.painScore { LabeledContent("疼痛", value: "\(pain)/10") }
                if !record.notes.isEmpty { Text(record.notes) }
            } footer: {
                Text("需要修改时，到「记录」页编辑这条记录")
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TaskEditor: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let plan: PlanVersion
    let task: PlanTask
    let date: LocalDate
    let record: ExecutionRecord?
    private let planned: [Exercise]

    @State private var progress: TaskProgress
    @State private var notes: String
    @State private var painScore: Int?
    @State private var choosingSkip = false

    init(plan: PlanVersion, task: PlanTask, date: LocalDate, record: ExecutionRecord?, draft: TaskDraft?) {
        self.plan = plan
        self.task = task
        self.date = date
        self.record = record
        let planned = plan.exercises(for: task, on: date)
        self.planned = planned
        _progress = State(initialValue: TaskProgress.initial(planned: planned, record: record, draft: draft))
        _notes = State(initialValue: record?.notes ?? "")
        _painScore = State(initialValue: record?.painScore)
    }

    var body: some View {
        let doneCount = progress.doneCount(planned: planned)
        let allDone = progress.allDone(planned: planned)
        Form {
            if let time = task.schedule.time {
                Section {
                    LabeledContent("时间", value: time)
                    if record?.status == .snoozed { Text("已延后，今天仍可完成").foregroundStyle(.orange) }
                    if record?.status == .partial { Text("部分完成，可继续").foregroundStyle(.mint) }
                }
            }

            if !planned.isEmpty {
                Section {
                    ForEach($progress.items, id: \.exerciseId) { $item in
                        ExerciseEditorRow(item: $item, target: planned.first { $0.id == item.exerciseId },
                                          isDone: progress.isDone(item.exerciseId)) {
                            withAnimation { progress.toggle(item.exerciseId) }
                        }
                    }
                } header: {
                    HStack {
                        Text("点圆圈逐个完成动作")
                        Spacer()
                        Text("\(doneCount)/\(planned.count)").monospacedDigit().foregroundStyle(allDone ? Color.green : Color.accentColor)
                    }
                } footer: {
                    if allDone { Text("🎉 全部动作完成！记录一下疼痛感受再提交") }
                }
            }

            if task.type == .workout {
                Section {
                    ScoreSlider(title: "疼痛程度 (0-10)", value: painScore, minLabel: "无痛", maxLabel: "剧痛",
                                hint: (painScore ?? 0) >= painRisk ? "⚠️ 疼痛较明显，建议停止训练并观察，必要时就医" : "完成后记录当前疼痛感受") {
                        painScore = $0
                    }
                }
            }

            Section("备注") {
                TextField("状态、感受…", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                Button {
                    submit(.done)
                } label: {
                    Label(doneCount > 0 && !allDone ? "保存进度" : "完成", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                HStack {
                    Button {
                        submit(.snoozed)
                    } label: {
                        Label("延后", systemImage: "clock").frame(maxWidth: .infinity)
                    }
                    Button {
                        choosingSkip = true
                    } label: {
                        Label("跳过", systemImage: "forward").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("跳过原因", isPresented: $choosingSkip, titleVisibility: .visible) {
            ForEach(SkipReason.allCases, id: \.self) { reason in
                Button(reason.label) { submit(.skipped(reason)) }
            }
        }
        .onChange(of: progress) { _, p in
            store.setDraft(p.draft, date: date, taskId: task.id)
        }
    }

    private func submit(_ outcome: TaskOutcome) {
        let draft = RecordDraft.make(task: task, planned: planned, progress: progress, outcome: outcome, notes: notes, painScore: painScore)
        store.submit(draft, date: date)
        dismiss()
    }
}
