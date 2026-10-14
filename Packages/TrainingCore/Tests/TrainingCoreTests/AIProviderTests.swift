import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrainingCore

/// 记录请求并按顺序返回预设响应
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case response(Int, String)
        case failure(Error)
        case hang
    }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
        switch reply {
        case .response(let status, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .failure(let e): throw e
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }

    var lastBody: JSONValue? { lock.withLock { requests.last?.httpBody.flatMap { try? JSONValue.parse($0) } } }
    var lastRequest: URLRequest? { lock.withLock { requests.last } }
    var count: Int { lock.withLock { requests.count } }
}

func openAIOK(_ content: String, finish: String = "stop") -> MockTransport.Reply {
    let body = try! JSONEncoder().encode(JSONValue.object(["choices": [["message": ["content": .string(content)], "finish_reason": .string(finish)]]]))
    return .response(200, String(decoding: body, as: UTF8.self))
}

@Suite("presets") struct PresetTests {
    @Test("从预设创建服务，同类自动编号") func numbering() {
        let a = createService(fromPreset: "deepseek")
        #expect(a.name == "DeepSeek" && a.format == .openai && a.model == "deepseek-chat" && a.jsonMode)
        let b = createService(fromPreset: "deepseek", existing: [a])
        #expect(b.name == "DeepSeek 2")
        #expect(b.id != a.id)
        #expect(createService(fromPreset: "anthropic").model == "claude-opus-5-5")
    }

    @Test("配置检查") func problems() {
        var custom = createService(fromPreset: "custom")
        #expect(custom.problems == ["请填写接口地址", "请填写模型名称"])
        custom.baseURL = "api.x.com"
        custom.model = "m"
        #expect(custom.problems == ["接口地址需以 http:// 或 https:// 开头"])
        custom.baseURL = "https://api.x.com/v1"
        #expect(custom.problems.isEmpty)
    }

    @Test("请求头解析与格式化") func headers() {
        let r = parseHeaders("X-Token: abc\n\nX-Org:  1 \n坏行")
        #expect(r.headers.map(\.0) == ["X-Token", "X-Org"])
        #expect(r.headers.map(\.1) == ["abc", "1"])
        #expect(r.invalid == ["坏行"])
        #expect(formatHeaders(["X-Token": "abc", "X-Org": "1"]) == "X-Org: 1\nX-Token: abc")
    }
}

@Suite("OpenAI 兼容调用") struct OpenAICompatibleTests {
    var service: AIServiceConfig {
        var s = createService(fromPreset: "custom")
        s.baseURL = "https://gw.example.com/v1/"
        s.model = "my-model"
        s.temperature = 0.3
        s.jsonMode = true
        s.extraHeaders = ["X-Proxy": "p1"]
        return s
    }

