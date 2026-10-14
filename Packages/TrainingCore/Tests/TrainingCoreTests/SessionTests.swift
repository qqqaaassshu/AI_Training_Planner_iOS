import Foundation
import Testing
@testable import TrainingCore

@Suite("今日任务：打勾与提交") struct TaskProgressTests {
    let plan = makePlan()
    var t1: PlanTask { plan.tasks[0] }
    var planned: [Exercise] { plan.exercises(for: t1, on: d("2026-06-15")) }

    @Test("计划默认值：计时动作不带次数") func defaults() {
        let p = TaskProgress.initial(planned: planned, record: nil, draft: nil)
        #expect(p.items.map(\.name) == ["深蹲", "臀桥", "平板支撑"])
        #expect(p.items[2].reps == nil && p.items[2].durationSec == 30)
        #expect(p.doneIds.isEmpty && p.draft == nil)
    }

    @Test("部分完成的记录优先于草稿") func partialWins() {
        let sets = expandSets([SetSummary(exerciseId: "e1", name: "深蹲", sets: 2, reps: 8)], completedAt: "")
        var r = rec("t1", "2026-06-15", .partial)
        r.sets = sets
        let draft = TaskDraft(doneIds: ["e2"], items: [])
        let p = TaskProgress.initial(planned: planned, record: r, draft: draft)
        #expect(p.doneIds == ["e1"])
        #expect(p.items[0].sets == 2 && p.items[0].reps == 8)
        #expect(TaskProgress.initial(planned: planned, record: nil, draft: draft).doneIds == ["e2"])
    }

    @Test("打勾进度") func toggle() {
        var p = TaskProgress.initial(planned: planned, record: nil, draft: nil)
        p.toggle("e1")
        p.toggle("e2")
        #expect(p.doneCount(planned: planned) == 2 && !p.allDone(planned: planned))
        p.toggle("e2")
        #expect(p.doneIds == ["e1"])
        p.toggle("e2")
        p.toggle("e3")
        #expect(p.allDone(planned: planned))
        #expect(p.draft?.doneIds == ["e1", "e2", "e3"])
    }

    @Test("只勾了部分动作时记为部分完成，只记录勾选的") func partialSubmit() {
        var p = TaskProgress.initial(planned: planned, record: nil, draft: nil)
        p.toggle("e1")
        let draft = RecordDraft.make(task: t1, planned: planned, progress: p, outcome: .done, notes: "n", painScore: 2)
        #expect(draft.status == .partial)
        #expect(draft.sets?.count == 3)
        #expect(draft.painScore == 2 && draft.notes == "n")
    }

    @Test("一个都没勾时按计划全部完成") func fullSubmit() {
        let p = TaskProgress.initial(planned: planned, record: nil, draft: nil)
        let draft = RecordDraft.make(task: t1, planned: planned, progress: p, outcome: .done, notes: "", painScore: nil)
        #expect(draft.status == .completed)
        #expect(draft.sets?.count == 9)
    }

    @Test("习惯：没有动作，不记疼痛") func habit() {
        let habit = plan.tasks[1]
        let draft = RecordDraft.make(task: habit, planned: [], progress: TaskProgress(items: []), outcome: .done, notes: "", painScore: 5)
        #expect(draft.status == .completed && draft.sets == nil && draft.painScore == nil)
    }

    @Test("延后与跳过") func others() {
        let p = TaskProgress(items: [])
        #expect(RecordDraft.make(task: t1, planned: planned, progress: p, outcome: .snoozed, notes: "", painScore: nil).status == .snoozed)
        let s = RecordDraft.make(task: t1, planned: planned, progress: p, outcome: .skipped(.noTime), notes: "", painScore: 3)
        #expect(s.status == .skipped && s.skipReason == .noTime && s.sets == nil && s.painScore == nil)
    }
}

@Suite("状态修改") struct StateMutationTests {
    let now = Date(timeIntervalSince1970: 1_781_000_000)

    func state() -> PersistedState {
        var s = PersistedState()
        s.addPlanVersion(makePlan())
        return s
    }

    @Test("导入与切换版本") func versions() {
        var s = state()
        let v2 = createPlanVersion(samplePlanInput(), existing: s.planVersions, source: .jsonImport, parent: s.currentPlan)
        s.addPlanVersion(v2)
        #expect(s.currentPlan?.version == 2)
        s.selectPlanVersion(id: s.planVersions[0].id)
        #expect(s.currentPlan?.version == 1)
        s.selectPlanVersion(id: "不存在")
        #expect(s.currentPlan?.version == 1)
    }

    @Test("同一任务同一天再次提交时覆盖，保留原 id") func overwrite() throws {
        var s = state()
        let firstOpt = s.record(RecordDraft(taskId: "t1", status: .snoozed), date: d("2026-06-15"), now: now)
        let first = try #require(firstOpt)
        #expect(first.completedAt == nil && first.planVersionId == s.currentPlanId)
        let secondOpt = s.record(RecordDraft(taskId: "t1", status: .completed), date: d("2026-06-15"), source: .watch, now: now)
        let second = try #require(secondOpt)
        #expect(second.id == first.id)
        #expect(second.completedAt == Timestamp.string(from: now))
        #expect(second.source == .watch)
        #expect(s.records.count == 1)
        s.record(RecordDraft(taskId: "t1", status: .completed), date: d("2026-06-17"), now: now)
        #expect(s.records.count == 2)
    }

    @Test("没有计划时不记录") func noPlan() {
        var s = PersistedState()
        #expect(s.record(RecordDraft(taskId: "t1", status: .completed), date: d("2026-06-15")) == nil)
    }

