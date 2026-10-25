import DesignTokens
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// hello 의 프로젝트 데이터 — 칸이 왕복하고 · 없으면 nil(옛 호스트) · 판 1 의 말로 내리면 새 칸이 걷히고 판 1 의 줄은 그대로 읽힌다 ·
// 프로젝트 데이터 꼴 안의 칸은 모두 선택(빠지면 기본값 · 모르는 칸은 보존) · 빌드된 표 요약의 맞대기 · 구성 서술의 꼴 재기(모르는 종류는 재지 않는다) ·
// 콜아웃 푼 값의 층 자료 왕복(판 칸 `v` — 없으면 1).

@Suite struct HelloProjectTests {
    static let schema = StyleSchema(screen: "s", elements: [], fields: [], defaults: [:])
    static let ia = IAInfo(appScreens: ["home"], entryWords: [.init(control: "plus", label: "＋"), .init(control: "more", label: "⋯")],
                           entryHands: ["home": ["plus"]], aliases: ["old": "home"], planned: ["later"])
    static let frames = [DeviceFrameInfo(id: "phone", platform: "iphone", name: "Phone 390×844", symbol: "iphone", size: Size(w: 390, h: 844),
                                         corner: 47, safeTop: 47, safeBottom: 34, scene: .init(name: "Phone 390×844")),
                         DeviceFrameInfo(id: "pad-portrait", platform: "ipad", name: "Pad", symbol: "ipad", size: Size(w: 820, h: 1180),
                                         corner: 18, safeTop: 24, safeBottom: 20)]
    static let built = BuiltTokens(scales: ["space": [.init(name: "md", pt: 8)]], layout: [.init(name: "gap-wide", pt: 10)],
                                   colors: [.init(name: "bg", values: ["light": "#ffffff", "dark": "#000000"])], themes: ["light", "dark"])

