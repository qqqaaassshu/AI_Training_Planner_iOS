import SwiftUI
import TrainingCore

struct HistoryView: View {
    @Environment(TrainingStore.self) private var store
    @State private var editing: ExecutionRecord?

    var body: some View {
        NavigationStack {
            Group {
                if store.state.records.isEmpty && store.state.dailyWellness.isEmpty {
                    ContentUnavailableView {
                        Label("还没有执行记录", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("完成任务后，记录会出现在这里")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("记录")
            .sheet(item: $editing) { record in
                RecordEditorView(record: record)
            }
        }
    }

    private var list: some View {
        let stats = HistoryStats(records: store.state.records)
        let versions = store.state.planVersions
        return List {
            Section {
                HStack {
                    stat("完成", "\(stats.done)", .green)
                    stat("跳过", "\(stats.skipped)", .secondary)
                    stat("完成率", "\(stats.rate)%", .accentColor)
                }
            }
            ForEach(historyDays(records: store.state.records, wellness: store.state.dailyWellness)) { day in
                Section {
                    ForEach(day.records) { r in
                        Button {
                            editing = r
                        } label: {
                            RecordRow(record: r, title: findTask(for: r, in: versions)?.task.title ?? "（已删除的任务）")
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", systemImage: "trash", role: .destructive) { store.deleteRecord(id: r.id) }
                        }
                    }
                } header: {
                    HStack {
                        Text(day.date == store.today ? "今天 · \(day.date.shortText)" : day.date.shortText)
                        Spacer()
                        if let f = day.fatigue { Text("疲劳 \(f)/10") }
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).bold().monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let record: ExecutionRecord
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.status.symbol).foregroundStyle(record.status.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).fontWeight(.medium)
                    Spacer()
                    Text(record.status.label + (record.skipReason.map { "·\($0.label)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(record.status.color)
                    if record.source == .watch {
                        Image(systemName: "applewatch").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let sets = record.sets, !sets.isEmpty { SetListView(sets: sets) }
                if let pain = record.painScore {
                    Text("疼痛 \(pain)/10").font(.caption).foregroundStyle(pain >= painRisk ? Color.red : Color.secondary)
                }
                if !record.notes.isEmpty {
                    Text(record.notes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
