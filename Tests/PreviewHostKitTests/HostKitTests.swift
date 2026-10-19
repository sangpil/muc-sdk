import CoreGraphics
import Foundation
@testable import PreviewHostKit
import PreviewProtocol
import PreviewWire
import ProjectFormat
import SwiftUI
import Testing

// 호스트 런타임 — 우편함이 연달아 온 patch 를 하나로 합친다 · 프레임 수집함의 차례 · 자기 창의 보이는 부분 · 엔진 hello 의 판(옛 엔진은 거절) ·
// 연결 = 세션(한 호스트가 같은 소켓 자리로 연결을 여럿 받고 세션마다 따로 그린다 · 모두 닫히면 끝) ·
// 그리기 전 준비(세션의 `prepare` 가 끝난 뒤에야 장을 그린다 — 첫 장부터 그 값의 그림 · 그 사이 온 메시지는 차례대로 뒤에 선다).
// 앵커를 모으는 손(`collectFrames`)은 프로젝트의 화면 코드가 `.snapID` 를 단 빌드(트레이트 `ActiveMarks`)에서만 값이 차므로 그 프로젝트 쪽 시험이 잰다.

@Suite struct HostKitTests {
    @Test func mailboxMergesConsecutivePatches() {
        let m = Mailbox()
        #expect(m.push(.patch(Patch(seq: 1, edits: [Edit(field: "a", value: .pt(1))])), recv: 10))
        #expect(!m.push(.patch(Patch(seq: 2, edits: [Edit(field: "a", value: .pt(2)), Edit(field: "b", value: .bool(true))])), recv: 11))
        #expect(!m.push(.render(RenderRequest(seq: 3, screen: "s", state: "n", size: Size(w: 1, h: 1), scale: 1)), recv: 12))
        #expect(!m.push(.patch(Patch(seq: 4, edits: [Edit(field: "a", value: .pt(4))])), recv: 13))
        let items = m.drain()
        #expect(items.count == 3)
        guard case .patch(let first) = items[0].item else { Issue.record("첫째가 patch 가 아니다"); return }
        #expect(first.seq == 2 && first.edits == [Edit(field: "a", value: .pt(2)), Edit(field: "b", value: .bool(true))])
        #expect(items[0].recv == 10)   // 합친 묶음의 받은 시각 = 가장 이른 것
        #expect(m.push(.bye(Bye(reason: "")), recv: 14))   // 비운 뒤엔 다시 깨운다
    }

    @Test func sinkSortsTopThenLeftThenID() {
        let sink = FrameSink()
        #expect(sink.frames.isEmpty)
        sink.set([SnapFrame(id: "b", rect: CGRect(x: 0, y: 10, width: 1, height: 1)),
                  SnapFrame(id: "c", rect: CGRect(x: 5, y: 0, width: 1, height: 1)),
                  SnapFrame(id: "a", rect: CGRect(x: 0, y: 10, width: 1, height: 1)),
                  SnapFrame(id: "d", rect: CGRect(x: 1, y: 0, width: 1, height: 1))])
        #expect(sink.frames.map(\.id) == ["d", "c", "a", "b"])
    }

    /// 자기 창의 보이는 부분 — 창은 잘린 자리만 덮고 화면 뷰는 제 크기 · 제 자리 그대로(엔진의 미리보기 자리가 스크롤에 잘렸을 때).
    @MainActor @Test func presenterCoversJustTheVisiblePart() {
        let p = WindowPresenter(size: CGSize(width: 100, height: 200), origin: .zero)
        p.clip(to: CGRect(x: 0, y: 50, width: 100, height: 100))   // 위 50 · 아래 50 이 잘렸다(위-왼쪽 원점)
        p.show(at: CGPoint(x: 10, y: 20))
        #expect(p.window.frame == CGRect(x: 10, y: 70, width: 100, height: 100))
        #expect(p.hosting.frame == CGRect(x: 0, y: -50, width: 100, height: 200))
        p.clip(to: nil)
        p.show(at: CGPoint(x: 10, y: 20))
        #expect(p.window.frame == CGRect(x: 10, y: 20, width: 100, height: 200))
        #expect(p.hosting.frame == CGRect(x: 0, y: 0, width: 100, height: 200))
        p.hide()
    }

