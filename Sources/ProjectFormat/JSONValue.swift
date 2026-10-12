import Foundation

/// JSON 값 한 덩이 — 프로젝트가 뜻을 정하는 칸(IA 의 크롬 구성 · 내비 항목 · 안 파일의 Style 값)과 엔진 명령의 JSON 결과를 싣는다.
/// 미리보기 호스트의 말(`PreviewProtocol` — 조절판 값 `patch` · 서술의 기본값)도 같은 한 벌이다. 키 차례는 쓸 때 정렬한다(같은 입력 = 같은 글자 — diff 가 뜻만 보인다).
/// 정수로 떨어지는 수는 정수로 쓴다(`18` — `18.0` 이 아니다) — 저장 파일의 바이트가 이 규칙에 기댄다.
/// **수의 정본 꼴** — Double 로 정확히 담기는 수(소수 · 크기 2^53 이하의 정수)는 `number` · 그보다 큰 정수는 `integer`(Int64 — 시각 ns · 큰 id 가
/// Double 로 깎이지 않게). 읽개와 `int(_:)` · 정수 리터럴이 이 꼴로 고른다 — 같은 수가 두 꼴로 서지 않는다.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    /// 크기가 2^53 을 넘는 정수(정본 꼴 — 그 아래는 `number`).
    case integer(Int64)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self), i.magnitude > Self.exactIntegerLimit { self = .integer(i) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .integer(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Double 로 정확히 담기는 정수의 한계(2^53).
    static let exactIntegerLimit: UInt64 = 1 << 53

    /// 정수 하나 — 정본 꼴로(크기 2^53 이하는 `number` · 넘으면 `integer`).
    public static func int(_ v: Int64) -> JSONValue { v.magnitude > exactIntegerLimit ? .integer(v) : .number(Double(v)) }

    /// 정수로 읽은 값 — `integer` 이거나 소수부 없는 `number`(Int64 에 담길 때) · 그 밖은 nil.
    public var integerValue: Int64? {
        switch self {
        case .integer(let i): i
        case .number(let n): n == n.rounded() ? Int64(exactly: n) : nil
        default: nil
        }
    }

    /// 수로 읽은 값 — `number` · `integer`(Double 로 옮기면 깎일 수 있다) · 그 밖은 nil.
    public var numberValue: Double? {
        switch self {
        case .number(let n): n
        case .integer(let i): Double(i)
        default: nil
        }
    }

    /// 사람이 읽는 들여쓴 글자(키 정렬 · 슬래시 그대로).
    public func text(pretty: Bool = true) -> String {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        guard let d = try? e.encode(self) else { return "null" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Codable 값 → JSON 값(매니페스트 · 프로젝트의 타입을 그대로 싣을 때).
    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Codable 값 → JSON 객체(객체로 인코드되는 값 — 화면 Style 하나). 객체가 아니면 던진다.
    public static func dictionary<T: Encodable>(from value: T) throws -> [String: JSONValue] {
        guard case .object(let o) = try from(value) else { throw JSONValueError.notObject(String(describing: T.self)) }
        return o
    }

    /// JSON 값 → Codable 값 — 프로젝트가 뜻을 정하는 칸(IA 의 크롬 구성 · 안 파일의 Style 값)을 프로젝트의 타입으로 읽는다(칸의 꼴은 그 타입의 Codable 이 정한다).
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

public enum JSONValueError: Error, CustomStringConvertible {
    case notObject(String)
    public var description: String {
        switch self { case .notObject(let t): return "\(t) 가 JSON 객체로 인코드되지 않았다" }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(Int64(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
}
