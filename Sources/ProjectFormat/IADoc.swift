import Foundation

// 화면 지도(IA) 문서의 **꼴** — 앱 전체에서 화면이 어디에 있고 무엇으로 열리는가(마디 · 점프 · 허브). 프로젝트의 `paths.ia`(매니페스트) 한 장이다.
// 엔진(화면 지도 창 · 생성기 · 형식 도구)이 읽고 쓰고, 프로젝트의 미리보기 호스트가 층 자료(`PreviewProtocol.LayerContext`)로 받아 읽는다 —
// 양쪽이 무는 꼴이라 SDK 에 든다(읽기 · 쓰기 · 캐시 손과 배선 문서는 엔진의 도구). 판은 이 모듈의 한 자리(`IAFormat.version`).
//
// 「무엇이 화면인가」의 정본이 이 문서이고, 프로젝트의 생성물(앱의 IA 상수 · 화면 목록 문서의 생성 블록)이 여기서 나온다 — 마디의 `mapID` 는 그 화면 목록 문서의 행 ID 다.
// 주소가 없고 화면도 아닌 **액션 폼**(시트)은 `form: true` — 지도 ID 가 없는 것이 옳다.
//
// 관계의 종류는 둘 — `parent`(트리 · 뒤로 가기 = 부모) · `ScreenJump`(트리 밖 간선 · 뒤로 가기 = 출발 화면). 「어느 안이 뜨나」는
// 관계가 아니라 배선이라 배선 문서에 따로 산다. 허브(`Hub` · 탭바)는 루트 화면을 슬롯으로 든다 —
// 탭이 없는 앱은 허브가 없고, 허브 슬롯에 없는 루트는 전역 오버레이(어느 탭 위에서도 뜬다)다.
//
// **프로젝트 낱말은 글자 · JSON 그대로 든다** — 진입 손(`JumpEntry.control` — `"more"` 같은 글자) · 마디의 크롬 구성(`ScreenNode.chrome` · `chromeChart`) ·
// 허브의 내비 항목(`Hub.items`)은 프로젝트가 뜻을 정하는 칸이다. 이 꼴은 그 칸을 읽은 그대로 들고(`JSONValue`) 그대로 쓴다 — 프로젝트의 타입으로 오가는
// 어댑터와 「모르는 낱말」 검사는 프로젝트의 몫이다. 파일 꼴은 그대로다(같은 칸 · 같은 글자).
//
// **플랫폼 칸**(IA 하나 + 플랫폼별 틀과 안) — 마디 · 허브의 `platforms` 는 **선택 칸**이다: 없으면 매니페스트(`muc.json` `platforms`)
// 전부에 선다. 적으면 그 부분집합만. 판 번호는 1 그대로(추가 칸이라 옛 파일이 그대로 읽힌다).
//
// **진입 칸**(`ScreenNode.entry` — 어느 화면 · 무엇을 · 요소) 도 선택 칸이다 — 없으면 진입은 `via` 글뿐 · 있으면 `via` 는 그 선택에서 지은 글(판 1 그대로).
//
// **모르는 칸 보존** — 꼴마다 `extra`(이 SDK 가 모르는 칸 — 읽은 그대로 들고 되쓴다). 같은 판에 칸이 더해져도 옛 엔진이 열어 저장하면 사라지지 않는다.

