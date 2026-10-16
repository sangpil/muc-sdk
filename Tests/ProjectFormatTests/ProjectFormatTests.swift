import Foundation
import ProjectFormat
import TestScratch
import Testing

// SDK 의 순수한 규칙 — 판 읽개 · UUID 규약 · 안 파일의 머리와 값 채우기 · 배선 고르기 · 구성요소의 관대한 읽기 · 낱말.
// 소비자(엔진 · 빌더 코어 · 프로젝트)의 시험은 이 값을 **쓰는** 자리를 재고, 여기는 값 자체를 잰다.

@Suite struct FormatStampTests {
    @Test func readsTheTopLevelInteger() {
        #expect(FormatStamp.version(Data(#"{"version": 4, "schema": {}}"#.utf8)) == 4)
        #expect(FormatStamp.integer("schema", in: Data(#"{"schema": 2}"#.utf8)) == 2)
        #expect(FormatStamp.version(Data(#"{"version": 3.0}"#.utf8)) == 3)
    }

    /// 판이 아닌 것은 판으로 읽지 않는다 — 참/거짓(1 로 새지 않게) · 소수 · 글자 · 없는 칸 · JSON 아님 · 맨 위가 배열.
    @Test func refusesWhatIsNotAnInteger() {
        for text in [#"{"version": true}"#, #"{"version": 2.5}"#, #"{"version": "3"}"#, #"{"name": "x"}"#, "not json", "[1]", #"{"version": 1e300}"#] {
            #expect(FormatStamp.version(Data(text.utf8)) == nil, "\(text)")
        }
    }
}

@Suite struct IsoDataIDsTests {
    /// RFC 4122 부록의 v5 검산값(DNS 이름공간 · www.example.com) — 해시 · 비트 자리가 표준 그대로다.
    @Test func uuid5MatchesTheRFCVector() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        #expect(IsoDataIDs.uuid5(namespace: dns, name: "www.example.com") == UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2"))
    }

    /// 규약의 검산값 — 엔진(데이터 도구)과 프로젝트(코어의 앉히기)가 같은 바이트를 내는 근거.
    @Test func recordUUIDIsTheContractValue() {
        let id = IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: "watering-1")
        #expect(id.uuidString.lowercased() == "28241eae-2497-50f0-b848-aa5eab203910")
        #expect(id == IsoDataIDs.uuid5(namespace: IsoDataIDs.uuid5(namespace: IsoDataIDs.urlNamespace, name: "com.makeusclever.isodata/sample"), name: "Watering/watering-1"))
        #expect(IsoDataIDs.defaultNamespace == "com.makeusclever.isodata")
        #expect(id != IsoDataIDs.uuid(schema: "sample", entity: "Pot", id: "watering-1"))
        #expect(id != IsoDataIDs.uuid(schema: "other", entity: "Watering", id: "watering-1"))
    }

    @Test func namespaceIsTheContractValue() {
        #expect(IsoDataIDs.namespace(schema: "sample").uuidString.lowercased() == "36cdee70-912d-59a8-a0e3-8a12914dd8d0")
    }

    /// 스키마가 적은 머리(`idNamespace`) — 그 머리로 해시한다(앉은 행의 UUID 를 지키는 길) · 없으면 기본 머리 · 엔티티의 이름 칸(`uuidKey`)을 쓴다.
    @Test func theSchemaNamespaceOverridesTheDefault() {
        let fixed = IsoDataIDs.uuid(namespace: "com.example.rows", schema: "sample", entity: "Watering", id: "watering-1")
        #expect(fixed.uuidString.lowercased() == "511f582f-4a12-5b51-8be1-3e67485b5e22")
        #expect(IsoDataIDs.uuid(namespace: nil, schema: "sample", entity: "Watering", id: "watering-1") == IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: "watering-1"))
        var schema = DataSchema(name: "sample")
        schema.idNamespace = "com.example.rows"
        #expect(IsoDataIDs.uuid(in: schema, entity: DataEntity(name: "Drip", uuidName: "Watering"), id: "watering-1") == fixed)
        schema.idNamespace = nil
        #expect(IsoDataIDs.uuid(in: schema, entity: DataEntity(name: "Watering"), id: "watering-1") != fixed)
    }

    /// UUID 꼴 id 는 해시하지 않고 그대로(대소문자 무관 · 이름공간을 타지 않는다) · UUID 꼴이 아니면(하이픈 없는 32자 · 접두 붙은 꼴) 해시한다.
    @Test func uuidShapedIDsPassThrough() {
        let upper = "28241EAE-2497-50F0-B848-AA5EAB203910"
        let got = IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: upper)
        #expect(got.uuidString.lowercased() == upper.lowercased())
        #expect(IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: upper.lowercased()) == got)
        #expect(IsoDataIDs.uuid(schema: "other", entity: "Pot", id: upper) == got)
        let bare = "28241eae249750f0b848aa5eab203910"
        #expect(IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: bare) == IsoDataIDs.uuid5(namespace: IsoDataIDs.namespace(schema: "sample"), name: "Watering/\(bare)"))
        #expect(IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: "watering-\(upper)") != got)
    }
}

