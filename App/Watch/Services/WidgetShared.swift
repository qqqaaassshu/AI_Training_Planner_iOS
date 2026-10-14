import Foundation

/// 手表 App 与表盘复杂功能（Widget 扩展）共享的数据位置
enum WidgetShared {
    /// App Group 名称写在两个 target 的 Info.plist（ATPAppGroup），由 project.yml 按标识前缀生成
    static var appGroup: String? { Bundle.main.object(forInfoDictionaryKey: "ATPAppGroup") as? String }

    /// 没有 App Group 能力（例如免费账号）时为 nil，表盘显示为空
    static var snapshotURL: URL? {
        guard let group = appGroup else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("complication.json")
    }
}
