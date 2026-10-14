import Foundation
import SwiftData

// SwiftData 只负责存储：每条数据以 TrainingCore 模型的 JSON 保存（与网页原型、AI、手表同步用的格式相同），
// 另存几个用于查询的字段。所有业务逻辑都在 TrainingCore。

@Model
final class PlanVersionEntity {
    @Attribute(.unique) var id: String
    var version: Int
    var payload: Data

    init(id: String, version: Int, payload: Data) {
        self.id = id
        self.version = version
        self.payload = payload
    }
}

@Model
final class RecordEntity {
    @Attribute(.unique) var id: String
    var taskId: String
    /// YYYY-MM-DD
    var date: String
    var payload: Data

    init(id: String, taskId: String, date: String, payload: Data) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.payload = payload
    }
}

@Model
final class WellnessEntity {
    /// YYYY-MM-DD，每天一条
    @Attribute(.unique) var date: String
    var payload: Data

    init(date: String, payload: Data) {
        self.date = date
        self.payload = payload
    }
}

@Model
final class AnalysisEntity {
    @Attribute(.unique) var id: String
    var payload: Data

    init(id: String, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

/// 训练中途的草稿，键为 “日期|任务 id”
@Model
final class DraftEntity {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}

/// 单例：当前版本、个人档案、AI 设置等
@Model
final class SettingsEntity {
    @Attribute(.unique) var key: String
    var currentPlanId: String?
    var profile: Data?
    var profileHistory: Data?
    var aiSettings: Data?

    init(key: String = SettingsEntity.mainKey) {
        self.key = key
    }

    static let mainKey = "main"
}

enum TrainingSchema {
    static let models: [any PersistentModel.Type] = [
        PlanVersionEntity.self, RecordEntity.self, WellnessEntity.self, AnalysisEntity.self, DraftEntity.self, SettingsEntity.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: config)
    }
}
