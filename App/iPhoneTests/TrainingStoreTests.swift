import Foundation
import SwiftData
import Testing
import TrainingCore
@testable import AITrainingPlanner

@MainActor
@Suite("TrainingStore：SwiftData 读写")
struct TrainingStoreTests {
    let container: ModelContainer
    let today = LocalDate.today()

    init() throws {
        container = try TrainingSchema.makeContainer(inMemory: true)
    }

    func importSample(into store: TrainingStore) throws {
        let text = samplePlanText(mode: .json, today: store.today)
        let preview = try #require(previewPlanImport(text, mode: .json, today: store.today, current: store.currentPlan).value)
        store.importPlan(preview)
    }

    @Test("导入计划、记录、疲劳与草稿在重新打开后仍在")
    func roundTrip() throws {
        let store = TrainingStore(context: container.mainContext)
        try importSample(into: store)
        let plan = try #require(store.currentPlan)
        let task = try #require(plan.tasks.first { $0.type == .habit })
        store.submit(RecordDraft(taskId: task.id, status: .completed, notes: "好"), date: today)
        store.setDailyFatigue(6)
        store.setDraft(TaskDraft(doneIds: ["e1"], items: []), date: today, taskId: "t1")

        let reopened = TrainingStore(context: ModelContext(container))
        #expect(reopened.currentPlan?.id == plan.id)
        #expect(reopened.state.records.count == 1)
        #expect(reopened.state.records.first?.notes == "好")
        #expect(reopened.state.dailyFatigue(on: today) == 6)
        #expect(reopened.draft(date: today, taskId: "t1")?.doneIds == ["e1"])
        #expect(store.lastError == nil)
    }

    @Test("再次提交覆盖同一条记录，并清除草稿；删除后不再读取")
    func overwriteAndDelete() throws {
        let store = TrainingStore(context: container.mainContext)
        try importSample(into: store)
        store.setDraft(TaskDraft(doneIds: ["e1"], items: []), date: today, taskId: "t1")
        store.submit(RecordDraft(taskId: "t1", status: .partial), date: today)
        store.submit(RecordDraft(taskId: "t1", status: .completed), date: today)
        #expect(store.state.records.count == 1)
        #expect(store.draft(date: today, taskId: "t1") == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RecordEntity>()) == 1)

        store.deleteRecord(id: store.state.records[0].id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RecordEntity>()) == 0)
        #expect(TrainingStore(context: ModelContext(container)).state.records.isEmpty)
    }

    @Test("新版本与切换版本")
    func versions() throws {
        let store = TrainingStore(context: container.mainContext)
        try importSample(into: store)
        try importSample(into: store)
        #expect(store.versionsNewestFirst.map(\.version) == [2, 1])
        let v1 = store.versionsNewestFirst[1]
        store.selectVersion(id: v1.id)
        #expect(TrainingStore(context: ModelContext(container)).currentPlan?.version == 1)
    }

    @Test("过期草稿在启动时清除")
    func staleDrafts() throws {
        let store = TrainingStore(context: container.mainContext)
        store.setDraft(TaskDraft(doneIds: ["e1"], items: []), date: today.adding(days: -1), taskId: "t1")
        _ = TrainingStore(context: ModelContext(container))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DraftEntity>()) == 0)
    }
}
