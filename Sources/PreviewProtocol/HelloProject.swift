import DesignTokens
import Foundation
import ProjectFormat

// 호스트가 `hello` 에 싣는 **프로젝트의 데이터** — 엔진이 프로젝트의 코드를 링크하지 않고 그 값을 받는 자리(정본 `Docs/SDK.md` §2).
// 값은 전부 프로젝트가 정하고(낱말 · 크기 · 생성물) 엔진은 뜻을 모른 채 받아 쓴다. 칸은 모두 선택이다 — 싣지 않은 호스트(옛 호스트 · 데이터가 없는 프로젝트)면
// 엔진은 그 칸이 없는 길로 선다.
//
//   hello.ia            IA 낱말 — 앱이 실제로 여는 화면 · 진입 손의 낱말과 이름 · 탭마다 손 · 옛 낱말 → IA id · 앱에 뷰가 아직 없는 화면
//   hello.frames        기기 틀 — 틀의 낱말 · 폼팩터 · 크기 · 코너 · 안전영역 · 편집기 기기 틀의 씬 띠
//   hello.tokensBuilt   빌드된 표 요약 — 호스트(와 같은 소스로 빌드되는 앱)가 굳혀 든 토큰 값. 엔진이 읽은 정본과 다르면 「재빌드 필요」(`BuiltTokens.differs`)
//   screens[].fixtureColorUsage   픽스처가 데이터로 고른 색 역할의 수(`ScreenInfo`)
//   layers[].composition          층의 구성 서술 — 층이 IA 문서에서 읽는 칸의 꼴(`LayerInfo` · `LayerComposition`) · 일반 편집기가 이것으로 칸을 그린다
//   frame.layers[].data           콜아웃 층의 푼 값(`CalloutValues` — pt · hex)

// MARK: hello.ia

/// IA 낱말 — 프로젝트의 IA 상수(앱 코드)가 정본인 값. 엔진의 화면 지도 · 흐름 · 읽기 검사가 이 값으로 선다.
public struct IAInfo: Codable, Equatable, Sendable {
    /// 진입 손 하나 — IA 문서 `JumpEntry.control` 의 낱말 · 사람이 읽는 이름.
    public struct EntryWord: Codable, Hashable, Sendable {
        public var control: String
        public var label: String
        public init(control: String, label: String) { self.control = control; self.label = label }
    }
    /// 앱이 실제로 여는 화면(IA id · 이름 차례).
    public var appScreens: [String]
    /// 진입 손의 낱말 전부 — 차례 그대로(읽기 검사는 이 목록 밖의 손을 거부한다).
    public var entryWords: [EntryWord]
    /// 탭(IA id) → 그 탭에서 앱이 실제로 세우는 손의 낱말.
    public var entryHands: [String: [String]]
    /// 옛 낱말 → IA id.
    public var aliases: [String: String]
    /// 앱에 뷰가 아직 없는 화면(IA id · 이름 차례).
    public var planned: [String]

    public init(appScreens: [String], entryWords: [EntryWord], entryHands: [String: [String]], aliases: [String: String], planned: [String]) {
        self.appScreens = appScreens; self.entryWords = entryWords; self.entryHands = entryHands; self.aliases = aliases; self.planned = planned
    }

    /// 진입 손의 낱말(차례 그대로).
    public var controls: [String] { entryWords.map(\.control) }
}

// MARK: hello.frames

/// 기기 틀 하나 — 화면을 그 틀의 크기로 그리고(찍기 · 창의 플랫폼 고르기) 편집기의 기기 틀이 씬을 덮는 띠를 잰다.
public struct DeviceFrameInfo: Codable, Equatable, Sendable {
    /// 편집기 기기 틀의 씬 띠 — 틀 이름과 그 기기에서 씬 그림을 덮는 띠.
    public struct SceneBand: Codable, Equatable, Sendable {
        public var name: String
        /// 덮는 띠(pt) — nil 이면 크롬 층이 그 크기에서 낸 덮는 띠(`LayerReport.cover`)를 쓴다.
        public var bands: Insets?
        public init(name: String, bands: Insets? = nil) { self.name = name; self.bands = bands }
    }
    /// 틀의 낱말(찍기 · 창의 인자 — 프로젝트가 정한다).
    public var id: String
    /// 폼팩터 낱말(`ProjectFormat.FormFactor` — 매니페스트 `platforms` · IA 플랫폼 칸과 한 벌).
    public var platform: String
    /// 사람이 읽는 이름.
    public var name: String
    /// 기호(SF Symbol 이름).
    public var symbol: String
    public var size: Size
    /// 디스플레이 코너(pt).
    public var corner: Double
    /// 안전영역 위 · 아래(pt).
    public var safeTop: Double
    public var safeBottom: Double
    /// 편집기 기기 틀이면 그 씬 띠 — nil 이면 편집기 틀이 아니다.
    public var scene: SceneBand?

