import Foundation
import Testing
@testable import TrainingCore

struct ExerciseCase: Sendable, CustomTestStringConvertible {
    var line: String
    var name: String
    var sets: Int
    var reps: Int?
    var durationSec: Int?
    var weightKg: Double?
    var testDescription: String { line }
}

let exerciseCases: [ExerciseCase] = [
    .init(line: "深蹲3组10次", name: "深蹲", sets: 3, reps: 10),
    .init(line: "Dead Bug 3组8次", name: "Dead Bug", sets: 3, reps: 8),
    .init(line: "- 深蹲 3组 x 10次", name: "深蹲", sets: 3, reps: 10),
    .init(line: "深蹲13组10次", name: "深蹲", sets: 13, reps: 10),
    .init(line: "深蹲3组10次 20kg", name: "深蹲", sets: 3, reps: 10, weightKg: 20),
    .init(line: "深蹲 3x10", name: "深蹲", sets: 3, reps: 10),
    .init(line: "深蹲3×10 @12.5kg", name: "深蹲", sets: 3, reps: 10, weightKg: 12.5),
    .init(line: "平板支撑3组30秒", name: "平板支撑", sets: 3, durationSec: 30),
    .init(line: "平板支撑 3x30秒", name: "平板支撑", sets: 3, durationSec: 30),
    .init(line: "靠墙静蹲3组1分钟", name: "靠墙静蹲", sets: 3, durationSec: 60),
    .init(line: "平板支撑60秒", name: "平板支撑", sets: 1, durationSec: 60),
    .init(line: "深蹲 3组 10", name: "深蹲", sets: 3, reps: 10),
]

@Suite("parseExerciseLine") struct ParseExerciseLineTests {
    @Test(arguments: exerciseCases) func parses(_ c: ExerciseCase) throws {
        let ex = try #require(parseExerciseLine(c.line))
        #expect(ex.name == c.name)
        #expect(ex.sets == c.sets)
        #expect(ex.reps == c.reps)
        #expect(ex.durationSec == c.durationSec)
        #expect(ex.weightKg == c.weightKg)
    }

    @Test("不是动作", arguments: ["12周恢复计划", "周二训练：", "", "深蹲0组10次"]) func notExercise(_ line: String) {
        #expect(parseExerciseLine(line) == nil)
    }
}

let sampleNL = """
12周恢复计划
开始日期：2026-06-15

周二训练：
深蹲3组10次
臀桥3组12次
Dead Bug 3组8次

周四训练：
俯卧撑3组8次
平板支撑3组30秒

每日习惯：
散步20分钟
22:30准备睡觉
"""

@Suite("parseNaturalLanguagePlan") struct ParseNLPlanTests {
    @Test("解析示例文本，平板支撑不丢失") func sample() throws {
        let r = try parseNaturalLanguagePlan(sampleNL, today: d("2026-06-01"))
        #expect(r.warnings.isEmpty)
        #expect(r.plan.planName == "12周恢复计划")
        #expect(r.plan.startDate == d("2026-06-15"))
        #expect(r.plan.tasks.map(\.title) == ["周二训练", "周四训练", "散步20分钟", "22:30准备睡觉"])
        #expect(r.plan.tasks[0].schedule == TaskSchedule(weekday: [2]))
        #expect(r.plan.tasks[1].exercises!.map(\.name) == ["俯卧撑", "平板支撑"])
        #expect(r.plan.tasks[1].exercises![1].durationSec == 30)
        #expect(r.plan.tasks[3].type == .habit)
        #expect(r.plan.tasks[3].schedule == TaskSchedule(daily: true, time: "22:30"))
        #expect(validatePlanInput(try JSONValue(encoding: r.plan)).isOK)
    }

    @Test("周一三五 与 时间") func compactWeekdays() throws {
        let r = try parseNaturalLanguagePlan("周一三五 07:30 力量训练：\n深蹲3组10次", today: d("2026-06-01"))
        #expect(r.plan.tasks[0].schedule == TaskSchedule(weekday: [1, 3, 5], time: "07:30"))
        #expect(r.plan.tasks[0].title == "周一三五 力量训练")
    }

    @Test("未识别的行进入 warnings") func warnings() throws {
        let r = try parseNaturalLanguagePlan("周二训练：\n深蹲3组10次\n弹力带激活一下", today: d("2026-06-01"))
        #expect(r.plan.tasks[0].exercises?.count == 1)
        #expect(r.warnings == ["未识别：弹力带激活一下"])
    }

    @Test("没有任何内容时报错") func empty() {
        #expect(throws: NLParseError.self) { try parseNaturalLanguagePlan("你好", today: d("2026-06-01")) }
    }

    @Test("未指定开始日期时用今天") func defaultStart() throws {
        #expect(try parseNaturalLanguagePlan("深蹲3组10次", today: d("2026-06-01")).plan.startDate == d("2026-06-01"))
    }
}
