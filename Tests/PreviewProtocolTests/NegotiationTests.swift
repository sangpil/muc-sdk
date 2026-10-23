import CoreGraphics
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// 판 맞대기 — 판정 표(같은 판 · 바닥까지의 옛 판 · 새 판 · 바닥 아래 · 판 없음) · 첫 줄의 판 읽기(몸을 풀기 전) · 옛 판의 말(줄 올리기 · 내리기 — 정수 그대로) ·
// 스텝 사슬(합성 = 직통 · 내리기 nil = 보내지 않음) · 디코더가 첫 줄에서 말을 고른다 · 호스트 쪽 규칙 · 문서의 판 글자.

@Suite struct NegotiationTests {
    static let now = PreviewProtocolVersion.current
    /// 가짜 다음 판(N+1)의 말 — 칸 이름 하나가 바뀌고(`scale` → `pixelScale`) 줄마다 표 `next` 가 붙은 꼴 · `ack` 는 판 N 에만 있다(N+1 로 내리면 nil).
    static let next = ProtocolDialect(version: now + 1, lift: { line in
        var l = line
        guard l.removeValue(forKey: "next") as? Bool == true else { throw Framing.Failure.badJSON("판 표 없음") }
        if let v = l.removeValue(forKey: "pixelScale") { l["scale"] = v }
        return l
    }, lower: { line in
        if line["type"] as? String == "ack" { return nil }
        var l = line
        if let v = l.removeValue(forKey: "scale") { l["pixelScale"] = v }
        l["next"] = true
        return l
    })
    /// 다음 판 엔진 — 제 판(N+1) · 판 N(지금 꼴 그대로) · 판 N-1(스텝 사슬)을 받는다.
    static let engineNext = ProtocolJudge(version: now + 1, dialects: [next, .current, .v6])
    /// `ack` 가 없는 옛 판 1 의 말 — 스텝 1 → 2(시험용 · `ack` 를 내리면 nil) 뒤에 실제 스텝 2 → 3 → … → 7.
    static let ackless = ProtocolDialect.chain([ProtocolDialect.Step(from: 1, lift: { $0 }, lower: { $0["type"] as? String == "ack" ? nil : $0 }), .v2to3, .v3to4, .v4to5, .v5to6, .v6to7])

    static func hello(_ version: Int?) -> Data {
        var top: [String: Any] = ["type": "hello", "role": "host", "pid": 1, "name": "h"]
        if let version { top["protocolVersion"] = version }
        return try! JSONSerialization.data(withJSONObject: top)
    }

    /// 판정 — 받으면 그 말의 판 · 거절하면 그 까닭.
    static func taken(_ r: Result<ProtocolDialect, ProtocolMismatch>) -> Int? { try? r.get().version }
    static func refused(_ r: Result<ProtocolDialect, ProtocolMismatch>) -> ProtocolMismatch? {
        if case .failure(let m) = r { return m }
        return nil
    }

    @Test func judgeTakesEveryVersionFromTheFloor() {
        let e = ProtocolJudge.engine, now = Self.now
        #expect(Self.taken(e.judge(host: now)) == now)
        #expect(Self.taken(e.judge(host: PreviewProtocolVersion.oldest)) == PreviewProtocolVersion.oldest, "바닥 판은 받는다")
        #expect(Self.refused(e.judge(host: now + 1)) == .hostNewer(host: now + 1, engine: now))
        #expect(Self.refused(e.judge(host: PreviewProtocolVersion.oldest - 1)) == .hostTooOld(host: PreviewProtocolVersion.oldest - 1, engine: now), "바닥 아래는 받지 않는다")
        #expect(Self.refused(e.judge(host: nil)) == .hostTooOld(host: nil, engine: now), "판을 못 읽으면 옛 판으로 본다")

        let n = Self.engineNext
        #expect(Self.taken(n.judge(host: now + 1)) == now + 1, "같은 판")
        #expect(Self.taken(n.judge(host: now)) == now, "한 판 뒤 — 그 판의 말")
        #expect(Self.taken(n.judge(host: now - 1)) == now - 1, "두 판 뒤도 말이 있으면 받는다(창은 바닥까지)")
        #expect(Self.refused(n.judge(host: now - 2)) == .hostTooOld(host: now - 2, engine: now + 1), "말이 없는 옛 판")
        #expect(Self.refused(n.judge(host: now + 2)) == .hostNewer(host: now + 2, engine: now + 1))
        let bare = ProtocolJudge(version: now + 1, dialects: [Self.next])
        #expect(Self.refused(bare.judge(host: now - 1)) == .hostTooOld(host: now - 1, engine: now + 1), "그 판의 말이 없으면 받지 않는다")
    }

