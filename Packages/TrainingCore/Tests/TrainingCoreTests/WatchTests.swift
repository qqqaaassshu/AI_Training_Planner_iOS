import Foundation
import Testing
@testable import TrainingCore

@Suite("手表逐组训练") struct WorkoutProgressTests {
    let t0 = Date(timeIntervalSince1970: 1_781_479_800)
    /// 深蹲 3×10（休息 60）、臀桥 3×12（休息 45）、平板支撑 3×30秒（休息 30）
    var exercises: [Exercise] { makePlan().tasks[0].exercises! }

    @Test("完成一组 → 休息 → 下一组；换动作时数值重置") func flow() throws {
        var w = WorkoutProgress(taskId: "t1", date: d("2026-06-15"), exercises: exercises, startedAt: t0)
        #expect(w.current?.name == "深蹲" && w.value == 10 && w.step == 1 && w.totalSets == 9)
        w.adjust(steps: 2)
        let untilOpt = w.completeSet(now: t0)
        let until = try #require(untilOpt)
        #expect(until == t0.addingTimeInterval(60))
        #expect(w.phase == .rest(until: until))
        w.setValue(99) // 休息中不能改
        #expect(w.value == 12)
        w.endRestIfDue(now: t0.addingTimeInterval(30))
        #expect(w.phase == .rest(until: until))
        w.endRestIfDue(now: until)
        #expect(w.phase == .set && w.setIndex == 2 && w.value == 12) // 同一动作沿用调整后的数值
        w.completeSet(now: t0)
        w.skipRest()
        w.completeSet(now: t0)
        w.skipRest()
        #expect(w.current?.name == "臀桥" && w.setIndex == 1 && w.value == 12)
        #expect(w.logs.map(\.reps) == [12, 12, 12])
    }

    @Test("计时动作按秒记录，每格 5 秒；全部完成后结束") func timedAndFinish() {
        var w = WorkoutProgress(taskId: "t1", date: d("2026-06-15"), exercises: exercises, startedAt: t0)
        for _ in 0..<6 {
            w.completeSet(now: t0)
            w.skipRest()
        }
        #expect(w.isTimed && w.step == 5 && w.valueText == "30秒")
        w.adjust(steps: -1)
        #expect(w.value == 25)
        w.completeSet(now: t0)
        w.skipRest()
        w.completeSet(now: t0)
        w.skipRest()
        let r1 = w.completeSet(now: t0)
        #expect(r1 == nil)
        #expect(w.isFinished)
        #expect(w.logs.last?.durationSec == 25 && w.logs.last?.reps == nil)
        let draft = w.recordDraft()
        #expect(draft.status == .completed && draft.sets?.count == 9)
        #expect(draft.startedAt == Timestamp.string(from: t0))
    }

    @Test("中途结束：有完成的组保存为部分完成，否则直接退出") func early() {
        var w = WorkoutProgress(taskId: "t1", date: d("2026-06-15"), exercises: exercises, startedAt: t0)
        let r2 = w.finishEarly()
        #expect(!r2)
        w.completeSet(now: t0)
        let r3 = w.finishEarly()
        #expect(r3)
        #expect(w.recordDraft().status == .partial)
        #expect(w.minutes(now: t0.addingTimeInterval(10)) == 1)
    }

    @Test("带重量的动作记录重量；可编码恢复") func weightAndCodable() throws {
        let phased = makePlan().exercises(for: makePlan().tasks[0], on: d("2026-07-13"))
        var w = WorkoutProgress(taskId: "t1", date: d("2026-07-13"), exercises: phased, startedAt: t0)
        w.completeSet(now: t0)
        #expect(w.logs[0].weightKg == 10)
        let back = try JSONDecoder().decode(WorkoutProgress.self, from: JSONEncoder().encode(w))
        #expect(back == w)
    }

    @Test("没有动作时直接结束") func empty() {
        #expect(WorkoutProgress(taskId: "t", date: d("2026-06-15"), exercises: []).isFinished)
    }
}

@Suite("iPhone ↔ Watch 同步") struct WatchSyncTests {
    func phoneState() -> PersistedState {
        var s = PersistedState()
        s.addPlanVersion(makePlan())
        s.addPlanVersion(createPlanVersion(samplePlanInput(), existing: s.planVersions, source: .jsonImport))
        return s
    }

    func record(_ date: String, _ status: RecordStatus, updated: String, id: String = newId()) -> ExecutionRecord {
        ExecutionRecord(id: id, taskId: "t1", planVersionId: "p", date: d(date), status: status, source: .watch, updatedAt: updated)
    }

    @Test("快照只带当前计划与最近 7 天的记录") func snapshot() throws {
        var s = phoneState()
        s.records = [rec("t1", "2026-06-09", .completed), rec("t1", "2026-06-10", .completed), rec("t1", "2026-06-16", .completed), rec("t1", "2026-06-17", .completed)]
        let snap = s.watchSnapshot(today: d("2026-06-16"))
        #expect(snap.plan?.version == 2)
        #expect(snap.records.map(\.date) == [d("2026-06-10"), d("2026-06-16")])
        #expect(try WatchSnapshot.decode(snap.encoded()) == snap)
    }

    @Test("合并：较新的覆盖较旧的并保留原 id；较旧的忽略") func merge() {
        var s = phoneState()
        s.records = [record("2026-06-15", .snoozed, updated: "2026-06-15T08:00:00.000Z", id: "phone")]
        let r4 = s.merge(record("2026-06-15", .completed, updated: "2026-06-15T07:00:00.000Z"))
        #expect(!r4)
        #expect(s.records[0].status == .snoozed)
        let r5 = s.merge(record("2026-06-15", .completed, updated: "2026-06-15T09:00:00.000Z", id: "watch"))
        #expect(r5)
        #expect(s.records.count == 1 && s.records[0].status == .completed && s.records[0].id == "phone")
        let same = s.records[0]
        let r7 = s.merge(same)
        #expect(!r7) // 相同内容
        let r6 = s.merge(record("2026-06-17", .completed, updated: "2026-06-17T09:00:00Z"))
        #expect(r6)
        #expect(s.records.count == 2)
    }

    @Test("时间戳比较兼容不同写法") func timestamps() {
        #expect(isNewer("2026-06-15T09:00:00Z", than: "2026-06-15T08:59:59.999Z"))
        #expect(!isNewer("2026-06-15T08:00:00+08:00", than: "2026-06-15T00:00:00.000Z"))
    }

    @Test("手表应用快照：计划以手机为准，手表上较新的记录保留") func applySnapshot() {
        var watch = PersistedState()
        watch.addPlanVersion(makePlan())
        watch.records = [record("2026-06-15", .completed, updated: "2026-06-15T09:00:00Z", id: "w")]
        var phone = phoneState()
        phone.records = [record("2026-06-15", .snoozed, updated: "2026-06-15T08:00:00Z", id: "p"),
                         record("2026-06-14", .skipped, updated: "2026-06-14T08:00:00Z", id: "p2")]
        watch.apply(phone.watchSnapshot(today: d("2026-06-15")))
        #expect(watch.planVersions.count == 1 && watch.currentPlan?.version == 2)
        #expect(watch.records.first { $0.date == d("2026-06-15") }?.status == .completed)
        #expect(watch.records.count == 2)
        watch.apply(WatchSnapshot(plan: nil, records: []))
        #expect(watch.currentPlan == nil)
    }
}
