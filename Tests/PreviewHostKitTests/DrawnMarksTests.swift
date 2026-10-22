import CoreGraphics
import Foundation
@testable import PreviewHostKit
import PreviewProtocol
import PreviewWire
import ProjectFormat
import SwiftUI
import Testing

// 그린 글줄 · 요소 바탕 — 작은 카드(표식 단 카드 안에 글줄 둘 · 바탕 색 · 모서리)를 그려 벡터 한 장에서 읽은 값을 잰다:
// 문자열 · 크기 · 굵기 · 색 · 소속 요소 · 바탕 색 · 모서리. 요소 경계는 카드의 고정 자리를 손으로 넘긴다(표식 수집은 트레이트 `ActiveMarks` 빌드의 일 —
// 읽는 손은 경계가 어디서 왔는지 모른다). 호스트가 청한 장에만 싣는 것은 `drawnRidesOnlyWhenAsked` 가 연결 한 쌍으로 잰다.

enum Card {
    static let size = CGSize(width: 300, height: 200)
    /// 카드(20,20 · 200×100) — 제목 줄(32,32 · 176×24) · 본문 줄 · 카드 밖 글줄 하나.
    static let frames = [SnapFrame(id: "card", rect: CGRect(x: 20, y: 20, width: 200, height: 100)),
                         SnapFrame(id: "card.title", rect: CGRect(x: 32, y: 32, width: 176, height: 24))]

    @MainActor static func view(corner: RoundedCornerStyle = .continuous) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            VStack(alignment: .leading, spacing: 4) {
                Text("Title 제목").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 176, height: 24, alignment: .leading)
                Text("Body").font(.custom("Helvetica", size: 12)).foregroundStyle(Color.black.opacity(0.5))
            }
            .padding(12)
            .frame(width: 200, height: 100, alignment: .topLeading)
            .background(Color(red: 0, green: 0, blue: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: corner))
            .offset(x: 20, y: 20)
            Text("Outside").font(.system(size: 13)).offset(x: 20, y: 160)
            Color(red: 0, green: 1, blue: 0).frame(width: 40, height: 20).offset(x: 240, y: 20)
        }
        .frame(width: size.width, height: size.height)
    }

    @MainActor static func read(_ view: some View, frames: [SnapFrame] = Card.frames) throws -> DrawnMarks.Page {
        let r = FrameRenderer()
        _ = try r.render(AnyView(view), size: size, scale: 2)
        return r.drawn(frames: frames)
    }
}

@Suite struct DrawnMarksTests {
    /// 글줄 셋 — 문자열 · 크기 · 굵기 · 색 · 소속(가장 안쪽 경계 · 경계 밖은 nil) · 한 줄에 섞인 대체 글꼴은 한 줄로.
    @MainActor @Test func textsCarryStringSizeWeightColorAndOwner() throws {
        let page = try Card.read(Card.view())
        #expect(page.texts.map(\.text) == ["Title 제목", "Body", "Outside"], "그린 차례 · 대체 글꼴이 섞인 줄도 한 줄")
        let title = try #require(page.texts.first { $0.text == "Title 제목" })
        #expect(title.size == 17)
        #expect((550...650).contains(title.weight), "semibold — 굵기 축 값 \(title.weight)")
        #expect(title.color == "#ff0000")
        #expect(title.font.hasPrefix("."), "시스템 UI 글꼴 — \(title.font)")
        #expect(title.element == "card.title", "가장 안쪽 경계")
        #expect(Card.frames[1].rect.contains(CGPoint(x: title.rect.midX, y: title.rect.midY)))
        let body = try #require(page.texts.first { $0.text == "Body" })
        #expect(body.size == 12 && body.font == "Helvetica" && body.weight == 400)
        #expect(body.color == "#00000080", "겹친 불투명도까지 곱한 색 — \(body.color ?? "nil")")
        #expect(body.element == "card")
        #expect(body.x >= 32 && body.x < 33, "본문 줄의 왼쪽 = 카드 + 안쪽 여백 — \(body.x)")
        let outside = try #require(page.texts.first { $0.text == "Outside" })
        #expect(outside.element == nil && outside.size == 13 && outside.weight == 400)
        #expect(outside.color?.hasPrefix("#000000") == true, "기본 글자 색 — 플랫폼의 라벨 색(검정 · 불투명도는 플랫폼 몫) \(outside.color ?? "nil")")
    }

