#if os(macOS)
import AppKit
import Foundation
import PreviewProtocol
import PreviewWire
import SwiftUI

// 호스트의 몸 — 연결 하나(= 세션 하나)를 받아 메시지를 처리한다. 호스트 프로세스는 연결마다 몸 하나를 세운다(`HostListener`). 읽기 스레드는 받은 것을 **우편함**에 넣고 메인에 한 번만 깨운다.
// 우편함은 연달아 온 patch 를 하나로 합친다(칸마다 마지막 값 · 입력 번호는 가장 큰 것) — 엔진이 최신값 우선으로 보내도
// 메인이 바쁜 사이 둘 이상 쌓일 수 있다(진행 중 한도 > 1 · 엔진 재연결 직후). 한 바퀴에 렌더는 한 장.
// 장을 그리기 전마다 세션의 준비(`PreviewSession.prepare` — 모델 그림 같은 비동기 원천)를 기다린다 — 처리는 메인 액터의 한 줄(`drain`)이라
// 기다리는 동안 메인은 비고(원천의 일이 메인에서 돈다) · 뒤에 온 메시지는 차례대로 그 뒤에 선다(우편함이 받아 두고 patch 는 합친다).
// 준비에는 시한이 있다(`prepareLimit` — 넘기면 취소하고 그때의 값으로 그린다) · 세션이 닫히면 기다리던 준비를 놓고 남은 우편을 버린다(닫힌 세션을 되살리지 않는다) ·
// 한 바퀴마다 메인을 한 번 내준다(쉬지 않는 연결이 다른 세션 · 이벤트를 굶기지 않게).

final class Mailbox: @unchecked Sendable {
    enum Item { case message(Message), patch(Patch) }
    private let lock = NSLock()
    private var items: [(item: Item, recv: UInt64)] = []
    private var scheduled = false

    /// 넣는다 — 메인을 깨워야 하면 참.
    func push(_ m: Message, recv: UInt64) -> Bool {
        lock.withLock {
            if case .patch(let p) = m {
                if let last = items.last, case .patch(let q) = last.item {
                    var merged: [String: Edit] = [:]
                    var order: [String] = []
                    for e in q.edits + p.edits {
                        let k = (e.layer ?? "") + "\u{1}" + e.field
                        if merged.updateValue(e, forKey: k) == nil { order.append(k) }
                    }
                    items[items.count - 1] = (.patch(Patch(seq: max(p.seq, q.seq), edits: order.map { merged[$0]! })), last.recv)
                } else {
                    items.append((.patch(p), recv))
                }
            } else {
                items.append((.message(m), recv))
            }
            if scheduled { return false }
            scheduled = true
            return true
        }
    }

    func drain() -> [(item: Item, recv: UInt64)] {
        lock.withLock { defer { items.removeAll(keepingCapacity: true); scheduled = false }; return items }
    }
}

@MainActor
final class HostServer {
    let screens: [String: any PreviewScreen]
    /// 받기 스레드가 이어 준 연결 — 첫 메시지와 함께 메인에 들어온다(hello 는 받기 스레드가 이미 보냈다)
    var conn: Connection!
    nonisolated let mailbox = Mailbox()
    /// 렌더러는 같은 render(값 · 틀까지 같은 요청)와 그 위의 patch 사이에서만 다시 쓴다 — 다른 render 는 새 렌더러로 그린다.
    /// 다시 쓴 렌더러는 앞 장의 뷰 그래프(@State · 래스터 캐시)를 들고 있어 같은 값의 새 장과 다른 바이트를 낸다(테마를 바꾼 다음 장에 앞 장의 래스터가 남는다). render 한 장 = 그 값의 새 그림이어야 찍기 · 비교가 선다.
    var renderer: FrameRenderer!   // 첫 render 가 세운다(받기 스레드가 몸을 세우므로 메인 액터의 렌더러는 그 뒤에)
    private var renderKey: RenderRequest?
    let onTokensChanged: @MainActor () -> Void

    var region: SharedRegion?
    var slotCursor = 0
    var current: (key: String, session: any PreviewSession)?
    var request: RenderRequest?
    var appliedSeq: UInt64 = 0
    var presenter: WindowPresenter?

    nonisolated init(screens: [any PreviewScreen], onTokensChanged: @escaping @MainActor () -> Void) {
        self.screens = Dictionary(uniqueKeysWithValues: screens.map { ($0.name, $0) })
        self.onTokensChanged = onTokensChanged
    }

