/// 폼팩터 — 프로젝트가 겨냥하는 기기의 낱말 **한 벌**. 매니페스트 `muc.json` 의 `platforms` 와
/// IA 의 플랫폼 칸(허브 · 마디의 `platforms` — 프로젝트의 생성 상수)이 같은 글자를 쓴다.
///
/// **열린 꼴**이다 — 아는 낱말은 상수(`iphone` · `ipad` · `mac` · 차례 `known` — 표 · 메뉴의 차례)이고, 모르는 낱말(새 기기)도 글자 그대로 든다.
/// 모르는 낱말을 어떻게 다루는가(거절 ⟂ 읽기 전용 ⟂ 건너뜀)는 읽는 쪽이 정한다 — 이 꼴은 그 낱말을 지우지 않는다.
/// 어느 폼팩터도 필수가 아니다 — 플랫폼 목록은 비지 않고 겹치지 않으면 된다(맥 전용 · iPad 전용 · iPhone 없는 어떤 조합도 선다 · `problems(in:)`).
public struct FormFactor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iphone = FormFactor(rawValue: "iphone")
    public static let ipad = FormFactor(rawValue: "ipad")
    public static let mac = FormFactor(rawValue: "mac")
    /// 이 SDK 가 아는 낱말 — 좁은 것에서 넓은 것으로(표 · 메뉴의 차례).
    public static let known: [FormFactor] = [.iphone, .ipad, .mac]

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