    public init(id: String, platform: String, name: String, symbol: String, size: Size, corner: Double, safeTop: Double, safeBottom: Double,
                scene: SceneBand? = nil) {
        self.id = id; self.platform = platform; self.name = name; self.symbol = symbol; self.size = size; self.corner = corner
        self.safeTop = safeTop; self.safeBottom = safeBottom; self.scene = scene
    }

    /// 폼팩터(모르는 낱말이면 nil).
    public var formFactor: FormFactor? { FormFactor(rawValue: platform) }
}

// MARK: hello.tokensBuilt

/// 빌드된 표 요약 — 호스트가 굳혀 든 토큰 값(스케일 · 간격 역할 · 색 역할 × 테마 · 테마 이름). 엔진이 실행 시점에 읽은 정본(`SoTScaleProvider` ·
/// `SoTColorProvider`)으로 같은 꼴을 세워(`init(scales:layout:colors:)`) 맞대면(`differs`) 「재빌드 필요」 판정이 엔진 쪽 한 벌로 선다.
public struct BuiltTokens: Codable, Equatable, Sendable {
    /// 색 역할 하나 — 이름 · 테마 → hex(`HexColor.hex`).
    public struct Role: Codable, Hashable, Sendable {
        public var name: String
        public var values: [String: String]
        public init(name: String, values: [String: String]) { self.name = name; self.values = values }
    }
    /// 스케일 종류(`ScaleKind` 낱말) → 단들(공급자의 차례 그대로). 줄에는 단마다 이름 · pt 만 실린다(쓰임 · Apple 대응은 싣지 않는다 — 읽으면 빈 쓰임).
    public var scales: [String: [ScaleEntry]]
    /// 간격 역할(이름 차례 · 줄에는 이름 · pt 만).
    public var layout: [ScaleEntry]
    /// 색 역할(공급자의 차례 그대로).
    public var colors: [Role]
    /// 테마 이름.
    public var themes: [String]

    public init(scales: [String: [ScaleEntry]], layout: [ScaleEntry], colors: [Role], themes: [String]) {
        self.scales = scales; self.layout = layout; self.colors = colors; self.themes = themes
    }

    /// 공급자 둘 + 간격 역할에서 — 호스트는 빌드된 표로 · 엔진은 정본 읽개로 같은 꼴을 세운다(간격 역할은 이름 차례로 세운다).
    public init(scales: any ScaleTokenProvider, layout: [ScaleEntry], colors: any ColorTokenProvider) {
        self.scales = Dictionary(uniqueKeysWithValues: ScaleKind.allCases.map { k in (k.rawValue, scales.entries(k).map { ScaleEntry(name: $0.name, pt: $0.pt) }) })
        self.layout = layout.sorted { $0.name < $1.name }.map { ScaleEntry(name: $0.name, pt: $0.pt) }
        self.colors = colors.entries().map { e in Role(name: e.name, values: e.values.mapValues(\.hex)) }
        self.themes = colors.themes().map(\.name)
    }

    /// 줄 꼴 — 단 한 칸은 이름 · pt 두 칸(`ScaleEntry` 의 쓰임 · Apple 대응은 요약의 몫이 아니다 · 읽으면 비어 선다).
    private struct Step: Codable { var name: String; var pt: Double }
    enum CodingKeys: String, CodingKey { case scales, layout, colors, themes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entry = { (s: Step) in ScaleEntry(name: s.name, pt: CGFloat(s.pt)) }
        scales = try c.decode([String: [Step]].self, forKey: .scales).mapValues { $0.map(entry) }
        layout = try c.decode([Step].self, forKey: .layout).map(entry)
        colors = try c.decode([Role].self, forKey: .colors)
        themes = try c.decode([String].self, forKey: .themes)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let step = { (e: ScaleEntry) in Step(name: e.name, pt: Double(e.pt)) }
        try c.encode(scales.mapValues { $0.map(step) }, forKey: .scales)
        try c.encode(layout.map(step), forKey: .layout)
        try c.encode(colors, forKey: .colors)
        try c.encode(themes, forKey: .themes)
    }

    /// 두 요약이 다른가 — 스케일 종류마다 단의 차례 · 이름 · pt, 간격 역할, 색 역할의 차례 · 테마 값이 하나라도 다르면 참 · 테마 이름은 집합으로 맞댄다
    /// (정본 읽개는 light · dark 를 앞에 세우고 생성 표는 파일 차례라 차례 비교면 늘 「다르다」가 된다).
    public func differs(from other: BuiltTokens) -> Bool {
        let kinds = Set(scales.keys).union(other.scales.keys)
        if kinds.contains(where: { (scales[$0] ?? []) != (other.scales[$0] ?? []) }) { return true }
        return layout != other.layout || colors != other.colors || themes.sorted() != other.themes.sorted()
    }
}

