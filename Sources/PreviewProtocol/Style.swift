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
// 문구(단추 글자 · 제목 — `StyleText`)는 칸 종류가 아니라 서술의 따로 선 목록(`texts`)이다 — 값은 같은 사전의 글자 하나(`"cta":"시작하기"`)이고
// 저장 꼴은 한 줄 라벨이다 — 줄바꿈은 공백 하나 · 앞뒤 공백을 걷고 · 최대 길이(글자 수 — 자소 묶음)로 자르고 · 빈 글이면 기본값(`defaults` 의 같은 칸).
// 닫힌 열거 `FieldKind` 를 늘리지 않는 까닭 — 갈래를 더하면 소비자의 전수 `switch` 가 깨진다(주 판). 목록은 기본값(빈 목록)이 있는 새 칸이다.
// 와이어에서 문구를 모르는 엔진(프로토콜 판 3 이하)은 판정이 막는다(판 4 호스트를 `hostNewer` 로 거절) — 문구 값이 조용히 빠진 채 그려지는 짝은 서지 않는다.
// 새 엔진 ⟂ 판 3 호스트는 서술에 문구가 없어 조절판에 문구 칸이 서지 않고, 실려 온 문구 값은 그 호스트가 서술 밖 칸으로 뺀다(화면은 기본 글).
// 그 값을 프로젝트의 Style 타입에 넣는 손(`StyleEdit` — Codable 왕복)도 한 벌이다 — 호스트가 `patch` 를 받는 자리와 엔진의 조절판이 같은 손을 부른다.
// 문구도 같은 손이다 — 프로젝트의 Style 타입이 문구를 `String` 칸으로 들면 앱 · 호스트의 화면 코드는 그 칸을 읽는다(사전으로 다루는 쪽은 `StyleSchema.text(_:in:)`).
// 자리(이미지 자리 — `StyleSlot`)도 문구와 같은 꼴의 따로 선 목록(`slots`)이다 — 화면 코드만 아는 이미지 자리를 호스트가 선언하고, 값은 같은 사전의 글자 하나:
// 빈 글(원래 이미지) ⟂ `<종류>:<이름>`(`isomodel:plant`). **서가** = 프로젝트가 정하는 폴더 — 참조의 이름은 그 폴더의 파일 이름(확장자 없이)이고 그 폴더를 정하고
// 이름을 파일로 푸는 것은 호스트 · 앱의 몫이다(이 SDK 는 값의 꼴만 약속한다). 그 값을 읽어 사진 대신 모델을 그리는 것도 호스트 · 앱의 화면 코드다(엔진은 경계 위에 덮어
// 그리지 않는다). 자리를 모르는 엔진(프로토콜 판 4 이하)은 판정이 막는다(판 5 호스트를 `hostNewer` 로 거절 — 자리를 선언하지 않은 호스트도 판 5 로 말한다).
// 효과(`StyleEffect` — 절의 `effects`)는 그 요소가 쓰는 시스템 효과(유리 · 머티리얼 · 모션 …)를 호스트가 사실로 선언하는 선택 칸이다 — 화면 코드만 아는 것을
// 데이터로 내어 엔진이 칸 이름으로 짐작하지 않게 한다. 어느 효과를 제 렌더가 그리지 못하는가는 엔진의 판단이다(이 SDK 는 낱말의 꼴만 약속한다).
// 효과를 모르는 엔진(프로토콜 판 6 이하)은 판정이 막고(판 7 호스트를 `hostNewer`) 판 6 호스트에게는 새 엔진이 절의 효과를 걷어 말한다(`v6to7`).

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

