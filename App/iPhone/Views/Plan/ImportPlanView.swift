import SwiftUI
import TrainingCore
import UniformTypeIdentifiers

/// 导入计划：粘贴 JSON 或自然语言 → 预览（错误 / 未识别的行 / 与当前版本的差异）→ 确认后生成新版本
struct ImportPlanView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var mode: PlanImportMode = .json
    @State private var text = ""
    @State private var result: ValidationResult<PlanImportPreview>?
    @State private var pickingFile = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("格式", selection: $mode) {
                        ForEach(PlanImportMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextEditor(text: $text)
                        .font(mode == .json ? .system(.footnote, design: .monospaced) : .body)
                        .frame(height: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(mode == .json ? "粘贴 JSON 计划…" : "例如：\n周二训练：\n深蹲3组10次 20kg\n平板支撑3组30秒")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    HStack {
                        Button("载入示例") {
                            text = samplePlanText(mode: mode, today: store.today)
                        }
                        Spacer()
                        Button("从文件导入") { pickingFile = true }
                    }
                    .font(.footnote)
                }

                if let current = store.currentPlan {
                    Section {
                        LabeledContent("当前计划", value: "\(current.planName) V\(current.version)")
                    } footer: {
                        Text("导入后生成 V\(store.state.planVersions.map(\.version).max().map { $0 + 1 } ?? 1)；任务按标题沿用原来的 id，历史统计保持连续")
                    }
                }

                switch result {
                case .failure(let errors)?:
                    Section {
                        ForEach(Array(errors.prefix(8).enumerated()), id: \.offset) { _, e in
                            Text(e).font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                        }
                        if errors.count > 8 { Text("…还有 \(errors.count - 8) 项").font(.caption).foregroundStyle(.red) }
                    } header: {
                        Label("无法导入，请修正以下问题", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                case .ok(let preview)?:
                    previewSections(preview)
                case nil:
                    EmptyView()
                }
            }
            .navigationTitle("导入计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") {
                        if case .ok(let preview)? = result {
                            store.importPlan(preview)
                            dismiss()
                        }
                    }
                    .disabled(result?.value == nil)
                }
            }
            .onChange(of: text) { refresh() }
            .onChange(of: mode) { refresh() }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json, .plainText, .text]) { picked in
                load(picked)
            }
        }
    }

    @ViewBuilder
    private func previewSections(_ p: PlanImportPreview) -> some View {
        Section("预览") {
            LabeledContent("名称", value: p.input.planName)
            LabeledContent("开始", value: p.input.startDate.description)
            if let end = p.input.endDate { LabeledContent("结束", value: end.description) }
            LabeledContent("任务", value: "\(p.input.tasks.count) 个")
            ForEach(p.input.tasks) { t in
                VStack(alignment: .leading) {
                    Text(t.title)
                    Text(t.schedule.summary + (t.exercises.map { " · \($0.count) 个动作" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if !p.warnings.isEmpty {
            Section {
                ForEach(p.warnings, id: \.self) { Text($0).font(.caption) }
            } header: {
                Label("以下内容没有识别，导入时会忽略", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        }
        if let diff = p.diff {
            Section("相对当前版本") { PlanDiffRows(diff: diff) }
        }
    }

    private func refresh() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = trimmed.isEmpty ? nil : previewPlanImport(trimmed, mode: mode, today: store.today, current: store.currentPlan)
    }

    private func load(_ picked: Result<URL, Error>) {
        do {
            let url = try picked.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let content = try String(contentsOf: url, encoding: .utf8)
            mode = url.pathExtension.lowercased() == "json" || content.trimmingCharacters(in: .whitespaces).hasPrefix("{") ? .json : .naturalLanguage
            text = content
        } catch {
            result = .failure(["读取文件失败：\(error.localizedDescription)"])
        }
    }
}
