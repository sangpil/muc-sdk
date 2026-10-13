import DesignTokens
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// Style 서술 — 프로젝트가 내는 데이터(칸 · 절 · 이름(선택) · 기본값)로 안 파일의 값을 잰다(`normalize`). 서술은 JSON 으로 오가도 같다(`hello` 에 실린다).
// 칸 하나 바꾸기(`StyleEdit` — 프로젝트의 Style 타입에 Codable 왕복)도 여기서 잰다. 쓰임 셈은 엔진의 몫이라 엔진 쪽 시험이 잰다.
// 문구(`StyleText`) — 선택 목록의 줄 꼴 · 저장 꼴(공백 · 최대 길이 · 빈 글 = 기본 글) · 관대한 읽개 · 옛 상대 둘(문구를 모르는 엔진 ⟂ 호스트) · 안 파일의 값.

@Suite struct StyleSchemaTests {
    static let pot = StyleElement(id: "pot", label: "화분", snapPrefix: "plants.pot")
    static let color = StyleElement(id: "color", label: "색 역할", snapPrefix: "")
    static let schema = StyleSchema(
        screen: "home", elements: [pot, color],
        fields: StyleField.list([("potGap", .scalar(.space)), ("potSize", .scalar(.type)), ("glassColor", .color), ("potOn", .bool)], elements: [pot, color]),
        defaults: ["potGap": ["token": "md"], "potSize": ["pt": 17], "glassColor": "ink", "potOn": true])

    /// 칸 목록 — 절은 가장 긴 앞머리 · `…Color` 는 색 절 · 앞머리 없는 칸은 첫 절 · 이름은 비운다(엔진이 짓는다).
    @Test func fieldListGroupsAndLeavesNamesToTheEngine() {
        let tray = StyleElement(id: "tray", label: "받침", snapPrefix: "x.tray")
        let fields = StyleField.list([("on", .bool), ("trayOn", .bool), ("trayTitleSize", .scalar(.type)), ("glassColor", .color)], elements: [tray, Self.color])
        #expect(fields.map(\.element.id) == ["tray", "tray", "tray", "color"])
        #expect(fields.allSatisfy { $0.label == nil })
        #expect(StyleField(name: "potGap", kind: .scalar(.space), element: Self.pot, label: "간격").label == "간격", "호스트가 지은 이름은 그대로")
        #expect(StyleElement.of(snapID: "plants.pot.title", in: Self.schema.elements)?.id == "pot")
        #expect(StyleElement.of(snapID: "other", in: Self.schema.elements) == nil)
    }

