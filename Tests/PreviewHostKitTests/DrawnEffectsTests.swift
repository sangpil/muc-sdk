import CoreGraphics
import Foundation
@testable import PreviewHostKit
import PreviewProtocol
import SwiftUI
import Testing

// 효과(머티리얼 · 유리 · 그림자)가 있는 장의 그린 글줄 · 바탕 — 같은 카드(글줄 둘 · 모서리 12)를 효과만 바꿔 그려 그림자 기준과 같은 글줄을 내는지 잰다.
// 진짜 머티리얼은 수집 그림(PDF)을 그 장 통째로 래스터 한 장으로 만든다(글 · 칠 0) — 수집 그림에서만 비활성 외양으로 그려 벡터로 남긴다(`FrameRenderer.DrawnRoot`).
// 유리는 공개 손으로 끌 수 없다 — 창이 선 프로세스에서는 유리가 있는 장이 통째로 래스터 한 장(글줄 · 바탕 0) · 창이 없는 프로세스에서는 유리와 그 안의
// 내용이 그림에도 없다. 그래서 프로젝트가 창 없는 장에서 유리를 근사로 그린다 — 시험은 그 한계와 근사 꼴의 수집을 붙든다.

enum Effects {
    /// 바탕(그라디언트) 위 카드(20,20 · 200×100) — `effect` 가 카드 내용에 효과를 입힌다 · 카드 밖 글줄 하나 · 경계 없는 초록 칸.
    @MainActor static func card(@ViewBuilder _ effect: (AnyView) -> some View) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)
            effect(AnyView(VStack(alignment: .leading, spacing: 4) {
                Text("Title 제목").font(.system(size: 17, weight: .semibold)).frame(width: 176, height: 24, alignment: .leading)
                Text("Body").font(.custom("Helvetica", size: 12))
            }.padding(12).frame(width: 200, height: 100, alignment: .topLeading)))
            .offset(x: 20, y: 20)
            Text("Outside").font(.system(size: 13)).offset(x: 20, y: 160)
            Color(red: 0, green: 1, blue: 0).frame(width: 40, height: 20).offset(x: 240, y: 20)
        }
        .frame(width: Card.size.width, height: Card.size.height)
    }

    static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let lines = ["Title 제목", "Body", "Outside"]

    /// 그림자 기준 — 흰 카드 + 그림자.
    @MainActor static var shadow: some View { card { $0.background(shape.fill(.white).shadow(radius: 4)) } }

    /// 그린 PNG 의 바이트.
    @MainActor static func pixels(_ r: FrameRenderer, _ view: some View) throws -> Data {
        let f = try r.render(AnyView(view), size: Card.size, scale: 2)
        return Data(bytes: f.base, count: f.bytes)
    }
}

@Suite struct DrawnEffectsTests {
    /// 기준 — 그림자가 있는 카드는 글줄 셋 · 카드 바탕(흰색 · 모서리 12).
    @MainActor @Test func shadowIsTheBaseline() throws {
        let page = try Card.read(Effects.shadow)
        #expect(page.texts.map(\.text) == Effects.lines)
        #expect(page.styles == [DrawnStyle(id: "card", background: "#ffffff", radius: page.styles.first?.radius ?? -1)])
        #expect(abs((page.styles.first?.radius ?? 0) - 12) <= 0.05)
    }

    /// 머티리얼 — 그림자 기준과 같은 글줄 · 카드 바탕은 단색 근사(비활성 외양 — 불투명 칠 위 옅은 겹칠을 합성한 불투명 회색) · 모서리 12.
    /// 고치기 전: 글줄 0 · 바탕 0(PDF 가 이미지 한 장).
    @MainActor @Test(.enabled(if: Self.hasMaterialAppearance), arguments: ["ultraThin", "thin", "regular", "thick", "ultraThick", "bar"])
    func materialKeepsLinesAndBackground(kind: String) throws {
        let material: Material = switch kind {
        case "ultraThin": .ultraThinMaterial
        case "thin": .thinMaterial
        case "regular": .regularMaterial
        case "thick": .thickMaterial
        case "ultraThick": .ultraThickMaterial
        default: .bar
        }
        let page = try Card.read(Effects.card { $0.background(material, in: Effects.shape) })
        #expect(page.texts.map(\.text) == Effects.lines, "\(kind) — \(page.texts.map(\.text))")
        #expect(page.texts.first?.element == "card.title" && page.texts.dropFirst().first?.element == "card")
        let card = try #require(page.styles.first { $0.id == "card" }, "\(kind) — 바탕 \(page.styles)")
        #expect(card.background.count == 7, "합성한 불투명 단색 — \(kind) \(card.background)")
        #expect(abs(card.radius - 12) <= 0.05, "모서리 \(card.radius)")
    }

