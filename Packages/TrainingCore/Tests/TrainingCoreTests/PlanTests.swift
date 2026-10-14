import Foundation
import Testing
@testable import TrainingCore

@Suite("日程与周数") struct ScheduleTests {
    let plan = makePlan()

    @Test("总周数与当前周") func weeks() {
        #expect(plan.totalWeeks == 12)
        #expect(plan.currentWeek(today: d("2026-06-15")) == 1)
        #expect(plan.currentWeek(today: d("2026-06-22")) == 2)
        #expect(plan.currentWeek(today: d("2026-12-01")) == 12)
    }

    @Test("计划开始前 / 结束后没有任务") func outOfRange() {
        #expect(plan.tasks(on: d("2026-06-14")).isEmpty)
        #expect(plan.tasks(on: d("2026-09-07")).isEmpty)
        #expect(plan.tasks(on: d("2026-06-15")).map(\.id) == ["t1", "t2", "t3"]) // 周一
        #expect(plan.tasks(on: d("2026-06-16")).map(\.id) == ["t2", "t3"]) // 周二
    }

    @Test("按周渐进：第 5 周起使用 phase 动作") func phases() {
        let t1 = plan.tasks[0]
        #expect(plan.exercises(for: t1, on: d("2026-07-10"))[0].targetText == "3×10") // 第 4 周
        #expect(plan.exercises(for: t1, on: d("2026-07-13"))[0].targetText == "4×10 @10kg") // 第 5 周
        #expect(plan.exercises(for: t1, on: d("2026-07-13"))[2].targetText == "3×45秒")
    }

    @Test("排期范围截断到计划起止日期") func clamp() {
        let s = plan.scheduledTasks(from: d("2026-06-01"), to: d("2026-06-16"))
        #expect(s[0].date == d("2026-06-15"))
        #expect(s.count == 5)
    }
}

@Suite("buildExportSummary") struct SummaryTests {
    let plan = makePlan()

    @Test("今天还没做的任务不算遗漏，partial 计半") func today() {
        // 6/15 周一：t1 t2 t3；6/16 周二（今天）：t2 t3
        let records = [
            rec("t1", "2026-06-15", .partial),
            rec("t2", "2026-06-15", .completed, pain: 2),
            rec("t3", "2026-06-15", .skipped, skipReason: .noTime),
            rec("t2", "2026-06-16", .completed, pain: 6),
        ]
        let s = buildExportSummary(plan: plan, records: records, dailyWellness: [], today: d("2026-06-16"))
        #expect(s.scheduledCount == 4) // 昨天 3 + 今天已记录 1
        #expect(s.completedCount == 2)
        #expect(s.partialCount == 1)
        #expect(s.skippedCount == 1)
        #expect(s.completionRate == 63) // (2 + 0.5) / 4
        #expect(s.missedTasks.isEmpty)
        #expect(s.skipReasons == [.noTime: 1])
        #expect(s.painAverage == 4)
        #expect(s.painMax == 6)
    }

    @Test("过去没有记录的任务计为遗漏") func missed() {
        let s = buildExportSummary(plan: plan, records: [], dailyWellness: [], today: d("2026-06-16"))
        #expect(s.scheduledCount == 3)
        #expect(s.missedTasks == ["2026-06-15 · 身体维护训练A", "2026-06-15 · 散步20分钟", "2026-06-15 · 22:30准备睡觉"])
        #expect(s.completionRate == 0)
    }

    @Test("疲劳来自记录与每日评分，支持区间") func fatigue() {
        let s = buildExportSummary(
            plan: plan,
            records: [rec("t1", "2026-06-15", .completed, fatigue: 4)],
            dailyWellness: [DailyWellness(date: d("2026-06-15"), fatigueScore: 6, updatedAt: ""),
                            DailyWellness(date: d("2026-06-01"), fatigueScore: 10, updatedAt: "")],
            today: d("2026-06-16"),
            range: DateRange(from: d("2026-06-10"), to: d("2026-06-16"))
        )
        #expect(s.fatigueAverage == 5)
    }

