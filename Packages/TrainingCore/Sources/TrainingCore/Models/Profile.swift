import Foundation

public enum Sex: String, Codable, Hashable, Sendable, CaseIterable {
    case male, female, other
}

public enum Experience: String, Codable, Hashable, Sendable, CaseIterable {
    case none, beginner, intermediate, advanced
}

/// 个人档案：写入 AI 系统提示词，帮助生成个性化建议
public struct UserProfile: Codable, Hashable, Sendable {
    /// 年龄段，如 "30-39"
    public var ageRange: String?
    public var sex: Sex?
    public var heightCm: Double?
    public var weightKg: Double?
    public var experience: Experience?
    /// 伤病与身体限制
    public var injuries: String?
    /// 可训练的时间
    public var availableTime: String?
    /// 可用器械
    public var equipment: String?
    public var goals: String?
    /// 其他偏好（喜欢/不喜欢的动作等）
    public var preferences: String?
    public var updatedAt: String?

    public init(ageRange: String? = nil, sex: Sex? = nil, heightCm: Double? = nil, weightKg: Double? = nil,
                experience: Experience? = nil, injuries: String? = nil, availableTime: String? = nil,
                equipment: String? = nil, goals: String? = nil, preferences: String? = nil, updatedAt: String? = nil) {
        self.ageRange = ageRange
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.experience = experience
        self.injuries = injuries
        self.availableTime = availableTime
        self.equipment = equipment
        self.goals = goals
        self.preferences = preferences
        self.updatedAt = updatedAt
    }

    /// 按字段取值（枚举取原始值）
    public subscript(field: ProfileField) -> ProfileValue? {
        switch field {
        case .ageRange: return ageRange.map(ProfileValue.string)
        case .sex: return sex.map { .string($0.rawValue) }
        case .heightCm: return heightCm.map(ProfileValue.number)
        case .weightKg: return weightKg.map(ProfileValue.number)
        case .experience: return experience.map { .string($0.rawValue) }
        case .injuries: return injuries.map(ProfileValue.string)
        case .availableTime: return availableTime.map(ProfileValue.string)
        case .equipment: return equipment.map(ProfileValue.string)
        case .goals: return goals.map(ProfileValue.string)
        case .preferences: return preferences.map(ProfileValue.string)
        }
    }

    enum CodingKeys: String, CodingKey {
        case sex, experience, injuries, equipment, goals, preferences
        case ageRange = "age_range"
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case availableTime = "available_time"
        case updatedAt = "updated_at"
    }
}

/// 档案字段，顺序即显示与写入提示词的顺序
public enum ProfileField: String, Codable, Hashable, Sendable, CaseIterable {
    case ageRange = "age_range"
    case sex
    case heightCm = "height_cm"
    case weightKg = "weight_kg"
    case experience
    case injuries
    case availableTime = "available_time"
    case equipment
    case goals
    case preferences
}

/// 档案字段的值：字符串或数字
public enum ProfileValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        }
    }

    public var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return jsNumber(n)
        }
    }
}

/// 档案变更记录，用于让 AI 看到状态变化趋势
public struct ProfileChange: Codable, Hashable, Sendable {
    public var at: String
    public var field: ProfileField
    public var from: ProfileValue?
    public var to: ProfileValue?

    public init(at: String, field: ProfileField, from: ProfileValue? = nil, to: ProfileValue? = nil) {
        self.at = at
        self.field = field
        self.from = from
        self.to = to
    }
}