/// 요소가 쓰는 시스템 효과 하나 — 열린 낱말(`ScaleKind` 와 같은 꼴: 아는 낱말 `known` · 모르는 낱말도 글자 그대로 들고 그대로 쓴다).
/// **사실의 선언**이다 — 「이 요소는 이 효과로 그려진다」. 그 효과를 어느 렌더가 그리지 못하는가는 읽는 쪽(엔진)의 판단이라 이 낱말에 없다.
/// 닫힌 열거로 두지 않는 까닭 — 새 낱말이 와도 서술이 읽히고(옛 SDK 로 지은 엔진이 새 호스트의 서술을 거절하지 않는다) 갈래를 더해도 소비자의 전수 `switch` 가 깨지지 않는다.
public struct StyleEffect: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 유리 — 뒤를 굴절해 비추는 시스템 재질(`glassEffect` · 유리 단추 꼴 · 유리 묶음 그릇).
    public static let glass = StyleEffect(rawValue: "glass")
    /// 머티리얼 — 뒤를 흐려 비추는 시스템 재질(`Material` 칠 · 막대 재질).
    public static let material = StyleEffect(rawValue: "material")
    /// 흐림 — 요소 제 그림을 흐린다(`blur`).
    public static let blur = StyleEffect(rawValue: "blur")
    /// 그림자 — 요소 둘레의 그림자(`shadow`).
    public static let shadow = StyleEffect(rawValue: "shadow")
    /// 모션 — 사람의 손 없이 움직이는 모습(되풀이 애니메이션 · 단계 애니메이션).
    public static let motion = StyleEffect(rawValue: "motion")
    /// 이 SDK 가 아는 낱말 — 차례 그대로.
    public static let known: [StyleEffect] = [.glass, .material, .blur, .shadow, .motion]
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// 조절판의 절 하나 — 칸 이름 앞머리 ↔ 요소 표식(`snapID`) 앞머리 · `…Color` 칸은 색 역할 절(`color`).
/// `effects` 는 그 요소가 쓰는 시스템 효과의 선언(선택 · 빈 목록이 기본 · 선언 차례 그대로 · 빈 목록이면 줄에 쓰지 않는다) — 선언이 없는 요소는
/// 「효과를 말하지 않았다」이지 「효과가 없다」가 아니다(읽는 쪽이 제 규칙으로 짐작해도 된다).
public struct StyleElement: Identifiable, Hashable, Sendable {
    public let id: String        // 칸 이름 앞머리
    public let label: String
    public let snapPrefix: String
    /// 이 요소가 쓰는 시스템 효과 — 선언 차례 그대로(모르는 낱말도 보존).
    public let effects: [StyleEffect]
    public init(id: String, label: String, snapPrefix: String) { self.init(id: id, label: label, snapPrefix: snapPrefix, effects: []) }
    /// 효과를 선언한 절 — `StyleElement(id: "card", label: "카드", snapPrefix: "garden.card", effects: [.glass])`.
    public init(id: String, label: String, snapPrefix: String, effects: [StyleEffect]) {
        self.id = id; self.label = label; self.snapPrefix = snapPrefix; self.effects = effects
    }

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

extension StyleElement: Codable {
    private enum Keys: String, CodingKey { case id, label, snapPrefix, effects }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decode(String.self, forKey: .id), label: try c.decode(String.self, forKey: .label),
                  snapPrefix: try c.decode(String.self, forKey: .snapPrefix),
                  effects: try c.decodeIfPresent([StyleEffect].self, forKey: .effects) ?? [])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(snapPrefix, forKey: .snapPrefix)
        if !effects.isEmpty { try c.encode(effects, forKey: .effects) }
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

/// 조절판의 문구 칸 하나 — 화면의 글(단추 글자 · 제목)을 디자이너가 조절판에서 바꾸는 자리. 값은 Style 값 사전의 같은 이름 칸에 든 글자 하나 ·
/// 기본 글은 서술의 `defaults` 의 같은 칸(프로젝트의 Style 타입의 기본값 — 한 자리) · 이름(`label`)은 칸과 같이 선택(nil = 엔진이 짓는다).
/// 저장 꼴(`normalized(_:)`) — **한 줄 라벨**이다: 글 속 줄바꿈은 공백 하나로 · 앞뒤 공백을 자소 묶음 단위로 걷고 · `maxLength` 글자(자소 묶음 — 사람이 보는
/// 글자 수)에서 자르고 · 비면 nil(= 기본 글).
public struct StyleText: Identifiable, Equatable, Sendable {
    /// 파일 키 — Style 값 사전의 칸 이름(칸 `StyleField.name` 과 겹치지 않는다).
    public let name: String
    public let element: StyleElement
    /// 조절판 칸의 이름 — 호스트(프로젝트)가 지은 것 · nil 이면 엔진이 제 규칙으로 짓는다.
    public let label: String?
    /// 최대 길이(글자 수) — **1 이상**(1 미만은 서지 않는다: 코드로 지으면 `precondition` · 줄에서 읽으면 디코드 오류) · 넘으면 자른다.
    public let maxLength: Int
    public var id: String { name }
    /// 최대 길이를 적지 않은 문구의 길이 — 줄에 `maxLength` 가 없을 때도 이 값.
    public static let defaultMaxLength = 200
    public init(name: String, element: StyleElement, label: String? = nil, maxLength: Int = StyleText.defaultMaxLength) {
        precondition(maxLength >= 1, "문구 \(name) 의 최대 길이 \(maxLength) 이 1 보다 작다")
        self.name = name; self.element = element; self.label = label; self.maxLength = maxLength
    }

