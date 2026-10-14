import SwiftUI
import TrainingCore

struct PlanView: View {
    @Environment(TrainingStore.self) private var store
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.currentPlan {
                    PlanDetailList(plan: plan, today: store.today, isCurrent: true)
                } else {
                    ContentUnavailableView {
                        Label("还没有训练计划", systemImage: "doc.text")
                    } description: {
                        Text("粘贴 AI 生成的 JSON 计划，或用文字描述，例如“深蹲3组10次”")
                    } actions: {
                        Button("导入计划") { importing = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("计划")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("导入", systemImage: "square.and.arrow.down") { importing = true }
                }
                if store.state.planVersions.count > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            VersionHistoryView()
                        } label: {
                            Label("版本", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
            .sheet(isPresented: $importing) {
                ImportPlanView()
            }
        }
    }
}

/// 一个版本的内容：概要与任务
struct PlanDetailList: View {
    let plan: PlanVersion
    let today: LocalDate
    let isCurrent: Bool
    var diffFromParent: PlanDiff?
    var onSelect: (() -> Void)?

    var body: some View {
        List {
            Section {
                LabeledContent("名称", value: plan.planName)
                LabeledContent("版本", value: "V\(plan.version)" + (isCurrent ? " · 当前" : ""))
                LabeledContent("日期", value: plan.endDate.map { "\(plan.startDate) ~ \($0)" } ?? "\(plan.startDate) 起")
                LabeledContent("进度", value: "第 \(plan.currentWeek(today: today)) / \(plan.totalWeeks) 周")
                LabeledContent("来源", value: plan.source.label)
                if let s = plan.aiSummary { Text(s).foregroundStyle(.secondary) }
            }
            if let note = plan.changeNote {
                Section("调整说明") { Text(note) }
            }
            if let diffFromParent {
                Section("相对上一版") { PlanDiffRows(diff: diffFromParent) }
            }
            Section("任务") {
                ForEach(plan.tasks) { task in
                    TaskSummaryRow(plan: plan, task: task, today: today)
                }
            }
            if let onSelect, !isCurrent {
                Section {
                    Button("设为当前版本", action: onSelect)
                } footer: {
                    Text("之后的记录会关联到这个版本；已有记录不受影响")
                }
            }
        }
    }
}

private struct TaskSummaryRow: View {
    let plan: PlanVersion
    let task: PlanTask
    let today: LocalDate

    var body: some View {
        let exercises = plan.exercises(for: task, on: max(today, plan.startDate))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: task.type == .workout ? "figure.strengthtraining.traditional" : "leaf")
                    .foregroundStyle(.tint)
                Text(task.title).fontWeight(.medium)
                Spacer()
                if task.reminder && task.schedule.time != nil {
                    Image(systemName: "bell").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(task.schedule.summary).font(.caption).foregroundStyle(.secondary)
            ForEach(exercises) { ex in
                HStack {
                    Text(ex.name)
                    Spacer()
                    Text(ex.targetText).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let phases = task.phases, !phases.isEmpty {
                Text("分阶段：" + phases.map { "第 \($0.weekFrom)–\($0.weekTo) 周" }.joined(separator: "、"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 版本差异（对应原型 PlanDiffView）
struct PlanDiffRows: View {
    let diff: PlanDiff

    var body: some View {
        if diff.isEmpty {
            Text("任务与动作没有变化").foregroundStyle(.secondary)
        }
        ForEach(diff.added, id: \.self) { a in
            Label {
                VStack(alignment: .leading) {
                    Text("新增：\(a.taskTitle)")
                    if !a.exercises.isEmpty { Text(a.exercises.joined(separator: "、")).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
            }
        }
        ForEach(diff.removed, id: \.self) { r in
            Label {
                Text("删除：\(r.taskTitle)")
            } icon: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
        }
        ForEach(diff.modified, id: \.self) { m in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.taskTitle)
                    ForEach(m.changes, id: \.self) { Text("· \($0)").font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: "pencil.circle.fill").foregroundStyle(.orange)
            }
        }
    }
}
