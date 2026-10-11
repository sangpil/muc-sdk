import Foundation

// 색 칸의 값 하나 — 저장 꼴(역할 이름 camel `inkSoft` ⟂ 리터럴 `#rrggbb`)을 **토큰 공급자로** 푼다(그 값을 담는 색 타입 없이).
// 이름의 규약은 한 벌이다 — 정본 실명(kebab) = 공급자의 역색인이 먼저(`gray-2` 처럼 숫자가 든 손편집 이름) · 없으면 글자 규칙(`ColorRoleNaming.kebab`) ·
// 리터럴은 실명이 없다(테마를 모른다). 엔진의 조절판(색 칩 · 팝오버 · 확정 거부) · 쓰임 셈이 이것을 쓴다.

public struct ColorValue: Hashable, Sendable {
    /// 저장 꼴 그대로(안 파일의 글자)
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    /// 정본 실명(kebab)의 역할 — 저장 꼴은 camel.
    public static func role(_ kebab: String) -> ColorValue { ColorValue(ColorRoleNaming.camel(kebab)) }
    /// 리터럴(`#rrggbb` · `#rrggbbaa`) — 토큰 밖.
    public static func literal(_ hex: HexColor) -> ColorValue { ColorValue(hex.hex) }
    /// 정본에 없는 역할 · 못 푼 색을 드러내는 색(마젠타).
    public static let unknown = HexColor(rgb: 0xFF00FF)

    /// 토큰 밖 리터럴인가(테마를 모른다 — 라이트에서 고른 색이 다크에서 그대로).
    public var isLiteral: Bool { raw.hasPrefix("#") }
    public var literal: HexColor? { isLiteral ? HexColor.parse(raw) : nil }

    /// 정본 실명(kebab) — 리터럴은 nil.
    public func tokenName(in colors: any ColorTokenProvider) -> String? {
        isLiteral ? nil : (colors.roleName(forCamel: raw) ?? ColorRoleNaming.kebab(raw))
    }
    /// 정본에 있는 역할인가.
    public func isKnown(in colors: any ColorTokenProvider) -> Bool { tokenName(in: colors).map { colors.entry($0) != nil } ?? false }
    /// 테마 하나에서의 값 — 리터럴은 그대로 · 모르는 역할 · 테마는 nil.
    public func hex(theme: String, in colors: any ColorTokenProvider) -> HexColor? {
        if let l = literal { return l }
        return tokenName(in: colors).flatMap { colors.color($0, theme: theme) }
    }
    /// 화면에 적는 이름 — 정본 실명(kebab) · 리터럴은 `#hex` 그대로(저장 꼴 camel 은 형식일 뿐이다).
    public func displayName(in colors: any ColorTokenProvider) -> String { tokenName(in: colors) ?? raw }
}
