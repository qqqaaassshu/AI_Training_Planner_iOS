import Foundation
import Testing
@testable import TrainingCore

let badPlans: [(String, JSONValue)] = [
    ("缺少 tasks", ["plan_name": "x", "start_date": "2026-06-15"]),
    ("空 tasks", ["plan_name": "x", "start_date": "2026-06-15", "tasks": []]),
    ("无效日期", ["plan_name": "x", "start_date": "2026-02-30", "tasks": [["title": "a", "type": "habit", "schedule": ["daily": true]]]]),
    ("动作缺 reps 与 duration", ["plan_name": "x", "start_date": "2026-06-15", "tasks": [["title": "a", "type": "workout", "schedule": ["daily": true], "exercises": [["name": "深蹲", "sets": 3]]]]]),
    ("weekday 越界", ["plan_name": "x", "start_date": "2026-06-15", "tasks": [["title": "a", "type": "habit", "schedule": ["weekday": [7]]]]]),
    ("schedule 为空", ["plan_name": "x", "start_date": "2026-06-15", "tasks": [["title": "a", "type": "habit", "schedule": [:]]]]),
    ("type 错误", ["plan_name": "x", "start_date": "2026-06-15", "tasks": [["title": "a", "type": "run", "schedule": ["daily": true]]]]),
]

@Suite("validatePlanInput") struct ValidatePlanTests {
    @Test("示例计划通过校验") func sample() {
        let r = validatePlanInput(samplePlanJSON)
        let v = try! #require(r.value)
        #expect(v.tasks.count == 3)
        #expect(v.tasks[0].phases?[0].exercises[0].weightKg == 10)
        #expect(v.timezone == "Asia/Shanghai")
    }

    @Test("示例计划也能直接按 Codable 解码，编码后与校验结果一致") func codableRoundTrip() throws {
        let decoded = try samplePlanJSON.decode(PlanInput.self)
        #expect(decoded == samplePlanInput())
        let again = try JSONDecoder().decode(PlanInput.self, from: JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }

    @Test("拒绝无效计划", arguments: badPlans.map(\.0)) func rejects(name: String) {
        let plan = badPlans.first { $0.0 == name }!.1
        let r = validatePlanInput(plan)
        #expect(!r.isOK)
        #expect(!r.errors.isEmpty)
    }

    @Test("错误信息带字段路径") func errorPath() {
        let r = validatePlanInput(badPlans[3].1)
        #expect(r.errors.first?.contains("tasks[0].exercises[0]") == true)
    }

    @Test("缺少 id 时自动生成，reminder 默认 true，weekday 去重排序") func defaults() throws {
        let r = validatePlanInput(["plan_name": "x", "start_date": "2026-06-15",
                                   "tasks": [["title": "a", "type": "workout", "schedule": ["weekday": [3, 1, 1]],
                                              "exercises": [["name": "深蹲", "sets": 3, "reps": 10]]]]])
        let t = try #require(r.value).tasks[0]
        #expect(!t.id.isEmpty)
        #expect(!t.exercises![0].id.isEmpty)
        #expect(t.reminder)
        #expect(t.schedule.weekday == [1, 3])
    }

    @Test("拒绝重复任务 id") func duplicateIds() {
        let r = validatePlanInput(["plan_name": "x", "start_date": "2026-06-15", "tasks": [
            ["id": "a", "title": "a", "type": "habit", "schedule": ["daily": true]],
            ["id": "a", "title": "b", "type": "habit", "schedule": ["daily": true]],
        ]])
        #expect(!r.isOK)
    }

    @Test("非整数、null 与错误时间格式") func types() {
        let base: JSONValue = ["title": "a", "type": "workout", "schedule": ["daily": true, "time": "7:30"],
                               "exercises": [["name": "深蹲", "sets": 2.5, "reps": nil]]]
        let r = validatePlanInput(["plan_name": "x", "start_date": "2026-06-15", "tasks": [base]])
        #expect(r.errors.contains("tasks[0].schedule.time：格式应为 HH:mm"))
        #expect(r.errors.contains("tasks[0].exercises[0].sets：应为 ≥1 的整数"))
        #expect(r.errors.contains("tasks[0].exercises[0].reps：应为 ≥1 的整数"))
        #expect(validatePlanInput(json: "{坏").errors == ["不是有效的 JSON"])
    }
}

@Suite("validateAIAnalysisOutput") struct ValidateAnalysisTests {
    let good: JSONValue = ["summary": "本周完成度良好。", "findings": [["level": "warn", "text": "周三疼痛 6 分"]], "suggested_plan": samplePlanJSON]

    @Test("合法输出") func ok() {
        #expect(validateAIAnalysisOutput(good).isOK)
    }

    @Test("suggested_plan 的错误带前缀") func prefixed() {
        let r = validateAIAnalysisOutput(good.with("suggested_plan", ["plan_name": "x"]))
        #expect(!r.isOK)
        #expect(r.errors.allSatisfy { $0.hasPrefix("suggested_plan.") })
    }

    @Test("level 非法") func badLevel() {
        #expect(!validateAIAnalysisOutput(["summary": "x", "findings": [["level": "danger", "text": "x"]]]).isOK)
    }

    @Test("suggested_plan 为 null 视为没有") func nullPlan() {
        #expect(validateAIAnalysisOutput(good.with("suggested_plan", nil)).value?.suggestedPlan == nil)
    }
}

@Suite("extractJSON") struct ExtractJSONTests {
    @Test("从代码块与说明文字中提取") func extract() throws {
        #expect(try extractJSON("好的：\n```json\n{\"a\":1}\n```\n以上") == ["a": 1])
        #expect(try extractJSON("结果如下 {\"a\":{\"b\":2}} 谢谢") == ["a": ["b": 2]])
        #expect(throws: JSONExtractionError.self) { try extractJSON("没有 JSON") }
    }

    @Test("JSONValue 区分布尔与数字") func boolVsNumber() throws {
        #expect(try JSONValue.parse("[true, 1, 1.5, null]") == [true, 1, 1.5, nil])
    }
}