// MARK: layers[].composition

/// 층의 구성 서술 — 층이 IA 문서에서 읽는 칸(마디의 구성 칸 · 허브 슬롯의 항목 칸)이 무엇이고 어떤 꼴인가. 프로젝트의 낱말(구성 칸 이름 · 기호 · 이름)은
/// 프로젝트가 정하고, 엔진은 이 서술로 일반 편집기의 칸을 세우고 IA 문서의 그 칸을 읽기에서 잰다(`CompositionField.Kind.accepts`). 저장은 IA 문서(엔진).
public struct LayerComposition: Codable, Equatable, Sendable {
    /// 마디에서 이 층의 구성이 사는 칸 하나 — 칸 이름(마디 JSON 의 키) · 사람이 읽는 이름.
    public struct NodeKey: Codable, Hashable, Sendable {
        public var key: String
        public var label: String
        public init(key: String, label: String) { self.key = key; self.label = label }
    }
    /// 구성 칸이 사는 마디 칸들(첫 칸이 기본).
    public var nodeKeys: [NodeKey]
    /// 구성 객체의 칸들(차례 = 편집기의 차례).
    public var fields: [CompositionField]
    /// 허브 슬롯 하나의 항목(`Hub.items[슬롯]`) 칸들 — nil 이면 이 층은 허브 항목을 읽지 않는다.
    public var hubItem: [CompositionField]?

    public init(nodeKeys: [NodeKey], fields: [CompositionField], hubItem: [CompositionField]? = nil) {
        self.nodeKeys = nodeKeys; self.fields = fields; self.hubItem = hubItem
    }

    /// 구성 객체 하나를 잰다 — 객체가 아니거나 서술의 칸이 꼴에 맞지 않으면 그 칸 이름 · 까닭(서술 밖 칸은 읽기가 무시하므로 재지 않는다 · 널은 비운 칸).
    public static func problems(_ value: JSONValue, fields: [CompositionField]) -> [String] {
        guard case .object(let o) = value else { return ["구성이 객체가 아니다"] }
        return fields.compactMap { f in
            guard let v = o[f.key], v != .null else { return nil }
            return f.kind.accepts(v) ? nil : "\(f.key) — \(f.kind.rawValue) 꼴이 아니다"
        }
    }
}

/// 구성 칸 하나 — 키 · 종류 · 사람이 읽는 이름 · 고를 값(`choice`) · 기본값 · 도움말 · 보이는 조건 · 기준 칸.
public struct CompositionField: Codable, Equatable, Sendable {
    /// 칸 종류 — JSON 꼴과 편집기의 컨트롤을 함께 정한다.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// 참거짓 — 토글
        case bool
        /// 글 한 줄 — 글 칸
        case text
        /// 기호 이름(SF Symbol) 하나 — 기호 칸
        case symbol
        /// 고르는 낱말 하나(`choices`) — 고르기
        case choice
        /// 기호 이름 목록(차례 있음) — 기호 칩 목록
        case symbols
        /// 기준 칸(`of`)의 값 → 이름 — 이름 표
        case labels
        /// 기준 칸(`of`) 목록의 부분 집합 — 켜고 끄기 목록
        case subset
        /// 허브 슬롯 화면(IA id) 하나 — 슬롯 고르기
        case slot

        /// 이 종류의 JSON 꼴인가.
        public func accepts(_ v: JSONValue) -> Bool {
            switch (self, v) {
            case (.bool, .bool): return true
            case (.text, .string), (.symbol, .string), (.choice, .string), (.slot, .string): return true
            case (.symbols, .array(let a)), (.subset, .array(let a)): return a.allSatisfy { if case .string = $0 { true } else { false } }
            case (.labels, .object(let o)): return o.values.allSatisfy { if case .string = $0 { true } else { false } }
            default: return false
            }
        }
    }
    /// 고를 값 하나 — 낱말 · 이름 · 기호(nil = 기호 없음).
    public struct Choice: Codable, Hashable, Sendable {
        public var value: String
        public var label: String
        public var symbol: String?
        public init(value: String, label: String, symbol: String? = nil) { self.value = value; self.label = label; self.symbol = symbol }
    }
    public var key: String
    public var kind: Kind
    public var label: String
    /// `choice` 의 값들(차례 그대로).
    public var choices: [Choice]?
    /// 칸을 적지 않았을 때의 뜻(읽기의 기본값) — nil 이면 비운 칸(없음).
    public var defaultValue: JSONValue?
    /// 마우스를 올리면 뜨는 한 줄.
    public var help: String?
    /// 이 칸이 서는 조건 — 같은 객체의 `bool` 칸 이름(그 칸이 참일 때만 선다 · nil = 늘).
    public var when: String?
    /// `labels` · `subset` 의 기준 칸(같은 객체의 `symbols` 칸 이름).
    public var of: String?

    public init(key: String, kind: Kind, label: String, choices: [Choice]? = nil, defaultValue: JSONValue? = nil, help: String? = nil,
                when: String? = nil, of: String? = nil) {
        self.key = key; self.kind = kind; self.label = label; self.choices = choices; self.defaultValue = defaultValue
        self.help = help; self.when = when; self.of = of
    }
}