@Suite struct FormatVersionTests {
    /// 데이터의 최소 판 — 모델 절이 있을 때만 모델 판.
    @Test func isoDataWritesTheLowestThatHoldsIt() {
        #expect(IsoDataFormat.minimumVersion(hasModel: false) == IsoDataFormat.life)
        #expect(IsoDataFormat.minimumVersion(hasModel: true) == IsoDataFormat.model)
        #expect(IsoDataFormat.newest >= IsoDataFormat.model)
    }

    /// 판 범위 한 벌 — 옛 상수와 같은 값 · 쓰는 바닥은 읽는 범위 안(업그레이드가 쓰는 판의 바닥 · 최신이 아니다).
    @Test func versionsAreTheConstants() {
        #expect(IsoDataFormat.versions == FormatVersions(oldest: 1, newest: IsoDataFormat.newest, writeFloor: IsoDataFormat.life, stampKey: "version"))
        #expect(DesignFormat.versions.newest == DesignFormat.version && IAFormat.versions.newest == IAFormat.version)
        for v in [IsoDataFormat.versions, DesignFormat.versions, IAFormat.versions] {
            #expect(v.oldest <= v.writeFloor && v.writeFloor <= v.newest)
            #expect(UpgradeChain(versions: v, steps: []).newest == v.newest)
        }
    }
}

@Suite struct SDKVersionTests {
    /// SDK 판 — 세 마디 정수(주.부.수). 정본 문서의 판 칸과의 맞대기는 `SDKDocumentTests` 의 몫이다.
    @Test func isMajorMinorPatch() {
        let parts = SDKVersion.current.split(separator: ".")
        #expect(parts.count == 3 && parts.allSatisfy { Int($0) != nil }, "주.부.수 — \(SDKVersion.current)")
    }
}

@Suite struct DesignFileTests {
    private func folder() throws -> URL {
        let root = TestScratch.location("design-file")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plants"), withIntermediateDirectories: true)
        return root
    }

    @Test func layoutAndNames() throws {
        let root = try folder()
        defer { TestScratch.remove(root) }
        for name in ["B", "A"] { try Data("{}".utf8).write(to: DesignFile.url(screen: "plants", name: name, in: root)) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("plants/notes.json"))
        #expect(DesignFile.url(screen: "plants", name: "A", in: root).lastPathComponent == "A.design.json")
        #expect(DesignFile.names(screen: "plants", in: root) == ["A", "B"])
        #expect(DesignFile.names(screen: "harvest", in: root).isEmpty)
    }

