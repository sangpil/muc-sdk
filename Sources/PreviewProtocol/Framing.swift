import Foundation

// 줄 꼴 — 제어 메시지는 JSON 한 줄(`\n` 끝). 프레임 바이트가 소켓으로 갈 때(전송 A)는 `frame` 줄 바로 뒤에
// **u32 리틀 엔디언 길이 + 바이트**가 따라온다. 길이는 줄 안의 `payload.inline` 과 같아야 한다(어긋나면 스트림이 깨진 것 — 끊는다).
//
//   record = json-line "\n" [ u32le(n) bytes(n) ]   ; 대괄호는 `frame` 의 payload 가 inline 일 때만
//
// 디코더는 상태 기계 하나다. 바이트를 조각으로 먹이는 길(`feed` — 시험 · 작은 읽기)과, 바이너리를 기다리는 동안 소켓에서
// **목적지 버퍼로 바로** 읽는 길(`directTarget` → `didFillDirect` — 5 MB 급 프레임을 중간 복사 없이)이 같은 상태를 공유한다.
// 줄은 판 하나의 말(`ProtocolDialect`)로 읽고 쓴다 — 기본은 지금 판. 엔진 쪽 디코더는 판정자(`ProtocolJudge`)를 받아 첫 줄(호스트 hello)에서 판을 읽고
// 그 판의 말을 고른다(`dialect` — 연결이 같은 말로 쓴다).

public enum Framing {
    public static let maxLineBytes = 16 << 20
    public static let maxPayloadBytes = 256 << 20

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e
    }()

    /// 메시지 한 줄 + (inline 프레임이면) 길이 접두 — 판 하나의 말로(기본 지금 판). 바이트 몸은 호출자가 이어 쓴다(복사하지 않게).
    public static func header(_ message: Message, dialect: ProtocolDialect = .current) throws -> Data {
        var d = try dialect.encode(message)
        d.append(0x0A)
        if let n = message.inlineBytes {
            precondition(n >= 0 && n <= maxPayloadBytes, "프레임이 너무 크다: \(n)")
            var le = UInt32(n).littleEndian
            withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        }
        return d
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case lineTooLong(Int)
        case badJSON(String)
        case lengthMismatch(header: Int, prefix: Int)
        public var description: String {
            switch self {
            case .lineTooLong(let n): "줄이 너무 길다(\(n) 바이트) — 줄 끝(\\n)이 빠졌다"
            case .badJSON(let s): "JSON 을 못 읽었다: \(s)"
            case .lengthMismatch(let h, let p): "길이 접두 \(p) ≠ 머리 \(h) — 스트림이 깨졌다"
            }
        }
    }
}

/// 받은 프레임 바이트 — 한 번 할당해 끝까지 들고 간다(CGDataProvider 가 복사 없이 문다).
public final class PayloadBuffer: @unchecked Sendable {
    public let base: UnsafeMutableRawPointer
    public let count: Int
    public init(count: Int) {
        self.count = count
        base = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 64)
    }
    deinit { base.deallocate() }
    public var bytes: UnsafeRawBufferPointer { UnsafeRawBufferPointer(start: base, count: count) }
}

public struct Inbound: Sendable {
    public let message: Message
    public let payload: PayloadBuffer?
    public init(message: Message, payload: PayloadBuffer?) { self.message = message; self.payload = payload }
}

public struct StreamDecoder {
    private enum State {
        case line
        case prefix(Message, header: Int)
        case payload(Message, PayloadBuffer, filled: Int)
    }
    private var state: State = .line
    private var lineBuf: [UInt8] = []
    private var prefixBuf: [UInt8] = []
    private var ready: [Inbound] = []
    private let decoder = JSONDecoder()
    /// 줄을 읽는 판의 말 — 판정자가 있으면 첫 줄에서 고른다.
    public private(set) var dialect: ProtocolDialect
    /// 첫 줄(호스트 hello)의 판을 가르는 판정자 — 엔진 쪽만 · 첫 줄을 읽으면 놓는다.
    private var judge: ProtocolJudge?
    /// 계측 — 조각 길(`feed`)로 프레임 버퍼에 memcpy 한 바이트 · 프레임 버퍼 할당 수 · 바이트(바로 읽기 길은 복사 0).
    public private(set) var copiedBytes = 0
    public private(set) var allocs = 0
    public private(set) var allocBytes = 0