    /// 글 하나의 저장 꼴 — 줄바꿈이 낀 자리(그 둘레 공백 포함)는 공백 하나로 · 앞뒤 공백을 자소 묶음 단위로 걷고(공백에 붙은 결합 문자가 맨 앞에 남지 않는다) ·
    /// 최대 길이에서 자른다(자른 끝의 공백도 걷는다) · 남은 글이 비면 nil(기본 글을 쓰라는 뜻).
    public func normalized(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).map(Self.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        var t = Self.trimmed(Substring(line))
        if t.count > maxLength { t = Self.trimmed(t.prefix(maxLength)) }
        return t.isEmpty ? nil : String(t)
    }

    /// 앞뒤의 공백 자소 묶음을 걷는다(`Character.isWhitespace` — 공백에 결합 문자가 붙은 묶음도 공백이다).
    private static func trimmed(_ s: Substring) -> Substring {
        var s = s
        while let c = s.first, c.isWhitespace { s.removeFirst() }
        while let c = s.last, c.isWhitespace { s.removeLast() }
        return s
    }
}

/// 조절판의 자리 칸 하나 — 화면의 이미지 자리(사진 · 그림이 서는 곳)를 디자이너가 다른 것(모델)으로 바꾸는 자리. 값은 Style 값 사전의 같은 이름 칸에 든 글자 하나:
/// 빈 글 = 원래 이미지 ⟂ `<종류>:<이름>`(참조 — `Reference` · 종류는 `kinds` 의 낱말 · 이름은 서가(프로젝트가 정하는 폴더 · 풀이는 호스트 몫) 안의 파일 이름(확장자 없이 — 경로가 아니다)).
/// 기본 값은 서술의 `defaults` 의 같은 칸(없으면 빈 글 — 자리를 선언만 한 호스트도 선다). 문구와 달리 **빈 글은 값이다**(원래 이미지를 고른 것) — 기본 값으로 돌아가지 않는다.
/// 받지 않는 종류의 참조는 빈 글로 정규화한다(문구의 강제 정규화와 같은 뜻 — 호스트가 `kinds` 를 좁혀도 옛 안 파일이 열린다).
/// `snap` 은 그 자리 요소의 표식(`snapID`) — 미리보기에서 그 요소를 누르면 엔진이 이 칸을 고른다(선택).
public struct StyleSlot: Identifiable, Equatable, Sendable {
    /// 파일 키 — Style 값 사전의 칸 이름(칸 `StyleField.name` · 문구 `StyleText.name` 과 겹치지 않는다).
    public let name: String
    public let element: StyleElement
    /// 그 자리 요소의 표식(`snapID`) — 정확히 같은 글자 · nil 이면 절로만 선다.
    public let snap: String?
    /// 조절판 칸의 이름 — 호스트(프로젝트)가 지은 것 · nil 이면 엔진이 제 규칙으로 짓는다.
    public let label: String?
    /// 받는 종류(참조의 머리 낱말) — 열린 낱말 목록 · **1 개 이상** · 낱말은 ASCII 영문자 · 숫자 · `-` · `_`(대소문자를 가린다 — 참조의 종류 규칙과 같다)
    /// (어기면 서지 않는다: 코드로 지으면 `precondition` · 줄에서 읽으면 디코드 오류).
    public let kinds: [String]
    public var id: String { name }
    /// 종류를 적지 않은 자리가 받는 종류 — 줄에 `kinds` 가 없을 때도 이 값.
    public static let defaultKinds = ["isomodel"]
    public init(name: String, element: StyleElement, snap: String? = nil, label: String? = nil, kinds: [String] = StyleSlot.defaultKinds) {
        precondition(!kinds.isEmpty, "자리 \(name) 이 받는 종류가 없다")
        precondition(kinds.allSatisfy(Reference.isKindWord), "자리 \(name) 의 종류 낱말이 꼴이 아니다 — \(kinds)")
        self.name = name; self.element = element; self.snap = snap; self.label = label; self.kinds = kinds
    }

