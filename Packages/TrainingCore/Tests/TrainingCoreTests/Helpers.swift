import Foundation
@testable import TrainingCore

/// 示例计划原始 JSON（与网页原型 src/app/fixtures/samplePlan.json 相同）
let samplePlanJSON: JSONValue = {
    let url = Bundle.module.url(forResource: "samplePlan", withExtension: "json")!
    return try! JSONValue.parse(Data(contentsOf: url))
}()

func d(_ s: String) -> LocalDate { LocalDate(s)! }

func samplePlanInput() -> PlanInput {
    guard case .ok(let p) = validatePlanInput(samplePlanJSON) else { fatalError("示例计划校验失败") }
    return p
}

func makePlan(now: Date = Date(timeIntervalSince1970: 1_780_272_000)) -> PlanVersion { // 2026-06-01T00:00:00Z
    createPlanVersion(samplePlanInput(), existing: [], source: .jsonImport, now: now)
}

nonisolated(unsafe) private var seq = 0
func rec(_ taskId: String = "t1", _ date: String, _ status: RecordStatus, planVersionId: String = "p",
         skipReason: SkipReason? = nil, pain: Int? = nil, fatigue: Int? = nil, notes: String = "") -> ExecutionRecord {
    seq += 1
    return ExecutionRecord(id: "r\(seq)", taskId: taskId, planVersionId: planVersionId, date: d(date), status: status,
                           skipReason: skipReason, painScore: pain, fatigueScore: fatigue, notes: notes, source: .phone,
                           updatedAt: "\(date)T12:00:00Z")
}

/// 修改 JSONValue 对象的某个键
extension JSONValue {
    func with(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(var o) = self else { return self }
        o[key] = value
        return .object(o)
    }
}
