import DesignTokens
import Foundation
import TestScratch
import Testing

// 토큰 정본의 곁 칸 둘 — 씬 칸 → 씬 역할 규칙(`SceneSlotNaming` · 별칭 칸 `semantic.$sceneSlots`)과 색 역할의 묶음(`ColorRoleGroups` · `semantic.$group`).
// 정본은 시험이 임시 폴더에 쓰는 작은 `tokens.json` 이다.

private let tokens = #"""
{
  "semantic": {
    "$sceneSlots": { "$note": "규칙 밖 칸", "hedgeMark": "scene-hedge-grid" },
    "$group": {
      "$order": ["바닥", "꽃", "칩", "나머지"],
      "$fallback": "나머지",
      "bg": "바닥",
      "primary": "꽃",
      "glow-*": "꽃",
      "chip-*": "칩",
      "chip-sand-*": "바닥"
    },
    "themes": {
      "light": { "bg": "#ffffff", "primary": "#0000ff", "chip-mint": "#10a0a0", "scene-lawn": "#30a030", "scene-hedge-grid": "#f0f0ff" },
      "dark": { "bg": "#000000", "primary": "#3333ff", "chip-mint": "#20b0b0", "scene-lawn": "#204020", "scene-hedge-grid": "#a0a0b0" }
    }
  }
}
"""#

@Suite struct SceneSlotNamingTests {
    @Test func theRuleIsScenePlusKebab() {
        #expect(SceneSlotNaming.tokenName(forSlot: "lawn") == "scene-lawn")
        #expect(SceneSlotNaming.tokenName(forSlot: "fenceTall") == "scene-fence-tall")
        #expect(SceneSlotNaming.tokenName(forSlot: "cloud") == "scene-cloud", "규칙 안 칸 — 별칭이 필요 없다")
        #expect(SceneSlotNaming.tokenName(forSlot: "hedgeMark") == "scene-hedge-mark", "별칭이 없으면 규칙 그대로")
        #expect(SceneSlotNaming.tokenName(forSlot: "hedgeMark", aliases: ["hedgeMark": "scene-hedge-grid"]) == "scene-hedge-grid", "별칭이 규칙을 앞선다")
    }

    @Test func aliasesComeFromTheCanonsSideCellWithoutNotes() throws {
        let url = TestScratch.location("scene-slots", ext: "json"); defer { TestScratch.remove(url) }
        try Data(tokens.utf8).write(to: url)
        let p = SoTColorProvider(tokensJSONURL: url)
        #expect(p.sceneSlotAliases() == ["hedgeMark": "scene-hedge-grid"], "`$` 키는 설명이라 뺀다")
        let role = SceneSlotNaming.tokenName(forSlot: "hedgeMark", aliases: p.sceneSlotAliases())
        #expect(p.color(role, theme: "dark")?.hex == "#a0a0b0")
        #expect(SceneSlotNaming.aliases(semantic: [:]).isEmpty, "칸이 없는 정본 = 빈 표")
    }
}

@Suite struct ColorRoleGroupsTests {
    @Test func exactThenLongestPrefixThenFallback() throws {
        let url = TestScratch.location("role-groups", ext: "json"); defer { TestScratch.remove(url) }
        try Data(tokens.utf8).write(to: url)
        let g = SoTColorProvider(tokensJSONURL: url).roleGroups()
        #expect(g.order == ["바닥", "꽃", "칩", "나머지"])
        #expect(g.group(of: "bg") == "바닥")
        #expect(g.group(of: "glow-leaf") == "꽃", "앞머리 키")
        #expect(g.group(of: "chip-mint") == "칩")
        #expect(g.group(of: "chip-sand-deep") == "바닥", "가장 긴 앞머리가 먼저")
        #expect(g.group(of: "plum-bloom") == "나머지", "어디에도 안 들면 `$fallback`")
        let grouped = g.grouped(["chip-mint", "bg", "plum-bloom", "primary"])
        #expect(grouped.map(\.group) == ["바닥", "꽃", "칩", "나머지"])
        #expect(grouped.first { $0.group == "꽃" }?.roles == ["primary"])
    }

    @Test func noSideCellMeansNoGroups() {
        let g = ColorRoleGroups(semantic: ["themes": [:]])
        #expect(g == .none)
        #expect(g.group(of: "bg") == nil)
        #expect(g.grouped(["bg"]).isEmpty)
        let outside = ColorRoleGroups(order: ["A"], exact: ["x": "B"])
        #expect(outside.grouped(["x"]).map(\.group) == ["B"], "`$order` 밖 묶음은 뒤에")
    }
}
