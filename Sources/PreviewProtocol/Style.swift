import DesignTokens
import Foundation
import ProjectFormat

// Style 서술 — 안 파일(`<화면>/<안>.design.json`)의 `style` 칸 한 덩이를 **사전(`StyleValues` — 칸 이름 → JSON 값)** 으로 다루는 잣대.
// 어떤 칸이 있고 · 무슨 꼴이고 · 조절판의 어느 절에 무슨 이름으로 서는가를 프로젝트가 **서술**(`StyleSchema` — JSON 으로 오가는 값)로 낸다 —
// 프로젝트의 Swift 타입(화면마다의 `…Style`)은 엔진에 오지 않는다. 서술은 미리보기 호스트의 `hello`(`ScreenInfo.style` · `LayerInfo.style`)에 실리고,
// 엔진은 같은 값으로 안 파일을 재고 · 쓰임을 세고 · 조절판의 칸 · 절을 읽는다. 칸의 이름(`StyleField.label`)은 선택이다 — 호스트가 지은 이름이 있으면
// 그것 · 없으면 엔진이 제 규칙으로 짓는다(사람 말 · 낱말 사전은 엔진 UI 의 몫이라 이 계약에 없다).
// 서술은 **데이터**다(클로저 · 타입을 넘기지 않는다). 값의 저장 꼴은 칸 종류가 정한다:
//   간격 · 반경 · 글자 크기 = `{"token":"md"}` ⟂ `{"pt":18}` · 색 = 역할 이름(`"inkSoft"` · 리터럴 `"#rrggbb"`) · 토글 = `true` — `patch` 의 값도 이 꼴이다.
// 그 값을 프로젝트의 Style 타입에 넣는 손(`StyleEdit` — Codable 왕복)도 한 벌이다 — 호스트가 `patch` 를 받는 자리와 엔진의 조절판이 같은 손을 부른다.

/// Style 값 사전 — 칸 이름 → 그 칸의 JSON 값(`style` 칸 한 덩이를 읽은 그대로).
public typealias StyleValues = [String: JSONValue]

extension JSONValue {
    /// 스칼라 칸(간격 · 반경 · 글자 크기)의 pt 직접 값 — `{"pt":p}`.
    public static func pt(_ p: Double) -> JSONValue { .object(["pt": .number(p)]) }
    /// 스칼라 칸의 토큰 이름 — `{"token":n}`.
    public static func token(_ n: String) -> JSONValue { .object(["token": .string(n)]) }
    /// 스칼라 칸 값의 토큰 이름 — `{"token":n}` 이면 n · 아니면 nil(토큰이 있으면 pt 보다 먼저다 — `normalize` 와 같은 규칙).
    public var scalarToken: String? {
        guard case .object(let o) = self, case .string(let t)? = o["token"] else { return nil }
        return t
    }
    /// 스칼라 칸 값의 pt 직접 값 — `{"pt":p}` 이면 p · 토큰 값이거나 스칼라 꼴이 아니면 nil.
    public var scalarPt: Double? {
        guard case .object(let o) = self, o["token"] == nil, case .number(let p)? = o["pt"] else { return nil }
        return p
    }
}

/// 칸 종류 — 스칼라(토큰 이름 ⟂ pt · 종류는 `ScaleKind` — 열린 꼴) · 색 역할 · 토글. JSON 으로는 평평한 낱말(`space` · `radius` · `type` · `color` · `bool`) ·
/// `color` · `bool` 밖의 낱말은 스칼라 종류로 읽는다(새 토큰 종류가 와도 서술이 읽힌다 — 스칼라 밖의 새 칸 종류는 프로토콜 판을 올린다).
public enum FieldKind: Hashable, Sendable {
    case scalar(ScaleKind)
    case color
    case bool

