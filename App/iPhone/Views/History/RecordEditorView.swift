import SwiftUI
import TrainingCore

/// 修改历史记录：补录实际完成的动作与备注
struct RecordEditorView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let record: ExecutionRecord
    @State private var items: [SetSummary] = []
    @State private var notes = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("日期", value: record.date.longText)
                    LabeledContent("状态", value: record.status.label + (record.skipReason.map { "（\($0.label)）" } ?? ""))
                }
                Section("实际完成动作") {
                    EditableSetList(items: $items)
                }
                Section("备注") {
                    TextField("疲劳、疼痛、状态…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(findTask(for: record, in: store.state.planVersions)?.task.title ?? "（已删除的任务）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                items = editorItems(for: record, versions: store.state.planVersions)
                notes = record.notes
            }
        }
    }

    private func save() {
        let completedAt = record.completedAt ?? Timestamp.now()
        let sets = expandSets(items.filter { $0.sets > 0 }, completedAt: completedAt)
        store.updateRecord(id: record.id) {
            $0.sets = sets.isEmpty ? nil : sets
            $0.notes = notes
        }
        dismiss()
    }
}
