import Foundation

// 对应原型 utils/profile.ts

extension Experience {
    public var label: String {
        switch self {
        case .none: return "几乎没有训练经验"
        case .beginner: return "入门（偶尔训练）"
        case .intermediate: return "有一定基础（规律训练半年以上）"
        case .advanced: return "经验丰富"
        }
    }
}

extension Sex {
    public var label: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .other: return "不便透露"
        }
    }
}

extension ProfileField {
    public var label: String {
        switch self {
        case .ageRange: return "年龄段"
        case .sex: return "性别"
        case .heightCm: return "身高"
        case .weightKg: return "体重"
        case .experience: return "训练经验"
        case .injuries: return "伤病与身体限制"
        case .availableTime: return "可训练时间"
        case .equipment: return "可用器械"
        case .goals: return "目标"
        case .preferences: return "偏好与其他"
        }
    }

    public var unit: String? {
        switch self {
        case .heightCm: return "cm"
        case .weightKg: return "kg"
        default: return nil
        }
    }
}

/// 空白字符串视为未填写
private func normalized(_ v: ProfileValue?) -> ProfileValue? {
    if case .string(let s) = v { let t = s.trimmed; return t.isEmpty ? nil : .string(t) }
    return v
}

/// 比较前后档案，生成变更记录
public func diffProfile(before: UserProfile, after: UserProfile, at: String) -> [ProfileChange] {
    ProfileField.allCases.compactMap { field in
        let from = normalized(before[field]), to = normalized(after[field])
        return from == to ? nil : ProfileChange(at: at, field: field, from: from, to: to)
    }
}

public func displayValue(_ field: ProfileField, _ v: ProfileValue?) -> String {
    guard let v, v.text != "" else { return "（空）" }
    switch field {
    case .experience: return Experience(rawValue: v.text)?.label ?? v.text
    case .sex: return Sex(rawValue: v.text)?.label ?? v.text
    default: return field.unit.map { "\(v.text)\($0)" } ?? v.text
    }
}

extension UserProfile {
    public var isEmpty: Bool { ProfileField.allCases.allSatisfy { normalized(self[$0]) == nil } }
}

/// 写入系统提示词的档案文本；未填写的项省略
public func formatProfileForPrompt(_ p: UserProfile) -> String {
    let lines = ProfileField.allCases.compactMap { f in normalized(p[f]).map { "- \(f.label)：\(displayValue(f, $0))" } }
    return lines.isEmpty ? "（用户未填写档案，请按保守的入门水平安排，并在 findings 中提醒补充档案）" : lines.joined(separator: "\n")
}