/// 화면 하나 — 트리의 마디.
public struct ScreenNode: Identifiable, Sendable, Equatable, Codable {
    /// 코드명(`plants.detail` 꼴 · 엔진이 화면을 부르는 이름과 같은 글자)
    public var id: String
    /// 한국어 이름
    public var label: String
    /// 부모 화면 코드명(없으면 루트 — 탭 ⟂ 전역 오버레이)
    public var parent: String?
    /// 진입 — 무엇을 눌러 열리나(사람 말 글 · 화면 목록 문서의 「진입」 칸). `entry` 가 있으면 그 선택에서 지은 글이다 —
    /// 둘이 어긋나면(손으로 고친 글 · `entry` 를 모르는 읽개가 글만 고친 파일) **글이 이긴다**(읽는 쪽이 어긋남을 알릴 뿐 글을 덮지 않는다).
    public var via: String
    /// 출처(이 화면이 어디서 왔나 — 소스의 파일:줄 · 문서의 행 같은 근거 글)
    public var source: String
    /// 라우트(해시 ⟂ 질의) — 주소가 없는 시트는 nil
    public var route: String?
    /// 화면 목록 문서(엔진이 생성하는 블록) 행 ID — `G1a` · `G2` 꼴. 액션 폼(`form`)은 nil(지도에 행이 없다).
    /// 합쳐 적힌 칸(`**G2/G3**`)은 한 쪽씩 든다 — 목록 = `G2`, 상세 = `G3`.
    public var mapID: String?
    /// 액션 폼인가 — 화면이 아니라 그 화면의 입력 시트(예: 새 항목 만들기). 「미재현」이 아니라 「폼」으로 선다.
    public var form: Bool
    /// 한 화면의 **상태들** — 같은 화면이 다르게 보이는 값(접힘/펼침 · 진행 중/완료 · 빈 상태). 화면이 아니라 상태라 마디로 늘리지 않고 여기 적는다.
    /// 엔진의 미리보기에선 픽스처 상태(`--state`) 또는 조절판 토글이 그 상태를 만든다 — 어느 쪽인지 낱말 뒤 괄호에.
    public var states: [String]
    /// 조형 파일이 사는 폴더(프로젝트 폴더 기준 상대경로) — 화면을 SwiftUI 로 재현하는 대신 **isoscene 을 그대로 렌더**하는 마디.
    /// 그리기는 `*.isoscene`, 데이터는 옆의 `*.isodata`. nil 이면 보통 마디.
    public var scenes: String?
    /// 크롬 **구성**(화면 위에 늘 떠 있는 층 — 화면의 속성이라 여기 산다) — **프로젝트가 뜻을 정하는 칸**이라 엔진은 JSON 그대로 든다
    /// (프로젝트의 꼴로 오가는 것은 프로젝트 어댑터). nil 이면 칸이 없다(프로젝트가 자리에서 유도한다).
    public var chrome: JSONValue?
    /// **두 번째 끝**의 크롬 구성 — 한 화면이 두 상태(지도 ⟂ 차트 같은)로 서면 그 둘째 상태의 구성. 같은 규칙(JSON 그대로 · nil = 칸 없음).
    public var chromeChart: JSONValue?
    /// **제안** 마디 — 엔진의 IA 창에서 더한 새 화면(「마디 추가」). 화면 목록 문서에 행이 아직 없어 `mapID` 가 없다 —
    /// 앱에서는 준비 중 화면으로 떨어진다. 문서에 행을 세우면 `mapID` 를 적고 이 표를 내린다(테스트가 둘을 맞댄다).
    public var proposed: Bool
    /// 이 화면이 서는 플랫폼(`iphone` · `ipad` · `mac`) — **선택 칸** · nil 이면 매니페스트 `platforms` 전부. 적으면 비지 않은 부분집합(생성기가 잰다).
    public var platforms: [String]?
    /// 이 화면이 읽는 **데이터** — 모델 파일(`*.isodata`)의 엔티티 이름 목록(`data.reads`). **선택 칸**이다 —
    /// 없으면 nil · 적는 것은 사람의 사실이다(화면의 입력 함수가 실제로 읽는 것과 같은지는 재지 않는다). 이름이 모델에 있는지는 엔진의 데이터 검사가 잰다.
    public var data: ScreenData?
    /// 진입의 **선택** — 어느 화면에서 · 무엇을 눌러 여나(`ScreenEntry`). **선택 칸**이다 — nil 이면 진입은 `via` 글뿐이다.
    /// 칸이 있는데 이 SDK 가 못 읽는 꼴이면 nil 이고 그 글자는 `extra["entry"]` 에 읽은 그대로 남는다(되쓰면 그대로 · 마디는 읽힌다).
    public var entry: ScreenEntry?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]

    public init(id: String, label: String, parent: String? = nil, via: String, source: String, route: String? = nil,
                mapID: String? = nil, form: Bool = false, states: [String] = [], scenes: String? = nil, chrome: JSONValue? = nil, proposed: Bool = false,
                platforms: [String]? = nil, chromeChart: JSONValue? = nil, data: ScreenData? = nil) {
        self.id = id; self.label = label; self.parent = parent; self.via = via; self.source = source; self.route = route
        self.mapID = mapID; self.form = form; self.states = states; self.scenes = scenes; self.chrome = chrome; self.proposed = proposed
        self.platforms = platforms; self.chromeChart = chromeChart; self.data = data
    }
    /// 진입 선택을 든 마디 — 위의 손과 같고 `entry` 하나를 더 받는다(덧붙인 칸은 오버로드로 — 있던 손의 꼴을 바꾸지 않는다).
    public init(id: String, label: String, parent: String? = nil, via: String, source: String, route: String? = nil,
                mapID: String? = nil, form: Bool = false, states: [String] = [], scenes: String? = nil, chrome: JSONValue? = nil, proposed: Bool = false,
                platforms: [String]? = nil, chromeChart: JSONValue? = nil, data: ScreenData? = nil, entry: ScreenEntry?) {
        self.init(id: id, label: label, parent: parent, via: via, source: source, route: route, mapID: mapID, form: form, states: states,
                  scenes: scenes, chrome: chrome, proposed: proposed, platforms: platforms, chromeChart: chromeChart, data: data)
        self.entry = entry
    }

    /// 읽는 엔티티 이름(칸이 없으면 빈 목록).
    public var reads: [String] { data?.reads ?? [] }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, label, parent, via, source, route, mapID, form, states, scenes, chrome, chromeChart, proposed, platforms, data, entry }
    /// 파일엔 비어 있는 것을 적지 않는다(form=false · states=[] · nil) — 한 마디가 한 덩어리로 읽히게.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        via = try c.decode(String.self, forKey: .via)
        source = try c.decode(String.self, forKey: .source)
        route = try c.decodeIfPresent(String.self, forKey: .route)
        mapID = try c.decodeIfPresent(String.self, forKey: .mapID)
        form = try c.decodeIfPresent(Bool.self, forKey: .form) ?? false
        states = try c.decodeIfPresent([String].self, forKey: .states) ?? []
        scenes = try c.decodeIfPresent(String.self, forKey: .scenes)
        chrome = try c.decodeIfPresent(JSONValue.self, forKey: .chrome)
        chromeChart = try c.decodeIfPresent(JSONValue.self, forKey: .chromeChart)
        proposed = try c.decodeIfPresent(Bool.self, forKey: .proposed) ?? false
        platforms = try c.decodeIfPresent([String].self, forKey: .platforms)
        data = try c.decodeIfPresent(ScreenData.self, forKey: .data)
        // 진입 칸은 관대하게 — 이 SDK 가 못 읽는 꼴(빠진 칸 · 다른 형 · 뒤 판의 변형)이면 마디째 거부하지 않고 읽은 그대로 모르는 칸으로 든다(되쓰면 그대로).
        entry = c.contains(.entry) ? (try? c.decode(ScreenEntry.self, forKey: .entry)) : nil
        extra = try ExtraKeys.decode(from: decoder, known: entry == nil ? Self.knownWithoutEntry : Self.known)
    }
    /// 진입 칸을 못 읽었을 때의 아는 칸 — 그 칸의 글자를 모르는 칸으로 보존한다.
    static let knownWithoutEntry = known.subtracting([CodingKeys.entry.rawValue])
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(label, forKey: .label)
        try c.encodeIfPresent(parent, forKey: .parent)
        try c.encode(via, forKey: .via); try c.encode(source, forKey: .source)
        try c.encodeIfPresent(route, forKey: .route); try c.encodeIfPresent(mapID, forKey: .mapID)
        if form { try c.encode(form, forKey: .form) }
        if !states.isEmpty { try c.encode(states, forKey: .states) }
        try c.encodeIfPresent(scenes, forKey: .scenes)
        try c.encodeIfPresent(chrome, forKey: .chrome)
        try c.encodeIfPresent(chromeChart, forKey: .chromeChart)
        if proposed { try c.encode(proposed, forKey: .proposed) }
        try c.encodeIfPresent(platforms, forKey: .platforms)
        if let d = data, !d.isEmpty { try c.encode(d, forKey: .data) }
        try c.encodeIfPresent(entry, forKey: .entry)
        try ExtraKeys.encode(extra, to: encoder, known: entry == nil ? Self.knownWithoutEntry : Self.known)
    }
}