    /// 저장 꼴을 잰다 — 값 하나를 이 종류의 꼴로 다시 쓴다(스칼라의 남는 열쇠는 떨어진다 · 꼴이 아니면 던진다).
    /// 프로젝트의 값 타입이 읽고 쓰는 꼴과 같다(스칼라: `token` 이 있으면 글자 · 없으면 `pt` 숫자 · 색: 글자 · 토글: 참거짓).
    func normalized(_ v: JSONValue) -> JSONValue? {
        switch (self, v) {
        case (.scalar, .object(let o)):
            if let t = o["token"] { if case .string = t { return .object(["token": t]) } else { return nil } }
            if let p = o["pt"], case .number = p { return .object(["pt": p]) }
            return nil
        case (.color, .string): return v
        case (.bool, .bool): return v
        default: return nil
        }
    }
}

extension FieldKind: Codable {
    public init(from decoder: Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        switch word {
        case "color": self = .color
        case "bool": self = .bool
        default:
            guard !word.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "칸 종류가 비었다"))
            }
            self = .scalar(ScaleKind(rawValue: word))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .scalar(let k): try c.encode(k.rawValue)
        case .color: try c.encode("color")
        case .bool: try c.encode("bool")
        }
    }
}

/// 조절판의 절 하나 — 칸 이름 앞머리 ↔ 요소 표식(`snapID`) 앞머리 · `…Color` 칸은 색 역할 절(`color`).
public struct StyleElement: Identifiable, Hashable, Codable, Sendable {
    public let id: String        // 칸 이름 앞머리
    public let label: String
    public let snapPrefix: String
    public init(id: String, label: String, snapPrefix: String) { self.id = id; self.label = label; self.snapPrefix = snapPrefix }

    /// 칸 이름 → 요소. `…Color` 는 색 역할(`color` 요소), 그 밖은 가장 긴 앞머리 일치 · 없으면 첫 요소.
    public static func of(field name: String, in all: [StyleElement]) -> StyleElement {
        if name.hasSuffix("Color"), let c = all.first(where: { $0.id == "color" }) { return c }
        let hit = all.filter { $0.id != "color" && name.hasPrefix($0.id) }.max { $0.id.count < $1.id.count }
        return hit ?? all[0]
    }
    /// snapID → 요소(가장 긴 snapPrefix 일치).
    public static func of(snapID id: String, in all: [StyleElement]) -> StyleElement? {
        all.filter { !$0.snapPrefix.isEmpty && id.hasPrefix($0.snapPrefix) }.max { $0.snapPrefix.count < $1.snapPrefix.count }
    }
}

/// 조절판의 칸 하나 — 파일 키 · 종류 · 절 · 이름(선택).
public struct StyleField: Identifiable, Equatable, Sendable {
    public let name: String
    public let kind: FieldKind
    public let element: StyleElement
    /// 조절판 칸의 이름 — 호스트(프로젝트)가 지은 것 · nil 이면 엔진이 제 규칙으로 짓는다. 파일 키는 `name`(툴팁).
    public let label: String?
    public var id: String { name }
    public init(name: String, kind: FieldKind, element: StyleElement, label: String? = nil) {
        self.name = name; self.kind = kind; self.element = element; self.label = label
    }

    /// 칸 목록 — (파일 키 · 종류)를 선언 차례대로 받아 절을 단다(절 = `StyleElement.of(field:in:)` · 이름은 비운다 — 엔진이 짓는다).
    public static func list(_ raw: [(name: String, kind: FieldKind)], elements: [StyleElement]) -> [StyleField] {
        raw.map { StyleField(name: $0.name, kind: $0.kind, element: StyleElement.of(field: $0.name, in: elements)) }
    }
}