    /// 엔진 hello 의 판 — 같거나 새 판이면 받는다(새 엔진은 호스트의 판으로 말한다 · 엔진이 판정자) · 옛 판이면 사람 말을 오류로 보내고 끊는다.
    @MainActor @Test func hostRefusesAnOlderEngineAndTakesANewerOne() async throws {
        let now = PreviewProtocolVersion.current
        for (engine, refused) in [(now - 1, true), (now, false), (now + 1, false)] {
            let (a, b) = try UnixSocket.pair()
            let server = HostServer(screens: [], onTokensChanged: {})
            server.conn = Connection(fd: a)
            let engineSide = Connection(fd: b)
            let got = Inbox()
            engineSide.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
            _ = server.mailbox.push(.hello(Hello(role: .engine, protocolVersion: engine, pid: 1, name: "e")), recv: 0)
            await server.drain()
            if refused {
                #expect(got.waitClosed(), "옛 엔진 \(engine) — 끊었다")
                #expect(got.messages == [.error(ErrorMessage(seq: nil, message: ProtocolMismatch.hostNewer(host: now, engine: engine).description))])
            } else {
                #expect(!got.waitClosed(timeout: 0.1), "엔진 \(engine) — 받았다")
                #expect(got.messages.isEmpty)
            }
            engineSide.close(); server.conn.close()
        }
    }

    /// 모르는 공유 메모리 종류 — 칸을 열지 않고(오류 없이) 프레임을 소켓으로 보낸다(전송 A).
    @MainActor @Test func anUnknownSharedMemoryKindFallsBackToTheSocket() async throws {
        let (a, b) = try UnixSocket.pair()
        let server = HostServer(screens: [], onTokensChanged: {})
        server.conn = Connection(fd: a)
        let engineSide = Connection(fd: b)
        let got = Inbox()
        engineSide.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
        let shared = SharedMemoryInfo(kind: SharedMemoryInfo.Kind(rawValue: "mach"), name: "x", slotBytes: 1, slots: 1)
        _ = server.mailbox.push(.hello(Hello(role: .engine, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "e", shared: shared)), recv: 0)
        await server.drain()
        #expect(server.region == nil)
        #expect(!got.waitClosed(timeout: 0.1) && got.messages.isEmpty, "오류 없이 받았다")
        engineSide.close(); server.conn.close()
    }

    /// 크기만 바뀐 render — 옛 보이는 부분이 새 화면 밖으로 나가면 새 크기에 맞춰 잘린다(창이 화면보다 크게 서지 않는다).
    @MainActor @Test func presenterResizeKeepsTheClipInsideTheScreen() {
        let p = WindowPresenter(size: CGSize(width: 100, height: 200), origin: .zero)
        p.clip(to: CGRect(x: 0, y: 50, width: 100, height: 150))   // 아래 끝까지
        p.resize(to: CGSize(width: 100, height: 120))
        p.show(at: CGPoint(x: 10, y: 20))
        #expect(p.window.frame == CGRect(x: 10, y: 20, width: 100, height: 70))   // 보이는 부분 = y 50–120
        #expect(p.hosting.frame == CGRect(x: 0, y: 0, width: 100, height: 120))
        p.hide()
    }
}

