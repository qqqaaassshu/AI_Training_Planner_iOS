import Foundation

public enum AnalysisKind: String, Codable, Hashable, Sendable, CaseIterable {
    case sessionFeedback = "session_feedback"
    case weeklyReview = "weekly_review"
    case planAdjustment = "plan_adjustment"
    case alert

    public var label: String {
        switch self {
        case .sessionFeedback: return "训练反馈"
        case .weeklyReview: return "每周复盘"
        case .planAdjustment: return "计划调整"
        case .alert: return "异常提醒"
        }
    }
}

public enum FindingLevel: String, Codable, Hashable, Sendable {
    case info, warn, risk
}

public struct Finding: Codable, Hashable, Sendable {
    public var level: FindingLevel
    public var text: String
    public init(level: FindingLevel, text: String) {
        self.level = level
        self.text = text
    }
}

/// AI 输出的分析结果（API 返回或手动粘贴回来），对应 ai-analysis.schema.json
public struct AIAnalysisOutput: Codable, Hashable, Sendable {
    public var summary: String
    public var findings: [Finding]
    public var suggestedPlan: PlanInput?

    public init(summary: String, findings: [Finding], suggestedPlan: PlanInput? = nil) {
        self.summary = summary
        self.findings = findings
        self.suggestedPlan = suggestedPlan
    }

    enum CodingKeys: String, CodingKey {
        case summary, findings
        case suggestedPlan = "suggested_plan"
    }
}

public enum AnalysisChannel: String, Codable, Hashable, Sendable {
    /// App 直接调用模型
    case api
    /// 导出后手动粘贴回来
    case manualImport = "manual_import"
}

public enum AnalysisStatus: String, Codable, Hashable, Sendable {
    case new, accepted, rejected
}

public struct AIAnalysis: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: String
    public var kind: AnalysisKind
    public var channel: AnalysisChannel
    public var planVersionId: String
    public var range: DateRange
    /// 服务名称（API 调用时）
    public var provider: String?
    public var model: String?
    public var status: AnalysisStatus
    /// 生成时使用的提示词版本
    public var promptVersion: Int?
    /// 用户为本次分析填写的补充说明
    public var userNote: String?
    public var summary: String
    public var findings: [Finding]
    /// 必须由用户确认后才生成新版本，App 不会自动替换计划
    public var suggestedPlan: PlanInput?

    public var output: AIAnalysisOutput { AIAnalysisOutput(summary: summary, findings: findings, suggestedPlan: suggestedPlan) }

    public init(id: String = newId(), createdAt: String = Timestamp.now(), kind: AnalysisKind, channel: AnalysisChannel,
                planVersionId: String, range: DateRange, provider: String? = nil, model: String? = nil,
                status: AnalysisStatus = .new, promptVersion: Int? = nil, userNote: String? = nil,
                output: AIAnalysisOutput) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.channel = channel
        self.planVersionId = planVersionId
        self.range = range
        self.provider = provider
        self.model = model
        self.status = status
        self.promptVersion = promptVersion
        self.userNote = userNote
        self.summary = output.summary
        self.findings = output.findings
        self.suggestedPlan = output.suggestedPlan
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, channel, range, provider, model, status, summary, findings
        case createdAt = "created_at"
        case planVersionId = "plan_version_id"
        case promptVersion = "prompt_version"
        case userNote = "user_note"
        case suggestedPlan = "suggested_plan"
    }
}

/// 接口格式：决定请求如何发送
public enum AIApiFormat: String, Codable, Hashable, Sendable {
    case anthropic, openai
}

/// 一个 AI 服务的配置（API Key 不在这里，存钥匙串）
public struct AIServiceConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// 显示名称，如“DeepSeek”“公司代理”
    public var name: String
    /// 来自哪个预设（anthropic / openai / deepseek / … / custom）
    public var preset: String
    public var format: AIApiFormat
    /// 接口地址；为空用预设的默认地址
    public var baseURL: String?
    public var model: String
    public var maxTokens: Int
    /// 仅 OpenAI 兼容接口使用；为空用服务默认值
    public var temperature: Double?
    /// OpenAI 兼容接口：请求 JSON 输出（response_format）
    public var jsonMode: Bool
    public var timeoutSec: Int
    /// 额外请求头，如代理鉴权
    public var extraHeaders: [String: String]?

    public init(id: String = newId(), name: String, preset: String, format: AIApiFormat, baseURL: String? = nil,
                model: String, maxTokens: Int = 16000, temperature: Double? = nil, jsonMode: Bool = false,
                timeoutSec: Int = 120, extraHeaders: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.preset = preset
        self.format = format
        self.baseURL = baseURL
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.jsonMode = jsonMode
        self.timeoutSec = timeoutSec
        self.extraHeaders = extraHeaders
    }

    enum CodingKeys: String, CodingKey {
        case id, name, preset, format, model, temperature
        case baseURL = "base_url"
        case maxTokens = "max_tokens"
        case jsonMode = "json_mode"
        case timeoutSec = "timeout_sec"
        case extraHeaders = "extra_headers"
    }
}

public struct AISettings: Codable, Hashable, Sendable {
    public var services: [AIServiceConfig]
    public var activeServiceId: String?
    public var consentGiven: Bool
    public var autoWeeklyReview: Bool

    public init(services: [AIServiceConfig] = [], activeServiceId: String? = nil, consentGiven: Bool = false,
                autoWeeklyReview: Bool = false) {
        self.services = services
        self.activeServiceId = activeServiceId
        self.consentGiven = consentGiven
        self.autoWeeklyReview = autoWeeklyReview
    }

    public var activeService: AIServiceConfig? { services.first { $0.id == activeServiceId } }

    enum CodingKeys: String, CodingKey {
        case services
        case activeServiceId = "active_service_id"
        case consentGiven = "consent_given"
        case autoWeeklyReview = "auto_weekly_review"
    }
}