    /// 이 엔진은 바닥(`oldest`)부터 지금 판까지 전부 받는다 — 판마다 말이 하나씩(`previous` = 바닥 … 지금 판 바로 아래).
    @Test func theEngineCarriesEveryDialectDownToTheFloor() {
        let e = ProtocolJudge.engine
        #expect(e.version == Self.now)
        #expect(PreviewProtocolVersion.oldest >= 1 && PreviewProtocolVersion.oldest <= Self.now)
        for v in PreviewProtocolVersion.oldest...Self.now { #expect(e.dialects[v] != nil, "판 \(v) 의 말이 없다 — 스텝을 이어 `previous` 에 더하라") }
        #expect(PreviewProtocolVersion.previous.map(\.version).sorted() == Array(PreviewProtocolVersion.oldest..<Self.now))
        #expect(PreviewProtocolVersion.previous.allSatisfy { $0.reaches == Self.now }, "옛 판의 말은 지금 판까지 닿아야 한다(사슬의 마지막 스텝 = 지금 판)")
        #expect(ProtocolDialect.current.reaches == Self.now && ProtocolDialect.v1.reaches == Self.now)
        #expect(ProtocolDialect.chain([.v1to2]).reaches == 2, "지금 판에 못 닿는 사슬은 그 판을 적는다")
    }

    /// 사슬의 차례 — 같은 칸을 건드리는 스텝 둘(1→2: a→b · 2→3: b→c): 올리기는 1→2→3 차례 · 내리기는 3→2→1 거꾸로(차례가 틀리면 칸이 엉뚱한 이름에 남는다).
    @Test func chainOrderMattersForStepsOnTheSameKey() throws {
        func rename(_ from: String, _ to: String) -> @Sendable (ProtocolDialect.Line) throws -> ProtocolDialect.Line {
            { line in var l = line; if let v = l.removeValue(forKey: from) { l[to] = v }; return l }
        }
        let ab = ProtocolDialect.Step(from: 1, lift: rename("a", "b"), lower: rename("b", "a"))
        let bc = ProtocolDialect.Step(from: 2, lift: rename("b", "c"), lower: rename("c", "b"))
        let up = try ProtocolDialect.Step.v2to3.lift(try bc.lift(try ab.lift(["a": 1])))
        #expect(up["c"] as? Int == 1 && up["a"] == nil && up["b"] == nil)
        let both = ProtocolDialect.chain([ab, bc])
        #expect(both.version == 1 && both.reaches == 3)
        // 사슬로 짓은 말의 내리기 — 메시지 줄의 맨 위에 c 를 얹어 내려 a 로 오는지(거꾸로 밟았는지)
        let line = try #require(try both.encodeIfSpoken(.bye(Bye(reason: "r"))))
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(top["reason"] as? String == "r")
        let probe = ProtocolDialect.chain([ProtocolDialect.Step(from: 1, lift: rename("a", "b"), lower: rename("b", "a")),
                                           ProtocolDialect.Step(from: 2, lift: rename("b", "reason"), lower: rename("reason", "b"))])
        let lowered = try #require(try probe.encodeIfSpoken(.bye(Bye(reason: "r"))))
        let down = try #require(try JSONSerialization.jsonObject(with: lowered) as? [String: Any])
        #expect(down["a"] as? String == "r" && down["reason"] == nil && down["b"] == nil, "내리기는 2→1 다음 1→… 거꾸로")
        #expect(try probe.decode(try JSONSerialization.data(withJSONObject: down)) == .bye(Bye(reason: "r")), "올리기는 차례대로")
    }

    /// 스텝 사슬 — 1 → 2 → … → 7 을 이은 말은 스텝을 차례로 손으로 밟은 것과 같다(올리기 · 내리기) · 판 1 의 줄은 지금 판의 메시지로 읽힌다.
    @Test func chainedStepsEqualTheDirectWalk() throws {
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", ia: IAInfo(appScreens: ["a"], entryWords: [], entryHands: [:], aliases: [:], planned: []),
                                        frames: [], tokensBuilt: nil))
        let line = try ProtocolDialect.v1.encode(hello)
        let native = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(hello)) as? ProtocolDialect.Line)
        let six = try #require(try ProtocolDialect.Step.v6to7.lower(native))
        let five = try #require(try ProtocolDialect.Step.v5to6.lower(six))
        let four = try #require(try ProtocolDialect.Step.v4to5.lower(five))
        let three = try #require(try ProtocolDialect.Step.v3to4.lower(four))
        let two = try #require(try ProtocolDialect.Step.v2to3.lower(three))
        let walked = try #require(try ProtocolDialect.Step.v1to2.lower(two))
        let chained = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(NSDictionary(dictionary: chained) == NSDictionary(dictionary: walked))
        guard case .hello(let back) = try ProtocolDialect.v1.decode(line) else { Issue.record("hello 가 아니다"); return }
        #expect(back.ia == nil && back.frames == nil, "판 1 은 프로젝트 데이터 칸이 없다")
        #expect(ProtocolDialect.v1.version == 1 && ProtocolDialect.v2.version == 2 && ProtocolDialect.v3.version == 3 && ProtocolDialect.v4.version == 4
                && ProtocolDialect.v5.version == 5 && ProtocolDialect.v6.version == 6)
    }

    /// 판 6 → 5 내리기 — `render` 의 청함(`drawn`)과 프레임 머리의 글줄 · 바탕(`texts` · `styles`)을 걷는다 · 나머지 칸 · 다른 메시지는 그대로 ·
    /// 올리기는 그대로(판 5 호스트의 프레임 머리 = 글줄 없음 → nil 로 읽힌다 — 빈 목록과 다르다).
    @Test func loweringToFiveDropsDrawn() throws {
        let render = Message.render(RenderRequest(seq: 2, screen: "s", state: "n", size: Size(w: 1, h: 1), scale: 1, frames: true, drawn: true))
        let down = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v5.encode(render)) as? [String: Any])
        #expect(down["drawn"] == nil && down["frames"] as? Bool == true, "판 5 의 render 엔 청함이 없다 · 경계 청함은 남는다")
        guard case .render(let r) = try ProtocolDialect.v5.decode(ProtocolDialect.v5.encode(render)) else { Issue.record(); return }
        #expect(r.drawn == nil && r.frames == true)

        let snap = SnapFrame(id: "card", rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        let frame = Message.frame(FrameHeader(seq: 3, applied: 3, w: 1, h: 1, stride: 4, scale: 1, format: .rgba8sRGB, snapFrames: [snap], elements: ["card"],
                                              texts: [DrawnText(text: "t", rect: CGRect(x: 1, y: 2, width: 3, height: 4), font: "F", size: 12, weight: 400,
                                                                color: "#000000", element: "card")],
                                              styles: [DrawnStyle(id: "card", background: "#ffffff", radius: 8)], ms: 0, payload: .inline(bytes: 4)))
        let five = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v5.encode(frame)) as? [String: Any])
        #expect(five["texts"] == nil && five["styles"] == nil && five["snapFrames"] != nil && five["elements"] != nil)
        guard case .frame(let f) = try ProtocolDialect.v5.decode(ProtocolDialect.v5.encode(frame)) else { Issue.record(); return }
        #expect(f.texts == nil && f.styles == nil, "판 5 호스트의 머리 — 글줄 · 바탕 없음(nil)")
        #expect(f.snapFrames == [snap] && f.elements == ["card"], "경계 · 요소 목록(경계 수 대조)은 그대로")

        // 다른 메시지는 판 5 에서도 같은 줄
        for m in [Message.patch(Patch(seq: 4, edits: [Edit(field: "a", value: true)])), .ack(Ack(seq: 5, applied: 5, ms: 0)), .bye(Bye(reason: "r"))] {
            let a = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v5.encode(m)) as? [String: Any])
            let b = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(m)) as? [String: Any])
            #expect(NSDictionary(dictionary: a) == NSDictionary(dictionary: b), "\(m.type)")
        }
    }

    /// 판 5 ⟂ 6 이 섞일 때 — 판 6 엔진은 판 5 호스트를 판 5 의 말로 받는다(청함을 걷어 말하고 · 글줄 없는 머리를 읽는다) ·
    /// 판 5 엔진은 판 6 호스트를 「빌더를 업데이트하세요」로 거절하고(엔진이 판정자) · 판 6 호스트도 판 5 엔진의 hello 를 거절한다(같은 말 한 줄).
    @Test func versionsFiveAndSixMeet() throws {
        let six = ProtocolJudge(version: 6, dialects: [.v6, .v5])
        #expect(Self.taken(six.judge(host: 5)) == 5)
        #expect(Self.taken(ProtocolJudge.engine.judge(host: 5)) == 5, "지금 엔진도 판 5 호스트를 받는다")
        let fiveEngine = ProtocolJudge(version: 5, dialects: [ProtocolDialect(version: 5, lift: { $0 }, lower: { $0 })])
        #expect(Self.refused(fiveEngine.judge(host: 6)) == .hostNewer(host: 6, engine: 5))
        #expect(!ProtocolJudge.hostAccepts(engine: 5, host: 6) && ProtocolJudge.hostAccepts(engine: 6, host: 5))
        // 판 5 호스트가 보낸 머리(글줄 칸이 없는 줄)를 판 6 엔진이 판 5 의 말로 읽는다
        let line = Data(#"{"type":"frame","seq":1,"applied":1,"w":1,"h":1,"stride":4,"scale":1,"format":{"pixel":"RGBA8-premultipliedLast","colorSpace":"sRGB"},"snapFrames":[],"ms":0,"payload":{"inline":4}}"#.utf8)
        guard case .frame(let f) = try #require(try six.judge(host: 5).get()).decode(line) else { Issue.record(); return }
        #expect(f.texts == nil && f.styles == nil)
    }

    /// 판 7 → 6 내리기 — hello 의 Style 서술마다 절의 효과 선언(`elements[].effects`)을 걷는다(판 6 은 효과를 모른다 · 절의 다른 칸 · 문구 · 자리는 남는다) ·
    /// 올리기는 그대로(효과 없는 절 = 빈 목록) · `render` · `patch` · `frame` 은 판 6 에서도 같은 줄이다.
    @Test func loweringToSixDropsEffects() throws {
        let card = StyleElement(id: "card", label: "카드", snapPrefix: "garden.card", effects: [.glass, StyleEffect(rawValue: "ripple")])
        let schema = StyleSchema(screen: "s", elements: [card], fields: [StyleField(name: "cardShown", kind: .bool, element: card)],
                                 texts: [StyleText(name: "cardTitle", element: card, maxLength: 20)],
                                 slots: [StyleSlot(name: "cardPicture", element: card, snap: "garden.card.picture")],
                                 defaults: ["cardShown": true, "cardTitle": "카드"])
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", screens: [ScreenInfo(name: "s", states: [], style: schema)],
                                        layers: [LayerInfo(name: "chrome", style: schema)]))
        let native = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(hello)) as? [String: Any])
        let nativeEl = try #require((((native["screens"] as? [[String: Any]])?.first?["style"] as? [String: Any])?["elements"] as? [[String: Any]])?.first)
        #expect(nativeEl["effects"] as? [String] == ["glass", "ripple"], "지금 판의 줄엔 선언 차례 그대로 · 모르는 낱말도 글자 그대로")
        let line = try ProtocolDialect.v6.encode(hello)
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        for key in ["screens", "layers"] {
            let style = try #require((top[key] as? [[String: Any]])?.first?["style"] as? [String: Any])
            let el = try #require((style["elements"] as? [[String: Any]])?.first)
            #expect(el["effects"] == nil, "\(key) 의 절에서 효과 선언을 걷는다")
            #expect(el["id"] as? String == "card" && el["snapPrefix"] as? String == "garden.card")
            #expect(style["texts"] != nil && style["slots"] != nil && style["fields"] != nil, "판 6 의 칸(문구 · 자리 포함)은 남는다")
        }
        guard case .hello(let back) = try ProtocolDialect.v6.decode(line) else { Issue.record(); return }
        #expect(back.screens?.first?.style.elements.first?.effects == [], "판 6 의 줄은 선언 없는 절로 읽힌다")
        #expect(back.screens?.first?.style.slots.map(\.name) == ["cardPicture"] && back.screens?.first?.style.texts.map(\.name) == ["cardTitle"])

        let render = Message.render(RenderRequest(seq: 2, screen: "s", state: "n", style: ["cardShown": false], size: Size(w: 1, h: 1), scale: 1, drawn: true))
        let patch = Message.patch(Patch(seq: 3, edits: [Edit(field: "cardShown", value: true)]))
        for m in [render, patch] {
            let down = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v6.encode(m)) as? [String: Any])
            let n = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(m)) as? [String: Any])
            #expect(NSDictionary(dictionary: down) == NSDictionary(dictionary: n), "\(m.type) 의 줄은 판 6 에서도 같다")
        }
        // 판 5 로 내리면 효과 선언과 청함(`drawn`)이 둘 다 걷힌다
        let five = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v5.encode(hello)) as? [String: Any])
        let el5 = try #require((((five["screens"] as? [[String: Any]])?.first?["style"] as? [String: Any])?["elements"] as? [[String: Any]])?.first)
        #expect(el5["effects"] == nil)
    }

    /// 판 6 ⟂ 7 이 섞일 때 — 판 7 엔진은 판 6 호스트를 판 6 의 말로 받는다(효과 선언 없는 서술 = 빈 목록) ·
    /// 판 6 엔진은 판 7 호스트를 「빌더를 업데이트하세요」로 거절하고 · 판 7 호스트도 판 6 엔진의 hello 를 거절한다.
    @Test func versionsSixAndSevenMeet() throws {
        let seven = ProtocolJudge.engine
        #expect(seven.version == 7)
        #expect(Self.taken(seven.judge(host: 6)) == 6)
        let sixEngine = ProtocolJudge(version: 6, dialects: [ProtocolDialect(version: 6, lift: { $0 }, lower: { $0 })])
        #expect(Self.refused(sixEngine.judge(host: 7)) == .hostNewer(host: 7, engine: 6))
        #expect(!ProtocolJudge.hostAccepts(engine: 6, host: 7) && ProtocolJudge.hostAccepts(engine: 7, host: 6))
        // 판 6 호스트의 hello(절에 효과 칸이 없는 줄)를 판 7 엔진이 판 6 의 말로 읽는다
        let line = Data(#"{"type":"hello","role":"host","protocolVersion":6,"pid":1,"name":"h","screens":[{"name":"s","states":[],"style":{"screen":"s","elements":[{"id":"card","label":"카드","snapPrefix":"garden.card"}],"fields":[],"defaults":{}}}]}"#.utf8)
        let dialect = try seven.dialect(greeting: line)
        #expect(dialect.version == 6)
        guard case .hello(let h) = try dialect.decode(line) else { Issue.record(); return }
        #expect(h.screens?.first?.style.elements.first?.effects == [])
    }

    /// 판 5 → 4 내리기 — hello 의 Style 서술마다 자리 목록을 걷는다(판 4 는 자리를 모른다 · 문구는 남는다) · 올리기는 그대로(자리 없는 서술 = 빈 목록) ·
    /// `render` · `patch` 의 자리 값(Style 값 사전의 글자 칸)은 그대로 내려간다 — 판 4 의 호스트는 그것을 서술 밖 칸으로 뺀다(`StyleSchemaTests`).
    @Test func loweringToFourDropsSlots() throws {
        let el = StyleElement(id: "pot", label: "화분", snapPrefix: "pot")
        let schema = StyleSchema(screen: "s", elements: [el], fields: [StyleField(name: "potOn", kind: .bool, element: el)],
                                 texts: [StyleText(name: "potTitle", element: el, maxLength: 20)],
                                 slots: [StyleSlot(name: "potPicture", element: el, snap: "pot.picture")],
                                 defaults: ["potOn": true, "potTitle": "화분"])
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", screens: [ScreenInfo(name: "s", states: [], style: schema)],
                                        layers: [LayerInfo(name: "chrome", style: schema)]))
        let line = try ProtocolDialect.v4.encode(hello)
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        for key in ["screens", "layers"] {
            let style = try #require((top[key] as? [[String: Any]])?.first?["style"] as? [String: Any])
            #expect(style["slots"] == nil, "\(key) 의 서술에서 자리 목록을 걷는다")
            #expect(style["texts"] != nil && style["fields"] != nil && style["defaults"] != nil, "판 4 의 칸(문구 포함)은 남는다")
        }
        guard case .hello(let back) = try ProtocolDialect.v4.decode(line) else { Issue.record(); return }
        #expect(back.screens?.first?.style.slots == [], "판 4 의 줄은 자리 없는 서술로 읽힌다")
        #expect(back.screens?.first?.style.texts == schema.texts && back.screens?.first?.style.fields == schema.fields)

        let render = Message.render(RenderRequest(seq: 2, screen: "s", state: "n", style: ["potOn": false, "potPicture": "isomodel:fern"], size: Size(w: 1, h: 1), scale: 1))
        let patch = Message.patch(Patch(seq: 3, edits: [Edit(field: "potPicture", value: "")]))
        for m in [render, patch] {
            let down = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v4.encode(m)) as? [String: Any])
            let native = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(m)) as? [String: Any])
            #expect(NSDictionary(dictionary: down) == NSDictionary(dictionary: native), "\(m.type) 의 줄은 판 4 에서도 같다")
            #expect(try ProtocolDialect.v4.decode(ProtocolDialect.v4.encode(m)) == m)
        }
        // 판 3 으로 내리면 자리 · 문구 둘 다 걷힌다
        let three = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v3.encode(hello)) as? [String: Any])
        let style3 = try #require((three["screens"] as? [[String: Any]])?.first?["style"] as? [String: Any])
        #expect(style3["slots"] == nil && style3["texts"] == nil)
    }

    /// 판 4 → 3 내리기 — hello 의 Style 서술마다 문구 목록을 걷는다(판 3 은 문구를 모른다) · 올리기는 그대로(문구 없는 서술 = 빈 목록) ·
    /// `render` · `patch` 의 문구 값(Style 값 사전의 글자 칸)은 그대로 내려간다 — 판 3 의 호스트는 그것을 서술 밖 칸으로 뺀다(`StyleSchemaTests`).
    @Test func loweringToThreeDropsTexts() throws {
        let el = StyleElement(id: "pot", label: "화분", snapPrefix: "pot")
        let schema = StyleSchema(screen: "s", elements: [el], fields: [StyleField(name: "potOn", kind: .bool, element: el)],
                                 texts: [StyleText(name: "potTitle", element: el, maxLength: 20)], defaults: ["potOn": true, "potTitle": "화분"])
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", screens: [ScreenInfo(name: "s", states: [], style: schema)],
                                        layers: [LayerInfo(name: "chrome", style: schema)]))
        let line = try ProtocolDialect.v3.encode(hello)
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        for key in ["screens", "layers"] {
            let style = try #require((top[key] as? [[String: Any]])?.first?["style"] as? [String: Any])
            #expect(style["texts"] == nil, "\(key) 의 서술에서 문구 목록을 걷는다")
            #expect(style["fields"] != nil && style["defaults"] != nil)
        }
        guard case .hello(let back) = try ProtocolDialect.v3.decode(line) else { Issue.record(); return }
        #expect(back.screens?.first?.style.texts == [], "판 3 의 줄은 문구 없는 서술로 읽힌다")
        #expect(back.screens?.first?.style.fields == schema.fields)

        let render = Message.render(RenderRequest(seq: 2, screen: "s", state: "n", style: ["potOn": false, "potTitle": "새 화분"], size: Size(w: 1, h: 1), scale: 1))
        let patch = Message.patch(Patch(seq: 3, edits: [Edit(field: "potTitle", value: "다른 화분")]))
        for m in [render, patch] {
            let down = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.v3.encode(m)) as? [String: Any])
            let native = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(m)) as? [String: Any])
            #expect(NSDictionary(dictionary: down) == NSDictionary(dictionary: native), "\(m.type) 의 줄은 판 3 에서도 같다")
            #expect(try ProtocolDialect.v3.decode(ProtocolDialect.v3.encode(m)) == m)
        }
    }

    /// 판 3 → 2 내리기 — 이름 없는 조절판 칸에 칸 키를 이름으로 채운다(판 2 는 이름을 필수로 읽는다) · 올리기는 그대로.
    @Test func loweringToTwoFillsFieldNames() throws {
        let el = StyleElement(id: "pot", label: "화분", snapPrefix: "pot")
        let schema = StyleSchema(screen: "s", elements: [el], fields: [StyleField(name: "potGap", kind: .bool, element: el)], defaults: ["potGap": true])
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", screens: [ScreenInfo(name: "s", states: [], style: schema)]))
        let line = try ProtocolDialect.v2.encode(hello)
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let field = (((top["screens"] as? [[String: Any]])?.first?["style"] as? [String: Any])?["fields"] as? [[String: Any]])?.first
        #expect(field?["label"] as? String == "potGap")
        guard case .hello(let back) = try ProtocolDialect.v2.decode(line) else { Issue.record(); return }
        #expect(back.screens?.first?.style.fields.first?.label == "potGap", "판 2 의 줄은 이름이 찬 채 읽힌다")
    }

    /// 내리는 손이 nil 이면 그 판에 없는 메시지 — 줄을 짓지 않는다(`encodeIfSpoken` nil · `encode` 는 `notSpoken`) · 연결은 보내지 않고 거짓.
    @Test func aMessageTheOlderVersionDoesNotSpeakIsNotSent() throws {
        let ack = Message.ack(Ack(seq: 1, applied: 1, ms: 0))
        #expect(try Self.next.encodeIfSpoken(ack) == nil)
        #expect(try Self.ackless.encodeIfSpoken(ack) == nil, "사슬의 어느 스텝이 nil 이면 nil")
        #expect(try Self.ackless.encodeIfSpoken(.bye(Bye(reason: "x"))) != nil)
        #expect(throws: ProtocolDialectError.notSpoken(type: "ack", version: Self.now + 1)) { try Self.next.encode(ack) }
        #expect(try Framing.headerIfSpoken(ack, dialect: Self.next) == nil)
        #expect(throws: ProtocolDialectError.self) { try Framing.header(ack, dialect: Self.next) }
        #expect(try Self.next.encodeIfSpoken(.bye(Bye(reason: "x"))) != nil, "그 판에 있는 메시지는 짓는다")
    }

    @Test func readsTheVersionFromTheFirstLineBeforeTheBody() throws {
        #expect(try ProtocolJudge.engine.dialect(greeting: Self.hello(Self.now)).version == Self.now)
        #expect(throws: ProtocolMismatch.hostNewer(host: Self.now + 1, engine: Self.now)) { try ProtocolJudge.engine.dialect(greeting: Self.hello(Self.now + 1)) }
        #expect(throws: ProtocolMismatch.hostTooOld(host: nil, engine: Self.now)) { try ProtocolJudge.engine.dialect(greeting: Self.hello(nil)) }
        // 몸이 다른 꼴이어도(다음 판의 칸) 판만 읽는다 — 판정은 몸을 풀기 전이다
        let odd = try JSONSerialization.data(withJSONObject: ["type": "hello", "protocolVersion": Self.now + 1, "registry": [1, 2]])
        #expect(try Self.engineNext.dialect(greeting: odd).version == Self.now + 1)
        // 참/거짓은 판이 아니다 · 첫 줄이 hello 가 아니면 줄이 깨진 것
        let bool = try JSONSerialization.data(withJSONObject: ["type": "hello", "protocolVersion": true])
        #expect(throws: ProtocolMismatch.hostTooOld(host: nil, engine: Self.now)) { try ProtocolJudge.engine.dialect(greeting: bool) }
        #expect(throws: Framing.Failure.self) { try ProtocolJudge.engine.dialect(greeting: Data(#"{"type":"render"}"#.utf8)) }
        #expect(throws: Framing.Failure.self) { try ProtocolJudge.engine.dialect(greeting: Data("nope".utf8)) }
    }

    /// 옛 판의 말 — 내린 줄은 그 판의 꼴(표 · 바뀐 칸 이름) · 올리면 같은 메시지 · 큰 정수(seq · 시각 ns)는 깎이지 않는다.
    @Test func aDialectLowersAndLiftsWithoutLosingIntegers() throws {
        let big: UInt64 = 9_007_199_254_740_993   // 2^53 + 1 — Double 로 옮기면 깎인다
        let m = Message.frame(FrameHeader(seq: big, applied: big, w: 1, h: 1, stride: 4, scale: 2, format: .rgba8sRGB, snapFrames: [], ms: 0,
                                          payload: .inline(bytes: 4), timing: HostTiming(recv: big, start: big, rendered: big, sent: big)))
        let line = try Self.next.encode(m)
        let top = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(top["next"] as? Bool == true)
        #expect(top["pixelScale"] != nil && top["scale"] == nil)
        #expect(try Self.next.decode(line) == m)
        #expect(throws: Framing.Failure.self) { try Self.next.decode(try ProtocolDialect.current.encode(m)) }
        #expect(try ProtocolDialect.current.decode(ProtocolDialect.current.encode(m)) == m)
    }

    /// 엔진 쪽 디코더 — 첫 줄(호스트 hello)에서 판을 읽고 그 판의 말로 그 줄과 뒤의 줄을 읽는다. 판이 맞지 않으면 사람 말 그대로 던진다.
    @Test func streamDecoderPicksTheDialectFromTheGreeting() throws {
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h"))
        let render = Message.render(RenderRequest(seq: 3, screen: "s", state: "n", size: Size(w: 1, h: 1), scale: 2))
        var bytes = try Framing.header(hello) + Framing.header(render)
        var d = StreamDecoder(judge: Self.engineNext)
        var got = try bytes.withUnsafeBytes { try d.feed($0) }
        #expect(d.dialect.version == Self.now, "엔진 N+1 이 호스트 N 의 말을 골랐다")
        #expect(got.map(\.message) == [hello, render])

        let nextHello = Message.hello(Hello(role: .host, protocolVersion: Self.now + 1, pid: 1, name: "h"))
        bytes = try Framing.header(nextHello, dialect: Self.next) + Framing.header(render, dialect: Self.next)
        d = StreamDecoder(judge: Self.engineNext)
        got = try bytes.withUnsafeBytes { try d.feed($0) }
        #expect(d.dialect.version == Self.now + 1)
        #expect(got.map(\.message) == [nextHello, render])

        var refusing = StreamDecoder(judge: .engine)
        #expect(throws: ProtocolMismatch.hostNewer(host: Self.now + 1, engine: Self.now)) { _ = try bytes.withUnsafeBytes { try refusing.feed($0) } }
        // 판정자가 없는 디코더(호스트 쪽)는 첫 줄도 제 판의 말로 읽는다
        var plain = StreamDecoder()
        #expect(try (try Framing.header(hello)).withUnsafeBytes { try plain.feed($0) }.map(\.message) == [hello])
    }

    /// 호스트 쪽 — 엔진이 같거나 새 판이면 받는다(새 엔진이 호스트의 판으로 말한다) · 옛 판이면 거절한다.
    @Test func hostAcceptsTheSameOrANewerEngine() {
        #expect(ProtocolJudge.hostAccepts(engine: 3, host: 3))
        #expect(ProtocolJudge.hostAccepts(engine: 4, host: 3))
        #expect(!ProtocolJudge.hostAccepts(engine: 2, host: 3))
        #expect(ProtocolJudge.hostAccepts(engine: Self.now, host: Self.now))
    }

    /// 사람 말 한 줄 — 무엇을 올리나(빌더 ⟂ 프로젝트) · 판 숫자.
    @Test func mismatchSaysWhatToUpdate() {
        #expect(ProtocolMismatch.hostNewer(host: 2, engine: 1).description
                == "미리보기 호스트가 이 빌더보다 새 판입니다 — 빌더를 업데이트하세요 (프로토콜 판 호스트 2 · 빌더 1)")
        #expect(ProtocolMismatch.hostTooOld(host: 0, engine: 2).description
                == "미리보기 호스트가 이 빌더보다 옛 판입니다 — 프로젝트를 pull 하고 다시 여세요 (프로토콜 판 호스트 0 · 빌더 2)")
        #expect(!ProtocolMismatch.hostTooOld(host: nil, engine: 1).description.contains("\n"))
    }
}
