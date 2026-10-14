import Foundation

/// `*_at` 字段为 ISO 8601 字符串（与原型 `toISOString()` 一致，如 2026-06-01T08:00:00.000Z）。
///
/// 模型里保持字符串而不是 `Date`，以便与网页原型、AI 交换的 JSON 逐字一致。
public enum Timestamp {
    /// 生成 ISO 8601 UTC 时间戳，带毫秒
    public static func string(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    public static func now() -> String { string(from: Date()) }

    /// 解析 ISO 8601：支持有无毫秒、有无时区（无时区时按 `localTimeZone` 解释，与 JS `new Date()` 一致）
    public static func parse(_ s: String, localTimeZone: TimeZone = .current) -> Date? {
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            let f = ISO8601DateFormatter()
            f.formatOptions = opts
            if let d = f.date(from: s) { return d }
        }
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = localTimeZone
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// 时间戳对应的本地日期；无法解析时退回前 10 个字符
    public static func localDate(of s: String, in timeZone: TimeZone = .current) -> LocalDate? {
        if let d = parse(s, localTimeZone: timeZone) { return LocalDate(d, in: timeZone) }
        return LocalDate(String(s.prefix(10)))
    }
}

/// 新 id：小写 UUID（与 `crypto.randomUUID()` 格式一致）
public func newId() -> String { UUID().uuidString.lowercased() }

/// 与 JS `String(number)` 一致：整数不带小数点（70 → "70"，12.5 → "12.5"）
func jsNumber(_ v: Double) -> String {
    if v.isFinite, v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
    return String(v)
}

/// JS `Math.round`（.5 向正无穷取整）
func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
