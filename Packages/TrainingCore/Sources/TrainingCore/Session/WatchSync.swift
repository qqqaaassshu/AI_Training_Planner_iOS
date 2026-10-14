import Foundation

// iPhone ↔ Watch 同步（WatchConnectivity）的数据格式与合并规则。
//
// - iPhone → Watch：`WatchSnapshot`，用 `updateApplicationContext` 发送（只保留最新一份）
// - Watch → iPhone：单条 `ExecutionRecord`，用 `transferUserInfo` 排队发送（不丢失）
// - 同一任务同一天两边都改过时，以 `updated_at` 较新的为准

/// iPhone 发给手表的数据：当前计划与最近的记录
public struct WatchSnapshot: Codable, Hashable, Sendable {
    public var plan: PlanVersion?
    public var records: [ExecutionRecord]
    public var generatedAt: String

    public init(plan: PlanVersion?, records: [ExecutionRecord], generatedAt: String = Timestamp.now()) {
        self.plan = plan
        self.records = records
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case plan, records
        case generatedAt = "generated_at"
    }

    /// WatchConnectivity 字典里的键
    public static let contextKey = "snapshot"
    public static let recordKey = "record"

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> WatchSnapshot { try JSONDecoder().decode(WatchSnapshot.self, from: data) }
}

extension ExecutionRecord {
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> ExecutionRecord { try JSONDecoder().decode(ExecutionRecord.self, from: data) }
}

extension PersistedState {
    /// 发给手表的快照：当前计划，以及最近 `days` 天（含今天）的记录
    public func watchSnapshot(today: LocalDate, days: Int = 7, now: Date = Date()) -> WatchSnapshot {
        let from = today.adding(days: -(days - 1))
        return WatchSnapshot(plan: currentPlan, records: records.filter { $0.date >= from && $0.date <= today },
                             generatedAt: Timestamp.string(from: now))
    }

    /// 合并另一台设备的记录。同一任务同一天只保留一条：较新的覆盖较旧的（保留本机原来的 id）。
    /// 返回是否有变化。
    @discardableResult
    public mutating func merge(_ incoming: ExecutionRecord) -> Bool {
        if let i = records.firstIndex(where: { $0.taskId == incoming.taskId && $0.date == incoming.date }) {
            guard isNewer(incoming.updatedAt, than: records[i].updatedAt) else { return false }
            var r = incoming
            r.id = records[i].id
            if r == records[i] { return false }
            records[i] = r
            return true
        }
        records.append(incoming)
        return true
    }

    /// 手表收到快照：计划以手机为准；记录逐条合并（手表上较新、还没同步过去的记录保留）
    public mutating func apply(_ snapshot: WatchSnapshot) {
        planVersions = snapshot.plan.map { [$0] } ?? []
        currentPlanId = snapshot.plan?.id
        for r in snapshot.records { merge(r) }
    }
}

/// 比较两个 ISO 8601 时间戳；无法解析时按字符串比较
func isNewer(_ a: String, than b: String) -> Bool {
    if let da = Timestamp.parse(a), let db = Timestamp.parse(b) { return da > db }
    return a > b
}