    /// 받기 스레드에서 — hello 를 곧장 보내고(메인이 NSApplication 을 세우는 동안 엔진이 등록부를 받는다) 읽기를 세운다.
    /// 읽은 것은 우편함으로 · 메인은 런루프가 선 뒤에 처리한다. 연결이 닫히면 `onClose`(읽기 스레드에서 한 번).
    nonisolated func attach(_ conn: Connection, hello: Hello, onClose: @escaping @Sendable () -> Void) throws {
        try conn.send(.hello(hello))
        HostTrace.mark("hello 보냄")
        let box = mailbox
        conn.start(name: "preview-host.read", onInbound: { [self] inbound in
            let t = PreviewClock.now()
            if box.push(inbound.message, recv: t) {
                Task { @MainActor in self.conn = conn; await self.drain() }
            }
        }, onClose: { _ in onClose() })
    }

    /// 우편함을 비울 때까지 차례대로 — 이미 도는 줄이 있으면 곧장 돌아온다(그 줄이 새로 온 것까지 집는다). 돌아오면 우편함이 비었다.
    private var draining = false
    /// 세션이 닫혔다(`shutdown`) — 줄은 남은 우편을 버리고 끝난다.
    private(set) var closed = false
    func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while true {
            let items = mailbox.drain()
            if items.isEmpty || closed { return }
            let start = PreviewClock.now()
            for (item, recv) in items {
                if closed { return }
                do {
                    switch item {
                    case .patch(let p): try await handlePatch(p, recv: recv, start: start)
                    case .message(let m): try await handle(m, recv: recv, start: start)
                    }
                } catch {
                    let seq: UInt64? = switch item { case .patch(let p): p.seq; case .message(let m): m.seq }
                    _ = try? conn.send(.error(ErrorMessage(seq: seq, message: String(describing: error))))
                }
            }
            await Task.yield()   // 한 바퀴마다 메인을 내준다 — 기다릴 것 없는 준비는 멈추지 않으므로 이것이 없으면 쉬지 않는 연결이 메인을 쥔다
        }
    }

    /// 준비 하나의 시한 — 엔진이 장을 기다리는 시한(원격 장 30 s) 안. 넘기면 준비를 취소하고 그때의 값으로 그린다.
    package static var prepareLimit: Duration = .seconds(20)
    /// 지금 기다리는 준비 — 닫힐 때 놓는다.
    private var waiting: PrepareWait?

    /// 준비 하나의 끝 — 준비가 돌아옴 ⟂ 시한 ⟂ 닫힘 중 먼저 온 것 하나만 기다림을 푼다.
    @MainActor final class PrepareWait {
        private var continuation: CheckedContinuation<Void, Never>?
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
        func arm(_ c: CheckedContinuation<Void, Never>) { continuation = c }
        func finish() {
            guard let c = continuation else { return }
            continuation = nil
            work?.cancel(); timer?.cancel()
            c.resume()
        }
    }

    /// 세션의 준비를 이 틀로 기다린다(시한 · 닫힘이 먼저면 취소하고 놓는다) — 그 사이 세션이 닫히거나(`shutdown`) 다른 화면으로 갈렸으면 거짓(이 장은 그리지 않는다).
    private func prepared(_ session: any PreviewSession, _ ctx: RenderContext) async -> Bool {
        let wait = PrepareWait()
        waiting = wait
        let limit = Self.prepareLimit
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            wait.arm(c)
            wait.work = Task { @MainActor in await session.prepare(ctx); wait.finish() }
            wait.timer = Task { @MainActor in
                guard (try? await Task.sleep(for: limit)) != nil else { return }
                wait.finish()
            }
        }
        if waiting === wait { waiting = nil }
        return !closed && current?.session === session
    }

    private func handle(_ m: Message, recv: UInt64, start: UInt64) async throws {
        switch m {
        case .hello(let h):
            // 판 — 엔진이 판정자다(새 엔진은 이 호스트의 판으로 말한다). 엔진이 옛 판이면 이 꼴을 모른다 — 사람 말을 오류로 보내고 끊는다(엔진의 떠남과 같은 길로 끝난다)
            guard ProtocolJudge.hostAccepts(engine: h.protocolVersion, host: PreviewProtocolVersion.current) else {
                let why = ProtocolMismatch.hostNewer(host: PreviewProtocolVersion.current, engine: h.protocolVersion).description
                FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(why)\n".utf8))
                _ = try? conn.send(.error(ErrorMessage(seq: nil, message: why)))
                conn.close()
                return
            }
            // 모르는 전송 종류면 공유 메모리를 쓰지 않는다(프레임은 소켓으로 — 전송 A)
            if let s = h.shared, SharedMemoryInfo.Kind.known.contains(s.kind) { region = try SharedRegion.open(s); slotCursor = 0 } else { region = nil }
        case .render(let r):
            request = r
            appliedSeq = max(appliedSeq, r.seq)
            var fresh = r
            fresh.seq = 0; fresh.frames = nil
            if fresh != renderKey { renderer = FrameRenderer(); renderKey = fresh }
            let key = "\(r.screen)|\(r.state)"
            if current?.key != key {
                guard let screen = screens[r.screen] else { throw PreviewHostError.unknownScreen(r.screen) }
                HostTrace.mark("세션 시작 \(key)")
                current = (key, try screen.session(state: r.state))
                HostTrace.mark("세션 섬")
            }
            // 값은 render 가 갈아 끼운다(엔진이 안 파일에서 읽은 것 · 픽스처 갈아 끼우기) — 앞 patch 는 그 밑에 묻힌다
            let session = current!.session
            try session.load(style: r.style, layers: r.layers ?? [], fixture: r.fixture)
            guard await prepared(session, context(r, offscreen: true)) else { return }
            // 자기 창이 서 있으면 그 창도 새 값 · 틀로(답은 늘 그 값의 프레임 — 엔진이 창 밑에 둔다)
            if let p = presenter { p.resize(to: CGSize(width: r.size.w, height: r.size.h)); p.update(session.view(context(r, offscreen: false))) }
            try produce(seq: r.seq, recv: recv, start: start)
            HostTrace.mark("프레임 보냄 \(r.seq)")
        case .tokensChanged(let t):
            onTokensChanged()
            renderer = FrameRenderer(); renderKey = nil   // 토큰 값이 바뀌었다 — 앞 장의 뷰 그래프를 버린다
            if let cur = current, let req = request { guard await prepared(cur.session, context(req, offscreen: true)) else { return } }
            if let p = presenter, let req = request, let cur = current { p.update(cur.session.view(context(req, offscreen: false))) }
            try produce(seq: t.seq, recv: recv, start: start)
        case .shot(let s):
            guard let req = request, let cur = current else { throw PreviewHostError.noSession }
            guard await prepared(cur.session, context(req, offscreen: true)) else { return }
            let t0 = PreviewClock.now()
            let f = try renderer.render(cur.session.view(context(req, offscreen: true)), size: CGSize(width: req.size.w, height: req.size.h), scale: req.scale)
            try FrameRenderer.writePNG(f.image, to: URL(fileURLWithPath: s.path))
            try conn.send(.ack(Ack(seq: s.seq, applied: appliedSeq, ms: PreviewClock.ms(t0, PreviewClock.now()))))
        case .window(let w):
            guard let req = request, let cur = current else { throw PreviewHostError.noSession }
            if !w.show {
                presenter?.hide(); presenter = nil
                try conn.send(.ack(Ack(seq: w.seq, applied: appliedSeq, ms: PreviewClock.ms(start, PreviewClock.now()))))
                return
            }
            guard await prepared(cur.session, context(req, offscreen: false)) else { return }
            let size = CGSize(width: w.w ?? req.size.w, height: w.h ?? req.size.h)
            let p = presenter ?? WindowPresenter(size: size, origin: CGPoint(x: w.x, y: w.y))
            presenter = p
            let before = cur.session.snapFrames()
            p.resize(to: size)
            p.clip(to: w.clip)
            p.update(cur.session.view(context(req, offscreen: false)))
            p.show(at: CGPoint(x: w.x, y: w.y), above: w.above)
            ackAfterCommit(seq: w.seq, recv: recv, start: start, before: before)
        case .bye:
            conn.close()   // 이 세션만 끝난다 — 프로세스는 연결이 모두 닫히면 끝난다(`HostListener`)
        case .frame, .ack, .error, .patch:
            break
        }
    }

    /// 세션이 닫혔다 — 자기 창을 내리고 · 공유 메모리 칸 · 세션 값 · 렌더러를 놓는다(메인에서 · 연결이 닫힌 뒤 한 번).
    func shutdown() {
        closed = true
        waiting?.finish(); waiting = nil   // 기다리던 준비를 취소하고 놓는다 — 줄은 닫힘을 보고 남은 우편을 버린다
        _ = mailbox.drain()
        presenter?.hide(); presenter = nil
        region = nil; current = nil; request = nil; renderer = nil
    }

    private func handlePatch(_ p: Patch, recv: UInt64, start: UInt64) async throws {
        guard let cur = current else { throw PreviewHostError.noSession }
        let before = presenter == nil ? [] : cur.session.snapFrames()
        for e in p.edits { try cur.session.apply(e) }
        appliedSeq = max(appliedSeq, p.seq)
        if let req = request { guard await prepared(cur.session, context(req, offscreen: presenter == nil)) else { return } }
        if let pres = presenter, let req = request {
            pres.update(cur.session.view(context(req, offscreen: false)))
            ackAfterCommit(seq: p.seq, recv: recv, start: start, before: before)
        } else {
            try produce(seq: p.seq, recv: recv, start: start)
        }
    }

    private func context(_ r: RenderRequest, offscreen: Bool) -> RenderContext {
        RenderContext(size: CGSize(width: r.size.w, height: r.size.h), theme: r.theme, layers: (r.layers ?? []).map(\.name),
                      offscreen: offscreen, interactive: !offscreen, scrollY: offscreen ? CGFloat(r.scroll ?? 0) : 0, layersOnly: r.layersOnly == true)
    }

    /// 지금 값으로 한 장 — 소켓(전송 A)이면 렌더러 바이트를 그대로 `writev`(사용자 공간 복사 0) ·
    /// 칸(전송 B)이면 칸에 memcpy 한 번 하고 칸 번호만 보낸다.
    private func produce(seq: UInt64, recv: UInt64, start: UInt64) throws {
        guard let req = request, let cur = current else { throw PreviewHostError.noSession }
        let view = cur.session.view(context(req, offscreen: true))
        let t0 = PreviewClock.now()
        let f = try renderer.render(view, size: CGSize(width: req.size.w, height: req.size.h), scale: req.scale)
        let t1 = PreviewClock.now()
        let payload: FramePayload
        var body: UnsafeRawBufferPointer?
        if let region, f.bytes <= region.info.slotBytes {
            // 칸을 돌려 쓴다 — 진행 중 요청이 하나면 엔진이 보고 있는 칸(직전 프레임)은 건드리지 않는다
            let slot = slotCursor
            slotCursor = (slotCursor + 1) % region.info.slots
            region.slot(slot).copyMemory(from: f.base, byteCount: f.bytes)
            payload = .slot(index: slot, bytes: f.bytes)
        } else {
            payload = .inline(bytes: f.bytes)
            body = UnsafeRawBufferPointer(start: f.base, count: f.bytes)
        }
        let rendered = PreviewClock.now()
        let wantsFrames = req.frames == true
        // 층만 그린 장은 층의 요소만 낸다(본체를 그리지 않았다 — 경계 수 대조가 그 장에서도 선다)
        let reports = wantsFrames ? cur.session.layerReports() : nil
        let elements = wantsFrames ? (req.layersOnly == true ? (reports ?? []).flatMap(\.elements) : cur.session.elementIDs()) : nil
        let header = FrameHeader(seq: seq, applied: appliedSeq, w: f.w, h: f.h, stride: f.stride, scale: req.scale, format: .rgba8sRGB,
                                 snapFrames: wantsFrames ? cur.session.snapFrames() : [], elements: elements, layers: reports,
                                 ms: PreviewClock.ms(t0, t1), payload: payload,
                                 timing: HostTiming(recv: recv, start: start, rendered: rendered, sent: PreviewClock.now()))
        _ = try withExtendedLifetime(f) { try conn.send(.frame(header), payload: body) }
    }

    /// 창 모드의 답 — 그 바퀴의 커밋이 끝난 뒤 ack.
    private func ackAfterCommit(seq: UInt64, recv: UInt64, start: UInt64, before: [SnapFrame]) {
        let applied = appliedSeq
        let session = current?.session
        let conn = conn!
        HostCommit.next {
            let t = PreviewClock.now()
            let changed = session.map { $0.snapFrames() != before }
            _ = try? conn.send(.ack(Ack(seq: seq, applied: applied, ms: PreviewClock.ms(start, t),
                                    timing: HostTiming(recv: recv, start: start, rendered: t, sent: t), changed: changed)))
        }
    }
}
#endif