    /// 안 파일의 판 — 칸이 없으면 1 · 있으면 그 수(「이 SDK 보다 새 안」을 가른다).
    @Test func designFileVersionDefaultsToOne() {
        #expect(DesignFile.version(Data(#"{"screen": "a"}"#.utf8)) == DesignFormat.version)
        #expect(DesignFile.version(Data(#"{"version": 2}"#.utf8)) == 2)
        #expect(DesignFile.head(Data(#"{"createdAt": "2040-01-02T03:00:00Z", "version": 2}"#.utf8))?.version == 2)
        #expect(DesignFile.head(Data(#"{"createdAt": "2040-01-02T03:00:00Z"}"#.utf8))?.version == 1)
    }

    @Test func headReadsConfirmedAndCreatedAt() {
        let head = DesignFile.head(Data(#"{"createdAt": "2040-01-02T03:00:00Z", "confirmed": true, "style": {}}"#.utf8))
        #expect(head == DesignFile.Head(confirmed: true, createdAt: Date(timeIntervalSinceReferenceDate: 1_230_778_800)))
        #expect(DesignFile.head(Data(#"{"createdAt": "2040-01-02T03:00:00Z"}"#.utf8))?.confirmed == false)
        #expect(DesignFile.head(Data(#"{"confirmed": true}"#.utf8)) == nil)
        #expect(DesignFile.head(Data(#"{"createdAt": "어제"}"#.utf8)) == nil)
    }

    private struct Style: Codable { var a = 1; var b = "x" }

    @Test func fillsOnlyMissingStyleKeys() throws {
        var style: [String: Any] = ["a": 7]
        #expect(try DesignFile.fillMissingStyleKeys(&style, from: Style()) == 1)
        #expect(style["a"] as? Int == 7)
        #expect(style["b"] as? String == "x")
        #expect(try DesignFile.fillMissingStyleKeys(&style, from: Style()) == 0)
    }

    private struct File: Codable, Equatable { var screen = "plants"; var createdAt = Date(timeIntervalSinceReferenceDate: 1_230_778_800); var path = "a/b" }

    /// 바이트 규칙 — 열쇠 글자 순 · `/` 그대로 · 날짜 ISO 8601 · 읽개와 짝.
    @Test func encoderIsTheByteRule() throws {
        let data = try DesignFile.encoder().encode(File())
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == "{\n  \"createdAt\" : \"2040-01-02T03:00:00Z\",\n  \"path\" : \"a/b\",\n  \"screen\" : \"plants\"\n}")
        #expect(try DesignFile.decoder().decode(File.self, from: data) == File())
    }
}

@Suite struct IAWiringTests {
    @Test func rule() {
        // 씬 — 배선이 후보면 그것 · 없거나 후보가 아니면 이름 순 첫 · 후보가 없으면 nil
        #expect(IAWiring.scene(wired: "b", among: ["a", "b"]) == "b")
        #expect(IAWiring.scene(wired: "z", among: ["a", "b"]) == "a")
        #expect(IAWiring.scene(wired: nil, among: ["a", "b"]) == "a")
        #expect(IAWiring.scene(wired: "a", among: []) == nil)
        // 안 — 배선 → 확정(차례의 첫) → 가장 최근(같으면 이름 뒤)
        let heads = [IAWiring.Head(name: "A", confirmed: false, createdAt: 1), IAWiring.Head(name: "B", confirmed: false, createdAt: 3),
                     IAWiring.Head(name: "C", confirmed: false, createdAt: 3)]
        #expect(IAWiring.rule(heads) == "C")
        #expect(IAWiring.rule(heads + [IAWiring.Head(name: "D", confirmed: true, createdAt: 0)]) == "D")
        #expect(IAWiring.design(wired: "A", names: ["A", "B", "C"]) { heads } == "A")
        #expect(IAWiring.design(wired: "Q", names: ["A", "B", "C"]) { heads } == "C")
        #expect(IAWiring.rule([IAWiring.Head<Int>]()) == nil)
    }
}

@Suite struct ScreenComponentTests {
    /// 관대한 읽기 — 모르는 종류 · 깨진 줄은 건너뛰고 까닭을 남긴다 · 나머지는 읽는다.
    @Test func decodeLenientSkipsWhatItCannotRead() {
        let value: Any = [
            ["id": "w.scene", "kind": "isoscene", "source": "a.isoscene"],
            ["id": "w.new", "kind": "hologram"],
            ["id": "w.bad", "kind": "isomodel", "region": "전체"],
            "줄",
        ]
        let read = ScreenComponent.decodeLenient(value)
        #expect(read.components.map(\.id) == ["w.scene"])
        #expect(read.skipped.count == 3)
        #expect(ScreenComponent.decodeLenient(nil).components.isEmpty)
        #expect(ScreenComponent.decodeLenient("x").skipped == ["components 가 배열이 아니다"])
    }

