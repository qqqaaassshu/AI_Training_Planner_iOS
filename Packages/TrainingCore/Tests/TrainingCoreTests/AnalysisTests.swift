import Foundation
import Testing
@testable import TrainingCore

@Suite("detectAlerts") struct DetectAlertsTests {
    @Test("无数据时无提醒") func empty() {
        #expect(detectAlerts(records: [], wellness: [], today: d("2026-06-20")).isEmpty)
    }

    @Test("疼痛 ≥7 为 risk") func risk() {
        let f = detectAlerts(records: [rec("t1", "2026-06-19", .completed, pain: 8)], wellness: [], today: d("2026-06-20"))
        #expect(f.count == 1)
        #expect(f[0].level == .risk)
    }

    @Test("连续两次疼痛 ≥5 为 warn；超过 7 天的不计") func warn() {
        let records = [rec("t1", "2026-06-17", .completed, pain: 5), rec("t1", "2026-06-19", .completed, pain: 6)]
        #expect(detectAlerts(records: records, wellness: [], today: d("2026-06-20")).map(\.level) == [.warn])
        #expect(detectAlerts(records: [rec("t1", "2026-06-01", .completed, pain: 9)], wellness: [], today: d("2026-06-20")).isEmpty)
    }

    @Test("频繁跳过与持续疲劳") func skipsAndFatigue() {
        let skips = [1, 2, 3].map { rec("t1", "2026-06-1\($0)", .skipped, skipReason: .pain) }
        let wellness = ["2026-06-12", "2026-06-13"].map { DailyWellness(date: d($0), fatigueScore: 8, updatedAt: "") }
        let texts = detectAlerts(records: skips, wellness: wellness, today: d("2026-06-13")).map(\.text)
        #expect(texts.contains { $0.contains("因疼痛跳过") })
        #expect(texts.contains { $0.contains("跳过 3 次") })
        #expect(texts.contains { $0.contains("疲劳") })
    }
}

@Suite("buildAnalysisInput") struct AnalysisInputTests {
    let plan = makePlan()
    var records: [ExecutionRecord] {
        [rec("t1", "2026-06-15", .completed, pain: 3, notes: "膝盖有点酸"), rec("t1", "2026-06-01", .completed)]
    }

    @Test("默认不包含备注，只含区间内记录") func noNotes() {
        let input = buildAnalysisInput(kind: .weeklyReview, plan: plan, versions: [plan], records: records, dailyWellness: [], today: d("2026-06-16"))
        #expect(input.range == DateRange(from: d("2026-06-10"), to: d("2026-06-16")))
        #expect(input.records.count == 1)
        #expect(input.records[0].notes == nil)
        #expect(input.records[0].taskTitle == "身体维护训练A")
        #expect(input.plan?.currentWeek == 1)
    }

    @Test("用户同意后包含备注") func notes() {
        let input = buildAnalysisInput(kind: .weeklyReview, plan: plan, versions: [plan], records: records, dailyWellness: [],
                                       today: d("2026-06-16"), includeNotes: true)
        #expect(input.records[0].notes == "膝盖有点酸")
    }

    @Test("计划调整默认看最近 4 周（不早于计划开始）") func adjustmentRange() {
        #expect(defaultRange(kind: .planAdjustment, plan: plan, today: d("2026-06-20")) == DateRange(from: d("2026-06-15"), to: d("2026-06-20")))
        #expect(defaultRange(kind: .planAdjustment, plan: plan, today: d("2026-08-01")) == DateRange(from: d("2026-07-05"), to: d("2026-08-01")))
    }

    @Test("手动提示词包含输出格式说明与数据") func manualPrompt() {
        let text = buildManualPrompt(buildAnalysisInput(kind: .planAdjustment, plan: plan, versions: [plan], records: records,
                                                        dailyWellness: [], today: d("2026-06-16")))
        #expect(text.contains("AIAnalysisOutput"))
        #expect(text.contains("suggested_plan"))
        #expect(text.contains("身体维护训练A"))
        #expect(text.contains(#""$id":"https://ai-training-planner/schema/plan.schema.json""#))
    }

    @Test("数据 JSON 使用原型的字段名，不含档案与补充说明") func dataJSON() throws {
        let input = buildAnalysisInput(kind: .weeklyReview, plan: plan, versions: [plan], records: records, dailyWellness: [],
                                       today: d("2026-06-16"), profile: UserProfile(goals: "睡好"), userNote: "x")
        let json = try JSONValue(encoding: input)
        #expect(json["schema_version"] == "2.0")
        #expect(json["plan"]?["total_weeks"] == 12)
        #expect(json["plan"]?["parent_version_id"] == nil)
        #expect(json["records"]?.arrayValue?[0]["task_title"] == "身体维护训练A")
        #expect(json["profile"] == nil)
        #expect(json["user_note"] == nil)
        #expect(json["local_alerts"] == [])
    }
}

