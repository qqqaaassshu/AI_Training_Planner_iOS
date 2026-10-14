import Foundation

/// 常用 AI 服务预设（对应原型 utils/ai/presets.ts）。模型名仅作建议，可在设置里自由填写。
public struct AIPreset: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var format: AIApiFormat
    public var baseURL: String
    public var defaultModel: String
    /// 输入框建议
    public var modelSuggestions: [String]
    /// 本地服务（如 Ollama）不需要 Key
    public var keyOptional = false
    public var keyPlaceholder: String?
    /// 获取 Key 的说明
    public var hint: String?
    public var jsonMode = false
}

public let aiPresets: [AIPreset] = [
    AIPreset(id: "anthropic", label: "Anthropic Claude", format: .anthropic, baseURL: "https://api.anthropic.com",
             defaultModel: "claude-opus-5-5", modelSuggestions: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
             keyPlaceholder: "sk-ant-…", hint: "在 console.anthropic.com 创建 API Key"),
    AIPreset(id: "openai", label: "OpenAI", format: .openai, baseURL: "https://api.openai.com/v1",
             defaultModel: "", modelSuggestions: [], keyPlaceholder: "sk-…", jsonMode: true),
    AIPreset(id: "deepseek", label: "DeepSeek", format: .openai, baseURL: "https://api.deepseek.com/v1",
             defaultModel: "deepseek-chat", modelSuggestions: ["deepseek-chat", "deepseek-reasoner"], keyPlaceholder: "sk-…", jsonMode: true),
    AIPreset(id: "qwen", label: "通义千问（阿里云百炼）", format: .openai, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
             defaultModel: "qwen-plus", modelSuggestions: ["qwen-plus", "qwen-max", "qwen-turbo"], keyPlaceholder: "sk-…", jsonMode: true),
    AIPreset(id: "moonshot", label: "Kimi（月之暗面）", format: .openai, baseURL: "https://api.moonshot.cn/v1",
             defaultModel: "", modelSuggestions: [], keyPlaceholder: "sk-…", jsonMode: true),
    AIPreset(id: "zhipu", label: "智谱 GLM", format: .openai, baseURL: "https://open.bigmodel.cn/api/paas/v4",
             defaultModel: "", modelSuggestions: []),
    AIPreset(id: "doubao", label: "豆包（火山方舟）", format: .openai, baseURL: "https://ark.cn-beijing.volces.com/api/v3",
             defaultModel: "", modelSuggestions: [], hint: "模型处填写方舟控制台里的模型 ID 或推理接入点 ID"),
    AIPreset(id: "ollama", label: "Ollama（本地模型）", format: .openai, baseURL: "http://localhost:11434/v1",
             defaultModel: "", modelSuggestions: [], keyOptional: true,
             hint: "需在电脑上运行 Ollama；在 iPhone 上请把地址改成电脑的局域网 IP", jsonMode: true),
    AIPreset(id: "custom", label: "自定义（OpenAI 兼容）", format: .openai, baseURL: "",
             defaultModel: "", modelSuggestions: [], keyOptional: true,
             hint: "任何兼容 /chat/completions 的服务或代理，例如 OpenRouter、One API、公司内网网关"),
]

public func preset(id: String) -> AIPreset {
    aiPresets.first { $0.id == id } ?? aiPresets[aiPresets.count - 1]
}

public func createService(fromPreset presetId: String, existing: [AIServiceConfig] = []) -> AIServiceConfig {
    let p = preset(id: presetId)
    let sameCount = existing.filter { $0.preset == p.id }.count
    return AIServiceConfig(
        name: sameCount > 0 ? "\(p.label) \(sameCount + 1)" : p.label,
        preset: p.id,
        format: p.format,
        baseURL: p.baseURL.isEmpty ? nil : p.baseURL,
        model: p.defaultModel,
        maxTokens: 16000,
        jsonMode: p.jsonMode,
        timeoutSec: 120
    )
}

nonisolated(unsafe) private let headerKeyRegex = jsRegex("^[A-Za-z0-9-]+$")

/// “Header: value” 每行一个；返回解析结果与无法解析的行（保持输入顺序）
public func parseHeaders(_ text: String) -> (headers: [(String, String)], invalid: [String]) {
    var headers: [(String, String)] = []
    var invalid: [String] = []
    for line in text.components(separatedBy: "\n").map(\.trimmed) where !line.isEmpty {
        let i = line.firstIndex(of: ":")
        let key = i.map { String(line[..<$0]).trimmed } ?? ""
        if key.isEmpty || !key.matches(headerKeyRegex) {
            invalid.append(line)
        } else {
            let value = String(line[line.index(after: i!)...]).trimmed
            if let idx = headers.firstIndex(where: { $0.0 == key }) { headers[idx].1 = value } else { headers.append((key, value)) }
        }
    }
    return (headers, invalid)
}

/// 字典没有顺序，按键名排序输出
public func formatHeaders(_ h: [String: String]?) -> String {
    (h ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
}

extension AIServiceConfig {
    /// 实际使用的接口地址（去掉末尾斜杠）
    public var resolvedBaseURL: String {
        var s = (baseURL?.isEmpty == false ? baseURL! : TrainingCore.preset(id: preset).baseURL)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 配置是否可以发起调用（不含 Key 检查）
    public var problems: [String] {
        var p: [String] = []
        let url = baseURL?.isEmpty == false ? baseURL! : TrainingCore.preset(id: preset).baseURL
        if url.isEmpty { p.append("请填写接口地址") }
        else if !(url.hasPrefix("http://") || url.hasPrefix("https://")) { p.append("接口地址需以 http:// 或 https:// 开头") }
        if model.trimmed.isEmpty { p.append("请填写模型名称") }
        return p
    }
}
