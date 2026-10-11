import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// 메시지 꼴 — 평평한 `type` 칸 · 왕복 · 칸 값 조각 · 요소 경계.

@Suite struct MessageTests {
    static let tray = StyleElement(id: "tray", label: "받침", snapPrefix: "home.tray")
    static let color = StyleElement(id: "color", label: "색 역할", snapPrefix: "")
    static let home = StyleSchema(
        screen: "home", elements: [tray, color],
        fields: StyleField.list([("trayGap", .scalar(.space)), ("leafColor", .color), ("trayGlass", .bool)], elements: [tray, color]),
        defaults: ["trayGap": .token("md"), "leafColor": "inkSoft", "trayGlass": false])
    static let samples: [Message] = [
        .hello(Hello(role: .host, protocolVersion: 1, pid: 7, name: "host",
                     screens: [ScreenInfo(name: "home", states: ["normal"], style: home)],
                     layers: [LayerInfo(name: "chrome", style: StyleSchema(screen: "chrome", elements: [], fields: [], defaults: [:]))],
                     formats: [.rgba8sRGB])),
        .hello(Hello(role: .engine, protocolVersion: 1, pid: 8, name: "bench", shared: SharedMemoryInfo(kind: .posix, name: "/mucp.1.2", slotBytes: 100, slots: 3))),
        .render(RenderRequest(seq: 1, screen: "home", state: "normal", style: ["trayGap": .pt(12), "leafColor": "inkSoft", "trayGlass": true],
                              theme: "dark", size: Size(w: 390, h: 844), scale: 2,
                              layers: [LayerState(name: "chrome", style: ["barOn": true], data: ["spec": ["tab": "home"]]), LayerState(name: "callout")],
                              frames: true, scroll: 400)),
        .render(RenderRequest(seq: 9, screen: "harvest", state: "empty", size: Size(w: 1, h: 1), scale: 1)),
        .render(RenderRequest(seq: 10, screen: "greenhouse", state: "sample", size: Size(w: 390, h: 844), scale: 2,
                              layers: [LayerState(name: "chrome")], frames: true, fixture: ["anchorX": .number(0.4), "anchorY": .number(0.6)], layersOnly: true)),
        .frame(FrameHeader(seq: 2, applied: 2, w: 780, h: 1688, stride: 3120, scale: 2, format: .rgba8sRGB,
                           snapFrames: [SnapFrame(id: "a", rect: CGRect(x: 1, y: 2, width: 3, height: 4))], elements: ["a", "b"],
                           ms: 2.5, payload: .inline(bytes: 5_265_600),
                           timing: HostTiming(recv: 1, start: 2, rendered: 3, sent: 4))),
        .frame(FrameHeader(seq: 3, applied: 9, w: 1, h: 1, stride: 4, scale: 1, format: .rgba8sRGB, snapFrames: [], ms: 0, payload: .slot(index: 2, bytes: 4))),
        .frame(FrameHeader(seq: 11, applied: 11, w: 1, h: 1, stride: 4, scale: 1, format: .rgba8sRGB, snapFrames: [], elements: ["a", "nav.back"],
                           layers: [LayerReport(name: "chrome", elements: ["nav.back"], data: ["spec": ["tab": "home"]],
                                                cover: Insets(top: 98, bottom: 83))], ms: 0, payload: .inline(bytes: 4))),
        .patch(Patch(seq: 4, edits: [Edit(field: "trayGap", value: .token("md")), Edit(field: "barOn", value: .bool(false), layer: "chrome")])),
        .tokensChanged(TokensChanged(seq: 5)),
        .shot(ShotRequest(seq: 6, path: "/tmp/a.png")),
        .window(WindowRequest(seq: 7, x: 10, y: 20, show: true)),
        .window(WindowRequest(seq: 12, x: -6000, y: 20, show: true, w: 390, h: 844, above: 4711)),
        .window(WindowRequest(seq: 13, x: 0, y: 0, show: true, w: 390, h: 844, above: 4711, clip: CGRect(x: 0, y: 120, width: 390, height: 600))),
        .ack(Ack(seq: 8, applied: 8, ms: 1.5, changed: true)),
        .error(ErrorMessage(seq: nil, message: "모름")),
        .bye(Bye(reason: "끝")),
    ]