    @Test("请求格式正确") func request() async throws {
        let t = MockTransport([openAIOK(#"{"a":1}"#)])
        let text = try await AIClient(transport: t).call(service, apiKey: "k1", AICallParams(system: "S", user: "U"))
        #expect(text == #"{"a":1}"#)
        let req = try #require(t.lastRequest)
        #expect(req.url?.absoluteString == "https://gw.example.com/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer k1")
        #expect(req.value(forHTTPHeaderField: "X-Proxy") == "p1")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(t.lastBody)
        #expect(body["model"] == "my-model")
        #expect(body["temperature"] == 0.3)
        #expect(body["response_format"] == ["type": "json_object"])
        #expect(body["messages"] == [["role": "system", "content": "S"], ["role": "user", "content": "U"]])
    }

    @Test("没有 Key 时不发送 Authorization；未设温度时不发送") func optional() async throws {
        let t = MockTransport([openAIOK("x")])
        var s = service
        s.temperature = nil
        s.jsonMode = false
        _ = try await AIClient(transport: t).call(s, apiKey: "", AICallParams(system: "S", user: "U"))
        #expect(t.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(t.lastBody?["temperature"] == nil)
        #expect(t.lastBody?["response_format"] == nil)
    }

    @Test("HTTP 错误", arguments: [(401, "API Key 无效", false), (404, "接口地址或模型不存在", false), (429, "请求过于频繁", true), (503, "服务错误（503）", true)])
    func httpErrors(status: Int, message: String, retryable: Bool) async {
        let t = MockTransport([.response(status, #"{"error":{"message":"detail"}}"#)])
        do {
            _ = try await AIClient(transport: t).call(service, apiKey: "k", AICallParams(system: "", user: ""))
            Issue.record("应当抛出错误")
        } catch let e as AIProviderError {
            #expect(e.message.contains(message))
            #expect(e.message.contains("detail"))
            #expect(e.retryable == retryable)
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test("网络失败给出可操作的提示") func network() async {
        let t = MockTransport([.failure(URLError(.notConnectedToInternet))])
        await #expect(throws: AIProviderError.self) {
            _ = try await AIClient(transport: t).call(service, apiKey: "k", AICallParams(system: "", user: ""))
        }
        let e = await errorOf { try await AIClient(transport: t).call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e?.message.contains("无法连接") == true)
        #expect(e?.retryable == true)
    }

    @Test("输出被截断时报错") func truncated() async {
        let t = MockTransport([openAIOK(#"{"a":"#, finish: "length")])
        let e = await errorOf { try await AIClient(transport: t).call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e?.message.contains("长度上限") == true)
    }

    @Test("超时") func timeout() async {
        var s = service
        s.timeoutSec = 1
        let t = MockTransport([.hang])
        let e = await errorOf { try await AIClient(transport: t).call(s, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e?.message.contains("超过 1 秒") == true)
    }
}

@Suite("Anthropic 调用") struct AnthropicTests {
    let service = createService(fromPreset: "anthropic")
    let okBody = #"{"type":"message","content":[{"type":"text","text":" {\"summary\":\"好\",\"findings\":[]} "}],"stop_reason":"end_turn"}"#

    @Test("请求格式：Messages API、服务端换模型重试、effort") func request() async throws {
        let t = MockTransport([.response(200, okBody)])
        let text = try await AIClient(transport: t).call(service, apiKey: "sk-ant", AICallParams(system: "S", user: "U"))
        #expect(text == #"{"summary":"好","findings":[]}"#)
        let req = try #require(t.lastRequest)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try #require(t.lastBody)
        #expect(body["model"] == "claude-opus-5-5")
        #expect(body["max_tokens"] == 16000)
        #expect(body["system"] == "S")
        #expect(body["messages"] == [["role": "user", "content": "U"]])
        #expect(body["fallbacks"] == "default")
        #expect(body["output_config"] == ["effort": "medium"])
        #expect(body["thinking"] == nil)
        #expect(body["temperature"] == nil)
    }

    @Test("测试连接用低 effort 与短输出") func testConnection() async throws {
        let t = MockTransport([.response(200, #"{"content":[{"type":"text","text":"OK"}],"stop_reason":"max_tokens"}"#)])
        let r = try await AIClient(transport: t).test(service, apiKey: "k")
        #expect(r.reply == "OK")
        #expect(t.lastBody?["max_tokens"] == 512)
        #expect(t.lastBody?["output_config"] == ["effort": "low"])
    }

    @Test("拒绝与截断") func refusal() async {
        let refused = MockTransport([.response(200, #"{"content":[],"stop_reason":"refusal"}"#)])
        let e1 = await errorOf { try await AIClient(transport: refused).call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e1?.message.contains("拒绝") == true)
        let cut = MockTransport([.response(200, #"{"content":[{"type":"text","text":"{"}],"stop_reason":"max_tokens"}"#)])
        let e2 = await errorOf { try await AIClient(transport: cut).call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e2?.message.contains("长度上限") == true)
    }

    @Test("错误映射", arguments: [(401, "API Key 无效", false), (403, "无权使用", false), (404, "找不到模型 claude-opus-5-5", false), (400, "服务错误（400）：bad", false)])
    func errors(status: Int, message: String, retryable: Bool) async {
        let t = MockTransport([.response(status, #"{"type":"error","error":{"type":"x","message":"bad"}}"#)])
        let e = await errorOf { try await AIClient(transport: t).call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e?.message.contains(message) == true)
        #expect(e?.retryable == retryable)
        #expect(t.count == 1)
    }

    @Test("限流与 5xx 重试一次") func retry() async throws {
        var client = AIClient(transport: MockTransport([.response(529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#), .response(200, okBody)]))
        client.retryDelay = .milliseconds(1)
        _ = try await client.call(service, apiKey: "k", AICallParams(system: "", user: ""))
        #expect((client.transport as! MockTransport).count == 2)

        var always429 = AIClient(transport: MockTransport([.response(429, "{}")]))
        always429.retryDelay = .milliseconds(1)
        let e = await errorOf { try await always429.call(service, apiKey: "k", AICallParams(system: "", user: "")) }
        #expect(e?.retryable == true)
        #expect((always429.transport as! MockTransport).count == 2)
    }

    @Test("runAnalysis：校验回复并生成分析记录") func runAnalysis() async throws {
        let t = MockTransport([.response(200, okBody)])
        let plan = makePlan()
        let input = buildAnalysisInput(kind: .weeklyReview, plan: plan, versions: [plan], records: [], dailyWellness: [],
                                       today: d("2026-06-16"), userNote: "下周出差")
        let a = try await AIClient(transport: t).runAnalysis(input: input, planVersionId: plan.id, service: service, apiKey: "k")
        #expect(a.channel == .api && a.provider == "Anthropic Claude" && a.model == "claude-opus-5-5")
        #expect(a.userNote == "下周出差")
        #expect(a.summary == "好")

        let bad = MockTransport([.response(200, #"{"content":[{"type":"text","text":"抱歉"}],"stop_reason":"end_turn"}"#)])
        await #expect(throws: AnalysisFormatError.self) {
            _ = try await AIClient(transport: bad).runAnalysis(input: input, planVersionId: plan.id, service: service, apiKey: "k")
        }
    }
}

func errorOf(_ body: () async throws -> some Any) async -> AIProviderError? {
    do {
        _ = try await body()
        return nil
    } catch {
        return error as? AIProviderError
    }
}
