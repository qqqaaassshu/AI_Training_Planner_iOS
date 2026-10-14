import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// AI 调用适配层（对应原型 utils/ai/providers.ts）：按服务配置的接口格式发送请求，返回模型的文本回复。
//
// - anthropic：Messages API（Swift 没有官方 SDK，直接走 HTTP）
// - openai：OpenAI 兼容的 /chat/completions（DeepSeek、通义千问、Kimi、Ollama、各类代理等）
//
// 正式 App 中：用户自带 Key 存钥匙串，由 iPhone 发起调用，手表不持有 Key。

public struct AICallParams: Sendable {
    public var system: String
    public var user: String
    /// 覆盖配置里的 maxTokens（测试连接时用）
    public var maxTokens: Int?

    public init(system: String, user: String, maxTokens: Int? = nil) {
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
    }
}

public struct AIProviderError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    /// 稍后重试可能成功（限流、服务端错误、网络问题、超时）
    public var retryable: Bool
    public init(_ message: String, retryable: Bool) {
        self.message = message
        self.retryable = retryable
    }
    public var errorDescription: String? { message }
}

/// HTTP 传输层，测试时替换
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public struct AIClient: Sendable {
    public var transport: HTTPTransport
    /// Anthropic 请求在限流、5xx、网络错误时额外重试的次数（与原型 SDK 的 maxRetries: 1 一致）
    public var anthropicRetries = 1
    public var retryDelay: Duration = .milliseconds(500)

    public static let anthropicVersion = "2023-06-01"
    /// 被安全分类器拒绝时由服务端自动换模型重试（fallbacks: "default"）
    public static let anthropicFallbackBeta = "server-side-fallback-2026-07-01"

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// 按服务配置调用模型，返回文本回复（应为 JSON，由调用方解析与校验）
    public func call(_ config: AIServiceConfig, apiKey: String, _ p: AICallParams) async throws -> String {
        let timeout = config.timeoutSec
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                config.format == .anthropic
                    ? try await callAnthropic(config, apiKey: apiKey, p)
                    : try await callOpenAICompatible(config, apiKey: apiKey, p)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AIProviderError("超过 \(timeout) 秒未响应，可在高级设置里调大超时时间", retryable: true)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// 测试连接：发送一条极短的请求，返回耗时（毫秒）与回复开头
    public func test(_ config: AIServiceConfig, apiKey: String) async throws -> (ms: Int, reply: String) {
        let clock = ContinuousClock()
        let start = clock.now
        let reply = try await call(config, apiKey: apiKey, AICallParams(system: "这是连接测试。", user: "请只回复两个字母：OK", maxTokens: 512))
        let elapsed = clock.now - start
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        return (ms, String(reply.prefix(40)))
    }

    // MARK: Anthropic

    func anthropicRequest(_ config: AIServiceConfig, apiKey: String, _ p: AICallParams) throws -> URLRequest {
        guard let url = URL(string: "\(config.resolvedBaseURL)/v1/messages") else { throw AIProviderError("接口地址无效", retryable: false) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue(Self.anthropicFallbackBeta, forHTTPHeaderField: "anthropic-beta")
        for (k, v) in config.extraHeaders ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        let body: JSONValue = [
            "model": .string(config.model),
            "max_tokens": .number(Double(p.maxTokens ?? config.maxTokens)),
            "system": .string(p.system),
            "messages": [["role": "user", "content": .string(p.user)]],
            "output_config": ["effort": .string(p.maxTokens != nil ? "low" : "medium")],
            "fallbacks": "default",
        ]
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    func callAnthropic(_ config: AIServiceConfig, apiKey: String, _ p: AICallParams) async throws -> String {
        let req = try anthropicRequest(config, apiKey: apiKey, p)
        var attempt = 0
        while true {
            do {
                return try await anthropicOnce(req, config: config, p)
            } catch let e as AIProviderError where e.retryable && attempt < anthropicRetries {
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    private func anthropicOnce(_ req: URLRequest, config: AIServiceConfig, _ p: AICallParams) async throws -> String {
        let (data, res) = try await send(req)
        let json = try? JSONValue.parse(data)
        guard (200..<300).contains(res.statusCode) else {
            let detail = json?["error"]?["message"]?.stringValue ?? String(decoding: data, as: UTF8.self)
            switch res.statusCode {
            case 401: throw AIProviderError("API Key 无效", retryable: false)
            case 403: throw AIProviderError("该 Key 无权使用此模型", retryable: false)
            case 404: throw AIProviderError("找不到模型 \(config.model)，或接口地址有误", retryable: false)
            case 429: throw AIProviderError("请求过于频繁或额度不足，请稍后再试", retryable: true)
            default:
                throw AIProviderError("服务错误（\(res.statusCode)）：\(detail.prefix(200))", retryable: res.statusCode >= 500 || res.statusCode == 408 || res.statusCode == 409)
            }
        }
        let stop = json?["stop_reason"]?.stringValue
        if stop == "refusal" { throw AIProviderError("模型拒绝了本次请求，请调整内容后重试", retryable: false) }
        if stop == "max_tokens" && p.maxTokens == nil {
            throw AIProviderError("回复超出长度上限，可在高级设置里调大最大输出长度", retryable: false)
        }
        let text = (json?["content"]?.arrayValue ?? [])
            .compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
            .joined()
        return text.trimmed
    }

    // MARK: OpenAI 兼容

    func openAIRequest(_ config: AIServiceConfig, apiKey: String, _ p: AICallParams) throws -> URLRequest {
        guard let url = URL(string: "\(config.resolvedBaseURL)/chat/completions") else { throw AIProviderError("接口地址无效", retryable: false) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.extraHeaders ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": [["role": "system", "content": .string(p.system)], ["role": "user", "content": .string(p.user)]],
            "max_tokens": .number(Double(p.maxTokens ?? config.maxTokens)),
        ]
        if let t = config.temperature { body["temperature"] = .number(t) }
        if config.jsonMode && p.maxTokens == nil { body["response_format"] = ["type": "json_object"] }
        req.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return req
    }

    func callOpenAICompatible(_ config: AIServiceConfig, apiKey: String, _ p: AICallParams) async throws -> String {
        let (data, res) = try await send(try openAIRequest(config, apiKey: apiKey, p))
        let json = try? JSONValue.parse(data)
        guard (200..<300).contains(res.statusCode) else {
            throw httpError(res.statusCode, json?["error"]?["message"]?.stringValue ?? String(decoding: data, as: UTF8.self))
        }
        let choice = json?["choices"]?.arrayValue?.first
        guard let content = choice?["message"]?["content"]?.stringValue, !content.isEmpty else {
            throw AIProviderError("服务返回了空内容，请检查模型名称", retryable: false)
        }
        if choice?["finish_reason"]?.stringValue == "length" && p.maxTokens == nil {
            throw AIProviderError("回复超出长度上限，可在高级设置里调大最大输出长度", retryable: false)
        }
        return content.trimmed
    }

    // MARK: 公共

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as AIProviderError {
            throw e
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AIProviderError("无法连接到服务：可能是网络问题或接口地址错误，请检查网络后重试，或改用“复制提示词”方式", retryable: true)
        }
    }
}

func httpError(_ status: Int, _ detail: String) -> AIProviderError {
    let d = detail.isEmpty ? "" : "：\(detail.prefix(200))"
    switch status {
    case 401: return AIProviderError("API Key 无效\(d)", retryable: false)
    case 403: return AIProviderError("没有权限\(d)", retryable: false)
    case 404: return AIProviderError("接口地址或模型不存在\(d)", retryable: false)
    case 429: return AIProviderError("请求过于频繁或额度不足\(d)", retryable: true)
    default: return AIProviderError("服务错误（\(status)）\(d)", retryable: status >= 500)
    }
}
