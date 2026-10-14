import Foundation

/// 提示词有实质修改时加 1，记录在每条分析里，便于对比不同版本的效果（与网页原型同步）
public let promptVersion = 2

extension AnalysisKind {
    var taskInstruction: String {
        switch self {
        case .sessionFeedback:
            return "针对最近一次训练给出简短反馈（summary 1-2 句），只在发现问题时给 findings。不要输出 suggested_plan。"
        case .weeklyReview:
            return "对统计区间（通常为最近 7 天）做复盘：完成情况、趋势、疼痛与疲劳风险。只有确有必要调整时才输出 suggested_plan，否则省略。"
        case .planAdjustment:
            return "基于执行数据给出下一版训练计划，必须输出 suggested_plan，并在 suggested_plan.change_note 中说明调整了什么、为什么。"
        case .alert:
            return "数据触发了本地风险规则（见 local_alerts）。解释可能原因并给出调整建议；如需减量，输出降低强度的 suggested_plan。"
        }
    }
}

let coachRules = """
你是一名谨慎、务实的体能训练与康复教练，帮助用户根据真实执行数据调整训练计划。用户是普通人，不是运动员，坚持下去比练得猛更重要。

【调整规则】
- 加量条件：近 2 周完成率 ≥ 85% 且疼痛 ≤ 3。每个动作一次只加一档（次数 +1~2、或时长 +5~10 秒、或组数 +1、或重量 +5%），不同时改多项。
- 某个动作疼痛 ≥ \(painWarn)：只针对该动作降一档，或换成同部位更轻的替代动作；其他动作不变。
- 因“没时间”跳过：缩短单次训练（减少动作数或组数），不降低强度；可建议更灵活的时间。
- 因“疼痛”或“生病”跳过：暂停加量，必要时安排一周恢复（量减至约 70%）。
- 完成率 < 60%：优先降低频率或难度，不新增任务。
- 不改训练时间和星期，除非数据显示当前安排执行不了，或用户补充说明中提出。
- 严格遵守用户档案中的伤病限制和器械条件，不安排需要所缺器械的动作。
- 参考 plan_history：若上一次调整后完成率下降或疼痛上升，说明该调整可能过量，应回退或放缓；若效果良好，可沿同方向小步推进。
- 参考 profile_changes：状态变好或变差（体重、伤病、可用时间）时相应调整。

【安全】
- 疼痛 ≥ \(painRisk)，或备注、补充说明中出现胸痛、头晕、呼吸困难、麻木、关节肿胀等情况：标为 level "risk"，建议停止相关训练并就医。
- 不做医学诊断，不推荐药物或补剂。

【输出风格】
- 使用中文。summary 2–4 句，引用具体数据（例如“周二深蹲后疼痛 6 分”），先说结论。
- findings 最多 5 条，按风险从高到低排列；没有问题时可为空数组。
- suggested_plan.change_note 逐条写“改了什么 + 为什么”。

【数据约定】
- 调整已有任务时沿用原任务的 id 和动作 id；新增任务可以省略 id。日期使用 YYYY-MM-DD；weekday 中 0 = 周日。
- 动作的 reps（次数）与 duration_sec（秒）二选一。
"""

var outputSpec: String {
    """
    【输出格式】只输出一个 JSON 对象，不要输出任何其他文字或代码块标记。格式必须符合下面的 JSON Schema（AIAnalysisOutput），其中 suggested_plan 符合 PlanInput：

    AIAnalysisOutput:
    \(Schemas.aiAnalysis)

    PlanInput:
    \(Schemas.plan)
    """
}

/// 系统提示词 = 教练规则 + 用户档案 + 输出格式。
/// 档案很少变化，系统提示词因此基本稳定（便于服务商缓存）；每次变化的数据都放在用户消息里。
public func buildSystemPrompt(profile: UserProfile) -> String {
    """
    \(coachRules)

    【用户档案】
    \(formatProfileForPrompt(profile))

    \(outputSpec)
    """
}

public struct Prompt: Hashable, Sendable {
    public var system: String
    public var user: String
}

public func buildPrompt(_ input: AnalysisInput) -> Prompt {
    let note = input.userNote.map { "\n本次补充说明（用户填写，优先考虑）：\($0)\n" } ?? ""
    let user = """
    任务：\(input.kind.label)
    \(input.kind.taskInstruction)
    \(note)
    以下是执行数据（JSON）：
    \(encodeJSONString(input, pretty: true))
    """
    return Prompt(system: buildSystemPrompt(profile: input.profile), user: user)
}

/// 手动复制给外部 AI 时，把系统提示与数据合成一段文本
public func buildManualPrompt(_ input: AnalysisInput) -> String {
    let p = buildPrompt(input)
    return "\(p.system)\n\n---\n\n\(p.user)"
}

// MARK: 结果

nonisolated(unsafe) private let thinkRegex = jsRegex(#"<think>[\s\S]*?</think>"#)

public func parseAnalysisReply(_ text: String) -> ValidationResult<AIAnalysisOutput> {
    // 推理模型可能把思考过程放在 <think> 标签里
    guard let raw = try? extractJSON(text.replacing(thinkRegex, with: "")) else { return .failure(["未找到有效的 JSON"]) }
    return validateAIAnalysisOutput(raw)
}

public func createAnalysis(_ output: AIAnalysisOutput, kind: AnalysisKind, channel: AnalysisChannel, planVersionId: String,
                           range: DateRange, provider: String? = nil, model: String? = nil, userNote: String? = nil,
                           now: Date = Date()) -> AIAnalysis {
    AIAnalysis(createdAt: Timestamp.string(from: now), kind: kind, channel: channel, planVersionId: planVersionId,
               range: range, provider: provider, model: model, status: .new, promptVersion: promptVersion,
               userNote: (userNote?.isEmpty ?? true) ? nil : userNote, output: output)
}