    @Test func kindFollowsTheFileExtension() {
        #expect(ScreenComponent.Kind.of(file: URL(fileURLWithPath: "/a/b.ISOSCENE")) == .isoscene)
        #expect(ScreenComponent.Kind.of(file: URL(fileURLWithPath: "/a/b.isomodel")) == .isomodel)
        #expect(ScreenComponent.Kind.of(file: URL(fileURLWithPath: "/a/b.png")) == nil)
        #expect(!ScreenComponent.Kind.general.hasFile)
    }

    /// 모르는 칸 보존 — 구성요소 · 영역의 모르는 칸이 왕복에 남는다(관대한 읽기도 든다).
    @Test func unknownCellsSurvive() throws {
        let json = #"{"id":"w.scene","kind":"isoscene","source":"a.isoscene","layer":2,"region":{"x":0,"y":0.5,"width":1,"height":0.5,"z":3}}"#
        let c = try JSONDecoder().decode(ScreenComponent.self, from: Data(json.utf8))
        #expect(c.extra == ["layer": 2] && c.region?.extra == ["z": 3])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(c)) == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
        let lenient = ScreenComponent.decodeLenient([["id": "w", "kind": "general", "tint": "x"]])
        #expect(lenient.components.first?.extra == ["tint": "x"])
    }

    @Test func regionClampsAndTellsFull() {
        #expect(ScreenComponent.Region(x: -1, y: 0, width: 2, height: 0).clamped == ScreenComponent.Region(x: 0, y: 0, width: 1, height: 0.05))
        #expect(ScreenComponent.Region.full.isFull)
    }
}

@Suite struct FormFactorTests {
    /// 낱말과 차례 — 매니페스트 `platforms` 와 IA 플랫폼 칸이 이 글자를 쓴다.
    @Test func wordsAndOrder() {
        #expect(FormFactor.known.map(\.rawValue) == ["iphone", "ipad", "mac"])
    }