/// 연결 = 세션 — 같은 듣는 자리로 둘이 붙으면 둘 다 제 hello 를 받고 · 제 render 에 제 프레임을 받는다 · 하나가 닫혀도 다른 쪽은 남고 · 모두 닫히면 끝난다.
@Suite(.serialized) struct HostSessionsTests {
    struct Probe: PreviewScreen {
        let name = "probe"
        func info() throws -> ScreenInfo { ScreenInfo(name: name, states: ["n"], style: StyleSchema(screen: name, elements: [], fields: [], defaults: [:])) }
        func session(state: String) throws -> any PreviewSession { Session() }
    }
    @MainActor final class Session: PreviewSession {
        func load(style: StyleValues?, layers: [LayerState], fixture: JSONValue?) throws {}
        func apply(_ edit: Edit) throws {}
        func view(_ context: RenderContext) -> AnyView { AnyView(Color.red.frame(width: context.size.width, height: context.size.height)) }
        func snapFrames() -> [SnapFrame] { [] }
        func elementIDs() -> [String] { [] }
        func layerReports() -> [LayerReport] { [] }
    }
    final class Flag: @unchecked Sendable { private let lock = NSLock(); private var on = false
        func set() { lock.withLock { on = true } }; var isSet: Bool { lock.withLock { on } } }

    @MainActor static func until(_ cond: () -> Bool) async -> Bool {
        for _ in 0..<500 { if cond() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
        return cond()
    }

    @MainActor @Test func oneHostServesManyConnections() async throws {
        let path = "/tmp/mucp-test.\(getpid()).\(Int.random(in: 0..<99999)).sock"
        let fd = try UnixSocket.listen(path: path)
        defer { unlink(path) }
        let emptied = Flag()
        let hello = Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "h", screens: [try Probe().info()])
        let listener = HostListener(listener: fd, hello: hello, screens: [Probe()], onTokensChanged: {}, grace: 0.05, onEmpty: { emptied.set() })
        listener.start()
        defer { listener.stop() }
        let a = Connection(fd: try UnixSocket.connect(path: path)), b = Connection(fd: try UnixSocket.connect(path: path))
        let ga = Inbox(), gb = Inbox()
        a.start(name: "test.a", onInbound: { ga.put($0.message) }, onClose: { _ in ga.close() })
        b.start(name: "test.b", onInbound: { gb.put($0.message) }, onClose: { _ in gb.close() })
        #expect(await Self.until { ga.messages.count == 1 && gb.messages.count == 1 }, "세션마다 제 hello")
        #expect(ga.messages.first?.type == "hello" && gb.messages.first?.type == "hello")
        #expect(listener.accepted == 2 && listener.live == 2)
        let engine = Hello(role: .engine, protocolVersion: PreviewProtocolVersion.current, pid: 2, name: "e")
        for (c, seq) in [(a, UInt64(3)), (b, UInt64(9))] {
            try c.send(.hello(engine))
            try c.send(.render(RenderRequest(seq: seq, screen: "probe", state: "n", size: Size(w: 4, h: 4), scale: 1)))
        }
        #expect(await Self.until { ga.messages.count == 2 && gb.messages.count == 2 }, "세션마다 제 프레임")
        #expect(ga.messages.last?.seq == 3 && gb.messages.last?.seq == 9, "seq 는 세션마다 따로")
        // 자기 창 — 세션마다 제 창 · 닫힌 세션의 창은 내려간다(소유자가 풀려도 패널은 화면에 남으므로 몸을 거둘 때 내린다)
        for (c, seq) in [(a, UInt64(4)), (b, UInt64(10))] { try c.send(.window(WindowRequest(seq: seq, x: 6000, y: 6000, show: true, w: 4, h: 4))) }
        #expect(await Self.until { listener.sessions().allSatisfy { $0.presenter != nil } })
        let windows = listener.sessions().compactMap { $0.presenter?.window }
        #expect(windows.count == 2 && windows.allSatisfy(\.isVisible), "창 둘")
        a.close()
        #expect(await Self.until { listener.live == 1 })
        #expect(await Self.until { windows.filter(\.isVisible).count == 1 }, "닫힌 세션의 창은 내려가고 남은 세션의 창은 그대로")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!emptied.isSet, "남은 세션이 있으면 끝나지 않는다")
        b.close()
        #expect(await Self.until { emptied.isSet }, "모두 닫히면 끝난다")
        #expect(await Self.until { windows.allSatisfy { !$0.isVisible } })
    }