/// 마디의 `data` 칸 — 지금은 `reads`(엔티티 이름 목록) 하나. 비면 칸째 적지 않는다(파일이 뜻 없는 칸을 들지 않게).
public struct ScreenData: Sendable, Equatable, Codable {
    public var reads: [String]
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(reads: [String]) { self.reads = reads }
    public var isEmpty: Bool { reads.isEmpty && extra.isEmpty }

    enum CodingKeys: String, CodingKey { case reads }
    public init(from decoder: Decoder) throws {
        reads = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([String].self, forKey: .reads) ?? []
        extra = try ExtraKeys.decode(from: decoder, known: ["reads"])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reads, forKey: .reads)
        try ExtraKeys.encode(extra, to: encoder, known: ["reads"])
    }
}

/// 마디의 `entry` 칸 — 진입을 **두 단으로 고른 것**: 어느 화면에서(`screen` — 같은 문서의 마디 id) · 무엇을 눌러서(`kind` — 열린 낱말) ·
/// 그 요소의 이름(`element` — 호스트의 요소 id(`ScreenMarks` 의 snap id)이거나 손으로 적은 글 · 선택).
/// `screen` 이 문서에 있는가 · `screen` 이 부모가 아니면 그 길을 점프로도 긋는가는 쓰는 쪽(엔진의 편집)이 정한다 — 이 꼴은 읽은 그대로 든다.
/// 파일 꼴 — `"entry": {"screen": "shelf", "kind": "row", "element": "shelf.row"}` · 빈 `element` 는 쓰지 않는다.
public struct ScreenEntry: Sendable, Equatable, Codable {
    /// 무엇을 눌러 여나 — 열린 꼴(모르는 낱말은 그대로 든다). 사람 말 이름은 읽는 쪽(엔진의 UI)의 몫이다.
    public struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let tab = Kind(rawValue: "tab")
        public static let button = Kind(rawValue: "button")
        public static let row = Kind(rawValue: "row")
        public static let card = Kind(rawValue: "card")
        public static let menu = Kind(rawValue: "menu")
        public static let gesture = Kind(rawValue: "gesture")
        public static let other = Kind(rawValue: "other")
        /// 이 SDK 가 아는 낱말 — 고르개의 차례.
        public static let known: [Kind] = [.tab, .button, .row, .card, .menu, .gesture, .other]

