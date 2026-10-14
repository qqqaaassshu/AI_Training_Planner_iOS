import Foundation
import Observation
import SwiftData
import TrainingCore

/// App 的数据入口：内存里是 TrainingCore 的 `PersistedState`，每次修改后写回 SwiftData。
@MainActor
@Observable
final class TrainingStore {
    private(set) var state = PersistedState()
    private(set) var drafts: [String: TaskDraft] = [:]
    /// 今天（设备时区）；跨过午夜或回到前台时刷新
    private(set) var today = LocalDate.today()
    /// 最近一次读写失败的原因，界面上提示
    var lastError: String?

    /// 数据变化后调用（发给手表）
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    @ObservationIgnored private let decoder = JSONDecoder()

    init(context: ModelContext) {
        self.context = context
        load()
    }

    var currentPlan: PlanVersion? { state.currentPlan }

    /// 版本从新到旧
    var versionsNewestFirst: [PlanVersion] { state.planVersions.sorted { $0.version > $1.version } }

    func refreshToday(now: Date = Date()) {
        let t = LocalDate.today(now: now)
        if t != today {
            today = t
            onChange?()
        }
    }

    /// 手表发来的记录：较新的覆盖较旧的
    func mergeFromWatch(_ record: ExecutionRecord) {
        mutate { $0.merge(record) }
    }

    // MARK: 修改

    func importPlan(_ preview: PlanImportPreview) {
        let version = preview.makeVersion(existing: state.planVersions, current: state.currentPlan)
        mutate { $0.addPlanVersion(version) }
    }

    func selectVersion(id: String) {
        mutate { $0.selectPlanVersion(id: id) }
    }

    /// 提交今日任务；同时清除草稿
    func submit(_ draft: RecordDraft, date: LocalDate) {
        mutate { $0.record(draft, date: date) }
        setDraft(nil, date: date, taskId: draft.taskId)
    }

    func updateRecord(id: String, _ change: (inout ExecutionRecord) -> Void) {
        mutate { $0.updateRecord(id: id, change) }
    }

    func deleteRecord(id: String) {
        mutate { $0.deleteRecord(id: id) }
    }

    func setDailyFatigue(_ score: Int) {
        mutate { $0.setDailyFatigue(score, date: today) }
    }

    // MARK: 草稿

    static func draftKey(date: LocalDate, taskId: String) -> String { "\(date)|\(taskId)" }

    func draft(date: LocalDate, taskId: String) -> TaskDraft? {
        drafts[Self.draftKey(date: date, taskId: taskId)]
    }