    @Test func roundTripsEveryType() throws {
        for m in Self.samples {
            let line = try Framing.header(m)
            let json = try JSONSerialization.jsonObject(with: line.prefix(while: { $0 != 0x0A })) as! [String: Any]
            #expect(json["type"] as? String == m.type, "평평한 type 칸 — \(m.type)")
            #expect(try JSONDecoder().decode(Message.self, from: line.prefix(while: { $0 != 0x0A })) == m)
        }
    }

    /// 층 자료의 엔진 쪽 꼴 — 화면 + IA 문서가 JSON 값으로 왕복한다(호스트가 받아 그 문서에서 셈한다).
    @Test func layerContextRoundTripsAsLayerData() throws {
        let doc = IADoc(nodes: [ScreenNode(id: "home", label: "홈", via: "탭", source: "s", chrome: ["topLeft": "avatar"])], jumps: [],
                        hubs: [Hub(id: "tabs", label: "탭바", kind: .tabBar, slots: ["home"])])
        let ctx = LayerContext(screen: "home", ia: doc)
        let state = LayerState(name: "chrome", data: try ctx.data())
        let back = try JSONDecoder().decode(LayerState.self, from: try JSONEncoder().encode(state))
        #expect(try LayerContext(data: back.data!) == ctx)
        #expect(throws: DecodingError.self) { try LayerContext(data: ["screen": "home"]) }
    }

    @Test func seqIsExposedForRequests() {
        #expect(Message.patch(Patch(seq: 4, edits: [])).seq == 4)
        #expect(Message.bye(Bye(reason: "")).seq == nil)
    }

    /// 화면 본체의 요소 = 그린 요소 − 층의 요소(차례 그대로) · 층 보고가 없으면 그린 요소 그대로 · 경계를 청하지 않은 장은 nil.
    @Test func screenElementsLeaveTheLayersOut() {
        func header(_ elements: [String]?, _ layers: [LayerReport]?) -> FrameHeader {
            FrameHeader(seq: 1, applied: 1, w: 1, h: 1, stride: 4, scale: 1, format: .rgba8sRGB, snapFrames: [], elements: elements, layers: layers,
                        ms: 0, payload: .inline(bytes: 4))
        }
        #expect(header(["b", "nav.back", "a", "tab.home"], [LayerReport(name: "chrome", elements: ["tab.home", "nav.back"])]).screenElements == ["b", "a"])
        #expect(header(["b", "a"], nil).screenElements == ["b", "a"])
        #expect(header(nil, nil).screenElements == nil)
    }

    @Test func unknownTypeFails() {
        #expect(throws: Message.DecodeError.self) { try JSONDecoder().decode(Message.self, from: Data(#"{"type":"teleport"}"#.utf8)) }
    }
}

@Suite struct SocketPathTests {
    @Test func shortStableAndDistinct() {
        let deep = "/tmp/" + String(repeating: "아주-깊은-폴더/", count: 20) + "project"
        let a = SocketPath.forFolder(deep), b = SocketPath.forFolder(deep), c = SocketPath.forFolder(deep + "2")
        #expect(a == b)
        #expect(a != c)
        #expect(SocketPath.fits(a))
        #expect(a.utf8.count == "/tmp/mucp-0123456789abcdef.sock".utf8.count)
        #expect(!SocketPath.fits("/tmp/" + String(repeating: "x", count: 100)))
    }
}

@Suite struct FormatTests {
    @Test func tightBytes() { #expect(FrameFormat.tightBytes(width: 780, height: 1688) == 5_266_560) }
}

@Suite struct SnapFrameTests {
    /// 경계 반올림(소수 둘째 자리) · 제 사각형 · `frames.json` 왕복.
    @Test func roundsToTwoPlacesAndKeepsItsRect() throws {
        let f = SnapFrame(id: "card.title", rect: CGRect(x: 10.123, y: 20.456, width: 100.005, height: 0.004))
        #expect([f.x, f.y, f.w, f.h] == [10.12, 20.46, 100.01, 0])
        #expect(f.rect == CGRect(x: 10.12, y: 20.46, width: 100.01, height: 0))
        #expect(try JSONDecoder().decode(SnapFrame.self, from: JSONEncoder().encode(f)) == f)
    }
}
