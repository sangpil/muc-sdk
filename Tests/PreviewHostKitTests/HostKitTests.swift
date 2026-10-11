import CoreGraphics
import Foundation
@testable import PreviewHostKit
import PreviewProtocol
import PreviewWire
import Testing

// 호스트 런타임 — 우편함이 연달아 온 patch 를 하나로 합친다 · 프레임 수집함의 차례 · 자기 창의 보이는 부분 · 엔진 hello 의 판(옛 엔진은 거절).
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
    @MainActor @Test func hostRefusesAnOlderEngineAndTakesANewerOne() throws {
        let now = PreviewProtocolVersion.current
        for (engine, refused) in [(now - 1, true), (now, false), (now + 1, false)] {
            let (a, b) = try UnixSocket.pair()
            let server = HostServer(screens: [], onTokensChanged: {})
            server.conn = Connection(fd: a)
            let engineSide = Connection(fd: b)
            let got = Inbox()
            engineSide.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
            _ = server.mailbox.push(.hello(Hello(role: .engine, protocolVersion: engine, pid: 1, name: "e")), recv: 0)
            server.drain()
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