    func setDraft(_ draft: TaskDraft?, date: LocalDate, taskId: String) {
        let key = Self.draftKey(date: date, taskId: taskId)
        guard drafts[key] != draft else { return }
        drafts[key] = draft
        do {
            let existing = try context.fetch(FetchDescriptor<DraftEntity>(predicate: #Predicate { $0.key == key })).first
            if let draft {
                let data = try encoder.encode(draft)
                if let existing { existing.payload = data } else { context.insert(DraftEntity(key: key, payload: data)) }
            } else if let existing {
                context.delete(existing)
            }
            try context.save()
        } catch {
            lastError = "保存草稿失败：\(error.localizedDescription)"
        }
    }

    // MARK: 读写

    private func mutate(_ change: (inout PersistedState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        do {
            try persist(next)
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
        onChange?()
    }

    private func load() {
        do {
            let versions = try context.fetch(FetchDescriptor<PlanVersionEntity>()).compactMap { try? decoder.decode(PlanVersion.self, from: $0.payload) }
            let records = try context.fetch(FetchDescriptor<RecordEntity>()).compactMap { try? decoder.decode(ExecutionRecord.self, from: $0.payload) }
            let wellness = try context.fetch(FetchDescriptor<WellnessEntity>()).compactMap { try? decoder.decode(DailyWellness.self, from: $0.payload) }
            let analyses = try context.fetch(FetchDescriptor<AnalysisEntity>()).compactMap { try? decoder.decode(AIAnalysis.self, from: $0.payload) }
            let settings = try settingsEntity()
            state = PersistedState(
                planVersions: versions.sorted { $0.version < $1.version },
                currentPlanId: settings.currentPlanId,
                records: records,
                dailyWellness: wellness,
                analyses: analyses,
                aiSettings: settings.aiSettings.flatMap { try? decoder.decode(AISettings.self, from: $0) } ?? AISettings(),
                profile: settings.profile.flatMap { try? decoder.decode(UserProfile.self, from: $0) } ?? UserProfile(),
                profileHistory: settings.profileHistory.flatMap { try? decoder.decode([ProfileChange].self, from: $0) } ?? []
            )
            var loaded: [String: TaskDraft] = [:]
            for e in try context.fetch(FetchDescriptor<DraftEntity>()) {
                // 过期草稿（不是今天的）直接清掉
                if e.key.hasPrefix("\(today)|"), let d = try? decoder.decode(TaskDraft.self, from: e.payload) {
                    loaded[e.key] = d
                } else {
                    context.delete(e)
                }
            }
            drafts = loaded
            try context.save()
        } catch {
            lastError = "读取数据失败：\(error.localizedDescription)"
        }
    }

    private func settingsEntity() throws -> SettingsEntity {
        let key = SettingsEntity.mainKey
        if let s = try context.fetch(FetchDescriptor<SettingsEntity>(predicate: #Predicate { $0.key == key })).first { return s }
        let s = SettingsEntity()
        context.insert(s)
        return s
    }

    /// 只写入有变化的条目
    private func persist(_ s: PersistedState) throws {
        try sync(s.planVersions, entities: context.fetch(FetchDescriptor<PlanVersionEntity>()), id: \.id, entityId: \.id,
                 payload: \.payload, make: { v, data in PlanVersionEntity(id: v.id, version: v.version, payload: data) })
        try sync(s.records, entities: context.fetch(FetchDescriptor<RecordEntity>()), id: \.id, entityId: \.id,
                 payload: \.payload, make: { r, data in RecordEntity(id: r.id, taskId: r.taskId, date: r.date.description, payload: data) },
                 update: { e, r in
                     e.taskId = r.taskId
                     e.date = r.date.description
                 })
        try sync(s.dailyWellness, entities: context.fetch(FetchDescriptor<WellnessEntity>()), id: { $0.date.description }, entityId: \.date,
                 payload: \.payload, make: { w, data in WellnessEntity(date: w.date.description, payload: data) })
        try sync(s.analyses, entities: context.fetch(FetchDescriptor<AnalysisEntity>()), id: \.id, entityId: \.id,
                 payload: \.payload, make: { a, data in AnalysisEntity(id: a.id, payload: data) })

        let settings = try settingsEntity()
        if settings.currentPlanId != s.currentPlanId { settings.currentPlanId = s.currentPlanId }
        let profile = try encoder.encode(s.profile)
        if settings.profile != profile { settings.profile = profile }
        let history = try encoder.encode(s.profileHistory)
        if settings.profileHistory != history { settings.profileHistory = history }
        let ai = try encoder.encode(s.aiSettings)
        if settings.aiSettings != ai { settings.aiSettings = ai }

        try context.save()
    }

    private func sync<T: Encodable, E: PersistentModel>(
        _ items: [T], entities: [E], id: (T) -> String, entityId: KeyPath<E, String>,
        payload: ReferenceWritableKeyPath<E, Data>, make: (T, Data) -> E, update: ((E, T) -> Void)? = nil
    ) throws {
        var byId = Dictionary(entities.map { ($0[keyPath: entityId], $0) }, uniquingKeysWith: { a, _ in a })
        for item in items {
            let data = try encoder.encode(item)
            if let e = byId.removeValue(forKey: id(item)) {
                if e[keyPath: payload] != data {
                    e[keyPath: payload] = data
                    update?(e, item)
                }
            } else {
                context.insert(make(item, data))
            }
        }
        for leftover in byId.values { context.delete(leftover) }
    }
}