    /// 바탕 — 경계와 같은 자리를 칠한 면의 색 · 모서리(연속 곡률 ⟂ 원호 모두 반경 12) · 경계가 없는 면(초록 칸)은 싣지 않는다 ·
    /// 경계와 맞는 면이 없는 요소(제목 줄)도 싣지 않는다.
    @MainActor @Test(arguments: [RoundedCornerStyle.continuous, .circular])
    func stylesCarryBackgroundAndCornerRadius(corner: RoundedCornerStyle) throws {
        let page = try Card.read(Card.view(corner: corner))
        #expect(page.styles.map(\.id) == ["card"])
        let card = try #require(page.styles.first)
        #expect(card.background == "#0000ff")
        #expect(abs(card.radius - 12) <= 0.05, "모서리 \(card.radius)")
    }

    /// 각진 바탕 — 반경 0 · 요소 차례는 경계의 차례 · 반투명 바탕은 알파까지.
    @MainActor @Test func squareAndTranslucentBackgrounds() throws {
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0, green: 1, blue: 0).frame(width: 40, height: 20).offset(x: 10, y: 10)
            Color(red: 1, green: 0, blue: 0).opacity(0.5).frame(width: 30, height: 30).offset(x: 100, y: 100)
        }.frame(width: Card.size.width, height: Card.size.height, alignment: .topLeading)
        let frames = [SnapFrame(id: "b", rect: CGRect(x: 100, y: 100, width: 30, height: 30)),
                      SnapFrame(id: "a", rect: CGRect(x: 10, y: 10, width: 40, height: 20))]
        let page = try Card.read(view, frames: frames)
        #expect(page.styles == [DrawnStyle(id: "b", background: "#ff000080", radius: 0), DrawnStyle(id: "a", background: "#00ff00", radius: 0)])
        #expect(page.texts.isEmpty)
    }

    /// 감긴 글 — 줄마다 하나 · 이어 붙이면 원래 글.
    @MainActor @Test func wrappedTextGivesOneLinePerLine() throws {
        let words = "one two three four five six seven"
        let view = Text(words).font(.system(size: 13)).frame(width: 70, alignment: .leading)
            .frame(width: Card.size.width, height: Card.size.height, alignment: .topLeading)
        let page = try Card.read(view, frames: [])
        #expect(page.texts.count > 1, "\(page.texts.map(\.text))")
        #expect(page.texts.map(\.text).joined(separator: " ") == words)
        #expect(zip(page.texts, page.texts.dropFirst()).allSatisfy { $0.y < $1.y }, "위에서 아래로")
    }

    /// 이름 · 굵기 — 묶음 표지와 가변 인스턴스 꼬리를 걷는다 · 굵기 축 값(16.16 고정소수) ⟂ 이름 꼬리의 낱말 ⟂ 400.
    @Test func fontNamesAndWeights() {
        typealias F = DrawnMarks.Font
        #expect(F.display("AAAAAE+.SFNS-Regular_wdth_opsz110000_GRAD_wght24E0000") == ".SFNS-Regular")
        #expect(F.display("AAAAAG+Helvetica") == "Helvetica")
        #expect(F.display("Helvetica-Bold") == "Helvetica-Bold")
        #expect(F.weight("AAAAAE+.SFNS-Regular_wdth_opsz110000_GRAD_wght24E0000") == 590)
        #expect(F.weight("AAAAAD+.SFNS-Regular_wdth_opsz160000_GRAD_wght3E80000") == 1000)
        #expect(F.weight("AAAAAB+.SFNS-Regular_wdth_opsz110000_GRAD_wght") == 400)
        #expect(F.weight("AAAAAF+.AppleSDGothicNeoI-SemiBold") == 600)
        #expect(F.weight("Helvetica-Bold") == 700)
        #expect(F.weight("Avenir-Light") == 300)
        #expect(F.weight("HelveticaNeue-UltraLight") == 200)
        #expect(F.weight("Helvetica") == 400)
    }

    /// 읽을 수 없는 바이트 — 빈 것(던지지 않는다).
    @Test func unreadableBytesGiveNothing() {
        #expect(DrawnMarks.read(pdf: Data("x".utf8), frames: Card.frames) == DrawnMarks.Page(texts: [], styles: []))
    }
}