    /// 마지막 연결이 닫힌 뒤 짧게 기다린다 — 그 사이 같은 자리로 새 연결이 서면 끝나지 않는다.
    @MainActor @Test func aNewConnectionWithinTheGraceKeepsTheHost() async throws {
        let path = "/tmp/mucp-test.\(getpid()).\(Int.random(in: 0..<99999)).sock"
        let fd = try UnixSocket.listen(path: path)
        defer { unlink(path) }
        let emptied = Flag()
        let hello = Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "h")
        let listener = HostListener(listener: fd, hello: hello, screens: [], onTokensChanged: {}, grace: 0.4, onEmpty: { emptied.set() })
        listener.start()
        defer { listener.stop() }
        let a = Connection(fd: try UnixSocket.connect(path: path))
        a.start(name: "test.a", onInbound: { _ in }, onClose: { _ in })
        #expect(await Self.until { listener.live == 1 })
        a.close()
        #expect(await Self.until { listener.live == 0 })
        let c = Connection(fd: try UnixSocket.connect(path: path))
        c.start(name: "test.c", onInbound: { _ in }, onClose: { _ in })
        #expect(await Self.until { listener.live == 1 })
        try? await Task.sleep(for: .milliseconds(600))
        #expect(!emptied.isSet, "유예 안에 다시 붙었다 — 끝나지 않는다")
        c.close()
        #expect(await Self.until { emptied.isSet })
    }
}

/// 그리기 전 준비 — 세션의 비동기 원천(모델 그림)이 차기 전에는 장을 그리지 않는다. 시간으로 기다리지 않는다: 원천의 끝을 시험이 손으로 연다.
@Suite(.serialized) struct HostPrepareTests {
    /// 값을 받으면 원천을 기다려야 하는 세션 — 준비가 열리기 전의 그림은 「빈 자리」 · 연 뒤는 「찬 자리」. 그린 장마다 그때 찼었나를 적는다.
    @MainActor final class Slow: PreviewSession {
        var filled = false
        var drawn: [Bool] = []
        var prepares = 0
        /// 준비가 기다리는 손 — 시험이 연다(`open`). nil = 기다리는 중이 아님.
        var gate: CheckedContinuation<Void, Never>?
        func load(style: StyleValues?, layers: [LayerState], fixture: JSONValue?) throws { filled = false }
        func apply(_ edit: Edit) throws { filled = false }
        func prepare() async {
            prepares += 1
            guard !filled else { return }
            await withCheckedContinuation { gate = $0 }
            filled = true
        }
        func open() { gate?.resume(); gate = nil }
        func view(_ context: RenderContext) -> AnyView {
            drawn.append(filled)
            return AnyView((filled ? Color.red : Color.clear).frame(width: context.size.width, height: context.size.height))
        }
        func snapFrames() -> [SnapFrame] { [] }
        func elementIDs() -> [String] { [] }
        func layerReports() -> [LayerReport] { [] }
    }
    struct Screen: PreviewScreen {
        let name = "slow"
        let made: Made
        func info() throws -> ScreenInfo { ScreenInfo(name: name, states: ["n"], style: StyleSchema(screen: name, elements: [], fields: [], defaults: [:])) }
        func session(state: String) throws -> any PreviewSession { MainActor.assumeIsolated { made.make() } }
    }
    @MainActor final class Made: @unchecked Sendable {
        var session: Slow?
        func make() -> Slow { let s = Slow(); session = s; return s }
    }
    /// 이 액터의 다른 일(우편함을 비우는 줄)에 차례를 넘기며 조건을 기다린다 — 시간이 아니라 차례로.
    @MainActor static func until(_ cond: () -> Bool) async -> Bool {
        for _ in 0..<10_000 { if cond() { return true }; await Task.yield() }
        return cond()
    }
    static func frames(_ got: Inbox) -> [UInt64] { got.messages.compactMap { if case .frame(let f) = $0 { f.seq } else { nil } } }

