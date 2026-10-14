import Foundation
import Testing
@testable import TrainingCore

@Suite("导入网页原型状态 / AI 设置迁移") struct PersistedStateTests {
    @Test("旧版单服务设置迁移为服务列表，旧 Key 归到该服务") func legacy() throws {
        let json = #"{"aiSettings":{"provider":"anthropic","model":"claude-sonnet-5-5","consent_given":true,"auto_weekly_review":false}}"#
        let r = try PersistedState.importPrototype(Data(json.utf8), legacyApiKey: "sk-old")
        let s = r.state.aiSettings
        #expect(s.services.count == 1)
        #expect(s.services[0].preset == "anthropic" && s.services[0].format == .anthropic && s.services[0].model == "claude-sonnet-5-5")
        #expect(s.activeServiceId == s.services[0].id)
        #expect(s.consentGiven)
        #expect(r.apiKeys == [s.services[0].id: "sk-old"])
    }

    @Test("新版设置原样读取；无数据时为空列表") func current() throws {
        #expect(try PersistedState.importPrototype(Data("{}".utf8)).state.aiSettings.services.isEmpty)
        let json = #"{"aiSettings":{"services":[{"id":"x","name":"n","preset":"custom","format":"openai","model":"m","max_tokens":100,"json_mode":false,"timeout_sec":60}],"active_service_id":"x","consent_given":false,"auto_weekly_review":false}}"#
        let s = try PersistedState.importPrototype(Data(json.utf8)).state.aiSettings
        #expect(s.services == [AIServiceConfig(id: "x", name: "n", preset: "custom", format: .openai, model: "m", maxTokens: 100, timeoutSec: 60)])
        #expect(s.activeService?.id == "x")
    }

    @Test("完整状态往返") func roundTrip() throws {
        let plan = makePlan()
        let state = PersistedState(planVersions: [plan], currentPlanId: plan.id, records: [rec("t1", "2026-06-15", .completed)])
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(back.currentPlan == plan)
        #expect(back.records == state.records)
    }
}