/// 화면 하나(또는 화면 위에 얹는 층 하나)의 Style **서술** — 프로젝트가 내는 데이터. JSON 꼴:
/// `{"screen":"…","elements":[{"id","label","snapPrefix"}],"fields":[{"name","kind","element","label"?}],"defaults":{…}}`(칸의 `label` 은 선택).
/// `defaults` 는 화면의 기본값(파일에 없는 칸을 채운다 — 칸이 늘어도 옛 안 파일이 읽힌다).
public struct StyleSchema: Equatable, Sendable {
    public let screen: String
    public let elements: [StyleElement]
    public let fields: [StyleField]
    public let defaults: StyleValues
    public init(screen: String, elements: [StyleElement], fields: [StyleField], defaults: StyleValues) {
        self.screen = screen; self.elements = elements; self.fields = fields; self.defaults = defaults
    }

    /// 값 한 덩이를 서술로 잰다 — 없는 칸은 기본값으로 채우고 · 칸마다 꼴을 재 다시 쓰고(스칼라의 남는 열쇠는 떨어진다) · 서술에 없는 칸은 뺀다.
    /// 프로젝트의 Style 타입이 읽고 다시 쓴 것과 같은 값이다.
    public func normalize(_ style: StyleValues) throws -> StyleValues {
        var out: StyleValues = [:]
        for f in fields {
            guard let v = style[f.name] ?? defaults[f.name] else { throw StyleSchemaError.missing(screen, f.name) }
            guard let n = f.kind.normalized(v) else { throw StyleSchemaError.badValue(screen, f.name, f.kind, v) }
            out[f.name] = n
        }
        return out
    }
}

extension StyleSchema: Codable {
    private struct WireField: Codable { var name: String; var kind: FieldKind; var element: String; var label: String? }
    private enum Keys: String, CodingKey { case screen, elements, fields, defaults }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        screen = try c.decode(String.self, forKey: .screen)
        elements = try c.decode([StyleElement].self, forKey: .elements)
        let byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        fields = try c.decode([WireField].self, forKey: .fields).map { w in
            guard let e = byID[w.element] else {
                throw DecodingError.dataCorruptedError(forKey: .fields, in: c, debugDescription: "칸 \(w.name) 의 절 \(w.element) 이 elements 에 없다")
            }
            return StyleField(name: w.name, kind: w.kind, element: e, label: w.label)
        }
        defaults = try c.decode(StyleValues.self, forKey: .defaults)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(screen, forKey: .screen)
        try c.encode(elements, forKey: .elements)
        try c.encode(fields.map { WireField(name: $0.name, kind: $0.kind, element: $0.element.id, label: $0.label) }, forKey: .fields)
        try c.encode(defaults, forKey: .defaults)
    }
}

/// 칸 하나를 바꾼 새 값 — Codable 왕복(JSON 사전의 키 하나를 갈아 끼우고 다시 디코드). 없는 이름이면 던진다.
/// 프로젝트의 Style 타입(객체로 인코드되는 값)에 그대로 쓴다 — 필드마다 KeyPath 표를 손으로 쓰지 않는다.
public enum StyleEdit {
    public static func setting<S: Codable, V: Encodable>(_ style: S, _ name: String, to newValue: V) throws -> S {
        var dict = try JSONValue.dictionary(from: style)
        guard dict[name] != nil else { throw StyleEditError.noField(name) }
        dict[name] = try JSONValue.from(newValue)
        return try JSONValue.object(dict).decode(S.self)
    }
}

public enum StyleEditError: Error, CustomStringConvertible {
    case noField(String)
    public var description: String {
        switch self { case .noField(let n): return "없는 필드: \(n)" }
    }
}

public enum StyleSchemaError: Error, CustomStringConvertible {
    case missing(String, String)
    case badValue(String, String, FieldKind, JSONValue)
    public var description: String {
        switch self {
        case .missing(let s, let f): return "\(s) — 칸 \(f) 의 값도 기본값도 없다"
        case .badValue(let s, let f, let k, let v): return "\(s) — 칸 \(f) 의 값이 \(k) 꼴이 아니다: \(v.text(pretty: false))"
        }
    }
}
