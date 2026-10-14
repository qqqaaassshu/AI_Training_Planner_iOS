import Foundation
import Testing
@testable import TrainingCore

@Suite("AI 分析状态") struct AnalysisStateTests {
    func state() -> PersistedState {
        var s = PersistedState()
        s.addPlanVersion(makePlan())
        return s
    }

    func analysis(kind: AnalysisKind = .planAdjustment, plan: PlanInput? = nil, createdAt: String = Timestamp.now()) -> AIAnalysis {
        AIAnalysis(createdAt: createdAt, kind: kind, channel: .api, planVersionId: "p",
                   range: DateRange(from: d("2026-06-15"), to: d("2026-06-21")),
                   output: AIAnalysisOutput(summary: "s", findings: [], suggestedPlan: plan))
    }

    @Test("接受建议：生成新版本（来源 AI、关联分析）并切换") func accept() throws {
        var s = state()
        var input = samplePlanInput()
        input.tasks[0].exercises![0].sets = 4
        input.changeNote = "深蹲加到 4 组"
        let a = analysis(plan: input)
        s.addAnalysis(a)
        #expect(a.previewDiff(current: s.currentPlan, versions: s.planVersions)?.modified.first?.changes == ["深蹲：3×10 → 4×10"])
        let nextOpt = s.acceptAnalysis(id: a.id)
        let next = try #require(nextOpt)
        #expect(next.version == 2 && next.source == .aiAnalysis && next.analysisId == a.id && next.changeNote == "深蹲加到 4 组")
        #expect(s.currentPlan?.id == next.id)
        #expect(s.analyses[0].status == .accepted)
    }

    @Test("没有建议计划时只标记；忽略") func acceptWithoutPlanAndReject() {
        var s = state()
        let a = analysis(kind: .weeklyReview), b = analysis()
        s.addAnalysis(a)
        s.addAnalysis(b)
        let accepted = s.acceptAnalysis(id: a.id)
        #expect(accepted == nil)
        #expect(s.planVersions.count == 1 && s.analyses[0].status == .accepted)
        s.rejectAnalysis(id: b.id)
        #expect(s.analyses[1].status == .rejected)
    }

    @Test("保存档案记录变化") func profile() {
        var s = state()
        let now = Date(timeIntervalSince1970: 1_781_000_000)
        s.saveProfile(UserProfile(weightKg: 72), now: now)
        s.saveProfile(UserProfile(weightKg: 71, goals: "睡好"), now: now)
        #expect(s.profileHistory.map(\.field) == [.weightKg, .weightKg, .goals])
        #expect(s.profile.updatedAt == Timestamp.string(from: now))
        s.saveProfile(s.profile, now: now)
        #expect(s.profileHistory.count == 3) // 没有变化不记录
    }

    @Test("服务增删与当前服务") func services() {
        var s = PersistedState()
        let a = createService(fromPreset: "anthropic"), b = createService(fromPreset: "deepseek")
        s.upsertService(a)
        s.upsertService(b)
        #expect(s.aiSettings.activeServiceId == a.id)
        var a2 = a
        a2.model = "claude-sonnet-5-5"
        s.upsertService(a2)
        #expect(s.aiSettings.services.count == 2 && s.aiSettings.activeService?.model == "claude-sonnet-5-5")
        s.removeService(id: a.id)
        #expect(s.aiSettings.activeServiceId == b.id)
        #expect(!b.isReady(apiKey: nil) && b.isReady(apiKey: "k"))
        var ollama = createService(fromPreset: "ollama")
        ollama.model = "qwen3"
        #expect(ollama.isReady(apiKey: nil))
    }

    @Test("每周自动复盘：条件齐备且满 7 天才运行") func weeklyDue() {
        var s = state()
        let today = d("2026-06-25")
        #expect(!isWeeklyReviewDue(state: s, apiKey: "k", today: today)) // 开关未开
        s.upsertService(createService(fromPreset: "anthropic"))
        s.aiSettings.autoWeeklyReview = true
        #expect(!isWeeklyReviewDue(state: s, apiKey: "k", today: today)) // 未同意上传
        s.aiSettings.consentGiven = true
        #expect(!isWeeklyReviewDue(state: s, apiKey: nil, today: today)) // 没有 Key
        #expect(!isWeeklyReviewDue(state: s, apiKey: "k", today: d("2026-06-20"))) // 计划开始不满 7 天
        #expect(isWeeklyReviewDue(state: s, apiKey: "k", today: today))
        s.addAnalysis(analysis(kind: .weeklyReview, createdAt: "2026-06-20T12:00:00"))
        #expect(!isWeeklyReviewDue(state: s, apiKey: "k", today: today))
        #expect(isWeeklyReviewDue(state: s, apiKey: "k", today: d("2026-06-27")))
    }
}

@Suite("通知操作与表盘") struct ComplicationTests {
    let plan = makePlan()
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    func at(_ date: String, _ h: Int, _ m: Int) -> Date { d(date).date(atHour: h, minute: m, in: shanghai)! }

    @Test("训练与习惯的通知操作") func categories() {
        #expect(ReminderCategory(taskType: .workout).actions == [.start, .snooze])
        #expect(ReminderCategory(taskType: .habit).actions == [.complete, .snooze])
        #expect(ReminderAction.start.opensApp && !ReminderAction.complete.opensApp)
    }

    @Test("表盘：今日进度与下一个任务") func summary() {
        // 周一 07:00：训练 07:30 是下一个
        let s = complicationSummary(plan: plan, records: [], now: at("2026-06-15", 7, 0))
        #expect(s.done == 0 && s.total == 3 && s.nextTitle == "身体维护训练A" && s.nextIsWorkout)
        #expect(s.nextTime == at("2026-06-15", 7, 30))
        // 训练完成后，下一个是 18:00 散步
        let s2 = complicationSummary(plan: plan, records: [rec("t1", "2026-06-15", .completed)], now: at("2026-06-15", 7, 40))
        #expect(s2.done == 1 && s2.nextTitle == "散步20分钟" && !s2.nextIsWorkout && s2.fraction == 1.0 / 3)
        // 过了时间 30 分钟还没做，不再显示为下一个
        let s3 = complicationSummary(plan: plan, records: [], now: at("2026-06-15", 8, 1))
        #expect(s3.nextTitle == "散步20分钟")
        #expect(complicationSummary(plan: nil, records: [], now: Date()) == .empty)
    }

    @Test("表盘时间线：任务时间点后切换，午夜换天") func timeline() {
        let entries = complicationTimeline(plan: plan, records: [], now: at("2026-06-15", 7, 0))
        #expect(entries.first?.date == at("2026-06-15", 7, 0))
        #expect(entries.map(\.date) == entries.map(\.date).sorted())
        #expect(entries.contains { $0.date == at("2026-06-16", 0, 0) && $0.summary.total == 2 }) // 周二只有两个习惯
        let afterWorkout = entries.first { $0.date > at("2026-06-15", 8, 0) }
        #expect(afterWorkout?.summary.nextTitle == "散步20分钟")
    }
}
