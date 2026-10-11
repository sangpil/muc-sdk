import Foundation
import Testing
import PreviewProtocol

// 줄 + 길이 접두 프레이밍 — 조각이 어디서 끊겨도 같은 메시지가 서야 한다.

@Suite struct FramingTests {
    func record(_ m: Message, payload: [UInt8] = []) throws -> [UInt8] { Array(try Framing.header(m)) + payload }

    func frame(_ n: Int, seq: UInt64 = 1) -> Message {
        .frame(FrameHeader(seq: seq, applied: seq, w: 1, h: n / 4, stride: 4, scale: 1, format: .rgba8sRGB, snapFrames: [], ms: 0, payload: .inline(bytes: n)))
    }

    func feedAll(_ bytes: [UInt8], chunk: Int) throws -> [Inbound] {
        var d = StreamDecoder(), out: [Inbound] = []
        var i = 0
        while i < bytes.count {
            let end = min(bytes.count, i + chunk)
            out += try bytes[i..<end].withUnsafeBytes { try d.feed($0) }
            i = end
        }
        return out
    }

    @Test(arguments: [1, 3, 7, 64, 4096])
    func survivesAnyChunking(chunk: Int) throws {
        let body = (0..<400).map { UInt8($0 % 251) }
        let stream = try record(.patch(Patch(seq: 1, edits: [Edit(field: "a", value: .pt(1))])))
            + record(frame(400, seq: 2), payload: body)
            + Array("\n".utf8)   // 빈 줄은 건너뛴다
            + record(.bye(Bye(reason: "끝")))
        let got = try feedAll(stream, chunk: chunk)
        #expect(got.map(\.message.type) == ["patch", "frame", "bye"])
        #expect(got[1].payload.map { Array($0.bytes) } == body)
    }

    @Test func zeroLengthPayload() throws {
        let got = try feedAll(try record(frame(0)), chunk: 5)
        #expect(got.count == 1 && got[0].payload?.count == 0)
    }

    @Test func lengthPrefixMustMatchHeader() throws {
        var bytes = Array(try Framing.header(frame(8)))
        bytes[bytes.count - 4] = 9   // 접두를 9 로 망가뜨린다
        #expect(throws: Framing.Failure.lengthMismatch(header: 8, prefix: 9)) { _ = try feedAll(bytes, chunk: 64) }
    }

    @Test func badJSONIsReported() {
        #expect(throws: Framing.Failure.self) { _ = try feedAll(Array("{nope\n".utf8), chunk: 64) }
    }

    /// 바로 읽기 길 — 머리는 조각으로, 몸은 목적지에 바로. 같은 상태 기계라 섞어도 맞다.
    @Test func directFillPath() throws {
        let body = (0..<1000).map { UInt8($0 % 256) }
        let head = try record(frame(1000))
        var d = StreamDecoder()
        // 머리 + 몸 앞 10 바이트를 조각으로
        let first = head + body[0..<10]
        #expect(try first.withUnsafeBytes { try d.feed($0) }.isEmpty)
        #expect(d.copiedBytes == 10 && d.allocs == 1)
        let dst = try #require(d.directTarget())
        #expect(dst.count == 990)
        body[10...].withUnsafeBytes { dst.copyMemory(from: $0) }
        let filled = d.didFillDirect(990)
        let m = try #require(filled)
        #expect(Array(m.payload!.bytes) == body)
        #expect(d.directTarget() == nil)
    }
}
