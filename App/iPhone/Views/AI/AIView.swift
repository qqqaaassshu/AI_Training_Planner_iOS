import SwiftUI
import TrainingCore
import UIKit

/// AI 页：本地安全提醒、通过 API 分析或复制提示词手动分析、分析结果列表
struct AIView: View {
    @Environment(TrainingStore.self) private var store

    @State private var kind: AnalysisKind = .weeklyReview
    @State private var userNote = ""
    @State private var includeNotes = false
    @State private var error: String?
    @State private var askingConsent = false
    @State private var pastingReply = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                let alerts = detectAlerts(records: store.state.records, wellness: store.state.dailyWellness, today: store.today)
                if !alerts.isEmpty {
                    Section("本地安全提醒") {
                        FindingList(findings: alerts)
                    }
                }

                Section {
                    Picker("分析类型", selection: $kind) {
                        ForEach(AnalysisKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("补充说明（可选），例如“下周出差”", text: $userNote, axis: .vertical)
                        .lineLimit(1...4)
                    Toggle("包含文字备注", isOn: $includeNotes)
                } header: {
                    Text("新的分析")
                } footer: {
                    Text("发送的是最近的执行数据、计划和个人档案；默认不包含你写的备注")
                }

                Section {
                    if let service = store.activeService {
                        Button {
                            if store.state.aiSettings.consentGiven { run() } else { askingConsent = true }
                        } label: {
                            HStack {
                                Label("用 \(service.name) 分析", systemImage: "sparkles")
                                Spacer()
                                if store.analyzing { ProgressView() }
                            }
                        }
                        .disabled(store.analyzing || !store.activeServiceReady || store.currentPlan == nil)
                        if !store.activeServiceReady {
                            Text(service.problems.first ?? "请在 AI 设置里填写 API Key").font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        NavigationLink("添加 AI 服务后可直接分析") { AISettingsView() }
                    }
                    Button {
                        UIPasteboard.general.string = buildManualPrompt(store.analysisInput(kind: kind, includeNotes: includeNotes, userNote: userNote))
                        copied = true
                    } label: {
                        Label(copied ? "已复制，粘贴给任意 AI" : "复制提示词（手动分析）", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        pastingReply = true
                    } label: {
                        Label("粘贴 AI 的回复", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }

                if !store.state.analyses.isEmpty {
                    Section("分析记录") {
                        ForEach(store.state.analysesNewestFirst) { a in
                            NavigationLink {
                                AnalysisDetailView(analysisId: a.id)
                            } label: {
                                AnalysisRow(analysis: a)
                            }
                        }
                        .onDelete { offsets in
                            let list = store.state.analysesNewestFirst
                            for i in offsets { store.deleteAnalysis(id: list[i].id) }
                        }
                    }
                }
            }
            .navigationTitle("AI")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ProfileView() } label: { Label("个人档案", systemImage: "person.crop.circle") }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { AISettingsView() } label: { Label("AI 设置", systemImage: "gearshape") }
                }
            }
            .onChange(of: kind) { copied = false }
            .alert("发送数据给 AI 服务？", isPresented: $askingConsent) {
                Button("同意并分析") {
                    store.updateAISettings { $0.consentGiven = true }
                    run()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将把训练计划、执行记录（完成情况、疼痛与疲劳评分）和个人档案发送给 \(store.activeService?.name ?? "AI 服务")。文字备注只有在打开开关时才会发送。")
            }
            .sheet(isPresented: $pastingReply) {
                ManualReplyView(kind: kind, includeNotes: includeNotes, userNote: userNote)
            }
        }
    }

    private func run() {
        error = nil
        Task {
            do {
                try await store.runAnalysis(kind: kind, includeNotes: includeNotes, userNote: userNote)
                userNote = ""
            } catch let e as AnalysisFormatError {
                error = "AI 返回的格式不对：\(e.errors.prefix(3).joined(separator: "；"))"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AnalysisRow: View {
    let analysis: AIAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(analysis.kind.label).fontWeight(.medium)
                Text("\(analysis.range.from) ~ \(analysis.range.to)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(analysis.status.label)
                    .font(.caption)
                    .foregroundStyle(analysis.status == .new ? Color.accentColor : Color.secondary)
            }
            Text(analysis.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if analysis.findings.contains(where: { $0.level == .risk }) {
                Label("有风险提醒", systemImage: "exclamationmark.shield.fill").font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// 发现的问题（info / warn / risk）
struct FindingList: View {
    let findings: [Finding]

    var body: some View {
        ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
            Label {
                Text(f.text).font(.callout)
            } icon: {
                Image(systemName: f.level.symbol).foregroundStyle(f.level.color)
            }
        }
    }
}

extension FindingLevel {
    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .risk: return "exclamationmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warn: return .orange
        case .risk: return .red
        }
    }
}

/// 分析详情：总结、发现、建议计划的变化，确认后生成新版本
struct AnalysisDetailView: View {
    @Environment(TrainingStore.self) private var store
    let analysisId: String
    @State private var confirming = false

    var body: some View {
        if let a = store.state.analyses.first(where: { $0.id == analysisId }) {
            List {
                Section {
                    Text(a.summary)
                    LabeledContent("区间", value: "\(a.range.from) ~ \(a.range.to)")
                    LabeledContent("来源", value: a.channel == .api ? (a.model ?? "API") : "手动导入")
                    if let note = a.userNote { LabeledContent("补充说明", value: note) }
                }
                if !a.findings.isEmpty {
                    Section("发现") { FindingList(findings: a.findings) }
                }
                if let plan = a.suggestedPlan {
                    Section {
                        if let note = plan.changeNote { Text(note) }
                        if let diff = a.previewDiff(current: store.currentPlan, versions: store.state.planVersions) {
                            PlanDiffRows(diff: diff)
                        }
                    } header: {
                        Text("建议的下一版计划")
                    } footer: {
                        Text("接受后会生成新的计划版本并设为当前；可以在版本历史里切换回原来的版本")
                    }
                }
                if a.status == .new {
                    Section {
                        Button(a.suggestedPlan == nil ? "标记为已读" : "接受建议") {
                            if a.suggestedPlan == nil { store.acceptAnalysis(id: a.id) } else { confirming = true }
                        }
                        Button("忽略", role: .destructive) { store.rejectAnalysis(id: a.id) }
                    }
                } else {
                    Section { LabeledContent("状态", value: a.status.label) }
                }
            }
            .navigationTitle(a.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("应用这个建议？", isPresented: $confirming, titleVisibility: .visible) {
                Button("生成新版本并设为当前") { store.acceptAnalysis(id: a.id) }
            }
        } else {
            ContentUnavailableView("分析已删除", systemImage: "trash")
        }
    }
}

/// 手动分析：把外部 AI 的回复粘贴回来
struct ManualReplyView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: AnalysisKind
    let includeNotes: Bool
    let userNote: String
    @State private var text = ""
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 240)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Button("从剪贴板粘贴") { text = UIPasteboard.general.string ?? "" }
                }
                if !errors.isEmpty {
                    Section("无法识别") {
                        ForEach(errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("粘贴 AI 回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        switch store.importManualReply(text, kind: kind, includeNotes: includeNotes, userNote: userNote) {
                        case .ok: dismiss()
                        case .failure(let e): errors = e
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