        public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
        public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    }
    public var screen: String
    public var kind: Kind
    public var element: String?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(screen: String, kind: Kind, element: String? = nil) { self.screen = screen; self.kind = kind; self.element = element }

    enum CodingKeys: String, CodingKey, CaseIterable { case screen, kind, element }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screen = try c.decode(String.self, forKey: .screen)
        kind = try c.decode(Kind.self, forKey: .kind)
        element = try c.decodeIfPresent(String.self, forKey: .element)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(screen, forKey: .screen); try c.encode(kind, forKey: .kind)
        if let e = element, !e.isEmpty { try c.encode(e, forKey: .element) }
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }
}

/// 트리 밖의 간선 — 다른 가지로 건너뛰는 자리(화면이 두 부모를 갖지 않게 하는 대신 여기로 적는다). 같은 (from · to) 는 하나.
public struct ScreenJump: Sendable, Equatable, Codable, Identifiable {
    public var from: String
    public var to: String
    /// 무엇을 눌러 건너뛰나
    public var label: String
    /// 출처 — 근거 글(소스의 파일:줄 ⟂ 문서의 행) ⟂ 「lab IA 창 YYYY-MM-DD」(엔진의 IA 창 — 캔버스 · 명령 — 이 그은 점프 · `labSource`).
    /// 근거 없는 점프는 없다(프로젝트의 시험이 커밋된 점프를 붙든다). 끊기 전 확인은 IA 창 밖 출처만 받는다 — IA 창(캔버스 · 명령)이 그은 것은 바로 끊긴다(⌘Z).
    public var source: String?
    /// 앱의 진입 — 이 점프를 크롬(또는 씬)의 어느 손이 여나(`JumpEntry`). nil = 앱 크롬에 진입이 없는 점프(근거 글만 있는 점프 · 화면 안 행).
    /// 앱 셸의 메뉴 항목은 이것을 프로젝트의 생성 상수로 읽는다 — 끊으면 앱의 그 항목도 사라진다.
    public var entries: [JumpEntry]?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(from: String, to: String, label: String, source: String? = nil, entries: [JumpEntry]? = nil) {
        self.from = from; self.to = to; self.label = label; self.source = source; self.entries = entries
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case from, to, label, source, entries }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from); to = try c.decode(String.self, forKey: .to)
        label = try c.decode(String.self, forKey: .label)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        entries = try c.decodeIfPresent([JumpEntry].self, forKey: .entries)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from); try c.encode(to, forKey: .to); try c.encode(label, forKey: .label)
        try c.encodeIfPresent(source, forKey: .source); try c.encodeIfPresent(entries, forKey: .entries)
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }
    public var id: String { "\(from)>\(to)" }

    /// IA 창이 그은 점프의 출처 머리 — 뒤에 날짜(`yyyy-MM-dd`)가 붙는다(글자는 이미 저장된 출처와 맞춘 값이라 바꾸지 않는다).
    public static let labSourcePrefix = "lab IA 창"
    /// IA 창(캔버스 · 명령)이 새로 긋는 점프의 출처 — 「lab IA 창 YYYY-MM-DD」.
    public static func labSource(on date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return "\(labSourcePrefix) \(f.string(from: date))"
    }
    /// IA 창이 그은 점프인가(출처가 `labSource` 꼴).
    public var isLabDrawn: Bool { source?.hasPrefix(Self.labSourcePrefix + " ") ?? false }
}