/// 호스트 — `drawn` 을 청한 장의 머리에만 글줄 · 바탕이 실린다(청하지 않은 장은 nil — 빈 목록과 다르다) · 경계 수 대조(`snapFrames` · `elements`)는 그대로.
@Suite(.serialized) struct HostDrawnTests {
    struct Screen: PreviewScreen {
        let name = "card"
        func info() throws -> ScreenInfo { ScreenInfo(name: name, states: ["n"], style: StyleSchema(screen: name, elements: [], fields: [], defaults: [:])) }
        func session(state: String) throws -> any PreviewSession { MainActor.assumeIsolated { Session() } }
    }
    @MainActor final class Session: PreviewSession {
        func load(style: StyleValues?, layers: [LayerState], fixture: JSONValue?) throws {}
        func apply(_ edit: Edit) throws {}
        func view(_ context: RenderContext) -> AnyView { AnyView(Card.view()) }
        func snapFrames() -> [SnapFrame] { Card.frames }
        func elementIDs() -> [String] { Card.frames.map(\.id) }
        func layerReports() -> [LayerReport] { [] }
    }

    @MainActor @Test func drawnRidesOnlyWhenAsked() async throws {
        let (a, b) = try UnixSocket.pair()
        let server = HostServer(screens: [Screen()], onTokensChanged: {})
        server.conn = Connection(fd: a)
        let engine = Connection(fd: b)
        let got = Inbox()
        engine.start(name: "test.engine", onInbound: { got.put($0.message) }, onClose: { _ in got.close() })
        defer { engine.close(); server.conn.close() }
        let size = Size(w: Card.size.width, h: Card.size.height)
        for (seq, frames, drawn) in [(UInt64(1), true, false), (2, true, true), (3, false, true), (4, false, false)] {
            _ = server.mailbox.push(.render(RenderRequest(seq: seq, screen: "card", state: "n", size: size, scale: 1, frames: frames, drawn: drawn)), recv: 0)
        }
        await server.drain()
        var heads: [FrameHeader] = []
        for _ in 0..<200 {
            heads = got.messages.compactMap { if case .frame(let f) = $0 { f } else { nil } }
            if heads.count == 4 { break }
            usleep(10_000)
        }
        try #require(heads.map(\.seq) == [1, 2, 3, 4])
        #expect(heads[0].texts == nil && heads[0].styles == nil && heads[0].snapFrames == Card.frames, "frames 만 — 경계는 그대로 · 글줄 없음")
        #expect(heads[1].snapFrames == Card.frames && heads[1].elements == Card.frames.map(\.id), "경계 수 대조는 그대로")
        #expect(heads[1].texts?.map(\.text) == ["Title 제목", "Body", "Outside"])
        #expect(heads[1].texts?.first?.element == "card.title")
        #expect(heads[1].styles == [DrawnStyle(id: "card", background: "#0000ff", radius: heads[1].styles?.first?.radius ?? -1)])
        #expect(heads[2].texts == heads[1].texts && heads[2].styles == heads[1].styles, "drawn 만 청해도 소속 · 바탕은 경계로 가린다")
        #expect(heads[2].snapFrames.isEmpty && heads[2].elements == nil, "frames 를 청하지 않은 장 — 경계는 싣지 않는다")
        #expect(heads[3].texts == nil && heads[3].styles == nil)
    }
}