    static func hello() -> Hello {
        Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "host",
              screens: [ScreenInfo(name: "home", states: ["normal"], style: schema, fixtureColorUsage: ["chip-mint": 2])],
              layers: [LayerInfo(name: "chrome", style: schema, composition: LayerComposition(nodeKeys: [.init(key: "chrome", label: "구성")],
                                                                                              fields: [.init(key: "bottom", kind: .bool, label: "아래")]))],
              formats: [.rgba8sRGB], ia: ia, frames: frames, tokensBuilt: built)
    }

    @Test func theProjectDataRoundTripsAndIsOptional() throws {
        let h = Self.hello()
        let line = try ProtocolDialect.current.encode(.hello(h))
        #expect(try ProtocolDialect.current.decode(line) == .hello(h))
        #expect(h.ia?.controls == ["plus", "more"])
        #expect(h.frames?.first?.formFactor == .iphone)
        #expect(h.frames?.last?.scene == nil, "편집기 틀이 아닌 틀")
        // 옛 호스트 — 칸이 없으면 nil
        let bare = try ProtocolDialect.current.decode(Data(#"{"type":"hello","role":"host","protocolVersion":2,"pid":1,"name":"h","screens":[{"name":"a","states":["n"],"style":{"screen":"a","elements":[],"fields":[],"defaults":{}}}],"layers":[{"name":"c","style":{"screen":"c","elements":[],"fields":[],"defaults":{}}}]}"#.utf8))
        guard case .hello(let b) = bare else { Issue.record("hello 가 아니다"); return }
        #expect(b.ia == nil && b.frames == nil && b.tokensBuilt == nil)
        #expect(b.screens?.first?.fixtureColorUsage == nil && b.layers?.first?.composition == nil)
    }

    /// 판 1 의 말 — 내리면 hello 의 새 칸이 걷히고(판 1 엔진이 모르는 칸) · 판 1 의 줄은 판 2 의 메시지로 그대로 읽힌다 · hello 밖의 줄은 그대로.
    @Test func theDialectOfVersionOneDropsTheNewCells() throws {
        let line = try ProtocolDialect.v1.encode(.hello(Self.hello()))
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(top["ia"] == nil && top["frames"] == nil && top["tokensBuilt"] == nil)
        #expect(((top["screens"] as? [[String: Any]])?.first)?["fixtureColorUsage"] == nil)
        #expect(((top["layers"] as? [[String: Any]])?.first)?["composition"] == nil)
        #expect(((top["layers"] as? [[String: Any]])?.first)?["name"] as? String == "chrome", "칸만 걷고 층은 남는다")
        guard case .hello(let back) = try ProtocolDialect.v1.decode(line) else { Issue.record("hello 가 아니다"); return }
        #expect(back.ia == nil && back.screens?.first?.name == "home")
        let render = Message.render(RenderRequest(seq: 3, screen: "home", state: "normal", size: Size(w: 1, h: 1), scale: 2,
                                                  layers: [LayerState(name: "chrome")]))
        #expect(try ProtocolDialect.v1.decode(ProtocolDialect.v1.encode(render)) == render)
        #expect(PreviewProtocolVersion.previous.map(\.version) == [2, 3, 4, 5, 6, 7], "엔진은 바닥(판 2)부터 받는다 — 판 1 의 말은 사슬로만 선다")
    }

    @Test func builtTokensDifferOnlyWhenAValueOrderOrThemeSetDiffers() {
        let a = Self.built
        var b = a
        b.themes = ["dark", "light"]
        #expect(!a.differs(from: b), "테마 이름은 집합으로")
        b.colors[0].values["dark"] = "#111111"
        #expect(a.differs(from: b))
        var c = a
        c.scales["radius"] = []
        #expect(!a.differs(from: c), "없는 종류 = 빈 단")
        c.layout = [.init(name: "gap-wide", pt: 13)]
        #expect(a.differs(from: c))
    }

    @Test func builtTokensFromProviders() {
        struct Scales: ScaleTokenProvider {
            func entries(_ kind: ScaleKind) -> [ScaleEntry] { kind == .space ? [ScaleEntry(name: "md", pt: 8)] : [] }
        }
        struct Colors: ColorTokenProvider {
            func themes() -> [ThemeInfo] { [ThemeInfo(name: "light", base: .light), ThemeInfo(name: "dark", base: .dark)] }
            func entries() -> [ColorEntry] { [ColorEntry(name: "bg", values: ["light": HexColor(rgb: 0xFFFFFF), "dark": HexColor(rgb: 0)])] }
        }
        let t = BuiltTokens(scales: Scales(), layout: [ScaleEntry(name: "gap-wide", pt: 10), ScaleEntry(name: "gap-narrow", pt: 5)], colors: Colors())
        #expect(t.scales["space"] == [.init(name: "md", pt: 8)])
        #expect(t.scales["radius"] == [] && t.scales.count == ScaleKind.known.count)
        #expect(t.layout.map(\.name) == ["gap-narrow", "gap-wide"], "간격 역할은 이름 차례")
        #expect(t.colors == Self.built.colors && t.themes == Self.built.themes)
        #expect(t.differs(from: Self.built), "간격 역할 하나가 더 있다")
        var same = Self.built; same.layout = t.layout
        #expect(!t.differs(from: same), "없는 스케일 종류 = 빈 단 · 나머지가 같으면 같다")
    }

    @Test func compositionKindsAcceptTheirJSONShape() {
        #expect(CompositionField.Kind.bool.accepts(true) && !CompositionField.Kind.bool.accepts("x"))
        for k in [CompositionField.Kind.text, .symbol, .choice, .slot] { #expect(k.accepts("x") && !k.accepts(1)) }
        for k in [CompositionField.Kind.symbols, .subset] { #expect(k.accepts(["a", "b"]) && !k.accepts([1]) && !k.accepts("a")) }
        #expect(CompositionField.Kind.labels.accepts(["a": "이름"]) && !CompositionField.Kind.labels.accepts(["a": 1]))
        let fields = [CompositionField(key: "bottom", kind: .bool, label: "아래"), CompositionField(key: "tools", kind: .symbols, label: "도구")]
        #expect(LayerComposition.problems(["bottom": false, "tools": ["plus"], "other": 3], fields: fields).isEmpty, "서술 밖 칸은 재지 않는다")
        #expect(LayerComposition.problems(["bottom": .null], fields: fields).isEmpty, "널 = 비운 칸")
        #expect(LayerComposition.problems(["bottom": "yes"], fields: fields) == ["bottom — bool 꼴이 아니다"])
        #expect(LayerComposition.problems("x", fields: fields) == ["구성이 객체가 아니다"])
        // 열린 종류 — 프로젝트가 서술로 더한 종류는 글자 그대로 들고 꼴은 재지 않는다
        let gauge = CompositionField.Kind(rawValue: "gauge")
        #expect(gauge.accepts(3) && gauge.accepts("x") && !CompositionField.Kind.known.contains(gauge))
        let wire = try? JSONEncoder().encode(CompositionField(key: "level", kind: gauge, label: "수위"))
        #expect(wire.flatMap { try? JSONDecoder().decode(CompositionField.self, from: $0) }?.kind == gauge)
    }

    @Test func calloutValuesRideTheLayerReport() throws {
        let v = CalloutValues(surface: "#ffffff", line: "#20304014", lineWidth: 1, cornerRadius: 10, padding: Size(w: 10, h: 8), lineSpacing: 4,
                              maximumWidth: 200, eyebrowSize: 10, eyebrowTracking: 0.5, eyebrowColor: "#607080", titleSize: 14, titleColor: "#203040",
                              valueSize: 12, valueColor: "#607080", dotDiameter: 8, dotColor: "#10a0a0", pointerLength: 16, pointerWidth: 2, edgeInset: 10)
        let report = LayerReport(name: "callout", elements: [], data: try v.data())
        #expect(try CalloutValues(data: try #require(report.data)) == v)
        guard case .object(let o) = try v.data() else { Issue.record("객체가 아니다"); return }
        #expect(o["v"] == .number(Double(CalloutValues.formatVersion)), "판 칸을 싣는다")
        // 칸이 빠진 자료도 읽힌다(빠진 칸 = 기본값 · 판 칸 없음 = 1) · 모르는 칸은 보존해 되쓴다
        let thin = try CalloutValues(data: ["surface": "#fff", "glow": 2])
        #expect(thin.surface == "#fff" && thin.lineWidth == 0 && thin.version == 1 && thin.extra == ["glow": 2])
        guard case .object(let back) = try thin.data() else { Issue.record("객체가 아니다"); return }
        #expect(back["glow"] == 2)
    }

    /// 프로젝트 데이터 꼴 안의 칸은 모두 선택 — 빠지면 기본값 · 모르는 칸은 들고 되쓴다(필수 칸으로 얼리지 않는다).
    @Test func projectDataCellsAreOptionalAndKeepUnknownCells() throws {
        let ia = try JSONDecoder().decode(IAInfo.self, from: Data(#"{"appScreens":["home"],"tabs":3}"#.utf8))
        #expect(ia.appScreens == ["home"] && ia.entryWords.isEmpty && ia.aliases.isEmpty && ia.extra == ["tabs": 3])
        #expect(try JSONValue.from(ia) == ["appScreens": ["home"], "entryWords": [], "entryHands": [:], "aliases": [:], "planned": [], "tabs": 3])
        let mac = try JSONDecoder().decode(DeviceFrameInfo.self, from: Data(#"{"id":"desk","platform":"mac","size":{"w":1280,"h":800},"titleBar":28}"#.utf8))
        #expect(mac.formFactor == .mac && mac.safeTop == 0 && mac.corner == 0 && mac.extra == ["titleBar": 28], "안전영역 없는 틀(맥 창)도 선다")
        #expect(try JSONDecoder().decode(DeviceFrameInfo.self, from: JSONEncoder().encode(mac)) == mac)
        #expect(DeviceFrameInfo().formFactor == nil, "낱말이 비면 폼팩터 없음")
        #expect(DeviceFrameInfo(id: "v", platform: "vision", name: "V", symbol: "v", size: Size(w: 1, h: 1), corner: 0, safeTop: 0, safeBottom: 0)
                    .formFactor?.rawValue == "vision", "모르는 폼팩터도 낱말 그대로")
    }

    /// 짚은 자리(선택 칸) — 실으면 왕복 · 싣지 않은 옛 보고는 nil 로 읽힌다(판 2 안의 덧붙임) · 그림 한 장 안의 점.
    @Test func calloutAnchorIsAnOptionalFieldOfTheValues() throws {
        let base = CalloutValues(surface: "#ffffff", line: "#000000", lineWidth: 1, cornerRadius: 10, padding: Size(w: 10, h: 8), lineSpacing: 4,
                                 maximumWidth: 200, eyebrowSize: 10, eyebrowTracking: 0.5, eyebrowColor: "#607080", titleSize: 14, titleColor: "#203040",
                                 valueSize: 12, valueColor: "#607080", dotDiameter: 8, dotColor: "#10a0a0", pointerLength: 16, pointerWidth: 2, edgeInset: 10)
        var with = base
        with.anchor = CalloutAnchor(x: 0.25, y: 0.75)
        #expect(try CalloutValues(data: try with.data()) == with)
        guard case .object(var o) = try base.data() else { Issue.record("객체가 아니다"); return }
        #expect(o["anchor"] == nil, "없으면 싣지 않는다")
        o["anchor"] = nil
        #expect(try CalloutValues(data: .object(o)).anchor == nil)
    }
}