// MARK: frame.layers[].data — 콜아웃

/// 콜아웃 층의 **푼 값** — 프로젝트의 콜아웃 안(Style 값)을 호스트가 이번 장의 테마로 푼 것(치수 pt · 색 `#rrggbb[aa]`). 콜아웃 카드는 씬을 읽어 서므로
/// 엔진(씬 미리보기)이 그리고, 이 값으로 렌더 코어의 콜아웃 값을 칸 대 칸 짓는다. 호스트는 층 보고(`LayerReport.data`)로 낸다.
public struct CalloutValues: Codable, Equatable, Sendable {
    /// 카드 바탕 · 테두리 색 · 테두리 굵기 · 모서리 반경.
    public var surface: String, line: String
    public var lineWidth: Double, cornerRadius: Double
    /// 안쪽 여백(폭 = 좌우 · 높이 = 위아래) · 줄 사이 · 카드 최대 폭.
    public var padding: Size
    public var lineSpacing: Double, maximumWidth: Double
    /// 눈썹 줄 — 글자 크기 · 자간 · 색.
    public var eyebrowSize: Double, eyebrowTracking: Double, eyebrowColor: String
    /// 제목 줄 — 글자 크기 · 색.
    public var titleSize: Double, titleColor: String
    /// 값 줄 — 글자 크기 · 색.
    public var valueSize: Double, valueColor: String
    /// 짚은 점 — 지름 · 색.
    public var dotDiameter: Double, dotColor: String
    /// 포인터 — 길이 · 굵기.
    public var pointerLength: Double, pointerWidth: Double
    /// 화면 가장자리 · 크롬에서 카드가 비켜서는 최소 거리.
    public var edgeInset: Double
    /// 짚은 자리 — 그림 폭 · 높이의 비율(0…1). 프로젝트의 콜아웃 표본이 정한 기본(그 자리에서 씬이 무엇을 읽는지는 엔진이 잰다) ·
    /// 엔진이 손으로 옮기면 그 값을 쓴다. nil = 싣지 않음(엔진이 가운데를 짚는다). 판 2 안의 선택 칸이다(옛 호스트는 싣지 않는다).
    public var anchor: CalloutAnchor?

    public init(surface: String, line: String, lineWidth: Double, cornerRadius: Double, padding: Size, lineSpacing: Double, maximumWidth: Double,
                eyebrowSize: Double, eyebrowTracking: Double, eyebrowColor: String, titleSize: Double, titleColor: String,
                valueSize: Double, valueColor: String, dotDiameter: Double, dotColor: String,
                pointerLength: Double, pointerWidth: Double, edgeInset: Double, anchor: CalloutAnchor? = nil) {
        self.surface = surface; self.line = line; self.lineWidth = lineWidth; self.cornerRadius = cornerRadius
        self.padding = padding; self.lineSpacing = lineSpacing; self.maximumWidth = maximumWidth
        self.eyebrowSize = eyebrowSize; self.eyebrowTracking = eyebrowTracking; self.eyebrowColor = eyebrowColor
        self.titleSize = titleSize; self.titleColor = titleColor; self.valueSize = valueSize; self.valueColor = valueColor
        self.dotDiameter = dotDiameter; self.dotColor = dotColor
        self.pointerLength = pointerLength; self.pointerWidth = pointerWidth; self.edgeInset = edgeInset
        self.anchor = anchor
    }

    /// 층 보고의 자료(JSON) — `LayerReport.data`.
    public func data() throws -> JSONValue { try JSONValue.from(self) }
    /// 층 보고의 자료에서.
    public init(data: JSONValue) throws { self = try data.decode(CalloutValues.self) }
}

/// 콜아웃의 짚은 자리 — 그림 폭 · 높이의 비율(0…1). 전송 계약은 비율 두 수만 싣는다(그림 안의 자리로 푸는 손은 받는 쪽의 것).
public struct CalloutAnchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
