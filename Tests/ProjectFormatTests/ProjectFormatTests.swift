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
        #expect(id.uuidString.lowercased() == "ee5c8311-4efc-5c4e-9c14-313d666b319d")
        #expect(id == IsoDataIDs.uuid5(namespace: IsoDataIDs.uuid5(namespace: IsoDataIDs.urlNamespace, name: "com.sangpil.isodata/sample"), name: "Watering/watering-1"))
        #expect(id != IsoDataIDs.uuid(schema: "sample", entity: "Pot", id: "watering-1"))
        #expect(id != IsoDataIDs.uuid(schema: "other", entity: "Watering", id: "watering-1"))
    }

    @Test func namespaceIsTheContractValue() {
        #expect(IsoDataIDs.namespace(schema: "sample").uuidString.lowercased() == "2efa13c1-8065-5859-986a-71b01fdfa997")
    }

    /// UUID 꼴 id 는 해시하지 않고 그대로(대소문자 무관 · 이름공간을 타지 않는다) · UUID 꼴이 아니면(하이픈 없는 32자 · 접두 붙은 꼴) 해시한다.
    @Test func uuidShapedIDsPassThrough() {
        let upper = "EE5C8311-4EFC-5C4E-9C14-313D666B319D"
        let got = IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: upper)
        #expect(got.uuidString.lowercased() == upper.lowercased())
        #expect(IsoDataIDs.uuid(schema: "sample", entity: "Watering", id: upper.lowercased()) == got)
        #expect(IsoDataIDs.uuid(schema: "other", entity: "Pot", id: upper) == got)
        let bare = "ee5c83114efc5c4e9c14313d666b319d"
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
        #expect(SceneFormat.oldestReadable <= SceneFormat.newestReadable)
    }

    /// 쓰는 손이 찍는 가장 낮은 판 — 읽는 범위 안이다(업그레이드가 쓰는 판의 바닥 · 최신이 아니다).
    @Test func theLowestWrittenVersionIsInsideWhatIsRead() {
        #expect(SceneFormat.oldestReadable <= SceneFormat.lowestWritten && SceneFormat.lowestWritten < SceneFormat.newestReadable)
        #expect(1 <= ModelFormat.lowestWritten && ModelFormat.lowestWritten < ModelFormat.newestReadable)
    }
}

@Suite struct SDKVersionTests {
    /// SDK 판 — 세 마디 정수(주.부.수). 정본 문서의 판 칸과의 맞대기는 엔진 쪽 시험의 몫 — SDK 는 저장소 배치를 가정하지 않는다.
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
}

@Suite struct FormFactorTests {
    /// 낱말과 차례 — 매니페스트 `platforms` 와 IA 플랫폼 칸이 이 글자를 쓴다.
    @Test func wordsAndOrder() {
        #expect(FormFactor.allCases.map(\.rawValue) == ["iphone", "ipad", "mac"])
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
    }
}
