import CoreGraphics
import Foundation
@testable import PreviewHostKit
import PreviewProtocol
import SwiftUI
import Testing

// 효과(머티리얼 · 유리 · 그림자)가 있는 장의 그린 글줄 · 바탕 — 같은 카드(글줄 둘 · 모서리 12)를 효과만 바꿔 그려 그림자 기준과 같은 글줄을 내는지 잰다.
// 진짜 머티리얼은 수집 그림(PDF)을 그 장 통째로 래스터 한 장으로 만든다(글 · 칠 0) — 수집 그림에서만 비활성 외양으로 그려 벡터로 남긴다(`FrameRenderer.DrawnRoot`).
// 유리는 창 없는 그림에서 제 안의 내용까지 그리지 않는다(그린 PNG 에도 없다) — 수집도 그린 것만 싣는다 · 유리를 바탕 층에 깐 꼴은 글줄이 그대로다.

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

    /// 그린 PNG 는 바꾸지 않는다 — 머티리얼 카드의 PNG 가 맨 `ImageRenderer` 의 것과 같은 바이트 · 수집 뒤 다시 그려도 같은 그림(렌더러의 내용을 되돌린다).
    /// 수집 뒤는 낱 차 1 까지 — 같은 렌더러에 내용을 다시 넣기만 해도(수집 없이) 그라디언트 낱이 1 씩 흔들린다(실측 · 수집과 무관). 비활성 외양이 새면
    /// 카드 자리가 반투명 분홍에서 불투명 회색으로 바뀌어 낱 차가 수십이다.
    @MainActor @Test func drawnPixelsStayTheSame() throws {
        let view = Effects.card { $0.background(.ultraThinMaterial, in: Effects.shape) }
        let bare = ImageRenderer(content: AnyView(view))
        bare.proposedSize = ProposedViewSize(Card.size)
        bare.scale = 2
        let img = try #require(bare.cgImage)
        let want = try #require(img.dataProvider?.data) as Data
        let r = FrameRenderer()
        #expect(try Effects.pixels(r, view) == want, "수집 뿌리가 그린 그림을 바꾸지 않는다")
        _ = r.drawn(frames: Card.frames)
        let after = try Effects.pixels(r, view)
        #expect(after.count == want.count)
        let worst = zip(after, want).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "수집 뒤에도 같은 그림 — 가장 큰 낱 차 \(worst)")
    }

    /// 유리를 바탕 층에 깐 카드 — 그림자 기준과 같은 글줄(유리 칠은 창 없는 그림에 그려지지 않는다 — 바탕 없음).
    @MainActor @Test func glassBehindKeepsLines() throws {
        guard #available(macOS 26, *) else { return }
        let page = try Card.read(Effects.card { $0.background { Effects.shape.fill(.clear).glassEffect(.regular, in: Effects.shape) } })
        #expect(page.texts.map(\.text) == Effects.lines)
    }

    /// 내용에 바로 씌운 유리 — 창 없는 그림은 유리와 그 안의 내용을 그리지 않는다(그린 PNG = 카드를 뺀 그림) · 수집도 그린 것만(카드 밖 글줄 하나).
    /// 프로젝트는 창 없는 장(`RenderContext.offscreen`)에서 유리를 근사로 그린다(SDK.md) — 이 시험은 그 까닭을 붙든다.
    @MainActor @Test func glassAroundContentIsNotDrawnOffscreen() throws {
        guard #available(macOS 26, *) else { return }
        let glass = Effects.card { $0.glassEffect(.regular, in: Effects.shape) }
        let none = Effects.card { _ in Color.clear.frame(width: 200, height: 100) }
        #expect(try Effects.pixels(FrameRenderer(), glass) == Effects.pixels(FrameRenderer(), none), "유리 카드는 그린 PNG 에도 없다")
        #expect(try Card.read(glass).texts.map(\.text) == ["Outside"])
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
    }

    static var hasMaterialAppearance: Bool { if #available(macOS 15, *) { true } else { false } }
}
