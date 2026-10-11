import DesignTokens
import Foundation
import ProjectFormat

// Style 서술 — 안 파일(`<화면>/<안>.design.json`)의 `style` 칸 한 덩이를 **사전(`StyleValues` — 칸 이름 → JSON 값)** 으로 다루는 잣대.
// 어떤 칸이 있고 · 무슨 꼴이고 · 조절판의 어느 절에 무슨 이름으로 서는가를 프로젝트가 **서술**(`StyleSchema` — JSON 으로 오가는 값)로 낸다 —
// 프로젝트의 Swift 타입(화면마다의 `…Style`)은 엔진에 오지 않는다. 서술은 미리보기 호스트의 `hello`(`ScreenInfo.style` · `LayerInfo.style`)에 실리고,
// 엔진은 같은 값으로 안 파일을 재고 · 쓰임을 세고 · 조절판의 칸 · 절 · 레이블을 읽는다.
// 그래서 꼴은 호스트(프로젝트)와 엔진이 함께 무는 계약이다 — 레이블 생성 규칙도 한 벌(`StyleField.label`)이다.
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

/// 칸 종류 다섯 — 스칼라 셋(토큰 이름 ⟂ pt) · 색 역할 · 토글. JSON 으로는 평평한 낱말(`space` · `radius` · `type` · `color` · `bool`).
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
            guard let k = ScaleKind(rawValue: word) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "모르는 칸 종류 — \(word)"))
            }
            self = .scalar(k)
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

/// 조절판의 칸 하나 — 파일 키 · 종류 · 절 · 레이블.
public struct StyleField: Identifiable, Equatable, Sendable {
    public let name: String
    public let kind: FieldKind
    public let element: StyleElement
    /// 조절판 칸의 레이블 — 생성 규칙(`label(for:element:kind:)`)이 낸다(요소 앞머리를 뗀 나머지 · 재는 낱말은 한국어). 파일 키는 `name`(툴팁).
    public let label: String
    public var id: String { name }
    public init(name: String, kind: FieldKind, element: StyleElement, label: String? = nil) {
        self.name = name; self.kind = kind; self.element = element
        self.label = label ?? Self.label(for: name, element: element, kind: kind)
    }

    /// 칸 목록 — (파일 키 · 종류)를 선언 차례대로 받아 절 · 레이블을 단다. 한 절 안에서 레이블이 겹치면(규칙이 두 키를 같은 말로 옮겼다 —
    /// `on` ⟂ `trayOn`) 그 칸들은 키를 그대로 쓴다 — 칸을 헷갈리지 않게.
    public static func list(_ raw: [(name: String, kind: FieldKind)], elements: [StyleElement]) -> [StyleField] {
        let fields = raw.map { StyleField(name: $0.name, kind: $0.kind, element: StyleElement.of(field: $0.name, in: elements)) }
        var seen: [String: Int] = [:]
        for f in fields { seen["\(f.element.id)|\(f.label)", default: 0] += 1 }
        return fields.map { f in
            seen["\(f.element.id)|\(f.label)", default: 0] > 1 ? StyleField(name: f.name, kind: f.kind, element: f.element, label: f.name) : f
        }
    }

    // MARK: 레이블 — 생성 규칙(조절판 칸 이름 — 칸 하나하나 손으로 고치지 않고 규칙으로 짓는다)
    //
    // ① **요소 앞머리를 뗀다** — 칸은 이미 그 요소의 절 안에 선다(「화분」 절의 `potLabelSize` → `LabelSize`). 절 이름을 칸마다 되풀이하지 않는다(HIG · 중복 제거).
    //    앞머리 뒤가 대문자로 이어질 때만 뗀다(`rootsBottom` 은 `root` + `sBottom` 이 아니다). 색 역할 절은 꼬리 `Color` 를 뗀다.
    // ② **camelCase 를 낱말로** 가르고 ③ **재는 낱말은 한국어로**(아래 사전 — 뜻이 하나로 정해지는 낱말만) · 사전에 없는 낱말(화면 고유 이름 —
    //    `sprout` · `trellis` · `mulch` …)은 코드 낱말 그대로 둔다(억지 번역이 틀린 뜻을 심는 것보다 낫다).
    // ④ 여백·간격 짝은 한국어 차례로 — `PadV` 세로 여백 · `PadH` 가로 여백 · `PadTop` 위 여백 · `GapRow` 행 간격 · 끝의 `Top`/`Bottom`(간격 값) = 위/아래 간격 · 끝의 `On`(켬끔) = 켜기.
    // 원래 키는 조절판 칸의 툴팁에 선다(파일 · grep 용).