    /// 자리 값의 참조 — `<종류>:<이름>`. 이름은 서가 안의 파일 이름(확장자 없이)이라 비지 않고 · 경로 글자(`/` · `\`)가 없고 · 이름 전체가 `.` · `..` 가 아니며 ·
    /// 점으로 시작하지 않고(숨긴 파일) · 앞뒤 공백 · 줄바꿈 · 제어 문자 · 서식 문자(쓰기 방향 덮어쓰기 · 폭 없는 공백 — 이름 위장)가 없다.
    public struct Reference: Hashable, Sendable {
        public let kind: String
        public let name: String
        public init(kind: String, name: String) { self.kind = kind; self.name = name }
        /// 저장 꼴 글자 — `<종류>:<이름>`.
        public var text: String { "\(kind):\(name)" }

        /// 글자 하나 → 참조(꼴이 아니면 nil · 빈 글도 nil). 첫 `:` 앞이 종류(비지 않는 ASCII 낱말 — 영문자 · 숫자 · `-` · `_`) · 뒤가 이름.
        public static func parse(_ text: String) -> Reference? {
            guard let colon = text.firstIndex(of: ":") else { return nil }
            let kind = String(text[..<colon]), name = String(text[text.index(after: colon)...])
            guard isKindWord(kind) else { return nil }
            guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."),
                  name.first?.isWhitespace == false, name.last?.isWhitespace == false,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) || $0.properties.generalCategory == .format })
            else { return nil }
            return Reference(kind: kind, name: name)
        }

        /// 종류 낱말의 꼴 — 비지 않는 ASCII 영문자 · 숫자 · `-` · `_`(대소문자를 가린다).
        static func isKindWord(_ kind: String) -> Bool {
            !kind.isEmpty && kind.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
        }
    }

    /// 값 하나의 저장 꼴 — 빈 글 · 받는 종류의 참조면 그 글자 그대로 · 받지 않는 종류의 참조는 빈 글(원래 이미지) · 꼴이 아니면 nil.
    public func normalized(_ text: String) -> String? {
        if text.isEmpty { return text }
        guard let r = Reference.parse(text) else { return nil }
        return kinds.contains(r.kind) ? text : ""
    }
}