    @Test("修改、删除记录与每日疲劳") func editing() throws {
        var s = state()
        let rOpt = s.record(RecordDraft(taskId: "t1", status: .completed), date: d("2026-06-15"), now: now)
        let r = try #require(rOpt)
        s.updateRecord(id: r.id, now: now.addingTimeInterval(60)) { $0.notes = "补录" }
        #expect(s.records[0].notes == "补录")
        #expect(s.records[0].updatedAt == Timestamp.string(from: now.addingTimeInterval(60)))
        s.setDailyFatigue(6, date: d("2026-06-15"), now: now)
        s.setDailyFatigue(7, date: d("2026-06-15"), now: now)
        #expect(s.dailyWellness.count == 1 && s.dailyFatigue(on: d("2026-06-15")) == 7)
        s.deleteRecord(id: r.id)
        #expect(s.records.isEmpty)
    }
}

@Suite("历史") struct HistoryTests {
    @Test("按日期从新到旧分组，只有疲劳的日期也列出") func grouping() {
        let records = [rec("t1", "2026-06-15", .completed), rec("t2", "2026-06-16", .skipped), rec("t3", "2026-06-15", .partial)]
        let days = historyDays(records: records, wellness: [DailyWellness(date: d("2026-06-17"), fatigueScore: 4, updatedAt: "")])
        #expect(days.map(\.date) == [d("2026-06-17"), d("2026-06-16"), d("2026-06-15")])
        #expect(days[0].records.isEmpty && days[0].fatigue == 4)
        #expect(days[2].records.map(\.taskId) == ["t1", "t3"])
        let stats = HistoryStats(records: records)
        #expect(stats.done == 2 && stats.skipped == 1 && stats.rate == 67)
    }

    @Test("记录对应的任务：优先记录所属版本") func findsTask() {
        let v1 = makePlan()
        var v2 = createPlanVersion(samplePlanInput(), existing: [v1], source: .jsonImport)
        v2.tasks[0].title = "新标题"
        let old = rec("t1", "2026-06-15", .completed, planVersionId: v1.id)
        #expect(findTask(for: old, in: [v1, v2])?.task.title == "身体维护训练A")
        let orphan = rec("t1", "2026-06-15", .completed, planVersionId: "已删除")
        #expect(findTask(for: orphan, in: [v1, v2])?.task.title == "新标题")
        #expect(findTask(for: rec("t9", "2026-06-15", .completed), in: [v1]) == nil)
    }

    @Test("补录编辑器初始值") func editorInit() {
        let v1 = makePlan()
        #expect(editorItems(for: rec("t1", "2026-07-13", .skipped, planVersionId: v1.id), versions: [v1]).first?.sets == 4) // 第 5 周
        var r = rec("t1", "2026-06-15", .completed)
        r.sets = expandSets([SetSummary(exerciseId: "x", name: "自定义", sets: 1, reps: 5)], completedAt: "")
        #expect(editorItems(for: r, versions: [v1]).map(\.name) == ["自定义"])
    }
}

@Suite("导入计划") struct PlanImportTests {
    @Test("JSON：校验并预览与当前版本的差异") func json() throws {
        let current = makePlan()
        let text = encodeJSONString(samplePlanJSON.with("plan_name", "改名"), pretty: false)
        let preview = try #require(previewPlanImport(text, mode: .json, today: d("2026-06-15"), current: current).value)
        #expect(preview.source == .jsonImport)
        #expect(preview.diff?.isEmpty == true) // 任务没有变化
        let v2 = preview.makeVersion(existing: [current], current: current)
        #expect(v2.version == 2 && v2.planName == "改名" && v2.parentVersionId == current.id)
    }

    @Test("JSON 语法错误与校验错误") func jsonErrors() {
        #expect(previewPlanImport("{", mode: .json, today: d("2026-06-15"), current: nil).errors == ["JSON 格式错误，请检查括号、引号与逗号"])
        #expect(previewPlanImport(#"{"plan_name":"x"}"#, mode: .json, today: d("2026-06-15"), current: nil).errors.contains("tasks：至少需要一个任务"))
    }

    @Test("自然语言：带出未识别的行，差异按标题匹配") func natural() throws {
        let first = try #require(previewPlanImport("周二训练：\n深蹲3组10次", mode: .naturalLanguage, today: d("2026-06-01"), current: nil).value)
        #expect(first.diff == nil)
        let v1 = first.makeVersion(existing: [], current: nil)
        let second = try #require(previewPlanImport("周二训练：\n深蹲3组12次\n弹力带激活一下", mode: .naturalLanguage, today: d("2026-06-01"), current: v1).value)
        #expect(second.warnings == ["未识别：弹力带激活一下"])
        #expect(second.diff?.modified == [.init(taskTitle: "周二训练", changes: ["深蹲：3×10 → 3×12"])])
        #expect(previewPlanImport("你好", mode: .naturalLanguage, today: d("2026-06-01"), current: nil).errors.first?.contains("未能识别") == true)
    }

    @Test("示例计划从本周一开始 12 周，且都能导入") func samples() throws {
        let today = d("2026-10-14") // 周三
        for mode in PlanImportMode.allCases {
            let p = try #require(previewPlanImport(samplePlanText(mode: mode, today: today), mode: mode, today: today, current: nil).value)
            #expect(p.input.startDate == d("2026-10-12"))
            #expect(p.warnings.isEmpty)
        }
        let json = try #require(previewPlanImport(samplePlanText(mode: .json, today: today), mode: .json, today: today, current: nil).value)
        #expect(json.input.endDate == d("2027-01-03"))
    }
}