/// 점프의 앱 진입 하나 — `control` = 손의 **낱말**(프로젝트가 정한 글자 — 예: `more` · `plus`) · `title` = 메뉴 항목 글(nil = 그 손이 바로 연다 ⟂ 행 고르기) ·
/// `order` = 한 손 메뉴 안 차례(메뉴 항목이면 필수 — 프로젝트의 생성기가 잰다).
/// 같은 (from · to) 가 손 둘로 열리면 한 점프에 진입이 둘이다 — 점프는 (from · to) 하나로 남는다.
/// 엔진은 낱말의 뜻을 모른다 — 어떤 낱말이 있는가 · 그 타입은 프로젝트의 것이고, 모르는 낱말은 프로젝트의 읽기 검사(엔진의 IA 저장소에 꽂는 손)가 거부한다.
/// 파일 꼴 — `"control": "more"` · 빈 칸은 쓰지 않는다.
public struct JumpEntry: Sendable, Equatable, Codable {
    public var control: String
    public var title: String?
    public var order: Int?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(control: String, title: String? = nil, order: Int? = nil) { self.control = control; self.title = title; self.order = order }
    enum CodingKeys: String, CodingKey, CaseIterable { case control, title, order }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        control = try c.decode(String.self, forKey: .control)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        order = try c.decodeIfPresent(Int.self, forKey: .order)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(control, forKey: .control)
        try c.encodeIfPresent(title, forKey: .title); try c.encodeIfPresent(order, forKey: .order)
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }
}

/// 허브 — 루트 화면을 슬롯으로 드는 내비 부품(탭바 · 사이드바). **탭 순서의 정본은 이 슬롯 차례다**(앱의 탭 차례가 따라온다).
public struct Hub: Sendable, Equatable, Codable, Identifiable {
    /// 열린 종류 — 사이드바 같은 새 허브가 와도 ia.json 전체가 안 읽히는 일이 없게(모르는 kind 는 그대로 든다).
    public struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let tabBar = Kind(rawValue: "tabBar")
        /// 사이드바 — 넓은 창(가로 regular · iPad)의 두 단 내비. 슬롯은 탭바와 같은 루트를 든다.
        public static let sidebar = Kind(rawValue: "sidebar")
    }
    public var id: String
    public var label: String
    public var kind: Kind
    /// 슬롯 = 탭 루트 화면 코드명(순서대로)
    public var slots: [String]
    /// 이 허브(내비 틀)가 서는 플랫폼 — **선택 칸** · nil 이면 매니페스트 `platforms` 전부. 어느 플랫폼에 어느 내비 틀이 서는가는 프로젝트가 적는다.
    public var platforms: [String]?
    /// 슬롯마다 **손댄 내비 항목** · 열쇠 = 슬롯 id · **선택 칸** — 항목의 꼴(표시명 · 기호 · 숨김 같은)은 프로젝트가 정하는 칸이라 JSON 그대로 든다.
    /// 차례는 `slots` 가 갖는다(항목 칸에 차례를 또 두지 않는다).
    public var items: [String: JSONValue]?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(id: String, label: String, kind: Kind, slots: [String], platforms: [String]? = nil, items: [String: JSONValue]? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.slots = slots; self.platforms = platforms; self.items = items
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case id, label, kind, slots, platforms, items }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(Kind.self, forKey: .kind); slots = try c.decode([String].self, forKey: .slots)
        platforms = try c.decodeIfPresent([String].self, forKey: .platforms)
        items = try c.decodeIfPresent([String: JSONValue].self, forKey: .items)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(label, forKey: .label); try c.encode(kind, forKey: .kind); try c.encode(slots, forKey: .slots)
        try c.encodeIfPresent(platforms, forKey: .platforms); try c.encodeIfPresent(items, forKey: .items)
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }
}

