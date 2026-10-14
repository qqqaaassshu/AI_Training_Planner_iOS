import Foundation

// AI 分析、AI 服务设置与个人档案的状态修改（对应原型 App.tsx 的 handleAddAnalysis / handleAcceptAnalysis 等）。

extension PersistedState {
    public mutating func addAnalysis(_ a: AIAnalysis) {
        analyses.append(a)
    }

    /// 接受 AI 建议：有建议计划时基于当前版本生成新版本（来源 ai_analysis）并切换；没有时只标记为已应用
    @discardableResult
    public mutating func acceptAnalysis(id: String, now: Date = Date()) -> PlanVersion? {
        guard let i = analyses.firstIndex(where: { $0.id == id }) else { return nil }
        analyses[i].status = .accepted
        guard let suggested = analyses[i].suggestedPlan else { return nil }
        let next = createPlanVersion(suggested, existing: planVersions, source: .aiAnalysis, parent: currentPlan,
                                     analysisId: id, now: now)
        addPlanVersion(next)
        return next
    }

    public mutating func rejectAnalysis(id: String) {
        guard let i = analyses.firstIndex(where: { $0.id == id }) else { return }
        analyses[i].status = .rejected
    }

    /// 分析从新到旧
    public var analysesNewestFirst: [AIAnalysis] { analyses.sortedStable { $0.createdAt > $1.createdAt } }

    // MARK: 个人档案

    /// 保存档案，并把变化记入 profileHistory
    public mutating func saveProfile(_ next: UserProfile, now: Date = Date()) {
        let at = Timestamp.string(from: now)
        profileHistory += diffProfile(before: profile, after: next, at: at)
        var p = next
        p.updatedAt = at
        profile = p
    }

    // MARK: AI 服务

    public mutating func upsertService(_ s: AIServiceConfig) {
        if let i = aiSettings.services.firstIndex(where: { $0.id == s.id }) {
            aiSettings.services[i] = s
        } else {
            aiSettings.services.append(s)
            if aiSettings.activeServiceId == nil { aiSettings.activeServiceId = s.id }
        }
    }

    public mutating func removeService(id: String) {
        aiSettings.services.removeAll { $0.id == id }
        if aiSettings.activeServiceId == id { aiSettings.activeServiceId = aiSettings.services.first?.id }
    }
}

extension AIServiceConfig {
    /// 配置完整、并且有 Key（或该服务不需要 Key）时才能调用
    public func isReady(apiKey: String?) -> Bool {
        problems.isEmpty && (!(apiKey ?? "").isEmpty || TrainingCore.preset(id: preset).keyOptional)
    }
}

/// 每周自动复盘是否该运行：开关已开、已同意上传、当前服务可用、计划已开始满 7 天，且距上次每周复盘满 7 天
public func isWeeklyReviewDue(state: PersistedState, apiKey: String?, today: LocalDate, timeZone: TimeZone = .current) -> Bool {
    let s = state.aiSettings
    guard let plan = state.currentPlan, s.autoWeeklyReview, s.consentGiven,
          let service = s.activeService, service.isReady(apiKey: apiKey) else { return false }
    if plan.startDate.days(to: today) < 7 { return false }
    let last = state.analyses.filter { $0.kind == .weeklyReview }.map(\.createdAt).max()
    if let last, let lastDate = Timestamp.localDate(of: last, in: timeZone), lastDate.days(to: today) < 7 { return false }
    return true
}

extension AnalysisStatus {
    public var label: String {
        switch self {
        case .new: return "待处理"
        case .accepted: return "已应用"
        case .rejected: return "已忽略"
        }
    }
}

extension AIAnalysis {
    /// 预览接受后的变化：与正式应用相同的 id 对齐逻辑，差异才准确
    public func previewDiff(current: PlanVersion?, versions: [PlanVersion]) -> PlanDiff? {
        guard let plan = suggestedPlan, let current else { return nil }
        return comparePlanVersions(current, createPlanVersion(plan, existing: versions, source: .aiAnalysis, parent: current))
    }
}