    @Test("skip_reasons 编码为对象") func encoding() throws {
        let s = buildExportSummary(plan: plan, records: [rec("t1", "2026-06-15", .skipped, skipReason: .pain)],
                                   dailyWellness: [], today: d("2026-06-16"))
        let json = try JSONValue(encoding: s)
        #expect(json["skip_reasons"] == ["pain": 1])
    }
}

@Suite("组记录") struct SetsTests {
    @Test("expandSets / summarizeSets 互逆") func roundTrip() {
        let items = [
            SetSummary(exerciseId: "e1", name: "深蹲", sets: 3, reps: 10, weightKg: 10),
            SetSummary(exerciseId: "e3", name: "平板支撑", sets: 2, durationSec: 30),
        ]
        let sets = expandSets(items, completedAt: "2026-06-15T08:00:00Z")
        #expect(sets.count == 5)
        #expect(sets[4].exerciseId == "e3" && sets[4].setIndex == 2 && sets[4].durationSec == 30)
        #expect(summarizeSets(sets) == items)
    }

    @Test("组数不足为 partial") func partial() {
        let planned = makePlan().tasks[0].exercises! // 共 9 组
        let sets = expandSets([SetSummary(exerciseId: "e1", name: "深蹲", sets: 3, reps: 10)], completedAt: "")
        #expect(statusForSets(planned: planned, sets: sets) == .partial)
        let all = expandSets(planned.map { SetSummary(exerciseId: $0.id, name: $0.name, sets: $0.sets, reps: $0.reps) }, completedAt: "")
        #expect(statusForSets(planned: planned, sets: all) == .completed)
    }
}

@Suite("版本") struct VersionTests {
    @Test("版本号递增并记录父版本") func increments() {
        let v1 = makePlan()
        let v2 = createPlanVersion(samplePlanInput(), existing: [v1], source: .aiAnalysis, analysisId: "a1")
        #expect(v2.version == 2)
        #expect(v2.parentVersionId == v1.id)
        #expect(v2.analysisId == "a1")
        #expect(v2.schemaVersion == "2.0")
        #expect(v1.createdAt == "2026-06-01T00:00:00.000Z")
    }

    @Test("自然语言重新导入时按标题沿用任务与动作 id，对比只显示真实变化") func reconcile() throws {
        func text(_ reps: Int) -> String { "周二训练：\n深蹲3组\(reps)次\n平板支撑3组30秒\n\n每日习惯：\n散步20分钟" }
        let v1 = createPlanVersion(try parseNaturalLanguagePlan(text(10), today: d("2026-06-01")).plan, existing: [], source: .nlImport)
        let v2 = createPlanVersion(try parseNaturalLanguagePlan(text(12), today: d("2026-06-01")).plan, existing: [v1], source: .nlImport)

        #expect(v2.tasks.map(\.id) == v1.tasks.map(\.id))
        #expect(v2.tasks[0].exercises![0].id == v1.tasks[0].exercises![0].id)

        let diff = comparePlanVersions(v1, v2)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.modified == [.init(taskTitle: "周二训练", changes: ["深蹲：3×10 → 3×12"])])
    }

    @Test("对比：新增 / 删除 / 日程变化") func compare() {
        let v1 = makePlan()
        var v2 = v1
        var t0 = v1.tasks[0]
        t0.schedule = TaskSchedule(weekday: [1, 4])
        v2.tasks = [t0, PlanTask(id: "t9", title: "冥想", type: .habit, schedule: .everyDay()), v1.tasks[2]]
        let diff = comparePlanVersions(v1, v2)
        #expect(diff.added.map(\.taskTitle) == ["冥想"])
        #expect(diff.removed.map(\.taskTitle) == ["散步20分钟"])
        #expect(diff.modified[0].changes == ["日程：周一、周三、周五 07:30 → 周一、周四"])
    }

    @Test("PlanVersion 编码为原型的 JSON 字段名") func encoding() throws {
        let json = try JSONValue(encoding: makePlan())
        #expect(json["plan_name"] == "12周体能恢复计划")
        #expect(json["start_date"] == "2026-06-15")
        #expect(json["tasks"]?.arrayValue?[0]["exercises"]?.arrayValue?[0]["rest_sec"] == 60)
        #expect(json["parent_version_id"] == nil)
    }
}
