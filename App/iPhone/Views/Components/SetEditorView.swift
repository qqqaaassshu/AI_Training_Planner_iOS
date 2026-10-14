import SwiftUI
import TrainingCore

/// 编辑一个动作的实际完成值（对应原型 SetEditor）
struct ExerciseEditorRow: View {
    @Binding var item: SetSummary
    /// 计划目标（今日任务时有）
    var target: Exercise?
    /// 逐个打勾；为 nil 时不显示勾选框
    var isDone: Bool?
    var onToggle: (() -> Void)?
    /// 补录时可改名
    var editableName = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let isDone, let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isDone ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDone ? "撤销完成 \(item.name)" : "完成 \(item.name)")
                }
                if editableName {
                    TextField("动作名称", text: $item.name)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(item.name)
                        .fontWeight(.medium)
                        .strikethrough(isDone == true)
                        .foregroundStyle(isDone == true ? .secondary : .primary)
                }
                Spacer()
                if isDone == true {
                    Text(item.targetText).font(.caption).monospacedDigit().foregroundStyle(.green)
                } else if let target {
                    Text("计划 \(target.targetText)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if isDone != true {
                if let cue = target?.cue {
                    Label(cue, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $item.sets, in: 0...50) {
                    LabeledContent("组数", value: "\(item.sets)")
                }
                if item.durationSec != nil {
                    Stepper(value: Binding(get: { item.durationSec ?? 0 }, set: { item.durationSec = $0 }), in: 0...3600, step: 5) {
                        LabeledContent("每组时长", value: formatDuration(item.durationSec ?? 0))
                    }
                } else {
                    Stepper(value: Binding(get: { item.reps ?? 0 }, set: { item.reps = $0 }), in: 0...500) {
                        LabeledContent("每组次数", value: "\(item.reps ?? 0)")
                    }
                }
                LabeledContent("重量 (kg)") {
                    TextField("无", value: Binding(get: { item.weightKg }, set: { item.weightKg = ($0 ?? 0) > 0 ? $0 : nil }),
                              format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 补录：可增删动作
struct EditableSetList: View {
    @Binding var items: [SetSummary]
    @State private var newName = ""

    var body: some View {
        ForEach($items, id: \.exerciseId) { $item in
            ExerciseEditorRow(item: $item, editableName: true)
        }
        .onDelete { items.remove(atOffsets: $0) }
        HStack {
            TextField("添加动作名称…", text: $newName)
                .onSubmit(add)
            Button("添加", systemImage: "plus.circle.fill", action: add)
                .labelStyle(.iconOnly)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        items.append(SetSummary(exerciseId: newId(), name: name.isEmpty ? "自定义动作" : name, sets: 3, reps: 10))
        newName = ""
    }
}
