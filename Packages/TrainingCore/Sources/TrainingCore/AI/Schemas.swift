import Foundation

/// 计划与分析结果的 JSON Schema（与网页原型 src/app/schema/ 同步，写入提示词）
public enum Schemas {
    public static let plan: String = load("plan.schema")
    public static let aiAnalysis: String = load("ai-analysis.schema")

    /// 读取资源并压缩成单行 JSON（键排序，结果稳定，便于提示词缓存）
    private static func load(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let min = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        else { fatalError("缺少资源 \(name).json") }
        return String(decoding: min, as: UTF8.self)
    }
}