    /// 칸 이름은 선택 — 줄에 없으면 nil · 있으면 그대로 왕복.
    @Test func fieldLabelIsOptionalOnTheWire() throws {
        let named = StyleSchema(screen: "x", elements: [Self.pot],
                                fields: [StyleField(name: "potGap", kind: .scalar(.space), element: Self.pot, label: "간격")], defaults: ["potGap": ["pt": 1]])
        #expect(try JSONDecoder().decode(StyleSchema.self, from: JSONEncoder().encode(named)) == named)
        let bare = Data(#"{"screen":"x","elements":[{"id":"q","label":"q","snapPrefix":""}],"fields":[{"name":"a","kind":"bool","element":"q"}],"defaults":{}}"#.utf8)
        let s = try JSONDecoder().decode(StyleSchema.self, from: bare)
        #expect(s.fields.first?.label == nil)
        let back = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        #expect(((back["fields"] as? [[String: Any]])?.first)?["label"] == nil, "없는 이름은 쓰지 않는다")
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
        // 새 칸 종류 낱말 — 스칼라 종류로 읽는다(열린 `ScaleKind` · 낱말 그대로 왕복)
        let newKind = Data(#"{"screen":"x","elements":[{"id":"q","label":"q","snapPrefix":""}],"fields":[{"name":"a","kind":"stroke","element":"q","label":"a"}],"defaults":{}}"#.utf8)
        let read = try JSONDecoder().decode(StyleSchema.self, from: newKind)
        #expect(read.fields.first?.kind == .scalar(ScaleKind(rawValue: "stroke")))
        #expect(try JSONDecoder().decode(StyleSchema.self, from: JSONEncoder().encode(read)) == read)
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

    // MARK: 문구

    static let texted = StyleSchema(
        screen: "home", elements: [pot, color],
        fields: StyleField.list([("potGap", .scalar(.space)), ("potOn", .bool)], elements: [pot, color]),
        texts: [StyleText(name: "potTitle", element: pot, label: "제목", maxLength: 6), StyleText(name: "potNote", element: pot)],
        defaults: ["potGap": ["token": "md"], "potOn": true, "potTitle": "  화분 하나  ", "potNote": ""])

    /// 문구 목록은 선택 칸 — 비면 줄에 쓰지 않고 · 없으면 빈 목록으로 읽고 · 있으면 왕복한다(최대 길이가 없으면 기본 길이) ·
    /// 모르는 절 · 칸 · 다른 문구와 겹치는 이름 · 1 보다 작은 최대 길이는 거부.
    @Test func textsAreAnOptionalListOnTheWire() throws {
        let plain = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.schema)) as? [String: Any])
        #expect(plain["texts"] == nil, "문구가 없으면 줄에 쓰지 않는다 — 문구를 모르는 상대와 같은 줄")
        #expect(Self.schema.texts.isEmpty)

        let data = try JSONEncoder().encode(Self.texted)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let texts = try #require(obj["texts"] as? [[String: Any]])
        #expect(texts.map { $0["name"] as? String } == ["potTitle", "potNote"])
        #expect(texts.map { $0["element"] as? String } == ["pot", "pot"])
        #expect(texts.map { $0["maxLength"] as? Int } == [6, StyleText.defaultMaxLength])
        #expect(texts.last?["label"] == nil, "없는 이름은 쓰지 않는다")
        #expect(try JSONDecoder().decode(StyleSchema.self, from: data) == Self.texted)

        func schema(_ texts: String) -> Data {
            Data(#"{"screen":"x","elements":[{"id":"q","label":"q","snapPrefix":""}],"fields":[{"name":"a","kind":"bool","element":"q"}],"texts":\#(texts),"defaults":{}}"#.utf8)
        }
        let bare = try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q"}]"#))
        #expect(bare.texts.first?.maxLength == StyleText.defaultMaxLength && bare.texts.first?.label == nil)
        #expect(throws: (any Error).self, "모르는 절") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"z"}]"#)) }
        #expect(throws: (any Error).self, "칸과 겹침") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"a","element":"q"}]"#)) }
        #expect(throws: (any Error).self, "문구끼리 겹침") {
            try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q"},{"name":"t","element":"q"}]"#))
        }
        #expect(throws: (any Error).self, "최대 길이 0") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q","maxLength":0}]"#)) }
        #expect(StyleText(name: "t", element: Self.pot, maxLength: 0).maxLength == 1, "코드로 지은 문구의 최대 길이는 1 이상으로 선다")
    }