    /// 칠(`.fill(material)`)로 쓴 머티리얼도 같다.
    @MainActor @Test(.enabled(if: Self.hasMaterialAppearance)) func materialFillKeepsLines() throws {
        let page = try Card.read(Effects.card { $0.background(Effects.shape.fill(.thinMaterial)) })
        #expect(page.texts.map(\.text) == Effects.lines)
        #expect(page.styles.map(\.id) == ["card"])
    }

    /// 그린 PNG 는 바꾸지 않는다 — 머티리얼 카드의 PNG 가 맨 `ImageRenderer` 의 것과 같은 그림 · 수집 뒤 다시 그려도 같은 그림(렌더러의 내용을 되돌린다).
    /// 낱 차 4 까지 — 머티리얼의 래스터는 같은 뷰를 새 렌더러로 그려도 낱이 2 까지 흔들린다(실측 · 수집과 무관). 비활성 외양이 새면 카드 자리가
    /// 반투명 분홍에서 불투명 회색으로 바뀌어 낱 차가 수십이다 — 그 기준(새는 그림)과의 차가 문턱보다 큰지도 잰다(문턱이 헛돌지 않게).
    @MainActor @Test func drawnPixelsStayTheSame() throws {
        let view = Effects.card { $0.background(.ultraThinMaterial, in: Effects.shape) }
        let bare = ImageRenderer(content: AnyView(view))
        bare.proposedSize = ProposedViewSize(Card.size)
        bare.scale = 2
        let img = try #require(bare.cgImage)
        let want = try #require(img.dataProvider?.data) as Data
        func worst(_ a: Data) -> Int { a.count == want.count ? zip(a, want).map { abs(Int($0) - Int($1)) }.max() ?? 0 : .max }
        let r = FrameRenderer()
        // 호스트의 실제 차례(`HostServer.produce` — 인라인 전송은 `drawn()` 뒤에 먼저 낸 Frame 의 `base` 를 보낸다): 수집이 그 바이트를 건드리지 않는다
        let frame = try r.render(AnyView(view), size: Card.size, scale: 2)
        let sent = Data(bytes: frame.base, count: frame.bytes)
        _ = r.drawn(frames: Card.frames)
        #expect(Data(bytes: frame.base, count: frame.bytes) == sent, "수집 뒤에도 먼저 낸 Frame 의 바이트 그대로")
        #expect(worst(sent) <= 4, "수집 뿌리가 그린 그림을 바꾸지 않는다")
        _ = r.drawn(frames: Card.frames)
        let after = worst(try Effects.pixels(r, view))
        #expect(after <= 4, "수집 뒤에도 같은 그림 — 가장 큰 낱 차 \(after)")
        if #available(macOS 15, *) {
            let leaked = worst(try Effects.pixels(FrameRenderer(), view.environment(\.materialActiveAppearance, .inactive)))
            // 30 은 이 장면(머티리얼 하나 · 단색에 가까운 그라디언트 바탕) 기준이다 — 다른 장면의 문턱이 아니다
            #expect(leaked > 30, "새는 그림은 문턱 밖 — \(leaked)")
        }
    }

    /// 유리 — 창이 하나라도 선 프로세스(호스트의 자기 창)에서는 `ImageRenderer` 가 유리를 진짜로 그리고, 그 장의 벡터 그림은 통째로 래스터 한 장이다
    /// (글줄 · 바탕 0 — 내용에 씌운 유리 ⟂ 바탕 층에 깐 유리 모두). 유리를 끄는 공개 환경값이 없다(비활성 외양 · 창 활성 · 휘도 · 대비 · 끔 모두 같음 — 실측).
    /// 창이 없는 프로세스에서는 유리와 그 안의 내용이 그림에도 수집에도 없다 — 어느 쪽이든 프로젝트는 창 없는 장(`RenderContext.offscreen`)에서 유리를
    /// 근사로 그린다(SDK.md). 시험은 창을 먼저 세워 상태를 하나로 고정한다(다른 시험이 창을 세우면 프로세스가 되돌아오지 않는다).
    @MainActor @Test(.enabled(if: Self.hasGlass, "유리 API 는 macOS 26 이상")) func glassPageIsOneImageOnceAWindowExists() throws {
        guard #available(macOS 26, *) else { return }   // 위 조건과 같다 — 컴파일러가 API 가용성을 보게
        _ = WindowPresenter(size: CGSize(width: 10, height: 10), origin: .zero)
        let around = try Card.read(Effects.card { $0.glassEffect(.regular, in: Effects.shape) })
        #expect(around.texts.isEmpty && around.styles.isEmpty, "\(around.texts.map(\.text))")
        let behind = try Card.read(Effects.card { $0.background { Effects.shape.fill(.clear).glassEffect(.regular, in: Effects.shape) } })
        #expect(behind.texts.isEmpty && behind.styles.isEmpty, "\(behind.texts.map(\.text))")
    }

    /// 유리의 근사(반투명 칠 + 테두리 — 창 없는 장의 갈래) — 그림자 기준과 같은 글줄 · 카드 바탕은 그 칠.
    @MainActor @Test func glassApproximationKeepsLines() throws {
        _ = WindowPresenter(size: CGSize(width: 10, height: 10), origin: .zero)
        let page = try Card.read(Effects.card { $0.background(Effects.shape.fill(Color.white.opacity(0.55)).overlay(Effects.shape.stroke(Color.white, lineWidth: 1))) })
        #expect(page.texts.map(\.text) == Effects.lines)
        #expect(page.styles.map(\.background) == ["#ffffff8c"])
    }

    /// 겹친 칠의 합성 — 불투명 칠 위 옅은 겹칠은 합성한 불투명 색 · 반투명 칠 하나는 그대로 · 맨 위 색을 모르면 nil · 맨 위가 불투명이면 그 색.
    @Test func stackedFillsComposite() {
        typealias F = DrawnMarks.Fill
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        let base = F(box: box, rgba: [0.94, 0.94, 0.94, 1], radius: 0), veil = F(box: box, rgba: [0.75, 0.75, 0.75, 0.05], radius: 0)
        #expect(DrawnMarks.composite([base, veil]).map(PageWalk.hex) == "#ededed", "0.94 × 0.95 + 0.75 × 0.05 = 0.9305")
        #expect(DrawnMarks.composite([veil]).map(PageWalk.hex) == "#bfbfbf0d")
        #expect(DrawnMarks.composite([base, F(box: box, rgba: nil, radius: 0)]) == nil)
        #expect(DrawnMarks.composite([veil, F(box: box, rgba: [1, 0, 0, 1], radius: 0)]).map(PageWalk.hex) == "#ff0000")
        // 중간 · 아래 칠의 색을 모르면 거기서 멈추고 그때까지 합성한 반투명 색
        #expect(DrawnMarks.composite([base, F(box: box, rgba: nil, radius: 0), veil]).map(PageWalk.hex) == "#bfbfbf0d", "중간이 무늬")
        #expect(DrawnMarks.composite([F(box: box, rgba: nil, radius: 0), veil, veil]).map(PageWalk.hex) == PageWalk.hex([0.75, 0.75, 0.75, 0.0975]), "맨 아래가 무늬")
    }

    static var hasGlass: Bool { if #available(macOS 26, *) { true } else { false } }
    static var hasMaterialAppearance: Bool { if #available(macOS 15, *) { true } else { false } }
}
