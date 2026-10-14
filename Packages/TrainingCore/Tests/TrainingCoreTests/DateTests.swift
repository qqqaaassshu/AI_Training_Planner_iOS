import Foundation
import Testing
@testable import TrainingCore

@Suite("date") struct DateTests {
    @Test("today 使用本地日期而非 UTC") func todayIsLocal() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        // 本地 2026-06-16 07:30 = UTC 前一天 23:30
        let t = Timestamp.parse("2026-06-15T23:30:00Z")!
        #expect(LocalDate.today(now: t, in: shanghai) == d("2026-06-16"))
        #expect(LocalDate.today(now: Timestamp.parse("2026-06-15T16:01:00Z")!, in: shanghai) == d("2026-06-16"))
        #expect(LocalDate.today(now: Timestamp.parse("2026-06-16T15:59:00Z")!, in: shanghai) == d("2026-06-16"))
    }

    @Test("addDays 跨月跨年") func addDays() {
        #expect(d("2026-01-31").adding(days: 1).description == "2026-02-01")
        #expect(d("2026-12-31").adding(days: 1).description == "2027-01-01")
        #expect(d("2026-03-01").adding(days: -1).description == "2026-02-28")
        #expect(d("2028-03-01").adding(days: -1).description == "2028-02-29")
    }

    @Test("daysBetween / weekday") func daysAndWeekday() {
        #expect(d("2026-06-15").days(to: d("2026-06-22")) == 7)
        #expect(d("2026-06-15").weekday == 1) // 周一
        #expect(d("2026-06-21").weekday == 0) // 周日
        #expect(d("1969-12-31").weekday == 3)
    }

    @Test("拒绝无效日期") func invalidDates() {
        #expect(LocalDate("2026-02-30") == nil)
        #expect(LocalDate("2026-6-1") == nil)
        #expect(LocalDate("2026-06-01") != nil)
    }

    @Test("Codable 为 YYYY-MM-DD 字符串") func codable() throws {
        let data = try JSONEncoder().encode([d("2026-06-01")])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-06-01"]"#)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-13-01"]"#.utf8)) }
    }

    @Test("时间戳：无时区按本地解释") func timestamps() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        #expect(Timestamp.localDate(of: "2026-06-14T20:00:00.000Z", in: shanghai) == d("2026-06-15"))
        #expect(Timestamp.localDate(of: "2026-06-14T20:00:00", in: shanghai) == d("2026-06-14"))
        #expect(Timestamp.string(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
    }

    @Test func duration() {
        #expect(formatDuration(45) == "45秒")
        #expect(formatDuration(60) == "1分钟")
        #expect(formatDuration(90) == "1分30秒")
    }
}