/// IA 문서 한 장(`paths.ia`) — 마디 · 점프 · 허브.
public struct IADoc: Sendable, Equatable, Codable {
    public static let currentVersion = IAFormat.version   // 판은 엔진 SDK 의 한 자리(엔진의 형식 판 등록표와 같은 값)
    public var version: Int
    public var nodes: [ScreenNode]
    public var jumps: [ScreenJump]
    public var hubs: [Hub]
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    /// 새 문서 — 판은 `IAFormat.version`(기본 인자가 아니라 이 손의 몸이 든다 — 판이 부르는 쪽 목적 코드에 묻지 않게).
    public init(nodes: [ScreenNode], jumps: [ScreenJump], hubs: [Hub]) { self.init(version: IAFormat.version, nodes: nodes, jumps: jumps, hubs: hubs) }
    public init(version: Int, nodes: [ScreenNode], jumps: [ScreenJump], hubs: [Hub]) {
        self.version = version; self.nodes = nodes; self.jumps = jumps; self.hubs = hubs
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case version, nodes, jumps, hubs }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        nodes = try c.decode([ScreenNode].self, forKey: .nodes)
        jumps = try c.decode([ScreenJump].self, forKey: .jumps)
        hubs = try c.decode([Hub].self, forKey: .hubs)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(nodes, forKey: .nodes); try c.encode(jumps, forKey: .jumps); try c.encode(hubs, forKey: .hubs)
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }

    public func node(_ id: String) -> ScreenNode? { nodes.first { $0.id == id } }
    public func children(of id: String) -> [ScreenNode] { nodes.filter { $0.parent == id } }
    public var roots: [ScreenNode] { nodes.filter { $0.parent == nil } }
    public func jumps(from id: String) -> [ScreenJump] { jumps.filter { $0.from == id } }
    /// 허브 슬롯에 선 루트(탭) — 순서는 허브의 것 · 허브가 여럿(탭바 ⟂ 사이드바)이 같은 루트를 들면 한 번만(처음 나온 차례).
    public var tabRoots: [ScreenNode] { hubSlots.compactMap { node($0) } }
    /// 모든 허브의 슬롯 — 겹침 없이 처음 나온 차례.
    public var hubSlots: [String] {
        var seen: Set<String> = []
        return hubs.flatMap(\.slots).filter { seen.insert($0).inserted }
    }
    /// 허브 슬롯에 없는 루트 = 전역 오버레이(어느 탭 위에서도 뜨고 닫으면 그 탭 그대로).
    public var overlays: [ScreenNode] {
        let slotted = Set(hubs.flatMap(\.slots))
        return roots.filter { !slotted.contains($0.id) }
    }

    /// 점프 놓기 — 같은 (from · to) 는 라벨만 갱신(출처 · 앱 진입은 있던 것을 지킨다). 새 점프는 `source` 를 출처로 적는다.
    public mutating func setJump(from: String, to: String, label: String, source: String? = nil) {
        let old = jumps.first { $0.from == from && $0.to == to }
        jumps.removeAll { $0.from == from && $0.to == to }
        jumps.append(ScreenJump(from: from, to: to, label: label, source: old?.source ?? source, entries: old?.entries))
    }
    public mutating func removeJump(from: String, to: String) { jumps.removeAll { $0.from == from && $0.to == to } }
}
