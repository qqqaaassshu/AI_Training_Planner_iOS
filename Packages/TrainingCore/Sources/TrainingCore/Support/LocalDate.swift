import Foundation

/// 本地日期 YYYY-MM-DD（按计划的 timezone 解释，不含时刻）。
///
/// 对应原型 `utils/date.ts`。日期运算是纯算术（不经过 `Calendar`），
/// 所以不受夏令时和设备时区影响；只有“现在是哪一天”需要指定时区。
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// 只接受有效的 YYYY-MM-DD（拒绝 2026-02-30、2026-6-1）
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func num(_ range: Range<Int>) -> Int? {
            var n = 0
            for i in range {
                let b = bytes[i]
                guard b >= 48, b <= 57 else { return nil }
                n = n * 10 + Int(b - 48)
            }
            return n
        }
        guard let y = num(0..<4), let m = num(5..<7), let d = num(8..<10) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= LocalDate.daysInMonth(year, month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// 某个时刻在指定时区下的日期（不要用 UTC 日期，否则 UTC+8 早上 8 点前会记到前一天）
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public static func today(now: Date = Date(), in timeZone: TimeZone = .current) -> LocalDate {
        LocalDate(now, in: timeZone)
    }

    public var description: String {
        let y = String(year).leftPadded(to: 4)
        let m = String(month).leftPadded(to: 2)
        let d = String(day).leftPadded(to: 2)
        return "\(y)-\(m)-\(d)"
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: 运算

    public func adding(days n: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + n)
    }

    /// other - self 的天数
    public func days(to other: LocalDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// 0 = 周日 … 6 = 周六（与 JS `getDay()` 一致；Swift `Calendar` 的 weekday 是 1 = 周日）
    public var weekday: Int {
        let w = (daysSinceEpoch + 4) % 7 // 1970-01-01 是周四
        return w < 0 ? w + 7 : w
    }

    /// 该日期在指定时区的某个时刻（HH:mm）。夏令时跳过的时刻由系统顺延。
    public func date(atHour hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    // MARK: 内部

    private static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Howard Hinnant 的 days_from_civil
    var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    init(daysSinceEpoch z0: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = LocalDate(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "无效日期：\(s)，应为 YYYY-MM-DD")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// 日期区间（含两端）
public struct DateRange: Codable, Hashable, Sendable {
    public var from: LocalDate
    public var to: LocalDate
    public init(from: LocalDate, to: LocalDate) {
        self.from = from
        self.to = to
    }
    public func contains(_ d: LocalDate) -> Bool { d >= from && d <= to }
}

extension String {
    func leftPadded(to n: Int, with ch: Character = "0") -> String {
        count >= n ? self : String(repeating: ch, count: n - count) + self
    }
}

/// 120 → "2分钟"，45 → "45秒"，90 → "1分30秒"
public func formatDuration(_ sec: Int) -> String {
    if sec < 60 { return "\(sec)秒" }
    let m = sec / 60, s = sec % 60
    return s != 0 ? "\(m)分\(s)秒" : "\(m)分钟"
}
