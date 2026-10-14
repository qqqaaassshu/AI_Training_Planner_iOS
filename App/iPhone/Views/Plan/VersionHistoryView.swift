import SwiftUI
import TrainingCore

/// 版本历史：每个版本的来源、调整说明与相对上一版的变化，可切换当前版本
struct VersionHistoryView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        List(store.versionsNewestFirst) { v in
            NavigationLink {
                VersionDetail(versionId: v.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("V\(v.version)").bold().monospacedDigit()
                        Text(v.planName)
                        Spacer()
                        if v.id == store.state.currentPlanId {
                            Text("当前").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                    }
                    Text("\(Timestamp.localDate(of: v.createdAt)?.description ?? v.createdAt) · \(v.source.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = v.changeNote {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("版本历史")
    }
}

private struct VersionDetail: View {
    @Environment(TrainingStore.self) private var store
    let versionId: String

    var body: some View {
        if let v = store.state.planVersions.first(where: { $0.id == versionId }) {
            let parent = store.state.planVersions.first { $0.id == v.parentVersionId }
            PlanDetailList(plan: v, today: store.today, isCurrent: v.id == store.state.currentPlanId,
                           diffFromParent: parent.map { comparePlanVersions($0, v) },
                           onSelect: { store.selectVersion(id: v.id) })
                .navigationTitle("V\(v.version)")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
