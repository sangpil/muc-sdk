import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// Style 서술 — 프로젝트가 내는 데이터(칸 · 절 · 레이블 · 기본값)로 안 파일의 값을 잰다(`normalize`). 서술은 JSON 으로 오가도 같다(`hello` 에 실린다).
// 칸 하나 바꾸기(`StyleEdit` — 프로젝트의 Style 타입에 Codable 왕복)도 여기서 잰다. 쓰임 셈은 엔진의 몫이라 엔진 쪽 시험이 잰다.

@Suite struct StyleSchemaTests {
    static let pot = StyleElement(id: "pot", label: "화분", snapPrefix: "plants.pot")
    static let color = StyleElement(id: "color", label: "색 역할", snapPrefix: "")
    static let schema = StyleSchema(
        screen: "home", elements: [pot, color],
        fields: StyleField.list([("potGap", .scalar(.space)), ("potSize", .scalar(.type)), ("glassColor", .color), ("potOn", .bool)], elements: [pot, color]),
        defaults: ["potGap": ["token": "md"], "potSize": ["pt": 17], "glassColor": "ink", "potOn": true])

    /// 규칙의 짝 — 한국어 차례(세로 여백 · 행 간격 · 위 간격 · 켜기)와 앞머리 떼기.
    @Test func rulePairs() {
        let pot = StyleElement(id: "pot", label: "화분", snapPrefix: "plants.pot")
        let trellis = StyleElement(id: "trellis", label: "격자", snapPrefix: "plants.trellis")
        let root = StyleElement(id: "root", label: "뿌리", snapPrefix: "plants.root")
        let color = StyleElement(id: "color", label: "색 역할", snapPrefix: "")
        #expect(StyleField.label(for: "potLabelSize", element: pot, kind: .scalar(.type)) == "라벨 크기")
        #expect(StyleField.label(for: "potSproutTop", element: pot, kind: .scalar(.space)) == "sprout 위 간격")
        #expect(StyleField.label(for: "trellisMulchPadV", element: trellis, kind: .scalar(.space)) == "mulch 세로 여백")
        #expect(StyleField.label(for: "rootGapRow", element: root, kind: .scalar(.space)) == "행 간격")
        #expect(StyleField.label(for: "rootsBottom", element: root, kind: .scalar(.space)) == "roots 아래 간격", "경계가 대문자가 아니면 떼지 않는다")
        #expect(StyleField.label(for: "potSproutRail", element: pot, kind: .bool) == "sprout rail")
        #expect(StyleField.label(for: "trellisOn", element: trellis, kind: .bool) == "켜기")
        #expect(StyleField.label(for: "glassColor", element: color, kind: .color) == "유리")
    }

    /// 칸 목록 — 절은 가장 긴 앞머리 · `…Color` 는 색 절 · 한 절 안에서 레이블이 겹치면 그 칸들은 키 그대로.
    @Test func fieldListGroupsAndKeepsLabelsUnique() {
        let tray = StyleElement(id: "tray", label: "받침", snapPrefix: "x.tray")
        let fields = StyleField.list([("on", .bool), ("trayOn", .bool), ("trayTitleSize", .scalar(.type))], elements: [tray, Self.color])
        #expect(fields.map(\.element.id) == ["tray", "tray", "tray"])
        #expect(fields.map(\.label) == ["on", "trayOn", "제목 크기"], "`on` ⟂ `trayOn` 이 둘 다 「켜기」가 되면 키로(앞머리 없는 칸은 첫 절)")
        #expect(StyleElement.of(snapID: "plants.pot.title", in: Self.schema.elements)?.id == "pot")
        #expect(StyleElement.of(snapID: "other", in: Self.schema.elements) == nil)
    }

