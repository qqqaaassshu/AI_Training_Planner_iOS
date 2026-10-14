import SwiftUI
import TrainingCore

/// AI 设置：多个服务、当前服务、数据上传同意、每周自动复盘
struct AISettingsView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let settings = store.state.aiSettings
        List {
            Section {
                ForEach(settings.services) { s in
                    NavigationLink {
                        ServiceEditorView(service: s)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.name)
                                Text(s.model.isEmpty ? "未填写模型" : s.model).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.id == settings.activeServiceId {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("设为当前") { store.updateAISettings { $0.activeServiceId = s.id } }.tint(.accentColor)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { store.removeService(id: settings.services[i].id) }
                }
                Menu {
                    ForEach(aiPresets) { p in
                        Button(p.label) { store.upsertService(createService(fromPreset: p.id, existing: settings.services)) }
                    }
                } label: {
                    Label("添加服务", systemImage: "plus")
                }
            } header: {
                Text("服务")
            } footer: {
                Text("向右滑动设为当前服务。API Key 保存在钥匙串里，不会同步到手表。")
            }

            Section {
                Toggle("允许把训练数据发送给 AI 服务", isOn: Binding(
                    get: { settings.consentGiven },
                    set: { v in store.updateAISettings { $0.consentGiven = v } }
                ))
                Toggle("每周自动复盘", isOn: Binding(
                    get: { settings.autoWeeklyReview },
                    set: { v in store.updateAISettings { $0.autoWeeklyReview = v } }
                ))
            } footer: {
                Text("每周自动复盘：打开 App 时，如果距上次每周复盘已满 7 天，会用当前服务运行一次")
            }
        }
        .navigationTitle("AI 设置")
    }
}

/// 编辑一个服务
struct ServiceEditorView: View {
    @Environment(TrainingStore.self) private var store
    @State private var service: AIServiceConfig
    @State private var apiKey: String
    @State private var headersText: String
    @State private var testResult: String?
    @State private var testing = false
    @State private var loadedKey = false

    init(service: AIServiceConfig) {
        _service = State(initialValue: service)
        _apiKey = State(initialValue: "")
        _headersText = State(initialValue: formatHeaders(service.extraHeaders))
    }

    var body: some View {
        let p = preset(id: service.preset)
        Form {
            Section {
                TextField("名称", text: $service.name)
                LabeledContent("接口格式", value: service.format == .anthropic ? "Anthropic" : "OpenAI 兼容")
                TextField("接口地址", text: Binding(get: { service.baseURL ?? "" }, set: { service.baseURL = $0.isEmpty ? nil : $0 }),
                          prompt: Text(p.baseURL.isEmpty ? "https://…" : p.baseURL))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型", text: $service.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !p.modelSuggestions.isEmpty {
                    Picker("常用模型", selection: $service.model) {
                        ForEach(p.modelSuggestions, id: \.self) { Text($0).tag($0) }
                        if !p.modelSuggestions.contains(service.model) { Text("自定义").tag(service.model) }
                    }
                }
                SecureField(p.keyOptional ? "API Key（可选）" : "API Key", text: $apiKey, prompt: Text(p.keyPlaceholder ?? "API Key"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                if let hint = p.hint { Text(hint) }
            }

            Section("高级") {
                Stepper("最大输出 \(service.maxTokens)", value: $service.maxTokens, in: 1000...128_000, step: 1000)
                Stepper("超时 \(service.timeoutSec) 秒", value: $service.timeoutSec, in: 10...600, step: 10)
                if service.format == .openai {
                    Toggle("JSON 模式", isOn: $service.jsonMode)
                    LabeledContent("温度") {
                        TextField("默认", value: $service.temperature, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                VStack(alignment: .leading) {
                    Text("额外请求头（每行一个 Header: value）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $headersText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 60)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if !service.problems.isEmpty {
                Section {
                    ForEach(service.problems, id: \.self) { Text($0).foregroundStyle(.orange) }
                }
            }

            Section {
                Button {
                    test()
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing || !service.isReady(apiKey: apiKey))
                if let testResult { Text(testResult).font(.caption) }
            }
        }
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loadedKey else { return }
            loadedKey = true
            apiKey = store.apiKey(for: service.id) ?? ""
        }
        .onDisappear(perform: save)
    }

    private func save() {
        var s = service
        let parsed = parseHeaders(headersText)
        s.extraHeaders = parsed.headers.isEmpty ? nil : Dictionary(parsed.headers, uniquingKeysWith: { _, b in b })
        store.upsertService(s)
        store.setAPIKey(apiKey, for: s.id)
    }

    private func test() {
        save()
        testing = true
        testResult = nil
        let config = service
        let key = apiKey
        Task {
            do {
                let r = try await AIClient().test(config, apiKey: key)
                testResult = "✅ 连接成功（\(r.ms) 毫秒）：\(r.reply)"
            } catch {
                testResult = "❌ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
