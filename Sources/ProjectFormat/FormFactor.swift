/// 폼팩터 — 프로젝트가 겨냥하는 기기의 낱말 **한 벌**. 매니페스트 `muc.json` 의 `platforms` 와
/// IA 의 플랫폼 칸(허브 · 마디의 `platforms` — 프로젝트의 생성 상수)이 같은 글자를 쓴다.
///
/// **열린 꼴**이다 — 아는 낱말은 상수(`iphone` · `ipad` · `mac` · `tv` · 차례 `known` — 표 · 메뉴의 차례)이고, 모르는 낱말(새 기기)도 글자 그대로 든다.
/// 모르는 낱말을 어떻게 다루는가(거절 ⟂ 읽기 전용 ⟂ 건너뜀)는 읽는 쪽이 정한다 — 이 꼴은 그 낱말을 지우지 않는다.
/// 어느 폼팩터도 필수가 아니다 — 플랫폼 목록은 비지 않고 겹치지 않으면 된다(맥 전용 · iPad 전용 · TV 전용 · iPhone 없는 어떤 조합도 선다 · `problems(in:)`).
///
/// **화면 벌** — 기기는 둘로 갈린다(`sharesScreens(mode:)` — 판정의 한 자리). 화면 한 벌을 나누는 기기(`iphone` · `ipad` · `mac` — 같은 화면 지도를
/// 틀만 바꿔 그린다)와 제 화면 벌을 갖는 기기(`tv` — 화면 · 입력이 달라 앱의 화면을 이어받지 않는다). 화면 지도의 화면 · 허브가 제 `platforms` 칸을 적지 않으면
/// 앱의 나누는 기기에만 선다(`inheritedScreenPlatforms(_:modes:)`) — 그래서 앱의 `platforms` 에 `tv` 를 더해도 있던 화면은 TV 화면이 되지 않는다.
public struct FormFactor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iphone = FormFactor(rawValue: "iphone")
    public static let ipad = FormFactor(rawValue: "ipad")
    public static let mac = FormFactor(rawValue: "mac")
    /// Apple TV — 제 화면 벌을 갖는 기기(`sharesScreens(mode:)` 가 false).
    public static let tv = FormFactor(rawValue: "tv")
    /// 이 SDK 가 아는 낱말 — 화면을 나누는 기기를 좁은 것에서 넓은 것으로, 그 뒤에 제 화면 벌을 갖는 기기(표 · 메뉴의 차례).
    public static let known: [FormFactor] = [.iphone, .ipad, .mac, .tv]

    /// 화면 한 벌을 나누는 기기인가 — 참이면 화면 지도의 화면이 칸 없이 이 기기에도 선다(앱 기본을 이어받는다) ·
    /// 거짓이면 제 화면 벌을 갖는 기기라 화면이 이 낱말을 적어야 이 기기의 화면이다.
    ///
    /// `iphone` · `ipad` · `mac` 은 참 · `tv` 와 모르는 낱말은 거짓(모르는 기기의 화면을 있던 화면으로 채우지 않는다).
    /// `mode` 는 이 기기가 서는 방식의 낱말(매니페스트의 방식 칸 — `mac` 의 `macMode` 같은 것)이다 — `designed-for-ipad`(iPad 앱을 그대로 연다)면
    /// 어느 기기든 iPad 의 화면을 그대로 쓰므로 참이다. 방식이 갈래를 가르는 기기도 이 한 자리가 판정한다.
    public func sharesScreens(mode: String? = nil) -> Bool {
        if mode == Self.designedForIPad { return true }
        return Self.sharing.contains(self)
    }

    /// 화면을 나누는 아는 낱말.
    static let sharing: Set<FormFactor> = [.iphone, .ipad, .mac]
    /// iPad 앱을 그대로 여는 방식의 낱말(매니페스트 방식 칸의 글자).
    static let designedForIPad = "designed-for-ipad"

    /// 제 `platforms` 칸이 없는 화면 · 허브가 서는 기기 — 앱의 플랫폼 목록(매니페스트 `platforms`) 중 화면을 나누는 것, 목록 차례 그대로.
    /// 나누는 기기가 없는 앱(TV 전용처럼)은 기기가 하나면 그 기기(화면 벌이 하나뿐이다) · 둘 이상이면 빈 목록(화면마다 제 낱말을 적는다).
    /// `modes` 는 기기 낱말 → 그 기기의 방식 낱말(`sharesScreens(mode:)` 에 넘긴다 — 없으면 방식 없음).
    public static func inheritedScreenPlatforms(_ platforms: [String], modes: [String: String] = [:]) -> [String] {
        let sharing = platforms.filter { FormFactor(rawValue: $0).sharesScreens(mode: modes[$0]) }
        if sharing.isEmpty, platforms.count == 1 { return platforms }
        return sharing
    }

    /// 화면 · 허브 하나가 서는 기기 — 제 칸(`own`)이 있으면 그것 · 없으면 `inheritedScreenPlatforms(_:modes:)`.
    public static func screenPlatforms(own: [String]?, app platforms: [String], modes: [String: String] = [:]) -> [String] {
        own ?? inheritedScreenPlatforms(platforms, modes: modes)
    }

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }

    /// 플랫폼 목록(매니페스트 `platforms` · IA 플랫폼 칸)의 꼴 문제 — 비었다 · 겹친다 · 낱말 꼴(소문자 로마자로 시작 · 소문자 · 숫자)이 아니다.
    /// 어느 낱말도 요구하지 않는다(iPhone 없는 조합도 선다) · 모르는 낱말은 문제가 아니다(읽는 쪽이 아는 낱말 `known` 과 견준다).
    public static func problems(in platforms: [String]) -> [String] {
        var out: [String] = []
        if platforms.isEmpty { out.append("플랫폼 목록이 비었다") }
        for (i, p) in platforms.enumerated() {
            if platforms.firstIndex(of: p) != i { out.append("플랫폼 ‘\(p)’ 이 겹친다") }
            let ok = p.unicodeScalars.first.map { ("a"..."z").contains($0) } == true
                && p.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            if !ok { out.append("플랫폼 ‘\(p)’ 은 소문자 로마자로 시작하는 소문자 · 숫자 낱말이어야 한다") }
        }
        return out
    }
}