    /// 서술은 데이터 — 칸 종류는 평평한 낱말 · 칸의 절은 id 로 · 모르는 절 · 모르는 종류는 거부.
    @Test func schemaRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.schema)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try #require(obj["fields"] as? [[String: Any]])
        #expect(fields.map { $0["kind"] as? String } == ["space", "type", "color", "bool"])
        #expect(fields.map { $0["element"] as? String } == ["pot", "pot", "color", "pot"])
        #expect(try JSONDecoder().decode(StyleSchema.self, from: data) == Self.schema)
        let badElement = Data(#"{"screen":"x","elements":[],"fields":[{"name":"a","kind":"bool","element":"q","label":"a"}],"defaults":{}}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StyleSchema.self, from: badElement) }
        let badKind = Data(#"{"screen":"x","elements":[{"id":"q","label":"q","snapPrefix":""}],"fields":[{"name":"a","kind":"glow","element":"q","label":"a"}],"defaults":{}}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StyleSchema.self, from: badKind) }
    }

    /// 값 재기 — 없는 칸은 기본값 · 스칼라의 남는 열쇠는 떨어지고(`token` 이 `pt` 를 앞선다) · 서술 밖 칸은 빠지고 · 꼴이 틀리면 거부.
    @Test func normalizeFillsDropsAndRefuses() throws {
        let s = Self.schema
        let got = try s.normalize(["potGap": ["token": "lg", "pt": 3], "glassColor": "#00ff00", "stale": 1])
        #expect(got == ["potGap": ["token": "lg"], "potSize": ["pt": 17], "glassColor": "#00ff00", "potOn": true])
        #expect(try s.normalize(["potSize": ["pt": .number(12.5), "x": 1]])["potSize"] == ["pt": .number(12.5)])
        #expect(throws: StyleSchemaError.self, "색 칸에 숫자") { try s.normalize(["glassColor": 3]) }
        #expect(throws: StyleSchemaError.self, "토큰 이름이 글자가 아니다") { try s.normalize(["potGap": ["token": 4]]) }
        #expect(throws: StyleSchemaError.self, "토큰도 pt 도 없다") { try s.normalize(["potGap": ["px": 4]]) }
        #expect(throws: StyleSchemaError.self, "토글에 글자") { try s.normalize(["potOn": "yes"]) }
        let noDefault = StyleSchema(screen: "x", elements: [Self.pot], fields: StyleField.list([("potOn", .bool)], elements: [Self.pot]), defaults: [:])
        #expect(throws: StyleSchemaError.self, "값도 기본값도 없다") { try noDefault.normalize([:]) }
    }

    /// 스칼라 값 읽기 — 저장 꼴(`{"token"}` ⟂ `{"pt"}`)을 만드는 손(`.token` · `.pt`)의 짝 · 토큰이 pt 를 앞선다(`normalize` 와 같은 규칙) · 꼴이 아니면 nil.
    @Test func scalarReadersMirrorTheStorageForm() {
        #expect(JSONValue.token("md").scalarToken == "md")
        #expect(JSONValue.token("md").scalarPt == nil)
        #expect(JSONValue.pt(12.5).scalarPt == 12.5)
        #expect(JSONValue.pt(12.5).scalarToken == nil)
        let both: JSONValue = ["token": "lg", "pt": 3]
        #expect(both.scalarToken == "lg")
        #expect(both.scalarPt == nil, "토큰이 있으면 pt 는 읽지 않는다")
        #expect(JSONValue.string("text").scalarToken == nil)
        #expect(JSONValue.bool(true).scalarPt == nil)
        #expect((["token": 4] as JSONValue).scalarToken == nil, "토큰 이름이 글자가 아니다")
    }

    /// 칸 하나 바꾸기 — Codable 왕복 · 없는 칸은 거부.
    @Test func editSetsExactlyThatField() throws {
        struct S: Codable, Equatable { var gap: Int; var on: Bool }
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "on", to: false) == S(gap: 1, on: false))
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "gap", to: 7) == S(gap: 7, on: true))
        #expect(throws: StyleEditError.self) { try StyleEdit.setting(S(gap: 1, on: true), "nope", to: 1) }
    }
}
