import Foundation
import PreviewProtocol
import PreviewWire
import Testing

// 전송 — 소켓 쌍 위의 상주 연결(머리 + 5 MB 몸) · 상대의 죽음 · 공유 메모리 칸 · shm 이름 한계.
// 경로를 잡지 않는다 — 소켓은 이어진 한 쌍(`socketpair`) · shm 이름은 pid + 난수(시험끼리 · 다른 프로세스와 자리를 다투지 않게).

@Suite struct WireTests {
    @Test func connectionCarriesFramesWithoutUserCopy() throws {
        let (a, b) = try UnixSocket.pair()
        let tx = Connection(fd: a), rx = Connection(fd: b)
        let n = 780 * 4 * 1688
        let body = PayloadBuffer(count: n)
        for i in stride(from: 0, to: n, by: 4096) { body.base.storeBytes(of: UInt8(i / 4096 % 256), toByteOffset: i, as: UInt8.self) }
        let got = Box()
        let sem = DispatchSemaphore(value: 0)
        rx.start(name: "test.read", onInbound: { got.items.append($0); if got.items.count == 3 { sem.signal() } }, onClose: { _ in })
        let header = FrameHeader(seq: 1, applied: 1, w: 780, h: 1688, stride: 3120, scale: 2, format: .rgba8sRGB, snapFrames: [], ms: 0, payload: .inline(bytes: n))
        try tx.send(.patch(Patch(seq: 1, edits: [])))
        try tx.send(.frame(header), payload: body.bytes)
        try tx.send(.bye(Bye(reason: "끝")))
        #expect(sem.wait(timeout: .now() + 5) == .success)
        #expect(got.items.map(\.message.type) == ["patch", "frame", "bye"])
        let p = try #require(got.items[1].payload)
        #expect(memcmp(p.base, body.base, n) == 0)
        // 몸 대부분은 바로 읽기(복사 0) — 머리와 같은 read 로 딸려 온 앞부분만 옮겨진다(256 KB 읽기 버퍼보다 작다)
        #expect(rx.stats.payloadCopiedBytes < 256 << 10)
        #expect(rx.stats.payloadAllocs == 1)
        tx.close(); rx.close()
    }

    @Test func peerDeathIsSeenAsClose() throws {
        let (a, b) = try UnixSocket.pair()
        let rx = Connection(fd: b)
        let sem = DispatchSemaphore(value: 0)
        rx.start(name: "test.read", onInbound: { _ in }, onClose: { _ in sem.signal() })
        Darwin.close(a)
        #expect(sem.wait(timeout: .now() + 2) == .success)
    }

    @Test(arguments: [SharedMemoryInfo.Kind.posix, .file])
    func sharedRegionIsShared(kind: SharedMemoryInfo.Kind) throws {
        let info = SharedMemoryInfo(kind: kind, name: SharedRegion.name(kind: kind, tag: Int.random(in: 0..<99999)), slotBytes: 4096, slots: 3)
        let owner = try SharedRegion.create(info)
        let other = try SharedRegion.open(info)
        other.slot(2).storeBytes(of: 0xAB, toByteOffset: 7, as: UInt8.self)
        #expect(owner.slot(2).load(fromByteOffset: 7, as: UInt8.self) == 0xAB)
        #expect(owner.slot(1) - owner.slot(0) == 4096)
    }

    /// 상대의 판에 없는 메시지(말의 내리기가 nil)는 보내지 않는다 — `send` 가 거짓 · 뒤의 메시지는 그대로 간다.
    @Test func aMessageThePeerDoesNotSpeakIsNotSent() throws {
        let (a, b) = try UnixSocket.pair()
        let quiet = ProtocolDialect.chain([ProtocolDialect.Step(from: PreviewProtocolVersion.current - 1, lift: { $0 },
                                                                lower: { $0["type"] as? String == "ack" ? nil : $0 })])
        let tx = Connection(fd: a, dialect: quiet), rx = Connection(fd: b, dialect: quiet)
        let got = Box()
        let sem = DispatchSemaphore(value: 0)
        rx.start(name: "test.read", onInbound: { got.items.append($0); sem.signal() }, onClose: { _ in })
        #expect(try tx.send(.ack(Ack(seq: 1, applied: 1, ms: 0))) == false)
        #expect(try tx.send(.bye(Bye(reason: "끝"))) == true)
        #expect(sem.wait(timeout: .now() + 2) == .success)
        #expect(got.items.map(\.message.type) == ["bye"])
        tx.close(); rx.close()
    }

    /// 모르는 공유 메모리 종류 — 만들지도 열지도 않고 이름 대고 거절(호스트는 그때 소켓으로 보낸다).
    @Test func unknownSharedMemoryKindIsRefused() {
        let info = SharedMemoryInfo(kind: SharedMemoryInfo.Kind(rawValue: "mach"), name: "x", slotBytes: 1, slots: 1)
        #expect(throws: SharedRegion.Failure.self) { _ = try SharedRegion.open(info) }
        #expect(!SharedMemoryInfo.Kind.known.contains(info.kind))
    }

    @Test func posixNameLimit() {
        #expect(throws: SharedRegion.Failure.self) {
            _ = try SharedRegion.create(SharedMemoryInfo(kind: .posix, name: "/" + String(repeating: "x", count: 40), slotBytes: 1, slots: 1))
        }
    }
}

final class Box: @unchecked Sendable { var items: [Inbound] = [] }
