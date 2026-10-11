#if os(macOS)
import AppKit
import Foundation
import PreviewProtocol
import PreviewWire
import SwiftUI

// 호스트의 몸 — 연결 하나를 받아 메시지를 처리한다. 읽기 스레드는 받은 것을 **우편함**에 넣고 메인에 한 번만 깨운다.
// 우편함은 연달아 온 patch 를 하나로 합친다(칸마다 마지막 값 · 입력 번호는 가장 큰 것) — 엔진이 최신값 우선으로 보내도
// 메인이 바쁜 사이 둘 이상 쌓일 수 있다(진행 중 한도 > 1 · 엔진 재연결 직후). 한 바퀴에 렌더는 한 장.

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
    var renderer = FrameRenderer()
    private var renderKey: RenderRequest?
    let onTokensChanged: @MainActor () -> Void

    var region: SharedRegion?
    var slotCursor = 0
    var current: (key: String, session: any PreviewSession)?
    var request: RenderRequest?
    var appliedSeq: UInt64 = 0
    var presenter: WindowPresenter?

    init(screens: [any PreviewScreen], onTokensChanged: @escaping @MainActor () -> Void) {
        self.screens = Dictionary(uniqueKeysWithValues: screens.map { ($0.name, $0) })
        self.onTokensChanged = onTokensChanged
    }

    /// 받기 스레드에서 — hello 를 곧장 보내고(메인이 NSApplication 을 세우는 동안 엔진이 등록부를 받는다) 읽기를 세운다.
    /// 읽은 것은 우편함으로 · 메인은 런루프가 선 뒤에 처리한다.
    nonisolated func attach(_ conn: Connection, hello: Hello) throws {
        try conn.send(.hello(hello))
        Trace.mark("hello 보냄")
        let box = mailbox
        conn.start(name: "preview-host.read", onInbound: { [self] inbound in
            let t = PreviewClock.now()
            if box.push(inbound.message, recv: t) {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.conn = conn; self.drain() } }
            }
        }, onClose: { _ in
            // 엔진이 떠났다 — 호스트는 엔진의 수명에 묶인다(고아로 남지 않는다). 메인에서 끝내되(정상 경로), 메인이 막혀 그 블록이 안 돌면
            // 2 s 뒤 읽기 쪽에서 곧장 끝낸다 — 연결이 닫힌 호스트가 읽기 고리 뒤에 남아 엔진의 거둠을 세우지 않게(그러면 시험이 끝나지 않고 매달린다).
            DispatchQueue.main.async { exit(0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { _exit(0) }
        })
    }

    func drain() {
        let start = PreviewClock.now()
        for (item, recv) in mailbox.drain() {
            do {
                switch item {
                case .patch(let p): try handlePatch(p, recv: recv, start: start)
                case .message(let m): try handle(m, recv: recv, start: start)
                }
            } catch {
                let seq: UInt64? = switch item { case .patch(let p): p.seq; case .message(let m): m.seq }
                try? conn.send(.error(ErrorMessage(seq: seq, message: String(describing: error))))
            }
        }
    }

    private func handle(_ m: Message, recv: UInt64, start: UInt64) throws {
        switch m {
        case .hello(let h):
            // 판 — 엔진이 판정자다(새 엔진은 이 호스트의 판으로 말한다). 엔진이 옛 판이면 이 꼴을 모른다 — 사람 말을 오류로 보내고 끊는다(엔진의 떠남과 같은 길로 끝난다)
            guard ProtocolJudge.hostAccepts(engine: h.protocolVersion, host: PreviewProtocolVersion.current) else {
                let why = ProtocolMismatch.hostNewer(host: PreviewProtocolVersion.current, engine: h.protocolVersion).description
                FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(why)\n".utf8))
                try? conn.send(.error(ErrorMessage(seq: nil, message: why)))
                conn.close()
                return
            }
            if let s = h.shared { region = try SharedRegion.open(s); slotCursor = 0 } else { region = nil }
        case .render(let r):
            request = r
            appliedSeq = max(appliedSeq, r.seq)
            var fresh = r
            fresh.seq = 0; fresh.frames = nil
            if fresh != renderKey { renderer = FrameRenderer(); renderKey = fresh }
            let key = "\(r.screen)|\(r.state)"
            if current?.key != key {
                guard let screen = screens[r.screen] else { throw PreviewHostError.unknownScreen(r.screen) }
                Trace.mark("세션 시작 \(key)")
                current = (key, try screen.session(state: r.state))
                Trace.mark("세션 섬")
            }
            // 값은 render 가 갈아 끼운다(엔진이 안 파일에서 읽은 것 · 픽스처 갈아 끼우기) — 앞 patch 는 그 밑에 묻힌다
            try current!.session.load(style: r.style, layers: r.layers ?? [], fixture: r.fixture)
            // 자기 창이 서 있으면 그 창도 새 값 · 틀로(답은 늘 그 값의 프레임 — 엔진이 창 밑에 둔다)
            if let p = presenter { p.resize(to: CGSize(width: r.size.w, height: r.size.h)); p.update(current!.session.view(context(r, offscreen: false))) }
            try produce(seq: r.seq, recv: recv, start: start)
            Trace.mark("프레임 보냄 \(r.seq)")
        case .tokensChanged(let t):
            onTokensChanged()
            renderer = FrameRenderer(); renderKey = nil   // 토큰 값이 바뀌었다 — 앞 장의 뷰 그래프를 버린다
            if let p = presenter, let req = request, let cur = current { p.update(cur.session.view(context(req, offscreen: false))) }
            try produce(seq: t.seq, recv: recv, start: start)
        case .shot(let s):
            guard let req = request, let cur = current else { throw PreviewHostError.noSession }
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
            exit(0)
        case .frame, .ack, .error, .patch:
            break
        }
    }

    private func handlePatch(_ p: Patch, recv: UInt64, start: UInt64) throws {
        guard let cur = current else { throw PreviewHostError.noSession }
        let before = presenter == nil ? [] : cur.session.snapFrames()
        for e in p.edits { try cur.session.apply(e) }
        appliedSeq = max(appliedSeq, p.seq)
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
        try withExtendedLifetime(f) { try conn.send(.frame(header), payload: body) }
    }

    /// 창 모드의 답 — 그 바퀴의 커밋이 끝난 뒤 ack.
    private func ackAfterCommit(seq: UInt64, recv: UInt64, start: UInt64, before: [SnapFrame]) {
        let applied = appliedSeq
        let session = current?.session
        let conn = conn!
        Commit.next {
            let t = PreviewClock.now()
            let changed = session.map { $0.snapFrames() != before }
            try? conn.send(.ack(Ack(seq: seq, applied: applied, ms: PreviewClock.ms(start, t),
                                    timing: HostTiming(recv: recv, start: start, rendered: t, sent: t), changed: changed)))
        }
    }
}
#endif