    /// 문구의 저장 꼴 — 앞뒤 공백 · 줄바꿈을 걷고 · 최대 길이(자소 묶음 글자 수)에서 자르고(자른 끝 공백도) · 비면 기본 글(기본 글도 같은 꼴) ·
    /// 없으면 기본 글 · 글자가 아니면 거부 · 칸과 겹치는 이름은 거부.
    @Test func normalizeTrimsCapsAndFallsBackToTheDefault() throws {
        let s = Self.texted
        let got = try s.normalize(["potTitle": "\n 새 화분 \t", "potNote": "메모", "stale": "x"])
        #expect(got == ["potGap": ["token": "md"], "potOn": true, "potTitle": "새 화분", "potNote": "메모"])
        #expect(try s.normalize(["potTitle": "가나다라마바사아"])["potTitle"] == "가나다라마바", "6 글자에서 자른다")
        #expect(try s.normalize(["potTitle": "👩‍👩‍👧‍👦🌱 가나다라"])["potTitle"] == "👩‍👩‍👧‍👦🌱 가나다", "글자 수는 자소 묶음으로 센다")
        #expect(try s.normalize(["potTitle": "가나다라마 바"])["potTitle"] == "가나다라마", "자른 끝의 공백도 걷는다")
        #expect(try s.normalize(["potTitle": "   "])["potTitle"] == "화분 하나", "빈 글 = 기본 글(기본 글도 저장 꼴로)")
        #expect(try s.normalize([:])["potTitle"] == "화분 하나", "없는 문구 = 기본 글")
        #expect(try s.normalize([:])["potNote"] == "", "기본 글이 빈 글이면 빈 글")
        #expect(throws: StyleTextError.self, "문구에 숫자") { try s.normalize(["potTitle": 3]) }
        let noDefault = StyleSchema(screen: "x", elements: [Self.pot], fields: [], texts: [StyleText(name: "potTitle", element: Self.pot)], defaults: [:])
        #expect(throws: StyleSchemaError.self, "값도 기본 글도 없다") { try noDefault.normalize([:]) }
        #expect(throws: StyleSchemaError.self, "빈 글인데 기본 글이 없다") { try noDefault.normalize(["potTitle": " "]) }
        let clash = StyleSchema(screen: "x", elements: [Self.pot], fields: StyleField.list([("potOn", .bool)], elements: [Self.pot]),
                                texts: [StyleText(name: "potOn", element: Self.pot)], defaults: ["potOn": true])
        #expect(throws: StyleTextError.self, "칸과 겹치는 문구") { try clash.normalize([:]) }
        // 한 번 잰 값을 다시 재도 같다(엔진이 쓴 안 파일을 다시 열어도 바이트가 그대로)
        #expect(try s.normalize(got) == got)
    }

    /// 사전으로 다루는 화면 코드의 읽개 — 저장 꼴 · 빈 글과 글자 아닌 값은 기본 글(관대한 읽기) · 서술에 없는 문구는 nil.
    @Test func textReaderIsLenient() {
        let s = Self.texted
        #expect(s.text("potTitle", in: ["potTitle": " 새 화분 "]) == "새 화분")
        #expect(s.text("potTitle", in: ["potTitle": ""]) == "화분 하나")
        #expect(s.text("potTitle", in: ["potTitle": 7]) == "화분 하나", "글자가 아니면 기본 글로 읽는다")
        #expect(s.text("potTitle", in: nil) == "화분 하나", "값이 없으면(nil = 서술의 기본값) 기본 글")
        #expect(s.text("potGap", in: [:]) == nil, "칸은 문구가 아니다")
        #expect(s.text("nope", in: [:]) == nil)
    }