    /// render — 준비가 열리기 전에는 장이 없고 · 연 뒤의 첫 장이 찬 그림이다 · 기다리는 사이 온 patch 는 그 뒤에 차례대로(그것도 찬 그림).
    @MainActor @Test func theFirstFrameWaitsForThePreparation() async throws {
        let (a, b) = try UnixSocket.pair()
        let made = Made()
        let server = HostServer(screens: [Screen(made: made)], onTokensChanged: {})
        server.conn = Connection(fd: a)
        let engineSide = Connection(fd: b)
        let got = Inbox()
        engineSide.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
        defer { engineSide.close(); server.conn.close() }

        _ = server.mailbox.push(.render(RenderRequest(seq: 1, screen: "slow", state: "n", size: Size(w: 4, h: 4), scale: 1)), recv: 0)
        let loop = Task { @MainActor in await server.drain() }
        #expect(await Self.until { made.session?.gate != nil }, "준비가 원천을 기다린다")
        let session = try #require(made.session)
        #expect(session.drawn.isEmpty, "준비가 열리기 전에는 그리지 않는다")
        // 기다리는 사이 온 patch — 우편함에 선다(도는 줄이 집는다)
        _ = server.mailbox.push(.patch(Patch(seq: 2, edits: [Edit(field: "x", value: .bool(true))])), recv: 0)
        session.open()
        #expect(await Self.until { session.gate != nil }, "patch 도 제 준비를 기다린다")
        #expect(session.drawn == [true])
        session.open()
        await loop.value
        #expect(session.drawn == [true, true], "장마다 찬 그림")
        #expect(Self.waitFrames(got, [1, 2]), "장은 차례대로 — render 다음 patch")
    }

    /// 준비하는 사이 세션이 닫히면 그 장은 그리지 않는다(닫힌 연결에 쓰지 않는다).
    @MainActor @Test func aSessionClosedWhilePreparingDrawsNothing() async throws {
        let (a, b) = try UnixSocket.pair()
        let made = Made()
        let server = HostServer(screens: [Screen(made: made)], onTokensChanged: {})
        server.conn = Connection(fd: a)
        let engineSide = Connection(fd: b)
        let got = Inbox()
        engineSide.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
        defer { engineSide.close(); server.conn.close() }
        _ = server.mailbox.push(.render(RenderRequest(seq: 1, screen: "slow", state: "n", size: Size(w: 4, h: 4), scale: 1)), recv: 0)
        let loop = Task { @MainActor in await server.drain() }
        #expect(await Self.until { made.session?.gate != nil })
        let session = try #require(made.session)
        server.shutdown()
        session.open()
        await loop.value
        #expect(session.drawn.isEmpty)
        #expect(!got.waitClosed(timeout: 0.1) && got.messages.isEmpty, "보낸 것 없음")
    }

    /// 프레임은 엔진 쪽 읽기 스레드가 받는다 — 보내기는 이미 끝났고 받는 줄만 기다린다(장이 이미 왔으면 곧장).
    static func waitFrames(_ got: Inbox, _ want: [UInt64]) -> Bool {
        for _ in 0..<200 { if frames(got) == want { return true }; usleep(10_000) }
        return frames(got) == want
    }
}

/// 엔진 쪽에서 받은 것 — 읽기 스레드가 넣고 시험이 읽는다.
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [Message] = []
    private let closed = DispatchSemaphore(value: 0)
    var messages: [Message] { lock.withLock { _messages } }
    func put(_ m: Message) { lock.withLock { _messages.append(m) } }
    func close() { closed.signal() }
    func waitClosed(timeout: Double = 2) -> Bool { closed.wait(timeout: .now() + timeout) == .success }
}