@Suite("parseAnalysisReply") struct ParseReplyTests {
    @Test("解析带说明文字的回复并生成分析记录") func parse() throws {
        let body = try JSONEncoder().encode(JSONValue.object([
            "summary": "完成率良好",
            "findings": [["level": "info", "text": "保持"]],
            "suggested_plan": samplePlanJSON.with("change_note", "深蹲加到 4 组"),
        ]))
        let reply = "好的，以下是分析：\n```json\n\(String(decoding: body, as: UTF8.self))\n```"
        let output = try #require(parseAnalysisReply(reply).value)
        let a = createAnalysis(output, kind: .planAdjustment, channel: .manualImport, planVersionId: "p",
                               range: DateRange(from: d("2026-06-15"), to: d("2026-06-16")))
        #expect(a.status == .new)
        #expect(a.suggestedPlan?.changeNote == "深蹲加到 4 组")
    }

    @Test("格式错误时返回错误列表") func errors() {
        #expect(!parseAnalysisReply("抱歉我无法回答").isOK)
        #expect(!parseAnalysisReply(#"{"summary": ""}"#).isOK)
    }

    @Test("忽略 <think> 中的内容") func think() {
        let reply = "<think>先看看 {这里有括号} 的数据</think>\n{\"summary\":\"好\",\"findings\":[]}"
        #expect(parseAnalysisReply(reply).isOK)
    }
}

@Suite("历史与档案进入提示词") struct HistoryPromptTests {
    let v1: PlanVersion
    let v2: PlanVersion

    init() throws {
        var a = makePlan()
        a.createdAt = "2026-06-14T12:00:00"
        v1 = a
        var tasks = samplePlanJSON["tasks"]!.arrayValue!
        var t1 = tasks[0].objectValue!
        var exs = t1["exercises"]!.arrayValue!
        exs[0] = exs[0].with("sets", 4)
        t1["exercises"] = .array(exs)
        tasks[0] = .object(t1)
        let input = try #require(validatePlanInput(samplePlanJSON.with("tasks", .array(tasks)).with("change_note", "深蹲加到 4 组")).value)
        var b = createPlanVersion(input, existing: [a], source: .aiAnalysis, parent: a)
        b.createdAt = "2026-06-22T12:00:00"
        v2 = b
    }

    @Test("plan_history：每个版本的变化与使用期间效果") func history() {
        let records = [rec("t1", "2026-06-15", .completed), rec("t1", "2026-06-22", .completed, pain: 6)]
        let h = buildPlanHistory(versions: [v1, v2], records: records, dailyWellness: [], today: d("2026-06-24"))
        #expect(h.count == 2)
        #expect(h[0].version == 1)
        #expect(h[0].active == DateRange(from: d("2026-06-15"), to: d("2026-06-21")))
        #expect(h[0].changes.isEmpty)
        #expect(h[1].version == 2)
        #expect(h[1].changeNote == "深蹲加到 4 组")
        #expect(h[1].changes == ["身体维护训练A · 深蹲：3×10 → 4×10"])
        #expect(h[1].active == DateRange(from: d("2026-06-22"), to: d("2026-06-24")))
        #expect(h[1].outcome.painMax == 6)
    }

    @Test("档案在系统提示词，补充说明与变更在用户消息；档案不重复放进数据") func placement() {
        let input = buildAnalysisInput(
            kind: .weeklyReview, plan: v2, versions: [v1, v2], records: [], dailyWellness: [], today: d("2026-06-24"),
            profile: UserProfile(injuries: "右手腕恢复中", availableTime: "工作日晚上 20 分钟"),
            profileHistory: [ProfileChange(at: "2026-06-20T08:00:00", field: .weightKg, from: .number(72), to: .number(71))],
            userNote: "下周出差"
        )
        let p = buildPrompt(input)
        #expect(p.system.contains("伤病与身体限制：右手腕恢复中"))
        #expect(p.system.contains("可训练时间：工作日晚上 20 分钟"))
        #expect(p.system.contains("plan_history"))
        #expect(p.user.contains("本次补充说明（用户填写，优先考虑）：下周出差"))
        #expect(p.user.contains(#""71kg""#))
        #expect(p.user.contains(#""plan_history""#))
        #expect(!p.user.contains("右手腕恢复中"))
    }

    @Test("系统提示词只随档案变化（便于缓存）") func stableSystem() {
        let a = buildPrompt(buildAnalysisInput(kind: .weeklyReview, plan: v2, versions: [v1, v2], records: [], dailyWellness: [],
                                               today: d("2026-06-24"), profile: UserProfile(goals: "睡好")))
        let b = buildPrompt(buildAnalysisInput(kind: .weeklyReview, plan: v2, versions: [v1, v2], records: [rec("t1", "2026-06-23", .skipped)],
                                               dailyWellness: [], today: d("2026-06-25"), profile: UserProfile(goals: "睡好"), userNote: "x"))
        #expect(a.system == b.system)
        #expect(a.user != b.user)
    }

    @Test("分析记录带提示词版本与补充说明") func meta() {
        let a = createAnalysis(AIAnalysisOutput(summary: "s", findings: []), kind: .weeklyReview, channel: .api, planVersionId: "p",
                               range: DateRange(from: d("2026-06-01"), to: d("2026-06-02")), userNote: "下周出差")
        #expect(a.promptVersion == promptVersion)
        #expect(a.userNote == "下周出差")
    }
}
