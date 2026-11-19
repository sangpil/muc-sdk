import CoreGraphics
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// 판 맞대기 — 판정 표(같은 판만 받는다 · 새 판 · 옛 판 · 판 없음) · 첫 줄의 판 읽기(몸을 풀기 전) · 디코더가 첫 줄에서 판을 가른다 · 큰 정수는 깎이지 않는다 ·
// 호스트 쪽 규칙 · 사람 말.

@Suite struct NegotiationTests {
    static let now = PreviewProtocolVersion.current

    static func hello(_ version: Int?) -> Data {
        var top: [String: Any] = ["type": "hello", "role": "host", "pid": 1, "name": "h"]
        if let version { top["protocolVersion"] = version }
        return try! JSONSerialization.data(withJSONObject: top)
    }

    /// 엔진은 제 판의 호스트만 받는다 — 새 판은 빌더를 올리고 · 옛 판 · 판 없음은 프로젝트를 받아 온다.
    @Test func judgeTakesOnlyItsOwnVersion() {
        let e = ProtocolJudge.engine, now = Self.now
        #expect(e.version == now)
        #expect(e.judge(host: now) == nil)
        #expect(e.judge(host: now + 1) == .hostNewer(host: now + 1, engine: now))
        #expect(e.judge(host: now - 1) == .hostTooOld(host: now - 1, engine: now), "옛 판의 호스트는 받지 않는다 — 호스트는 같은 SDK 판으로 함께 옮긴다")
        #expect(e.judge(host: nil) == .hostTooOld(host: nil, engine: now), "판을 못 읽으면 옛 판으로 본다")
        let next = ProtocolJudge(version: now + 1)
        #expect(next.judge(host: now + 1) == nil)
        #expect(next.judge(host: now) == .hostTooOld(host: now, engine: now + 1), "한 판 뒤도 받지 않는다")
    }

    @Test func readsTheVersionFromTheFirstLineBeforeTheBody() throws {
        try ProtocolJudge.engine.check(greeting: Self.hello(Self.now))
        #expect(throws: ProtocolMismatch.hostNewer(host: Self.now + 1, engine: Self.now)) { try ProtocolJudge.engine.check(greeting: Self.hello(Self.now + 1)) }
        #expect(throws: ProtocolMismatch.hostTooOld(host: Self.now - 1, engine: Self.now)) { try ProtocolJudge.engine.check(greeting: Self.hello(Self.now - 1)) }
        #expect(throws: ProtocolMismatch.hostTooOld(host: nil, engine: Self.now)) { try ProtocolJudge.engine.check(greeting: Self.hello(nil)) }
        // 몸이 다른 꼴이어도(다음 판의 칸) 판만 읽는다 — 판정은 몸을 풀기 전이다
        let odd = try JSONSerialization.data(withJSONObject: ["type": "hello", "protocolVersion": Self.now + 1, "registry": [1, 2]])
        try ProtocolJudge(version: Self.now + 1).check(greeting: odd)
        // 참/거짓은 판이 아니다 · 첫 줄이 hello 가 아니면 줄이 깨진 것
        let bool = try JSONSerialization.data(withJSONObject: ["type": "hello", "protocolVersion": true])
        #expect(throws: ProtocolMismatch.hostTooOld(host: nil, engine: Self.now)) { try ProtocolJudge.engine.check(greeting: bool) }
        #expect(throws: Framing.Failure.self) { try ProtocolJudge.engine.check(greeting: Data(#"{"type":"render"}"#.utf8)) }
        #expect(throws: Framing.Failure.self) { try ProtocolJudge.engine.check(greeting: Data("nope".utf8)) }
    }

    /// 줄은 지금 판의 꼴 — 큰 정수(seq · 시각 ns)는 깎이지 않는다.
    @Test func aLineKeepsBigIntegers() throws {
        let big: UInt64 = 9_007_199_254_740_993   // 2^53 + 1 — Double 로 옮기면 깎인다
        let m = Message.frame(FrameHeader(seq: big, applied: big, w: 1, h: 1, stride: 4, scale: 2, format: .rgba8sRGB, snapFrames: [], ms: 0,
                                          payload: .inline(bytes: 4), timing: HostTiming(recv: big, start: big, rendered: big, sent: big)))
        var d = StreamDecoder()
        let got = try (try Framing.header(m) + Data(count: 4)).withUnsafeBytes { try d.feed($0) }
        #expect(got.map(\.message) == [m])
    }

    /// 엔진 쪽 디코더 — 첫 줄(호스트 hello)에서 판을 가르고 그 줄과 뒤의 줄을 읽는다. 판이 맞지 않으면 사람 말 그대로 던진다(줄이 깨진 것과 가른다).
    @Test func streamDecoderJudgesTheGreeting() throws {
        let hello = Message.hello(Hello(role: .host, protocolVersion: Self.now, pid: 1, name: "h"))
        let render = Message.render(RenderRequest(seq: 3, screen: "s", state: "n", size: Size(w: 1, h: 1), scale: 2))
        let bytes = try Framing.header(hello) + Framing.header(render)
        var d = StreamDecoder(judge: .engine)
        #expect(try bytes.withUnsafeBytes { try d.feed($0) }.map(\.message) == [hello, render])

        var refusing = StreamDecoder(judge: ProtocolJudge(version: Self.now + 1))
        #expect(throws: ProtocolMismatch.hostTooOld(host: Self.now, engine: Self.now + 1)) { _ = try bytes.withUnsafeBytes { try refusing.feed($0) } }
        // 판정자가 없는 디코더(호스트 쪽)는 판을 가르지 않는다
        var plain = StreamDecoder()
        #expect(try (try Framing.header(hello)).withUnsafeBytes { try plain.feed($0) }.map(\.message) == [hello])
    }

    /// 호스트 쪽 — 엔진이 같거나 새 판이면 받는다(판이 다른 호스트는 엔진이 끊는다) · 옛 판이면 거절한다.
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