/// 화면 하나(또는 화면 위에 얹는 층 하나)의 Style **서술** — 프로젝트가 내는 데이터. JSON 꼴:
/// `{"screen":"…","elements":[{"id","label","snapPrefix","effects"?}],"fields":[{"name","kind","element","label"?}],"texts"?:[{"name","element","label"?,"maxLength"}],`
/// `"slots"?:[{"name","element","snap"?,"label"?,"kinds"}],"defaults":{…}}`
/// (칸의 `label` 은 선택 · 절의 `effects` · `texts` · `slots` 는 선택 — 없으면 빈 목록 · 빈 목록이면 줄에 쓰지 않는다 · 문구의 `maxLength` 가 없으면 `StyleText.defaultMaxLength` ·
/// 자리의 `kinds` 가 없으면 `StyleSlot.defaultKinds`).
/// `defaults` 는 화면의 기본값(파일에 없는 칸 · 문구를 채운다 — 칸이 늘어도 옛 안 파일이 읽힌다).
public struct StyleSchema: Equatable, Sendable {
    public let screen: String
    public let elements: [StyleElement]
    public let fields: [StyleField]
    /// 문구 칸 — 빈 목록이 기본(문구를 내지 않는 서술 · 판 3 의 줄에서 읽은 서술).
    public let texts: [StyleText]
    /// 자리 칸 — 빈 목록이 기본(자리를 내지 않는 서술 · 판 4 이하의 줄에서 읽은 서술).
    public let slots: [StyleSlot]
    public let defaults: StyleValues
    public init(screen: String, elements: [StyleElement], fields: [StyleField], defaults: StyleValues) {
        self.init(screen: screen, elements: elements, fields: fields, texts: [], slots: [], defaults: defaults)
    }
    public init(screen: String, elements: [StyleElement], fields: [StyleField], texts: [StyleText], defaults: StyleValues) {
        self.init(screen: screen, elements: elements, fields: fields, texts: texts, slots: [], defaults: defaults)
    }
    public init(screen: String, elements: [StyleElement], fields: [StyleField], texts: [StyleText], slots: [StyleSlot], defaults: StyleValues) {
        self.screen = screen; self.elements = elements; self.fields = fields; self.texts = texts; self.slots = slots; self.defaults = defaults
    }

    /// 값 한 덩이를 서술로 잰다 — 없는 칸은 기본값으로 채우고 · 칸마다 꼴을 재 다시 쓰고(스칼라의 남는 열쇠는 떨어진다) · 서술에 없는 칸은 뺀다.
    /// 문구는 글자여야 하고(아니면 거부) 저장 꼴로 다시 쓴다(`StyleText.normalized` — 비면 기본 글 · 기본 글도 같은 꼴로 잰다).
    /// 문구 이름이 칸 이름 · 다른 문구 이름과 겹치면 거부한다. 자리는 글자여야 하고 빈 글 ⟂ 참조의 꼴이어야 한다(아니면 `StyleSlotError` · 받지 않는 종류의 참조는 빈 글로) ·
    /// 없으면 기본 값(`defaults` 의 같은 칸 · 그것도 없으면 빈 글) · 이름이 칸 · 문구 · 다른 자리와 겹치면 거부한다.
    /// 프로젝트의 Style 타입이 읽고 다시 쓴 것과 같은 값이다.
    public func normalize(_ style: StyleValues) throws -> StyleValues {
        var out: StyleValues = [:]
        for f in fields {
            guard let v = style[f.name] ?? defaults[f.name] else { throw StyleSchemaError.missing(screen, f.name) }
            guard let n = f.kind.normalized(v) else { throw StyleSchemaError.badValue(screen, f.name, f.kind, v) }
            out[f.name] = n
        }
        for t in texts {
            guard out[t.name] == nil else { throw StyleTextError.nameTaken(screen, t.name) }
            out[t.name] = .string(try resolved(t, style[t.name]))
        }
        for slot in slots {
            guard out[slot.name] == nil else { throw StyleSlotError.nameTaken(screen, slot.name) }
            out[slot.name] = .string(try resolved(slot, style[slot.name] ?? defaults[slot.name] ?? ""))
        }
        return out
    }