    /// 열린 꼴 — 모르는 낱말도 글자 그대로 들고 나온다.
    @Test func unknownWordsRoundTrip() throws {
        let words = try JSONDecoder().decode([FormFactor].self, from: Data(#"["mac", "vision"]"#.utf8))
        #expect(words == [.mac, FormFactor(rawValue: "vision")] && !FormFactor.known.contains(words[1]))
        #expect(String(decoding: try JSONEncoder().encode(words), as: UTF8.self) == #"["mac","vision"]"#)
    }

    /// 어느 폼팩터도 필수가 아니다 — iPhone 없는 조합(맥 전용 · iPad 전용 · iPad + 맥)도 선다 · 비었다 · 겹친다 · 낱말 꼴만 문제.
    @Test func noFormFactorIsRequired() {
        for ok in [["mac"], ["ipad"], ["ipad", "mac"], ["iphone"], ["vision"]] { #expect(FormFactor.problems(in: ok).isEmpty, "\(ok)") }
        #expect(FormFactor.problems(in: []) == ["플랫폼 목록이 비었다"])
        #expect(FormFactor.problems(in: ["mac", "mac"]).count == 1)
        #expect(FormFactor.problems(in: ["Mac"]).count == 1)
    }
}

@Suite struct JSONValueTests {
    /// 종류를 지킨다 — 참거짓이 수로 · 수가 글자로 새지 않는다(디코드는 참거짓 → 수 → 글자 → 배열 → 객체 차례로 잰다).
    @Test func keepsKinds() throws {
        let v = try JSONDecoder().decode([JSONValue].self, from: Data(#"[true, 1, 1.5, "x", null, {"pt": 18}, [false]]"#.utf8))
        #expect(v == [.bool(true), .number(1), .number(1.5), .string("x"), .null, ["pt": 18], .array([.bool(false)])])
    }

    /// 쓰는 꼴 — 정수로 떨어지는 수는 정수 · 키는 정렬 · 슬래시 그대로(저장 파일 · 명령 결과의 바이트가 기댄다) · Codable 값 → JSON 값.
    @Test func writesIntegersAndSortedKeys() throws {
        let v: JSONValue = ["b": 18, "a": .number(1.5), "p": "a/b"]
        #expect(v.text(pretty: false) == #"{"a":1.5,"b":18,"p":"a/b"}"#)
        struct S: Encodable { let gap = 4; let on = true }
        #expect(try JSONValue.from(S()) == ["gap": 4, "on": true])
    }

    /// 큰 정수는 깎이지 않는다 — 2^53 을 넘는 정수는 `integer`(Int64) 꼴로 읽고 그대로 쓴다 · 그 아래와 소수는 `number`(정본 꼴 하나).
    @Test func largeIntegersRoundTripExactly() throws {
        let text = #"{"big":1700000000000000001,"neg":-9007199254740993,"small":9007199254740992,"half":1.5}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(v == ["big": .integer(1_700_000_000_000_000_001), "neg": .integer(-9_007_199_254_740_993), "small": .number(9_007_199_254_740_992), "half": .number(1.5)])
        #expect(v.text(pretty: false) == #"{"big":1700000000000000001,"half":1.5,"neg":-9007199254740993,"small":9007199254740992}"#, "글자 그대로 되쓴다(키 정렬)")
        #expect(JSONValue.int(1_700_000_000_000_000_001) == .integer(1_700_000_000_000_000_001) && JSONValue.int(7) == .number(7) && (7 as JSONValue) == .number(7))
        #expect(JSONValue.integer(1_700_000_000_000_000_001).integerValue == 1_700_000_000_000_000_001 && JSONValue.number(4).integerValue == 4 && JSONValue.number(4.5).integerValue == nil)
        struct Stamp: Codable, Equatable { var ns: UInt64 = 1_700_000_000_000_000_001 }
        #expect(try JSONValue.from(Stamp()).decode(Stamp.self) == Stamp(), "Codable 값의 큰 정수도 왕복")
    }

    /// 프로젝트의 타입으로 오가기 — 객체로 인코드되는 값 → 사전(객체가 아니면 거부) · JSON 값 → 그 타입(꼴이 틀리면 거부).
    @Test func objectAndDecodeRoundTrip() throws {
        struct S: Codable, Equatable { var gap: Int; var on: Bool }
        let o = try JSONValue.dictionary(from: S(gap: 4, on: true))
        #expect(o == ["gap": 4, "on": true])
        #expect(try JSONValue.object(o).decode(S.self) == S(gap: 4, on: true))
        #expect(throws: JSONValueError.self) { try JSONValue.dictionary(from: 7) }
        #expect(throws: DecodingError.self) { try JSONValue.string("x").decode(S.self) }
    }
}

/// IA 문서의 꼴 — 파일엔 빈 칸을 적지 않는다(form=false · states=[] · nil · 빈 data) · 프로젝트 칸은 JSON 그대로 왕복 · 탭 루트 ⟂ 전역 오버레이 · 점프 놓기.
@Suite struct IADocTests {
    static let doc = IADoc(
        nodes: [ScreenNode(id: "home", label: "홈", via: "탭", source: "s"),
                ScreenNode(id: "home.detail", label: "상세", parent: "home", via: "행", source: "s", chrome: ["topLeft": "back", "glow": 1]),
                ScreenNode(id: "shed", label: "헛간", via: "문", source: "s", form: true, states: ["빈"], data: ScreenData(reads: ["Tool"]))],
        jumps: [ScreenJump(from: "home", to: "shed", label: "헛간", source: "x", entries: [JumpEntry(control: "more", title: "헛간", order: 1)])],
        hubs: [Hub(id: "tabs", label: "탭바", kind: .tabBar, slots: ["home"], items: ["home": ["label": "처음"]])])

    @Test func fileShapeOmitsEmptyFieldsAndKeepsProjectWords() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let node = String(decoding: try enc.encode(Self.doc.nodes[0]), as: UTF8.self)
        #expect(node == #"{"id":"home","label":"홈","source":"s","via":"탭"}"#)
        let back = try JSONDecoder().decode(IADoc.self, from: try enc.encode(Self.doc))
        #expect(back == Self.doc)
        #expect(back.node("home.detail")?.chrome == ["topLeft": "back", "glow": 1], "프로젝트 칸은 모르는 칸까지 그대로")
        #expect(back.node("shed")?.reads == ["Tool"])
        #expect(String(decoding: try enc.encode(ScreenData(reads: [])), as: UTF8.self) == #"{"reads":[]}"#)
        #expect(!String(decoding: try enc.encode(ScreenNode(id: "a", label: "a", via: "v", source: "s", data: ScreenData(reads: []))), as: UTF8.self).contains("data"))
    }

    /// 제안 마디(`proposed`) — 참이면 적고 거짓이면 적지 않는다 · 왕복이 같다.
    @Test func proposedFieldRoundTripsAndStaysOffWhenFalse() throws {
        let n = ScreenNode(id: "plants.journal", label: "재배 일지", parent: "plants", via: "⋯", source: "제안", proposed: true)
        let data = try JSONEncoder().encode(n)
        #expect(try JSONDecoder().decode(ScreenNode.self, from: data) == n)
        #expect(String(decoding: data, as: UTF8.self).contains("\"proposed\":true"))
        #expect(!String(decoding: try JSONEncoder().encode(ScreenNode(id: "a", label: "a", via: "", source: "")), as: UTF8.self).contains("proposed"))
    }

    @Test func treeTabsOverlaysAndJumps() {
        var d = Self.doc
        #expect(d.tabRoots.map(\.id) == ["home"])
        #expect(d.overlays.map(\.id) == ["shed"])
        #expect(d.children(of: "home").map(\.id) == ["home.detail"])
        d.setJump(from: "home", to: "shed", label: "새 이름", source: "무시")
        #expect(d.jumps.count == 1)
        #expect(d.jumps[0].label == "새 이름")
        #expect(d.jumps[0].source == "x", "출처 · 진입은 있던 것을 지킨다")
        #expect(d.jumps[0].entries?.first?.control == "more")
        d.removeJump(from: "home", to: "shed")
        #expect(d.jumps.isEmpty)
        #expect(ScreenJump(from: "a", to: "b", label: "l", source: ScreenJump.labSource()).isLabDrawn)
        #expect(IADoc.currentVersion == IAFormat.version)
        #expect(IADoc(nodes: [], jumps: [], hubs: []).version == IAFormat.version, "판 없는 손 = 지금 판")
    }

    /// 진입 선택(`entry`) — 왕복 · 빈 요소는 적지 않는다 · 없으면 칸째 없다(옛 파일의 바이트 불변) · 모르는 종류 낱말 · 모르는 칸 보존.
    @Test func entryRoundTripsAndOldFilesStayByteForByte() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let n = ScreenNode(id: "shelf.detail", label: "상세", parent: "shelf", via: "선반 › 행 shelf.row", source: "s",
                           entry: ScreenEntry(screen: "shelf", kind: .row, element: "shelf.row"))
        let data = try enc.encode(n)
        #expect(String(decoding: data, as: UTF8.self).contains(#""entry":{"element":"shelf.row","kind":"row","screen":"shelf"}"#))
        #expect(try JSONDecoder().decode(ScreenNode.self, from: data) == n)
        #expect(String(decoding: try enc.encode(ScreenEntry(screen: "a", kind: .tab, element: "")), as: UTF8.self) == #"{"kind":"tab","screen":"a"}"#,
                "빈 요소는 칸째 쓰지 않는다")
        // 옛 파일(entry 없음) — 읽고 되쓴 바이트가 같다
        let old = #"{"id":"home","label":"홈","source":"s","via":"탭"}"#
        let back = try JSONDecoder().decode(ScreenNode.self, from: Data(old.utf8))
        #expect(back.entry == nil)
        #expect(String(decoding: try enc.encode(back), as: UTF8.self) == old)
        // 열린 낱말 — 모르는 종류는 그대로 · 아는 낱말의 차례
        let odd = try JSONDecoder().decode(ScreenEntry.self, from: Data(#"{"screen":"a","kind":"swipe","hint":1}"#.utf8))
        #expect(odd.kind.rawValue == "swipe" && odd.extra == ["hint": 1])
        #expect(ScreenEntry.Kind.known.map(\.rawValue) == ["tab", "button", "row", "card", "menu", "gesture", "other"])
    }

    /// `entry` 를 모르는 읽개(1.1 의 마디 — 아는 칸에 `entry` 가 없다)는 그 칸을 `extra` 로 들고 되쓴다 — 새 파일을 옛 빌더가 열어 저장해도 선택이 남는다.
    @Test func aReaderWithoutEntryKeepsItAsAnUnknownCell() throws {
        struct OldNode: Codable {   // 1.1 의 아는 칸 집합 — entry 가 없다
            var id: String; var via: String; var extra: [String: JSONValue] = [:]
            enum K: String, CodingKey { case id, via }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: K.self)
                id = try c.decode(String.self, forKey: .id); via = try c.decode(String.self, forKey: .via)
                let all = try decoder.singleValueContainer().decode([String: JSONValue].self)
                extra = all.filter { $0.key != "id" && $0.key != "via" }
            }
            func encode(to encoder: Encoder) throws {
                var all = extra; all["id"] = .string(id); all["via"] = .string(via)
                var c = encoder.singleValueContainer(); try c.encode(all)
            }
        }
        let json = #"{"id":"b","label":"B","source":"s","via":"A › 단추","entry":{"screen":"a","kind":"button"}}"#
        let old = try JSONDecoder().decode(OldNode.self, from: Data(json.utf8))
        #expect(old.extra["entry"] != nil)
        let rewritten = try JSONDecoder().decode(ScreenNode.self, from: try JSONEncoder().encode(old))
        #expect(rewritten.entry == ScreenEntry(screen: "a", kind: .button))
        #expect(rewritten.extra.isEmpty, "아는 칸이 된 entry 는 extra 에 남지 않는다")
    }

    /// 모르는 칸 보존 — 문서 · 마디 · 점프 · 진입 · 허브 · 읽는 칸의 모르는 칸이 왕복에 남는다(같은 판의 덧붙임을 옛 엔진이 지우지 않는다).
    @Test func unknownCellsSurviveARoundTrip() throws {
        let json = #"{"version":1,"theme":"x","nodes":[{"id":"a","label":"A","via":"v","source":"s","badge":2,"data":{"reads":["T"],"writes":["U"]}}],"jumps":[{"from":"a","to":"a","label":"l","weight":1,"entries":[{"control":"more","hint":"h"}]}],"hubs":[{"id":"h","label":"H","kind":"rail","slots":["a"],"pinned":true}]}"#
        let doc = try JSONDecoder().decode(IADoc.self, from: Data(json.utf8))
        #expect(doc.extra == ["theme": "x"] && doc.nodes[0].extra == ["badge": 2] && doc.nodes[0].data?.extra == ["writes": ["U"]])
        #expect(doc.jumps[0].extra == ["weight": 1] && doc.jumps[0].entries?.first?.extra == ["hint": "h"])
        #expect(doc.hubs[0].extra == ["pinned": true] && doc.hubs[0].kind.rawValue == "rail")
        let back = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(doc))
        #expect(back == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
    }
}
