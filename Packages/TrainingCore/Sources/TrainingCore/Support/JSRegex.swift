import Foundation

/// 让 Swift Regex 的行为与原型里的 JS 正则一致：`\d`、`\w`、`\b` 只按 ASCII 判断
///（Swift 默认按 Unicode，汉字会被当成 `\w`，导致 “30准备” 之间没有词边界）。
func jsRegex(_ pattern: String) -> Regex<AnyRegexOutput> {
    // 这些模式都是代码里的常量，写错应在测试中立即暴露
    // swiftlint:disable:next force_try
    let r = try! Regex(pattern)
    return r.asciiOnlyDigits().asciiOnlyWordCharacters().wordBoundaryKind(.simple)
}

extension String {
    /// 第 n 个捕获组（没有参与匹配时为 nil）
    func firstMatchGroups(_ regex: Regex<AnyRegexOutput>) -> [String?]? {
        guard let m = try? regex.firstMatch(in: self) else { return nil }
        return (0..<m.output.count).map { i in m.output[i].substring.map(String.init) }
    }

    func matches(_ regex: Regex<AnyRegexOutput>) -> Bool {
        (try? regex.firstMatch(in: self)) != nil
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