    /// 자리 하나의 값 — 사전의 그 칸(nil = 비었다 → 기본 값 · 기본 값도 없으면 빈 글)의 글자. 사전으로 다루는 화면 코드가 자리를 읽는 손이다.
    /// 읽기는 관대하다 — 값이 글자가 아니거나 꼴이 아니면 빈 글(원래 이미지)로 읽는다(거부는 `normalize` 의 몫 · 받지 않는 종류는 둘 다 빈 글). 서술에 없는 자리는 nil.
    /// 참조로 풀려면 `StyleSlot.Reference.parse`.
    public func slot(_ name: String, in style: StyleValues?) -> String? {
        guard let s = slots.first(where: { $0.name == name }) else { return nil }
        guard case .string(let v)? = style?[name] ?? defaults[name] else { return "" }
        return s.normalized(v) ?? ""
    }

    private func resolved(_ s: StyleSlot, _ value: JSONValue) throws -> String {
        guard case .string(let v) = value else { throw StyleSlotError.notText(screen, s.name, value) }
        guard let n = s.normalized(v) else { throw StyleSlotError.badReference(screen, s.name, v) }
        return n
    }

    /// 문구 하나의 글 — 값(사전의 그 칸 · nil = 비었다)을 저장 꼴로 · 비면 기본 글. 사전으로 다루는 화면 코드가 문구를 읽는 손이다
    /// (프로젝트의 Style 타입으로 푸는 쪽은 그 타입의 `String` 칸을 읽는다 — 엔진이 쓴 값은 이미 저장 꼴이다).
    /// 읽기는 관대하다 — 값이 글자가 아니면 기본 글로 읽는다(거부는 `normalize` 의 몫). 서술에 없는 문구 · 기본 글도 글자가 아니면 nil.
    public func text(_ name: String, in style: StyleValues?) -> String? {
        guard let t = texts.first(where: { $0.name == name }) else { return nil }
        if case .string(let s)? = style?[name], let n = t.normalized(s) { return n }
        guard case .string(let d)? = defaults[name] else { return nil }
        return t.normalized(d) ?? ""
    }

    private func resolved(_ t: StyleText, _ value: JSONValue?) throws -> String {
        if let value {
            guard case .string(let s) = value else { throw StyleTextError.notText(screen, t.name, value) }
            if let n = t.normalized(s) { return n }
        }
        guard let d = defaults[t.name] else { throw StyleSchemaError.missing(screen, t.name) }
        guard case .string(let s) = d else { throw StyleTextError.notText(screen, t.name, d) }
        return t.normalized(s) ?? ""
    }
}

