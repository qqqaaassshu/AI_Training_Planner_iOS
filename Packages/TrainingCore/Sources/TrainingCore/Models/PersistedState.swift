import Foundation

/// 网页原型保存在 localStorage 里的完整状态（atp:state:v2）。
/// iOS 端用 SwiftData 存储，这里只用于从网页原型导入数据。
public struct PersistedState: Codable, Hashable, Sendable {
    public var schemaVersion: String
    public var planVersions: [PlanVersion]
    public var currentPlanId: String?
    public var records: [ExecutionRecord]
    public var dailyWellness: [DailyWellness]
    public var analyses: [AIAnalysis]
    public var aiSettings: AISettings
    public var profile: UserProfile
    public var profileHistory: [ProfileChange]

    public init(schemaVersion: String = TrainingCore.schemaVersion, planVersions: [PlanVersion] = [], currentPlanId: String? = nil,
                records: [ExecutionRecord] = [], dailyWellness: [DailyWellness] = [], analyses: [AIAnalysis] = [],
                aiSettings: AISettings = AISettings(), profile: UserProfile = UserProfile(), profileHistory: [ProfileChange] = []) {
        self.schemaVersion = schemaVersion
        self.planVersions = planVersions
        self.currentPlanId = currentPlanId
        self.records = records
        self.dailyWellness = dailyWellness
        self.analyses = analyses
        self.aiSettings = aiSettings
        self.profile = profile
        self.profileHistory = profileHistory
    }

    public var currentPlan: PlanVersion? { planVersions.first { $0.id == currentPlanId } }

    enum CodingKeys: String, CodingKey {
        case planVersions, currentPlanId, records, dailyWellness, analyses, aiSettings, profile, profileHistory
        case schemaVersion = "schema_version"
    }

    /// 缺失的字段用默认值，AI 设置兼容旧版单服务格式
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? TrainingCore.schemaVersion,
            planVersions: try c.decodeIfPresent([PlanVersion].self, forKey: .planVersions) ?? [],
            currentPlanId: try c.decodeIfPresent(String.self, forKey: .currentPlanId),
            records: try c.decodeIfPresent([ExecutionRecord].self, forKey: .records) ?? [],
            dailyWellness: try c.decodeIfPresent([DailyWellness].self, forKey: .dailyWellness) ?? [],
            analyses: try c.decodeIfPresent([AIAnalysis].self, forKey: .analyses) ?? [],
            aiSettings: AISettings(),
            profile: try c.decodeIfPresent(UserProfile.self, forKey: .profile) ?? UserProfile(),
            profileHistory: try c.decodeIfPresent([ProfileChange].self, forKey: .profileHistory) ?? []
        )
        aiSettings = migrateAISettings(try c.decodeIfPresent(JSONValue.self, forKey: .aiSettings)).settings
    }

    /// 导入网页原型的状态。`legacyApiKey` 是旧版单个 Key（atp:ai-api-key），会归到迁移出的服务下。
    /// 返回的 `apiKeys`（服务 id → Key）应存入钥匙串。
    public static func importPrototype(_ data: Data, legacyApiKey: String? = nil) throws -> (state: PersistedState, apiKeys: [String: String]) {
        var state = try JSONDecoder().decode(PersistedState.self, from: data)
        let raw = try JSONValue.parse(data)["aiSettings"]
        let migrated = migrateAISettings(raw, legacyApiKey: legacyApiKey)
        state.aiSettings = migrated.settings
        return (state, migrated.apiKeys)
    }
}

/// 兼容旧版设置 { provider, model, base_url }
public func migrateAISettings(_ raw: JSONValue?, legacyApiKey: String? = nil) -> (settings: AISettings, apiKeys: [String: String]) {
    let r = raw ?? .object([:])
    if r["services"]?.arrayValue != nil, let s = try? r.decode(AISettings.self) { return (s, [:]) }
    if r["services"]?.arrayValue != nil {
        // 新格式但部分字段缺失
        let services = (try? r["services"]!.decode([AIServiceConfig].self)) ?? []
        return (AISettings(services: services, activeServiceId: r["active_service_id"]?.stringValue,
                           consentGiven: r["consent_given"]?.boolValue ?? false,
                           autoWeeklyReview: r["auto_weekly_review"]?.boolValue ?? false), [:])
    }
    var settings = AISettings(consentGiven: r["consent_given"]?.boolValue == true, autoWeeklyReview: r["auto_weekly_review"]?.boolValue == true)
    var keys: [String: String] = [:]
    if let provider = r["provider"]?.stringValue, !provider.isEmpty {
        var service = createService(fromPreset: provider)
        if let m = r["model"]?.stringValue, !m.isEmpty { service.model = m }
        if let u = r["base_url"]?.stringValue, !u.isEmpty { service.baseURL = u }
        settings.services = [service]
        settings.activeServiceId = service.id
        if let k = legacyApiKey, !k.isEmpty { keys[service.id] = k }
    }
    return (settings, keys)
}

/// 训练中途的草稿（已勾选的动作与实际数值），按日期 + 任务保存，提交后清除
public struct TaskDraft: Codable, Hashable, Sendable {
    public var doneIds: [String]
    public var items: [SetSummary]
    public init(doneIds: [String], items: [SetSummary]) {
        self.doneIds = doneIds
        self.items = items
    }
}
