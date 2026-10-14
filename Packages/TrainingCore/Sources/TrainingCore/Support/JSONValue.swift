import Foundation

/// 任意 JSON 值。用于校验外部输入（导入的计划、AI 回复）：
/// 先按原样解析，再逐字段检查并给出带路径的错误，而不是让 `Decodable` 在第一个错误处失败。
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var numberValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// 与 JS `Number.isInteger` 一致
    public var intValue: Int? {
        guard let n = numberValue, n.isFinite, n == n.rounded(), abs(n) < 1e15 else { return nil }
        return Int(n)
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// 把任意 Encodable 转成 JSONValue（测试与构造 AI 输入时使用）
    public init<T: Encodable>(encoding value: T) throws {
        self = try JSONValue.parse(JSONEncoder().encode(value))
    }

    /// 解码为具体模型
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "无法识别的 JSON 值") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if let i = intValue { try c.encode(i) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(stringLiteral v: String) { self = .string(v) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
}

/// 输出给 AI / 导出用的 JSON 编码：键排序（结果稳定，便于提示词缓存）、不转义斜杠
func makeJSONEncoder(pretty: Bool) -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
    return e
}

func encodeJSONString<T: Encodable>(_ value: T, pretty: Bool) -> String {
    guard let data = try? makeJSONEncoder(pretty: pretty).encode(value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
}