    static let glossary: [String: String] = [
        "size": "크기", "gap": "간격", "pad": "여백", "radius": "반경", "height": "높이", "width": "폭", "color": "색",
        "title": "제목", "row": "행", "rows": "행", "label": "라벨", "labels": "라벨", "line": "선", "head": "머리", "sub": "보조", "card": "카드",
        "gauge": "게이지", "status": "상태", "badge": "배지", "item": "항목", "items": "항목", "chip": "칩", "num": "숫자",
        "indent": "들여쓰기", "min": "최소", "max": "최대", "value": "값", "group": "묶음", "text": "글", "bg": "바탕",
        "icon": "아이콘", "name": "이름", "date": "날짜", "amount": "금액", "btn": "단추", "body": "본문", "divider": "구분선",
        "dot": "점", "bar": "막대", "shadow": "그림자", "legend": "범례", "tick": "눈금", "cell": "칸", "count": "개수",
        "total": "합계", "arrow": "화살표", "avatar": "아바타", "glyph": "기호", "tab": "탭", "glass": "유리",
        "left": "왼쪽", "right": "오른쪽", "top": "위", "bottom": "아래", "side": "옆", "inset": "안쪽", "fade": "페이드",
        "action": "액션", "content": "콘텐츠", "empty": "빈", "col": "열", "angle": "각도", "length": "길이", "density": "밀도",
    ]

    static func strippedRemainder(_ name: String, element: StyleElement) -> String {
        if element.id == "color" { return name.hasSuffix("Color") && name.count > 5 ? String(name.dropLast(5)) : name }
        guard name.hasPrefix(element.id), name.count > element.id.count else { return name }
        let rest = name.dropFirst(element.id.count)
        return rest.first?.isUppercase == true ? String(rest) : name
    }

    /// camelCase → 낱말(소문자) — `chartTrellisBtnRadius` → chart · trellis · btn · radius · `PadV` → pad · v.
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in s {
            if ch.isUppercase, !cur.isEmpty { out.append(cur); cur = "" }
            cur.append(ch)
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.lowercased() }
    }

    public static func label(for name: String, element: StyleElement, kind: FieldKind) -> String {
        var w = words(strippedRemainder(name, element: element))
        guard !w.isEmpty else { return name }
        var tail: [String] = []
        // ④ 짝 — 끝에서부터
        func ends(_ xs: [String]) -> Bool { w.count >= xs.count && Array(w.suffix(xs.count)) == xs }
        let pairs: [([String], String)] = [
            (["pad", "v"], "세로 여백"), (["pad", "h"], "가로 여백"), (["pad", "top"], "위 여백"), (["pad", "bottom"], "아래 여백"),
            (["pad", "side"], "옆 여백"), (["gap", "row"], "행 간격"), (["gap", "col"], "열 간격"),
        ]
        if let hit = pairs.first(where: { ends($0.0) }) {
            w.removeLast(hit.0.count); tail = [hit.1]
        } else if case .scalar(.space) = kind, let last = w.last, last == "top" || last == "bottom" {
            w.removeLast(); tail = [last == "top" ? "위 간격" : "아래 간격"]
        } else if kind == .bool, w.last == "on" {
            w.removeLast(); tail = ["켜기"]
        }
        let head = w.map { glossary[$0] ?? $0 }
        let out = (head + tail).joined(separator: " ")
        return out.isEmpty ? name : out
    }
}

/// 화면 하나(또는 화면 위에 얹는 층 하나)의 Style **서술** — 프로젝트가 내는 데이터. JSON 꼴:
/// `{"screen":"…","elements":[{"id","label","snapPrefix"}],"fields":[{"name","kind","element","label"}],"defaults":{…}}`.
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
    private struct WireField: Codable { var name: String; var kind: FieldKind; var element: String; var label: String }
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
