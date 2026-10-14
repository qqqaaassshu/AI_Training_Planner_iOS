import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
import TrainingCore
@testable import AITrainingPlanner

/// 返回固定回复的网络层，测试不访问网络
struct FixedTransport: HTTPTransport {
    let body: String
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
@Suite("AI 分析流程")
struct AIFlowTests {
    let container: ModelContainer

    init() throws {
        container = try TrainingSchema.makeContainer(inMemory: true)
    }

    /// 本地 Ollama 服务不需要 Key，避免测试依赖钥匙串
    func makeStore(reply: String) throws -> TrainingStore {
        let content = try String(decoding: JSONEncoder().encode(reply), as: UTF8.self)
        let body = #"{"choices":[{"message":{"content":\#(content)},"finish_reason":"stop"}]}"#
        let store = TrainingStore(context: container.mainContext, aiClient: AIClient(transport: FixedTransport(body: body)))
        let text = samplePlanText(mode: .json, today: store.today)
        store.importPlan(try #require(previewPlanImport(text, mode: .json, today: store.today, current: nil).value))
        var service = createService(fromPreset: "ollama")
        service.model = "qwen3"
        store.upsertService(service)
        return store
    }

    @Test("API 分析：保存结果，接受建议后生成新版本，重新打开后仍在")
    func runAndAccept() async throws {
        let plan = try JSONValue.parse(samplePlanText(mode: .json, today: LocalDate.today())).with("change_note", "深蹲加到 4 组")
        let reply = String(decoding: try JSONEncoder().encode(JSONValue.object([
            "summary": "完成率良好", "findings": [["level": "info", "text": "保持"]], "suggested_plan": plan,
        ])), as: UTF8.self)
        let store = try makeStore(reply: reply)
        #expect(store.activeServiceReady)
        let a = try await store.runAnalysis(kind: .planAdjustment, includeNotes: false, userNote: "下周出差")
        #expect(a.summary == "完成率良好" && a.userNote == "下周出差" && a.channel == .api)
        store.acceptAnalysis(id: a.id)
        #expect(store.currentPlan?.source == .aiAnalysis && store.currentPlan?.version == 2)

        let reopened = TrainingStore(context: ModelContext(container))
        #expect(reopened.state.analyses.first?.status == .accepted)
        #expect(reopened.currentPlan?.analysisId == a.id)
        #expect(reopened.state.aiSettings.services.first?.model == "qwen3")
    }

    @Test("手动粘贴回复；格式错误时返回错误")
    func manualReply() throws {
        let store = try makeStore(reply: "")
        #expect(store.importManualReply("抱歉", kind: .weeklyReview, includeNotes: false, userNote: nil).errors.isEmpty == false)
        let ok = store.importManualReply(#"好的 {"summary":"不错","findings":[]}"#, kind: .weeklyReview, includeNotes: false, userNote: nil)
        #expect(ok.value?.channel == .manualImport)
        #expect(store.state.analyses.count == 1)
    }

    @Test("保存个人档案并记录变化")
    func profile() throws {
        let store = try makeStore(reply: "")
        store.saveProfile(UserProfile(weightKg: 70, injuries: "手腕"))
        store.saveProfile(UserProfile(weightKg: 69, injuries: "手腕"))
        let reopened = TrainingStore(context: ModelContext(container))
        #expect(reopened.state.profile.weightKg == 69)
        #expect(reopened.state.profileHistory.count == 3)
    }
}
