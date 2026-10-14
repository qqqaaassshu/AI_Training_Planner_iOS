import Foundation

// 导入计划（对应原型 ImportPlan）：解析 → 校验 → 预览与当前版本的差异 → 确认后生成新版本。

public enum PlanImportMode: String, Hashable, Sendable, CaseIterable, Identifiable {
    case json
    case naturalLanguage

    public var id: String { rawValue }
    public var label: String { self == .json ? "JSON" : "自然语言" }
    var source: PlanSource { self == .json ? .jsonImport : .nlImport }
}

public struct PlanImportPreview: Sendable {
    public var input: PlanInput
    public var source: PlanSource
    /// 自然语言里没识别的行
    public var warnings: [String]
    /// 相对当前版本的变化（已按标题沿用 id）；没有当前计划时为 nil
    public var diff: PlanDiff?

    /// 确认导入：生成新版本（parent 为当前版本）
    public func makeVersion(existing: [PlanVersion], current: PlanVersion?, now: Date = Date()) -> PlanVersion {
        createPlanVersion(input, existing: existing, source: source, parent: current, now: now)
    }
}

public func previewPlanImport(_ text: String, mode: PlanImportMode, today: LocalDate, current: PlanVersion?) -> ValidationResult<PlanImportPreview> {
    let raw: JSONValue
    var warnings: [String] = []
    switch mode {
    case .json:
        guard let v = try? JSONValue.parse(text) else { return .failure(["JSON 格式错误，请检查括号、引号与逗号"]) }
        raw = v
    case .naturalLanguage:
        do {
            let r = try parseNaturalLanguagePlan(text, today: today)
            warnings = r.warnings
            raw = try JSONValue(encoding: r.plan)
        } catch {
            return .failure([(error as? LocalizedError)?.errorDescription ?? "格式错误"])
        }
    }
    switch validatePlanInput(raw) {
    case .failure(let errors):
        return .failure(errors)
    case .ok(let input):
        let diff = current.map { cur in
            comparePlanVersions(cur, createPlanVersion(input, existing: [cur], source: mode.source, parent: cur))
        }
        return .ok(PlanImportPreview(input: input, source: mode.source, warnings: warnings, diff: diff))
    }
}

/// 示例计划：从本周一开始的 12 周
public func samplePlanText(mode: PlanImportMode, today: LocalDate) -> String {
    let monday = today.adding(days: -((today.weekday + 6) % 7))
    switch mode {
    case .json:
        guard let url = Bundle.module.url(forResource: "samplePlan", withExtension: "json"),
              let data = try? Data(contentsOf: url), let json = try? JSONValue.parse(data) else { return "" }
        let plan = json.with("start_date", .string(monday.description)).with("end_date", .string(monday.adding(days: 83).description))
        return encodeJSONString(plan, pretty: true)
    case .naturalLanguage:
        return """
        12周恢复计划
        开始日期：\(monday)
        周一三五 07:30 力量训练：
        深蹲3组10次
        臀桥3组12次
        Dead Bug 3组8次
        平板支撑3组30秒
        周二四训练：
        俯卧撑3组8次
        靠墙静蹲3组45秒
        每日习惯：
        散步20分钟
        22:30准备睡觉
        """
    }
}

extension JSONValue {
    /// 返回修改了某个键的对象副本
    public func with(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(var o) = self else { return self }
        o[key] = value
        return .object(o)
    }
}