extension StyleSchema: Codable {
    private struct WireField: Codable { var name: String; var kind: FieldKind; var element: String; var label: String? }
    private struct WireText: Codable { var name: String; var element: String; var label: String?; var maxLength: Int? }
    private struct WireSlot: Codable { var name: String; var element: String; var snap: String?; var label: String?; var kinds: [String]? }
    private enum Keys: String, CodingKey { case screen, elements, fields, texts, slots, defaults }
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
        var taken = Set(fields.map(\.name))
        texts = try (c.decodeIfPresent([WireText].self, forKey: .texts) ?? []).map { w in
            guard let e = byID[w.element] else {
                throw DecodingError.dataCorruptedError(forKey: .texts, in: c, debugDescription: "문구 \(w.name) 의 절 \(w.element) 이 elements 에 없다")
            }
            guard taken.insert(w.name).inserted else {
                throw DecodingError.dataCorruptedError(forKey: .texts, in: c, debugDescription: "문구 \(w.name) 의 이름이 칸 · 다른 문구와 겹친다")
            }
            if let m = w.maxLength, m < 1 {
                throw DecodingError.dataCorruptedError(forKey: .texts, in: c, debugDescription: "문구 \(w.name) 의 최대 길이 \(m) 이 1 보다 작다")
            }
            return StyleText(name: w.name, element: e, label: w.label, maxLength: w.maxLength ?? StyleText.defaultMaxLength)
        }
        slots = try (c.decodeIfPresent([WireSlot].self, forKey: .slots) ?? []).map { w in
            guard let e = byID[w.element] else {
                throw DecodingError.dataCorruptedError(forKey: .slots, in: c, debugDescription: "자리 \(w.name) 의 절 \(w.element) 이 elements 에 없다")
            }
            guard taken.insert(w.name).inserted else {
                throw DecodingError.dataCorruptedError(forKey: .slots, in: c, debugDescription: "자리 \(w.name) 의 이름이 칸 · 문구 · 다른 자리와 겹친다")
            }
            if let k = w.kinds, k.isEmpty {
                throw DecodingError.dataCorruptedError(forKey: .slots, in: c, debugDescription: "자리 \(w.name) 이 받는 종류가 없다")
            }
            if let bad = w.kinds?.first(where: { !StyleSlot.Reference.isKindWord($0) }) {
                throw DecodingError.dataCorruptedError(forKey: .slots, in: c, debugDescription: "자리 \(w.name) 의 종류 낱말 \(bad) 이 꼴이 아니다(ASCII 영문자 · 숫자 · - · _)")
            }
            return StyleSlot(name: w.name, element: e, snap: w.snap, label: w.label, kinds: w.kinds ?? StyleSlot.defaultKinds)
        }
        defaults = try c.decode(StyleValues.self, forKey: .defaults)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(screen, forKey: .screen)
        try c.encode(elements, forKey: .elements)
        try c.encode(fields.map { WireField(name: $0.name, kind: $0.kind, element: $0.element.id, label: $0.label) }, forKey: .fields)
        if !texts.isEmpty {
            try c.encode(texts.map { WireText(name: $0.name, element: $0.element.id, label: $0.label, maxLength: $0.maxLength) }, forKey: .texts)
        }
        if !slots.isEmpty {
            try c.encode(slots.map { WireSlot(name: $0.name, element: $0.element.id, snap: $0.snap, label: $0.label, kinds: $0.kinds) }, forKey: .slots)
        }
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

/// 문구가 서지 않는다(`StyleSchema.normalize`) — 값도 기본 글도 없으면 칸과 같은 `StyleSchemaError.missing` 이다.
public enum StyleTextError: Error, CustomStringConvertible {
    /// 문구의 값(또는 기본 글)이 글자가 아니다 — 화면 · 문구 이름 · 값.
    case notText(String, String, JSONValue)
    /// 문구 이름이 칸 이름 · 다른 문구 이름과 겹친다(한 사전의 한 칸이라 둘이 설 수 없다) — 화면 · 문구 이름.
    case nameTaken(String, String)
    public var description: String {
        switch self {
        case .notText(let s, let t, let v): return "\(s) — 문구 \(t) 의 값이 글자가 아니다: \(v.text(pretty: false))"
        case .nameTaken(let s, let t): return "\(s) — 문구 \(t) 의 이름이 칸 · 다른 문구와 겹친다"
        }
    }
}

/// 자리가 서지 않는다(`StyleSchema.normalize`) — 자리의 오류는 칸 · 문구의 오류 열거(닫힌 열거)에 갈래를 더하지 않고 이 타입으로 낸다.
public enum StyleSlotError: Error, CustomStringConvertible {
    /// 자리의 값(또는 기본 값)이 글자가 아니다 — 화면 · 자리 이름 · 값.
    case notText(String, String, JSONValue)
    /// 빈 글도 `<종류>:<이름>` 꼴도 아니다(이름의 경로 글자 · 숨김 · 공백 · 제어 · 서식 문자 포함) — 화면 · 자리 이름 · 값.
    case badReference(String, String, String)
    /// 자리 이름이 칸 · 문구 · 다른 자리와 겹친다 — 화면 · 자리 이름.
    case nameTaken(String, String)
    public var description: String {
        switch self {
        case .notText(let s, let n, let v): return "\(s) — 자리 \(n) 의 값이 글자가 아니다: \(v.text(pretty: false))"
        case .badReference(let s, let n, let v): return "\(s) — 자리 \(n) 의 값이 빈 글도 <종류>:<이름> 꼴도 아니다: \(v)"
        case .nameTaken(let s, let n): return "\(s) — 자리 \(n) 의 이름이 칸 · 문구 · 다른 자리와 겹친다"
        }
    }
}
