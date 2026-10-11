#if os(macOS)
import Darwin
import Foundation
import PreviewProtocol

// 상주 연결 하나 — 쓰기는 락 하나로 줄 세우고(`writev` 로 머리 + 몸을 한 번에), 읽기는 전용 스레드가 돈다.
// 받은 메시지는 그 읽기 스레드에서 `onInbound` 로 넘긴다(어느 큐로 보낼지는 쓰는 쪽이 정한다 — 스레드 홉을 하나라도 덜게).
// 상대가 죽으면 읽기가 EOF(0)·오류를 보고 `onClose` 를 한 번 부른다 — 엔진의 크래시 감지가 이것이다.
// 읽고 쓰는 줄은 판 하나의 말(`dialect` — 기본 지금 판)이다. 엔진 쪽은 판정자를 넘겨(`start(judge:)`) 첫 줄(호스트 hello)에서 판을 가르고 그 판의 말로
// 갈아 탄다 — 그 hello 를 넘기기 **전에** 갈아 타므로 받는 쪽이 곧장 보내는 답(엔진 hello)부터 호스트의 판으로 나간다. 판이 맞지 않으면 끊고
// `onClose` 에 `ProtocolMismatch` 를 넘긴다.

/// 전송 계측 — 복사 바이트 · 할당 · 시스템 호출 수. 0-copy 구간을 숫자로 가리려고 연결마다 센다.
public struct WireStats: Sendable, Equatable {
    public var writeCalls = 0, readCalls = 0
    public var bytesOut = 0, bytesIn = 0
    /// 사용자 공간 memcpy 로 옮긴 프레임 바이트(읽기 임시 버퍼 → 프레임 버퍼). 바로 읽기(direct)면 0 이다.
    public var payloadCopiedBytes = 0
    /// 프레임 버퍼 할당 횟수 · 바이트
    public var payloadAllocs = 0, payloadAllocBytes = 0
    public init() {}
}

public final class Connection: @unchecked Sendable {
    public let fd: Int32
    private let writeLock = NSLock()
    private let statsLock = NSLock()
    private var _stats = WireStats()
    private var closed = false
    private let closeLock = NSLock()
    private let dialectLock = NSLock()
    private var _dialect: ProtocolDialect

    /// `dialect` = 처음 읽고 쓰는 판의 말(기본 지금 판 — 호스트는 늘 이것).
    public init(fd: Int32, dialect: ProtocolDialect = .current) { self.fd = fd; _dialect = dialect }
    deinit { close() }

    public var stats: WireStats { statsLock.withLock { _stats } }
    /// 지금 읽고 쓰는 판의 말.
    public var dialect: ProtocolDialect { dialectLock.withLock { _dialect } }
    public func resetStats() { statsLock.withLock { _stats = WireStats() } }

    /// 메시지 하나(+ inline 프레임 몸). 몸은 복사하지 않고 `writev` 로 커널에 바로 넘긴다.
    public func send(_ message: Message, payload: UnsafeRawBufferPointer? = nil) throws {
        let head = try Framing.header(message, dialect: dialect)
        precondition((message.inlineBytes ?? 0) == (payload?.count ?? 0), "머리의 inline 길이와 몸이 다르다")
        try writeLock.withLock {
            try head.withUnsafeBytes { h in
                if let p = payload, p.count > 0 { try writeAll([h, p]) } else { try writeAll([h]) }
            }
        }
    }

    private func writeAll(_ parts: [UnsafeRawBufferPointer]) throws {
        var iov = parts.map { iovec(iov_base: UnsafeMutableRawPointer(mutating: $0.baseAddress), iov_len: $0.count) }
        var idx = 0
        var calls = 0, total = 0
        while idx < iov.count {
            let n = iov[idx...].withUnsafeBufferPointer { writev(fd, $0.baseAddress, Int32($0.count)) }
            calls += 1
            if n < 0 {
                if errno == EINTR { continue }
                throw UnixSocket.Failure.sys("writev", errno)
            }
            total += n
            var left = n
            while idx < iov.count, left >= iov[idx].iov_len { left -= iov[idx].iov_len; idx += 1 }
            if idx < iov.count, left > 0 { iov[idx].iov_base += left; iov[idx].iov_len -= left }
        }
        statsLock.withLock { _stats.writeCalls += calls; _stats.bytesOut += total }
    }

    /// 읽기 스레드를 세운다. `onInbound` · `onClose` 는 그 스레드에서 불린다. `judge` = 첫 줄의 판을 가를 판정자(엔진 쪽).
    public func start(name: String, judge: ProtocolJudge? = nil, onInbound: @escaping @Sendable (Inbound) -> Void,
                      onClose: @escaping @Sendable (Error?) -> Void) {
        let t = Thread { [self] in readLoop(judge: judge, onInbound: onInbound, onClose: onClose) }
        t.name = name
        t.qualityOfService = .userInteractive
        t.start()
    }

    private func readLoop(judge: ProtocolJudge?, onInbound: @Sendable (Inbound) -> Void, onClose: @Sendable (Error?) -> Void) {
        var decoder = StreamDecoder(dialect: dialect, judge: judge)
        var reading = decoder.dialect.version
        /// 디코더가 첫 줄에서 판을 골랐으면 쓰기도 그 말로 — 받은 것을 넘기기 전에.
        func follow() {
            guard decoder.dialect.version != reading else { return }
            reading = decoder.dialect.version
            let d = decoder.dialect
            dialectLock.withLock { _dialect = d }
        }
        let tmpSize = 256 << 10
        let tmp = UnsafeMutableRawPointer.allocate(byteCount: tmpSize, alignment: 16)
        defer { tmp.deallocate() }
        var calls = 0, bytes = 0
        var seen = (copied: 0, allocs: 0, allocBytes: 0)
        func flushStats() {
            let d = (copied: decoder.copiedBytes - seen.copied, allocs: decoder.allocs - seen.allocs, allocBytes: decoder.allocBytes - seen.allocBytes)
            seen = (decoder.copiedBytes, decoder.allocs, decoder.allocBytes)
            statsLock.withLock {
                _stats.readCalls += calls; _stats.bytesIn += bytes
                _stats.payloadCopiedBytes += d.copied; _stats.payloadAllocs += d.allocs; _stats.payloadAllocBytes += d.allocBytes
            }
            calls = 0; bytes = 0
        }
        func ended(_ n: Int) -> Bool {
            guard n <= 0 else { return false }
            flushStats()
            finish(onClose, n == 0 ? nil : UnixSocket.Failure.sys("read", errno))
            return true
        }
        while true {
            // 프레임 몸을 기다리는 중이면 목적지 버퍼로 바로 — 중간 복사 0
            if let dst = decoder.directTarget() {
                let n = read(fd, dst.baseAddress, dst.count)
                calls += 1
                if n < 0, errno == EINTR { continue }
                if ended(n) { return }
                bytes += n
                if let m = decoder.didFillDirect(n) { flushStats(); onInbound(m) }
                continue
            }
            let n = read(fd, tmp, tmpSize)
            calls += 1
            if n < 0, errno == EINTR { continue }
            if ended(n) { return }
            bytes += n
            do {
                let got = try decoder.feed(UnsafeRawBufferPointer(start: tmp, count: n))
                follow()
                if !got.isEmpty { flushStats(); for m in got { onInbound(m) } }
            } catch {
                flushStats(); finish(onClose, error); return
            }
        }
    }

    private func finish(_ onClose: @Sendable (Error?) -> Void, _ error: Error?) {
        close()
        onClose(error)
    }

    public func close() {
        closeLock.withLock {
            guard !closed else { return }
            closed = true
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }
}
#endif
