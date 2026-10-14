import Foundation

/// 手表 App 与表盘复杂功能（Widget 扩展）共享的数据位置
enum WidgetShared {
    /// 需要在两个 target 的 App Groups 能力里都加上这个组（真机安装时换成自己的标识）
    static let appGroup = "group.com.example.aitrainingplanner"

    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("complication.json")
    }
}