    /// `dialect` = 읽는 판의 말(기본 지금 판) · `judge` = 첫 줄에서 판을 가를 판정자(엔진 쪽 — 판이 맞지 않으면 `feed` 가 `ProtocolMismatch` 를 던진다).
    public init(dialect: ProtocolDialect = .current, judge: ProtocolJudge? = nil) {
        self.dialect = dialect; self.judge = judge
    }

    /// 조각을 먹인다 — 다 찬 메시지들을 돌려준다.
    public mutating func feed(_ chunk: UnsafeRawBufferPointer) throws -> [Inbound] {
        var i = 0
        let n = chunk.count
        while i < n {
            switch state {
            case .line:
                // 줄 끝을 찾는다 — 찾을 때까지 모은다
                let rest = UnsafeRawBufferPointer(rebasing: chunk[i..<n])
                if let nl = rest.firstIndex(of: 0x0A) {
                    lineBuf.append(contentsOf: rest[rest.startIndex..<nl])
                    i += nl - rest.startIndex + 1
                    try finishLine()
                } else {
                    lineBuf.append(contentsOf: rest)
                    i = n
                    if lineBuf.count > Framing.maxLineBytes { throw Framing.Failure.lineTooLong(lineBuf.count) }
                }
            case .prefix(let m, let header):
                let take = min(4 - prefixBuf.count, n - i)
                prefixBuf.append(contentsOf: chunk[i..<(i + take)])
                i += take
                if prefixBuf.count == 4 {
                    let len = Int(UInt32(prefixBuf[0]) | UInt32(prefixBuf[1]) << 8 | UInt32(prefixBuf[2]) << 16 | UInt32(prefixBuf[3]) << 24)
                    prefixBuf.removeAll(keepingCapacity: true)
                    guard len == header else { throw Framing.Failure.lengthMismatch(header: header, prefix: len) }
                    startPayload(m, len)
                }
            case .payload(let m, let buf, let filled):
                let take = min(buf.count - filled, n - i)
                (buf.base + filled).copyMemory(from: chunk.baseAddress! + i, byteCount: take)
                copiedBytes += take
                i += take
                advancePayload(m, buf, filled + take)
            }
        }
        defer { ready.removeAll(keepingCapacity: true) }
        return ready
    }

    /// 바이너리를 기다리는 중이면 남은 자리 — 호출자가 `read(2)` 로 바로 채운다.
    public func directTarget() -> UnsafeMutableRawBufferPointer? {
        guard case .payload(_, let buf, let filled) = state else { return nil }
        return UnsafeMutableRawBufferPointer(start: buf.base + filled, count: buf.count - filled)
    }

    /// `directTarget` 에 `n` 바이트를 채웠다 — 다 찼으면 그 메시지.
    public mutating func didFillDirect(_ n: Int) -> Inbound? {
        guard case .payload(let m, let buf, let filled) = state else { return nil }
        advancePayload(m, buf, filled + n)
        defer { ready.removeAll(keepingCapacity: true) }
        return ready.first
    }

    private mutating func finishLine() throws {
        defer { lineBuf.removeAll(keepingCapacity: true) }
        if lineBuf.isEmpty { return }   // 빈 줄은 건너뛴다(손으로 nc 칠 때)
        let line = Data(lineBuf)
        if let j = judge {
            judge = nil
            dialect = try j.dialect(greeting: line)   // 판이 맞지 않으면 그대로 던진다(사람 말 — 줄이 깨진 것과 가른다)
        }
        let m: Message
        do { m = try dialect.decode(line, using: decoder) }
        catch { throw Framing.Failure.badJSON(String(describing: error)) }
        if let n = m.inlineBytes { state = .prefix(m, header: n) } else { ready.append(Inbound(message: m, payload: nil)) }
    }

    private mutating func startPayload(_ m: Message, _ len: Int) {
        allocs += 1; allocBytes += len
        if len == 0 { ready.append(Inbound(message: m, payload: PayloadBuffer(count: 0))); state = .line; return }
        state = .payload(m, PayloadBuffer(count: len), filled: 0)
    }

    private mutating func advancePayload(_ m: Message, _ buf: PayloadBuffer, _ filled: Int) {
        if filled == buf.count { ready.append(Inbound(message: m, payload: buf)); state = .line }
        else { state = .payload(m, buf, filled: filled) }
    }
}