    /// 옛 상대 둘 — (1) 문구를 모르는 읽개(1.0 의 서술 디코더는 모르는 키를 넘긴다 — `texts` 를 걷고 읽은 것과 같다)가 잰 값에는 문구가 없고,
    /// 그 값을 받은 새 호스트는 기본 글로 그린다(뜻이 틀리지 않는다 — 디자이너가 바꾼 적 없는 화면과 같다).
    /// (2) 새 엔진이 문구 값을 실어 보내도 문구를 모르는 호스트(서술에 문구가 없다)는 서술 밖 칸으로 빼고 깨지지 않는다 · 그 호스트의 Style 타입도 모르는 칸을 넘긴다.
    @Test func olderPeersIgnoreTextsWithoutChangingTheMeaning() throws {
        // (1) 문구를 모르는 엔진
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.texted)) as? [String: Any])
        wire["future"] = ["shape": 1]   // 모르는 키를 넘기는 것이 옛 읽개가 문구를 넘기는 길이다
        let withFuture = try JSONDecoder().decode(StyleSchema.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(withFuture == Self.texted, "서술 디코더는 모르는 키를 넘긴다")
        wire.removeValue(forKey: "texts")
        let oldView = try JSONDecoder().decode(StyleSchema.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(oldView.texts.isEmpty && oldView.fields == Self.texted.fields)
        let sentByOld = try oldView.normalize(["potGap": ["pt": 4], "potTitle": "바꾼 제목"])
        #expect(sentByOld["potTitle"] == nil, "옛 엔진은 문구 값을 싣지 못한다")
        let drawn = try Self.texted.normalize(sentByOld)
        #expect(drawn["potTitle"] == "화분 하나" && drawn["potGap"] == ["pt": 4], "새 호스트는 기본 글로 그리고 칸 값은 그대로")
        #expect(Self.texted.text("potTitle", in: sentByOld) == "화분 하나")

        // (2) 문구를 모르는 호스트 — 서술에 문구가 없다
        let oldHost = StyleSchema(screen: "home", elements: [Self.pot, Self.color],
                                  fields: StyleField.list([("potGap", .scalar(.space)), ("potOn", .bool)], elements: [Self.pot, Self.color]),
                                  defaults: ["potGap": ["token": "md"], "potOn": true])
        let fromNewEngine = try Self.texted.normalize(["potTitle": "바꾼 제목"])
        #expect(try oldHost.normalize(fromNewEngine) == ["potGap": ["token": "md"], "potOn": true], "문구 값은 서술 밖 칸으로 빠진다")
        struct OldStyle: Codable, Equatable { var potGap: JSONValue; var potOn: Bool }
        #expect(try JSONValue.object(fromNewEngine).decode(OldStyle.self) == OldStyle(potGap: ["token": "md"], potOn: true), "옛 Style 타입은 문구 칸을 넘긴다")
    }

    /// 안 파일의 값 — 문구는 Style 값 사전의 글자 칸 · 프로젝트의 Style 타입은 그것을 `String` 칸으로 든다(기본값 = 기본 글 · 서술의 `defaults` 도 그 타입에서) ·
    /// 바이트 규칙(`DesignFile.encoder`)으로 쓰고 읽어도 같은 값 · 옛 안 파일(문구 없음)은 기본 글로 채운다 · 조절판의 칸 하나 바꾸기도 같은 손(`StyleEdit`).
    @Test func textsLiveInTheDesignFileStyle() throws {
        struct HomeStyle: Codable, Equatable { var potOn = true; var potTitle = "화분 하나" }
        let schema = StyleSchema(screen: "home", elements: [Self.pot], fields: StyleField.list([("potOn", .bool)], elements: [Self.pot]),
                                 texts: [StyleText(name: "potTitle", element: Self.pot, maxLength: 12)], defaults: try JSONValue.dictionary(from: HomeStyle()))
        let saved = try schema.normalize(["potOn": false, "potTitle": "  오늘의 화분  "])
        let bytes = try DesignFile.encoder().encode(["style": saved])
        let read = try DesignFile.decoder().decode([String: StyleValues].self, from: bytes)["style"]
        #expect(read == saved && saved["potTitle"] == "오늘의 화분")
        #expect(try JSONValue.object(saved).decode(HomeStyle.self) == HomeStyle(potOn: false, potTitle: "오늘의 화분"), "앱의 Style 타입이 그대로 읽는다")
        var old: [String: Any] = ["potOn": false]
        #expect(try DesignFile.fillMissingStyleKeys(&old, from: HomeStyle()) == 1)
        #expect(old["potTitle"] as? String == "화분 하나", "옛 안 파일은 기본 글로 채운다")
        #expect(try StyleEdit.setting(HomeStyle(), "potTitle", to: "새 글") == HomeStyle(potOn: true, potTitle: "새 글"))
    }

    /// 칸 하나 바꾸기 — Codable 왕복 · 없는 칸은 거부.
    @Test func editSetsExactlyThatField() throws {
        struct S: Codable, Equatable { var gap: Int; var on: Bool }
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "on", to: false) == S(gap: 1, on: false))
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "gap", to: 7) == S(gap: 7, on: true))
        #expect(throws: StyleEditError.self) { try StyleEdit.setting(S(gap: 1, on: true), "nope", to: 1) }
    }
}
