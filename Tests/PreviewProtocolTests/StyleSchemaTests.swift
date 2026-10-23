import DesignTokens
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// Style 서술 — 프로젝트가 내는 데이터(칸 · 절 · 이름(선택) · 기본값)로 안 파일의 값을 잰다(`normalize`). 서술은 JSON 으로 오가도 같다(`hello` 에 실린다).
// 칸 하나 바꾸기(`StyleEdit` — 프로젝트의 Style 타입에 Codable 왕복)도 여기서 잰다. 쓰임 셈은 엔진의 몫이라 엔진 쪽 시험이 잰다.
// 문구(`StyleText`) — 선택 목록의 줄 꼴 · 저장 꼴(공백 · 최대 길이 · 빈 글 = 기본 글) · 관대한 읽개 · 옛 상대 둘(문구를 모르는 엔진은 판정이 막는다 ⟂ 호스트는 서술 밖 칸으로 뺀다) · 글자 엣지(자소 묶음 · 한 줄 라벨) · 안 파일의 값.
// 자리(`StyleSlot`) — 선택 목록의 줄 꼴 · 저장 꼴(빈 글 ⟂ 받는 종류의 참조 · 빈 글은 값) · 이름 겹침 · 관대한 읽개 · 참조 풀기 · 옛 상대 둘 · 안 파일의 값.

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

    /// 절의 효과 선언 — 선택 칸(없으면 빈 목록 · 빈 목록이면 줄에 쓰지 않는다) · 선언 차례 그대로 왕복 · 모르는 낱말도 글자 그대로 들고 되쓴다 ·
    /// 옛 이니셜라이저는 선언 없는 절 · 효과는 절의 같음에 든다.
    @Test func elementEffectsAreOptionalAndOpen() throws {
        let card = StyleElement(id: "card", label: "카드", snapPrefix: "garden.card", effects: [.motion, .glass, StyleEffect(rawValue: "ripple")])
        let schema = StyleSchema(screen: "garden", elements: [card, Self.pot], fields: [StyleField(name: "cardShown", kind: .bool, element: card)], defaults: ["cardShown": true])
        let data = try JSONEncoder().encode(schema)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let els = try #require(obj["elements"] as? [[String: Any]])
        #expect(els[0]["effects"] as? [String] == ["motion", "glass", "ripple"], "선언 차례 · 글자 그대로")
        #expect(els[1]["effects"] == nil, "선언 없는 절은 칸을 쓰지 않는다")
        let back = try JSONDecoder().decode(StyleSchema.self, from: data)
        #expect(back == schema)
        #expect(back.elements[0].effects.contains(StyleEffect(rawValue: "ripple")) && !StyleEffect.known.contains(StyleEffect(rawValue: "ripple")))
        #expect(back.fields[0].element.effects == card.effects, "칸의 절도 효과를 든다")
        #expect(Self.pot.effects == [], "옛 이니셜라이저 = 선언 없음")
        #expect(StyleElement(id: "pot", label: "화분", snapPrefix: "plants.pot", effects: []) == Self.pot)
        #expect(card != StyleElement(id: "card", label: "카드", snapPrefix: "garden.card"), "효과는 같음에 든다")
        // 옛 줄(효과 칸 없음)은 빈 목록 · 빈 배열 줄도 빈 목록(되쓰면 칸이 없다)
        let empty = Data(#"{"id":"q","label":"q","snapPrefix":"","effects":[]}"#.utf8)
        let e = try JSONDecoder().decode(StyleElement.self, from: empty)
        #expect(e.effects == [])
        let re = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        #expect(re["effects"] == nil && re.count == 3)
        // 낱말이 글자가 아니면 거부
        let bad = Data(#"{"id":"q","label":"q","snapPrefix":"","effects":[1]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StyleElement.self, from: bad) }
        #expect(StyleEffect.known.map(\.rawValue) == ["glass", "material", "blur", "shadow", "motion"])
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
        #expect(throws: (any Error).self, "최대 길이 음수") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q","maxLength":-3}]"#)) }
        #expect(try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q","maxLength":1}]"#)).texts.first?.maxLength == 1, "1 은 선다")
    }

    /// 문구의 저장 꼴 — 앞뒤 공백을 걷고 · 최대 길이(자소 묶음 글자 수)에서 자르고(자른 끝 공백도) · 비면 기본 글(기본 글도 같은 꼴) ·
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
        let twin = StyleSchema(screen: "x", elements: [Self.pot], fields: [],
                               texts: [StyleText(name: "potTitle", element: Self.pot), StyleText(name: "potTitle", element: Self.pot, maxLength: 3)],
                               defaults: ["potTitle": "화분"])
        #expect(throws: StyleTextError.self, "문구끼리 겹치는 이름") { try twin.normalize([:]) }
        // 한 번 잰 값을 다시 재도 같다(엔진이 쓴 안 파일을 다시 열어도 바이트가 그대로)
        #expect(try s.normalize(got) == got)
    }

    /// 글 하나의 저장 꼴 엣지 — 최대 길이 1 · 결합 문자(조합형 한글 · 결합 악센트)는 한 글자 · 공백에 붙은 결합 문자는 공백과 함께 걷힌다 ·
    /// 기본 길이(200) 넘침 · 한 줄 라벨(줄바꿈과 그 둘레 공백은 공백 하나 · 줄바꿈만 든 글은 빈 글).
    @Test func normalizedHandlesGraphemesAndLineBreaks() {
        let one = StyleText(name: "t", element: Self.pot, maxLength: 1)
        #expect(one.normalized("가나") == "가")
        #expect(one.normalized(" 👩‍👩‍👧‍👦x") == "👩‍👩‍👧‍👦", "이모지 묶음은 한 글자")
        let three = StyleText(name: "t", element: Self.pot, maxLength: 3)
        let jamo = "\u{1112}\u{1161}\u{11AB}"   // 조합형 「한」 — 자소 셋이 한 글자
        #expect(three.normalized(jamo + jamo + jamo + jamo) == jamo + jamo + jamo)
        #expect(three.normalized("e\u{301}e\u{301}e\u{301}e\u{301}") == "e\u{301}e\u{301}e\u{301}", "결합 악센트는 앞 글자와 한 글자")
        #expect(three.normalized(" \u{301}a") == "a", "공백에 붙은 결합 문자는 맨 앞에 남지 않는다")
        #expect(three.normalized("a \u{301}") == "a", "끝도 같다")
        let plain = StyleText(name: "t", element: Self.pot)
        #expect(plain.maxLength == StyleText.defaultMaxLength)
        let long = String(repeating: "가", count: StyleText.defaultMaxLength + 50)
        #expect(plain.normalized(long) == String(repeating: "가", count: StyleText.defaultMaxLength), "기본 길이에서 자른다")
        #expect(plain.normalized("첫 줄 \n\n  둘째 줄\r\n셋째\u{2028}넷") == "첫 줄 둘째 줄 셋째 넷", "줄바꿈은 공백 하나")
        #expect(plain.normalized("가  나") == "가  나", "줄바꿈이 아닌 글 속 공백은 그대로")
        #expect(plain.normalized("\n\r\n \u{2028}") == nil, "줄바꿈만 든 글은 빈 글")
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

    /// 옛 상대 둘 — (1) 문구를 모르는 엔진(프로토콜 판 3 이하)은 판정이 막는다: 문구를 싣는 판 4 호스트의 hello 를 몸을 풀기 전에 `hostNewer` 로 거절한다
    /// (문구 값이 조용히 빠진 채 그려지는 짝은 와이어에서 서지 않는다). 서술 디코더가 모르는 키를 넘기는 것은 읽기 방어일 뿐이다.
    /// (2) 새 엔진이 문구 값을 실어 보내도 문구를 모르는 호스트(서술에 문구가 없다)는 서술 밖 칸으로 빼고 깨지지 않는다 · 그 호스트의 Style 타입도 모르는 칸을 넘긴다
    /// (화면은 기본 글 — 그 호스트에겐 문구 칸이 없으니 조절판에도 서지 않는다).
    @Test func olderEnginesAreRefusedAndOlderHostsDropTexts() throws {
        // (1) 문구를 모르는 엔진 — 판정이 막는다
        #expect(PreviewProtocolVersion.current >= 4, "문구 목록은 프로토콜 판 4 부터의 꼴")
        let hello = Message.hello(Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "h",
                                        screens: [ScreenInfo(name: "home", states: ["n"], style: Self.texted)]))
        let greeting = try ProtocolDialect.current.encode(hello)
        let engine3 = ProtocolJudge(version: 3, dialects: [])
        #expect(throws: ProtocolMismatch.hostNewer(host: PreviewProtocolVersion.current, engine: 3), "판 3 엔진은 판 4 이상 호스트를 거절한다") { try engine3.dialect(greeting: greeting) }
        // 읽기 방어 — 서술 디코더는 모르는 키를 넘긴다(판정을 거친 상대의 뜻밖의 칸을 잃지 않고 읽을 뿐 · 판을 올리지 않아도 된다는 뜻이 아니다)
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.texted)) as? [String: Any])
        wire["future"] = ["shape": 1]
        #expect(try JSONDecoder().decode(StyleSchema.self, from: JSONSerialization.data(withJSONObject: wire)) == Self.texted)

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

    // MARK: 자리

    static let slotted = StyleSchema(
        screen: "home", elements: [pot, color],
        fields: StyleField.list([("potOn", .bool)], elements: [pot, color]),
        texts: [StyleText(name: "potTitle", element: pot)],
        slots: [StyleSlot(name: "potPicture", element: pot, snap: "plants.pot.picture", label: "그림"),
                StyleSlot(name: "potBadge", element: pot, kinds: ["isomodel", "isoscene"])],
        defaults: ["potOn": true, "potTitle": "화분", "potBadge": "isoscene:meadow"])

    /// 자리 목록은 선택 칸 — 비면 줄에 쓰지 않고 · 없으면 빈 목록 · 있으면 왕복(종류가 없으면 기본 종류 · 표식 · 이름은 선택) ·
    /// 모르는 절 · 칸 · 문구 · 다른 자리와 겹치는 이름 · 빈 종류 목록은 거부.
    @Test func slotsAreAnOptionalListOnTheWire() throws {
        let plain = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.texted)) as? [String: Any])
        #expect(plain["slots"] == nil, "자리가 없으면 줄에 쓰지 않는다 — 자리를 모르는 상대와 같은 줄")
        #expect(Self.texted.slots.isEmpty)

        let data = try JSONEncoder().encode(Self.slotted)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let slots = try #require(obj["slots"] as? [[String: Any]])
        #expect(slots.map { $0["name"] as? String } == ["potPicture", "potBadge"])
        #expect(slots.map { $0["element"] as? String } == ["pot", "pot"])
        #expect(slots.first?["snap"] as? String == "plants.pot.picture" && slots.last?["snap"] == nil, "없는 표식은 쓰지 않는다")
        #expect(slots.map { $0["kinds"] as? [String] } == [["isomodel"], ["isomodel", "isoscene"]])
        #expect(try JSONDecoder().decode(StyleSchema.self, from: data) == Self.slotted)

        func schema(_ slots: String, texts: String = "[]") -> Data {
            Data(#"{"screen":"x","elements":[{"id":"q","label":"q","snapPrefix":""}],"fields":[{"name":"a","kind":"bool","element":"q"}],"texts":\#(texts),"slots":\#(slots),"defaults":{}}"#.utf8)
        }
        let bare = try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"q"}]"#))
        #expect(bare.slots.first?.kinds == StyleSlot.defaultKinds && bare.slots.first?.snap == nil && bare.slots.first?.label == nil)
        #expect(throws: (any Error).self, "모르는 절") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"z"}]"#)) }
        #expect(throws: (any Error).self, "칸과 겹침") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"a","element":"q"}]"#)) }
        #expect(throws: (any Error).self, "문구와 겹침") {
            try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"t","element":"q"}]"#, texts: #"[{"name":"t","element":"q"}]"#))
        }
        #expect(throws: (any Error).self, "자리끼리 겹침") {
            try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"q"},{"name":"p","element":"q"}]"#))
        }
        #expect(throws: (any Error).self, "받는 종류가 없다") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"q","kinds":[]}]"#)) }
        for bad in [#"[""]"#, #"["a:b"]"#, #"["모델"]"#, #"["iso model"]"#] {
            #expect(throws: (any Error).self, "종류 낱말의 꼴: \(bad)") { try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"q","kinds":"# + bad + "}]")) }
        }
        #expect(try JSONDecoder().decode(StyleSchema.self, from: schema(#"[{"name":"p","element":"q","kinds":["Iso_Model-2"]}]"#)).slots.first?.kinds == ["Iso_Model-2"])
    }

    /// 자리의 저장 꼴 — 빈 글(원래 이미지)과 받는 종류의 참조는 그대로 · 없으면 기본 값(없으면 빈 글) · **빈 글은 기본 값으로 돌아가지 않는다** ·
    /// 받지 않는 종류의 참조는 빈 글(원래 이미지 — 문구의 강제 정규화와 같은 뜻) · 글자 아님 · 꼴 아님 · 경로 글자는 `StyleSlotError` · 이름 겹침은 `nameTaken` · 다시 재도 같다.
    @Test func normalizeKeepsSlotReferencesAndRefusesTheRest() throws {
        let s = Self.slotted
        let got = try s.normalize(["potPicture": "isomodel:fern", "stale": "isomodel:x"])
        #expect(got == ["potOn": true, "potTitle": "화분", "potPicture": "isomodel:fern", "potBadge": "isoscene:meadow"])
        #expect(try s.normalize([:])["potPicture"] == "", "기본 값이 없는 자리 = 빈 글(원래 이미지)")
        #expect(try s.normalize(["potBadge": ""])["potBadge"] == "", "빈 글은 값이다 — 기본 값으로 돌아가지 않는다")
        #expect(try s.normalize(["potBadge": "isomodel:fern"])["potBadge"] == "isomodel:fern")
        #expect(try s.normalize(got) == got, "다시 재도 같다")
        #expect(throws: StyleSlotError.self, "글자 아님") { try s.normalize(["potPicture": 3]) }
        #expect(throws: StyleSlotError.self, "꼴 아님") { try s.normalize(["potPicture": "fern"]) }
        #expect(throws: StyleSlotError.self, "이름 빔") { try s.normalize(["potPicture": "isomodel:"]) }
        #expect(throws: StyleSlotError.self, "종류 빔") { try s.normalize(["potPicture": ":fern"]) }
        #expect(try s.normalize(["potPicture": "photo:fern"])["potPicture"] == "", "받지 않는 종류 = 원래 이미지(안 파일이 통째로 막히지 않는다)")
        #expect(try s.normalize(["potPicture": "isoscene:meadow"])["potPicture"] == "", "받지 않는 종류(다른 자리는 받는다)")
        #expect(try s.normalize(["potPicture": "IsoModel:fern"])["potPicture"] == "", "종류는 대소문자를 가린다")
        for bad in ["isomodel:../fern", "isomodel:a/b", "isomodel:a\\b", "isomodel:..", "isomodel:.", "isomodel:.hidden", "isomodel: fern", "isomodel:fern ",
                    "isomodel:a\nb", "isomodel:a\u{202E}b", "isomodel:a\u{200B}b"] {
            #expect(throws: StyleSlotError.self, "경로 글자 · 숨김 · 공백 · 제어 · 서식 문자: \(bad)") { try s.normalize(["potPicture": .string(bad)]) }
        }
        #expect(try s.normalize(["potPicture": "isomodel:fern..2"])["potPicture"] == "isomodel:fern..2", "이름 안의 `..` 는 경로가 아니다")
        do { _ = try s.normalize(["potPicture": "isomodel:.."]); Issue.record("거부해야 한다") } catch let e as StyleSlotError {
            guard case .badReference("home", "potPicture", "isomodel:..") = e else { Issue.record("꼴 아님으로 갈라야 한다: \(e)"); return }
        }
        let otherDefault = StyleSchema(screen: "x", elements: [Self.pot], fields: [], texts: [],
                                       slots: [StyleSlot(name: "potPicture", element: Self.pot)], defaults: ["potPicture": "photo:x"])
        #expect(try otherDefault.normalize([:])["potPicture"] == "", "기본 값도 같은 정규화")
        let badDefault = StyleSchema(screen: "x", elements: [Self.pot], fields: [], texts: [],
                                     slots: [StyleSlot(name: "potPicture", element: Self.pot)], defaults: ["potPicture": "isomodel:a/b"])
        #expect(throws: StyleSlotError.self, "기본 값도 잰다") { try badDefault.normalize([:]) }
        let clash = StyleSchema(screen: "x", elements: [Self.pot], fields: StyleField.list([("potOn", .bool)], elements: [Self.pot]), texts: [],
                                slots: [StyleSlot(name: "potOn", element: Self.pot)], defaults: ["potOn": true])
        #expect(throws: StyleSlotError.self, "칸과 겹치는 자리") { try clash.normalize([:]) }
        let clashText = StyleSchema(screen: "x", elements: [Self.pot], fields: [], texts: [StyleText(name: "p", element: Self.pot)],
                                    slots: [StyleSlot(name: "p", element: Self.pot)], defaults: ["p": "글"])
        #expect(throws: StyleSlotError.self, "문구와 겹치는 자리") { try clashText.normalize([:]) }
    }

    /// 사전으로 다루는 화면 코드의 읽개 — 참조 그대로 · 없으면 기본 값 · 글자 아님 · 꼴 아님 · 받지 않는 종류는 빈 글(원래 이미지) · 서술에 없는 자리는 nil ·
    /// 참조 풀기(`Reference.parse`)는 종류 · 이름으로 가른다.
    @Test func slotReaderIsLenientAndReferencesParse() {
        let s = Self.slotted
        #expect(s.slot("potPicture", in: ["potPicture": "isomodel:fern"]) == "isomodel:fern")
        #expect(s.slot("potPicture", in: [:]) == "")
        #expect(s.slot("potBadge", in: nil) == "isoscene:meadow", "값이 없으면 기본 값")
        #expect(s.slot("potBadge", in: ["potBadge": ""]) == "", "빈 글은 값이다")
        #expect(s.slot("potPicture", in: ["potPicture": 7]) == "", "글자가 아니면 원래 이미지")
        #expect(s.slot("potPicture", in: ["potPicture": "photo:x"]) == "", "받지 않는 종류면 원래 이미지")
        #expect(s.slot("potTitle", in: [:]) == nil, "문구는 자리가 아니다")
        #expect(s.slot("nope", in: [:]) == nil)

        #expect(StyleSlot.Reference.parse("isomodel:fern") == StyleSlot.Reference(kind: "isomodel", name: "fern"))
        #expect(StyleSlot.Reference.parse("isomodel:fern:two")?.name == "fern:two", "첫 `:` 에서 가른다")
        #expect(StyleSlot.Reference.parse("isomodel:큰 화분")?.name == "큰 화분", "이름은 서가의 파일 이름 — 공백 · 한글을 받는다")
        #expect(StyleSlot.Reference(kind: "isomodel", name: "fern").text == "isomodel:fern")
        #expect(StyleSlot.Reference.parse("isomodel:v1..final")?.name == "v1..final", "이름 안의 `..` 는 받는다")
        for bad in ["", "fern", ":fern", "isomodel:", "iso model:fern", "제목:글", "isomodel:../x", "isomodel:a/b", "isomodel:a\tb",
                    "isomodel:..", "isomodel:.git", "isomodel:\u{202E}lmth", "isomodel:fern\u{FEFF}", "isomodel: x"] {
            #expect(StyleSlot.Reference.parse(bad) == nil, "꼴 아님: \(bad)")
        }
    }

    /// 옛 상대 둘 — (1) 자리를 모르는 엔진(프로토콜 판 4 이하)은 판정이 막는다(판 5 호스트를 `hostNewer`).
    /// (2) 새 엔진이 자리 값을 실어 보내도 자리를 모르는 호스트(서술에 자리가 없다)는 서술 밖 칸으로 빼고 깨지지 않는다(화면은 원래 이미지).
    @Test func olderEnginesAreRefusedAndOlderHostsDropSlots() throws {
        #expect(PreviewProtocolVersion.current >= 5, "자리 목록은 프로토콜 판 5 부터의 꼴")
        let hello = Message.hello(Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "h",
                                        screens: [ScreenInfo(name: "home", states: ["n"], style: Self.slotted)]))
        let greeting = try ProtocolDialect.current.encode(hello)
        let engine4 = ProtocolJudge(version: 4, dialects: [])
        #expect(throws: ProtocolMismatch.hostNewer(host: PreviewProtocolVersion.current, engine: 4), "판 4 엔진은 판 5 이상의 호스트를 거절한다") { try engine4.dialect(greeting: greeting) }

        let fromNewEngine = try Self.slotted.normalize(["potPicture": "isomodel:fern"])
        #expect(try Self.texted.normalize(["potTitle": "화분"].merging(fromNewEngine) { a, _ in a })["potPicture"] == nil, "자리 값은 서술 밖 칸으로 빠진다")
        struct OldStyle: Codable, Equatable { var potOn: Bool; var potTitle: String }
        #expect(try JSONValue.object(fromNewEngine).decode(OldStyle.self) == OldStyle(potOn: true, potTitle: "화분"), "옛 Style 타입은 자리 칸을 넘긴다")
    }

    /// 안 파일의 값 — 자리는 Style 값 사전의 글자 칸 · 프로젝트의 Style 타입은 그것을 `String` 칸으로 든다(기본값 = 빈 글) ·
    /// 바이트 규칙으로 쓰고 읽어도 같은 값 · 옛 안 파일(자리 없음)은 기본 값으로 채운다 · 조절판의 바꾸기도 같은 손(`StyleEdit`).
    @Test func slotsLiveInTheDesignFileStyle() throws {
        struct HomeStyle: Codable, Equatable { var potOn = true; var potPicture = "" }
        let schema = StyleSchema(screen: "home", elements: [Self.pot], fields: StyleField.list([("potOn", .bool)], elements: [Self.pot]), texts: [],
                                 slots: [StyleSlot(name: "potPicture", element: Self.pot)], defaults: try JSONValue.dictionary(from: HomeStyle()))
        let saved = try schema.normalize(["potOn": false, "potPicture": "isomodel:fern"])
        let bytes = try DesignFile.encoder().encode(["style": saved])
        #expect(try DesignFile.decoder().decode([String: StyleValues].self, from: bytes)["style"] == saved)
        #expect(try JSONValue.object(saved).decode(HomeStyle.self) == HomeStyle(potOn: false, potPicture: "isomodel:fern"), "앱의 Style 타입이 그대로 읽는다")
        var old: [String: Any] = ["potOn": false]
        #expect(try DesignFile.fillMissingStyleKeys(&old, from: HomeStyle()) == 1)
        #expect(old["potPicture"] as? String == "", "옛 안 파일은 원래 이미지로 채운다")
        #expect(try StyleEdit.setting(HomeStyle(), "potPicture", to: "isomodel:fern") == HomeStyle(potOn: true, potPicture: "isomodel:fern"))
    }

    /// 칸 하나 바꾸기 — Codable 왕복 · 없는 칸은 거부.
    @Test func editSetsExactlyThatField() throws {
        struct S: Codable, Equatable { var gap: Int; var on: Bool }
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "on", to: false) == S(gap: 1, on: false))
        #expect(try StyleEdit.setting(S(gap: 1, on: true), "gap", to: 7) == S(gap: 7, on: true))
        #expect(throws: StyleEditError.self) { try StyleEdit.setting(S(gap: 1, on: true), "nope", to: 1) }
    }
}
