import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// 판 맞대기 — 판정 표(같은 판 · 한 판 뒤 · 새 판 · 너무 옛 판 · 판 없음) · 첫 줄의 판 읽기(몸을 풀기 전) · 옛 판의 말(줄 올리기 · 내리기 — 정수 그대로) ·
// 디코더가 첫 줄에서 말을 고른다 · 호스트 쪽 규칙 · 판 1 은 한 판 뒤가 없다 · 문서의 판 글자.

@Suite struct NegotiationTests {
    static let now = PreviewProtocolVersion.current
    /// 가짜 다음 판(N+1) — 칸 이름 하나가 바뀌고(`scale` → `pixelScale`) 줄마다 표 `next` 가 붙은 꼴.
    static let next = ProtocolDialect(version: now + 1, lift: { line in
        var l = line
        guard l.removeValue(forKey: "next") as? Bool == true else { throw Framing.Failure.badJSON("판 표 없음") }
        if let v = l.removeValue(forKey: "pixelScale") { l["scale"] = v }
        return l
    }, lower: { line in
        var l = line
        if let v = l.removeValue(forKey: "scale") { l["pixelScale"] = v }
        l["next"] = true
        return l
    })
    static let engineNext = ProtocolJudge(version: now + 1, dialects: [next, .current])

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

    @Test func judgeTakesTheSameVersionAndOneBehindOnly() {
        let e = ProtocolJudge.engine, now = Self.now
        #expect(Self.taken(e.judge(host: now)) == now)
        #expect(Self.refused(e.judge(host: now + 1)) == .hostNewer(host: now + 1, engine: now))
        #expect(Self.refused(e.judge(host: now - 2)) == .hostTooOld(host: now - 2, engine: now))
        #expect(Self.refused(e.judge(host: nil)) == .hostTooOld(host: nil, engine: now), "판을 못 읽으면 옛 판으로 본다")

        let n = Self.engineNext
        #expect(Self.taken(n.judge(host: now + 1)) == now + 1, "같은 판")
        #expect(Self.taken(n.judge(host: now)) == now, "한 판 뒤 — 그 판의 말")
        #expect(Self.refused(n.judge(host: now - 1)) == .hostTooOld(host: now - 1, engine: now + 1), "두 판 뒤는 받지 않는다")
        #expect(Self.refused(n.judge(host: now + 2)) == .hostNewer(host: now + 2, engine: now + 1))
        let bare = ProtocolJudge(version: now + 1, dialects: [Self.next])
        #expect(Self.refused(bare.judge(host: now)) == .hostTooOld(host: now, engine: now + 1), "한 판 뒤의 말이 없으면 받지 않는다")
    }

    /// 판을 올리는 변경은 한 판 뒤의 말을 함께 낸다 — 이 엔진이 지금 판과 (판 2 부터) 한 판 뒤를 받는다. 판 1 은 한 판 뒤가 없다.
    @Test func theEngineCarriesTheDialectOfOneVersionBehind() {
        let e = ProtocolJudge.engine
        #expect(e.version == Self.now)
        #expect(e.dialects[Self.now] != nil)
        if Self.now > 1 {
            #expect(e.dialects[Self.now - 1] != nil, "판을 올렸으면 한 판 뒤(N-1)의 말을 `PreviewProtocolVersion.previous` 에 더하라")
        } else {
            #expect(PreviewProtocolVersion.previous.isEmpty)
        }
        #expect(PreviewProtocolVersion.previous.allSatisfy { $0.version == Self.now - 1 }, "받는 옛 판은 한 판 뒤 하나")
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
