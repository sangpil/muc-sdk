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
    static let engineNext = ProtocolJudge(version: now + 1, dialects: [next, .current, .v2])
    /// `ack` 가 없는 옛 판 1 의 말 — 스텝 1 → 2(시험용 · `ack` 를 내리면 nil) 뒤에 실제 스텝 2 → 3.
    static let ackless = ProtocolDialect.chain([ProtocolDialect.Step(from: 1, lift: { $0 }, lower: { $0["type"] as? String == "ack" ? nil : $0 }), .v2to3])

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

    /// 스텝 사슬 — 1 → 2 → 3 을 이은 말은 스텝을 차례로 손으로 밟은 것과 같다(올리기 · 내리기) · 판 1 의 줄은 판 3 의 메시지로 읽힌다.
    @Test func chainedStepsEqualTheDirectWalk() throws {
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h", ia: IAInfo(appScreens: ["a"], entryWords: [], entryHands: [:], aliases: [:], planned: []),
                                        frames: [], tokensBuilt: nil))
        let line = try ProtocolDialect.v1.encode(hello)
        let native = try #require(try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(hello)) as? ProtocolDialect.Line)
        let two = try #require(try ProtocolDialect.Step.v2to3.lower(native))
        let walked = try #require(try ProtocolDialect.Step.v1to2.lower(two))
        let chained = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(NSDictionary(dictionary: chained) == NSDictionary(dictionary: walked))
        guard case .hello(let back) = try ProtocolDialect.v1.decode(line) else { Issue.record("hello 가 아니다"); return }
        #expect(back.ia == nil && back.frames == nil, "판 1 은 프로젝트 데이터 칸이 없다")
        #expect(ProtocolDialect.v1.version == 1 && ProtocolDialect.v2.version == 2)
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
