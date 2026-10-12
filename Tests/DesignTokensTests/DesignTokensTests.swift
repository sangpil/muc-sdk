import CoreGraphics
import DesignTokens
import Foundation
import SwiftUI
import TestScratch
import Testing

// 디자인 토큰의 꼴 — 색 값 읽기 · 정본 읽개(테마 · 역할 차례 · 참조 풀기 · 표시 지도) · 이름 표기 · 스케일 읽개 · 열거 공급자.
// 정본은 시험이 임시 폴더에 쓰는 작은 `tokens.json` 이다(프로젝트의 정본을 읽지 않는다) — 꼴은 엔진 토큰 정본의 줄 꼴 그대로(테마 블록 6칸 · 역할 8칸).

/// 시험용 정본 — dark 가 파일에서 먼저 오고 커스텀 테마 `warm` 이 끝에 · 참조 사슬 · `$note` 문자열 · 표시 지도(`$apple` · `$doc`).
private let fixture = #"""
{
  "primitive": {
    "color": {
      "ink": { "950": "#101010", "alias": "{primitive.color.ink.950}" }
    },
    "font": {
      "$apple": { "display": "title(28)" },
      "scale": {
        "$doc": { "display": "표지 제목", "body": "본문" },
        "s": { "display": 36, "body": 10 },
        "m": { "display": 40, "body": 12 },
        "l": { "display": 44, "body": 14 }
      }
    },
    "space": {
      "$status": "초안",
      "$doc": { "xs": "작은 틈" },
      "sm": 6,
      "xs": 4,
      "md": 8
    },
    "radius": {
      "pill": 999,
      "card": 12
    }
  },
  "semantic": {
    "layout": {
      "$note": "간격 역할 — 테마와 무관",
      "$doc": { "gap-wide": "넓은 틈" },
      "gap-wide": { "pt": "{primitive.space.md}", "scales": true },
      "margin-edge": { "pt": 16, "scales": false },
      "broken": { "pt": "{primitive.space.none}" }
    },
    "$apple": { "ink": "label" },
    "$doc": { "ink": "본문 글자", "ink-soft": "보조 글자" },
    "themes": {
      "$note": "테마 설명 — 테마가 아니다",
      "dark": {
        "ink":        "#e0d0c0",
        "ink-soft":   "#a0b0c0",
        "gray-2":     "{primitive.color.ink.alias}"
      },
      "light": {
        "ink":        "#203040",
        "ink-soft":   "#607080",
        "gray-2":     "#00000020"
      },
      "warm": {
        "$base": "light",
        "$doc": "따뜻한 라이트",
        "ink":        "#302010",
        "ink-soft":   "#706050",
        "gray-2":     "#fff0e0"
      }
    }
  }
}
"""#

/// 시험 정본 파일 하나 — 부른 쪽이 `defer { TestScratch.remove(url) }`.
private func writeFixture(_ text: String = fixture) throws -> URL {
    let url = TestScratch.location("design-tokens", ext: "json")
    try Data(text.utf8).write(to: url)
    return url
}

@Suite struct HexColorTests {
    @Test func parsesEveryAcceptedForm() {
        #expect(HexColor.parse("#A05010")?.hex == "#a05010")
        #expect(HexColor.parse("a05010")?.hex == "#a05010")
        #expect(HexColor.parse("0xA05010")?.rgb == 0xA05010)
        #expect(HexColor.parse("#fff")?.hex == "#ffffff")
        #expect(abs((HexColor.parse("#ffffff20")?.alpha ?? 0) - 32.0 / 255) < 0.001)
        #expect(HexColor.parse("#ffffff20")?.hex == "#ffffff20")
        #expect(HexColor.parse("rgb(160, 80, 16)")?.hex == "#a05010")
        #expect(HexColor.parse("rgba(160, 80, 16, 0.5)")?.hex == "#a0501080")
        #expect(abs((HexColor.parse("rgba(160, 80, 16, 50%)")?.alpha ?? 0) - 0.5) < 0.001)
    }

    @Test func refusesWhatIsNotAColor() {
        for raw in ["#12345", "rgb(300,0,0)", "blue", "rgba(1,2,3,1.5)", "rgb(1,2)", ""] { #expect(HexColor.parse(raw) == nil, "\(raw)") }
    }

    @Test func displayContrastAndCGColor() {
        #expect(HexColor.parse("#a05010")?.display == "#a05010")
        #expect(HexColor.parse("#a0501014")?.display == "#a05010 · 8%")
        #expect(HexColor.parse("#000000")!.contrast(against: HexColor.parse("#ffffff")!) > 20)
        let cg = HexColor(rgb: 0xFF8000, alpha: 0.5).cgColor
        #expect(cg.components?.map { ($0 * 255).rounded() } == [255, 128, 0, 128])
    }

    /// SwiftUI 색 — sRGB 성분 그대로(풀어 보면 8비트 값 · 알파가 돌아온다). 256 단 모두.
    @Test func swiftUIColorKeepsSRGBComponents() {
        let env = EnvironmentValues()
        for v in 0...255 {
            let c = UInt8(v)
            let r = Color(HexColor(r: c, g: 255 - c, b: c / 2, alpha: Double(v) / 255)).resolve(in: env)
            #expect((Double(r.red) * 255).rounded() == Double(c))
            #expect((Double(r.green) * 255).rounded() == Double(255 - c))
            #expect((Double(r.blue) * 255).rounded() == Double(c / 2))
            #expect(abs(Double(r.opacity) - Double(v) / 255) < 1e-6)
        }
    }
}

@Suite struct SoTColorProviderTests {
    /// 테마 차례 = light · dark 가 앞 · 커스텀은 블록 안 등장 순 · `$note` 문자열은 테마가 아니다 · `$base` 가 외양을 정한다.
    @Test func readsThemesInCanonicalOrder() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }

        let p = SoTColorProvider(tokensJSONURL: url)
        #expect(p.themes().map(\.name) == ["light", "dark", "warm"])
        #expect(p.theme("dark")?.base == .dark)
        #expect(p.theme("warm")?.base == .light)
        #expect(p.theme("warm")?.doc == "따뜻한 라이트")
    }

    /// 역할 차례 = 머리 테마(light) 블록 안의 키 차례 · 참조 사슬을 끝까지 푼다 · 표시 지도를 싣는다.
    @Test func readsRolesResolvesReferencesAndMaps() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }

        let p = SoTColorProvider(tokensJSONURL: url)
        #expect(p.entries().map(\.name) == ["ink", "ink-soft", "gray-2"])
        #expect(p.color("gray-2", theme: "dark")?.hex == "#101010", "참조 사슬 {alias} → {950} → 값")
        #expect(p.color("gray-2", theme: "light")?.hex == "#00000020")
        #expect(p.entry("ink")?.apple == "label")
        #expect(p.entry("ink-soft")?.apple == nil)
        #expect(p.entry("ink-soft")?.doc == "보조 글자")
        #expect(p.index().count == 3)
    }

    /// 저장 이름(camel) → 정본 실명 — 숫자가 든 손편집 이름도 돌아온다.
    @Test func mapsCamelNamesBack() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }

        let p = SoTColorProvider(tokensJSONURL: url)
        #expect(p.roleName(forCamel: "inkSoft") == "ink-soft")
        #expect(p.roleName(forCamel: "gray2") == "gray-2")
        #expect(p.roleName(forCamel: "nope") == nil)
    }

    /// 저장 직후 `invalidate()` — 수정 시각 확인 주기를 기다리지 않고 다시 읽는다.
    @Test func invalidateRereadsAtOnce() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }
        let p = SoTColorProvider(tokensJSONURL: url)
        #expect(p.color("ink", theme: "light")?.hex == "#203040")
        try Data(fixture.replacingOccurrences(of: "#203040", with: "#123456").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        p.invalidate()
        #expect(p.color("ink", theme: "light")?.hex == "#123456")
    }

    @Test func missingOrBrokenFileIsEmpty() throws {
        #expect(SoTColorProvider(tokensJSONURL: URL(fileURLWithPath: "/var/empty/none.json")).entries().isEmpty)
        let broken = try writeFixture("{ not json"); defer { TestScratch.remove(broken) }
        #expect(SoTColorProvider(tokensJSONURL: broken).themes().isEmpty)
    }
}

/// 색 칸의 값 — 저장 꼴(camel ⟂ `#hex`)을 공급자로 푼다: 역색인이 먼저(숫자가 든 손편집 이름) · 없으면 글자 규칙 · 리터럴은 실명이 없다 ·
/// 정본에 없는 역할은 모른다 · 테마 값 · 화면에 적는 이름(kebab ⟂ `#hex`).
@Suite struct ColorValueTests {
    @Test func resolvesRolesAndLiteralsThroughTheProvider() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }
        let p = SoTColorProvider(tokensJSONURL: url)
        let muted = ColorValue("inkSoft")
        #expect(!muted.isLiteral && muted.tokenName(in: p) == "ink-soft" && muted.isKnown(in: p))
        #expect(muted.hex(theme: "warm", in: p) == HexColor.parse("#706050"))
        #expect(muted.displayName(in: p) == "ink-soft")
        #expect(ColorValue("gray2").tokenName(in: p) == "gray-2", "역색인이 먼저 — 글자 규칙이면 gray2")
        #expect(ColorValue.role("gray-2") == ColorValue("gray2"))
        let lit = ColorValue.literal(HexColor(rgb: 0x112233))
        #expect(lit.isLiteral && lit.literal == HexColor(rgb: 0x112233) && lit.tokenName(in: p) == nil && !lit.isKnown(in: p))
        #expect(lit.hex(theme: "dark", in: p) == HexColor(rgb: 0x112233), "리터럴은 테마를 모른다")
        #expect(lit.displayName(in: p) == "#112233")
        let unknown = ColorValue("plumBloom")
        #expect(!unknown.isKnown(in: p) && unknown.hex(theme: "light", in: p) == nil && unknown.tokenName(in: p) == "plum-bloom")
    }
}

@Suite struct ColorRoleNamingTests {
    @Test func kebabAndCamelRoundTrip() {
        #expect(ColorRoleNaming.camel("ink-soft") == "inkSoft")
        #expect(ColorRoleNaming.kebab("inkSoft") == "ink-soft")
        #expect(ColorRoleNaming.camel("scene-fence-x") == "sceneFenceX")
        #expect(ColorRoleNaming.kebab(ColorRoleNaming.camel("moss-tone")) == "moss-tone")
    }
}

@Suite struct ScaleProviderTests {
    /// 간격 · 반경은 오름차순 · 글자 크기는 `font.scale.m` 의 내림차순 · `$` 칸은 값이 아니다 · 쓰임 · Apple 대응을 싣는다.
    @Test func readsScalesFromTheCanonicalFile() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }

        let p = SoTScaleProvider(tokensJSONURL: url)
        #expect(p.entries(.space).map(\.name) == ["xs", "sm", "md"])
        #expect(p.entries(.space).first?.doc == "작은 틈")
        #expect(p.entries(.radius).map(\.pt) == [12, 999])
        #expect(p.entries(.type).map(\.name) == ["display", "body"])
        #expect(p.entries(.type).first?.pt == 40)
        #expect(p.entries(.type).first?.apple == "title(28)")
        #expect(p.entries(.type).last?.doc == "본문")
    }

    /// 간격 역할(`semantic.layout`) — 숫자는 그대로 · 간격 스케일 참조는 그 단의 값 · 못 푸는 참조는 뺀다 · 이름 차례 · 쓰임.
    /// 간격 이름 → pt 는 스케일의 단이 먼저 · 없으면 역할.
    @Test func readsLayoutRolesAndResolvesSpaceNames() throws {
        let url = try writeFixture(); defer { TestScratch.remove(url) }
        let p = SoTScaleProvider(tokensJSONURL: url)
        #expect(p.layout() == [ScaleEntry(name: "gap-wide", pt: 8, doc: "넓은 틈"), ScaleEntry(name: "margin-edge", pt: 16)])
        #expect(p.spacePt("md") == 8)
        #expect(p.spacePt("margin-edge") == 16)
        #expect(p.spacePt("broken") == nil)
        #expect(p.spacePt("nope") == nil)
    }

    private enum Space: CGFloat, CaseIterable, NamedScaleEnum {
        case sm = 6, md = 8
        var name: String { "\(self)" }
        var doc: String { self == .sm ? "작게" : "" }
    }
    private enum Radius: CGFloat, CaseIterable, NamedScaleEnum {
        case card = 12
        var name: String { "card" }
        var doc: String { "" }
    }

    /// 생성 열거 꼴(`NamedScaleEnum`)을 그대로 목록으로 — 차례는 `allCases`.
    @Test func enumProviderListsGeneratedCases() {
        let p = EnumScaleProvider(space: Space.self, radius: Radius.self, type: Space.self)
        #expect(p.entries(.space) == [ScaleEntry(name: "sm", pt: 6, doc: "작게"), ScaleEntry(name: "md", pt: 8)])
        #expect(p.entries(.radius).map(\.name) == ["card"])
        #expect(p.entries(.type).count == 2)
        #expect(ScaleKind.known.map(\.rawValue) == ["space", "radius", "type"])
        // 열린 종류 — 모르는 종류(새 토큰 종류)는 빈 목록 · 낱말 그대로 왕복
        let stroke = ScaleKind(rawValue: "stroke")
        #expect(p.entries(stroke).isEmpty && !ScaleKind.known.contains(stroke))
        #expect((try? JSONDecoder().decode(ScaleKind.self, from: JSONEncoder().encode(stroke))) == stroke)
    }
}
