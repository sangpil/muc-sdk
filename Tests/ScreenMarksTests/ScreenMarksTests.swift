import CoreGraphics
import Foundation
import ScreenMarks
import SwiftUI
import Testing

// 화면 요소 표식 — 이 모듈이 약속하는 것만 잰다: 키 · 탭 환경값의 꼴은 트레이트와 무관하게 늘 서고 비어 있다 ·
// 표식이 꺼진 빌드(트레이트 `ActiveMarks` 없음 — 시험의 기본)에서 `.snapID` 는 뷰를 그대로 돌려주고 경계를 올리지 않는다(값이 0).
// 표식은 레이아웃을 바꾸지 않는다 — 켜진 빌드(`swift test --traits ActiveMarks`)와 꺼진 빌드 둘 다에서 같은 뷰를 표식 있음 ⟂ 없음으로 그려 맞댄다.
// 그린 것도 바꾸지 않는다 — 같은 카드의 벡터 장(내용 흐름)이 표식 있음 ⟂ 없음으로 같다(호스트가 그린 글줄 · 바탕을 그 장에서 읽는다).
// 켜진 빌드에서는 표식이 경계를 올린다는 것까지만 잰다 — 경계 수집의 쓰임은 표식을 단 화면 코드가 있는 쪽(프로젝트 · 엔진의 도구)의 시험이 잰다.

/// 렌더 중에 읽은 표식 수 — 레이아웃 중 동기 호출로 찬다.
private final class Seen: @unchecked Sendable {
    var counts: [Int] = []
}

/// 렌더 중에 잰 요소 프레임(뿌리 좌표) — 이름마다 마지막 값.
private final class Frames: @unchecked Sendable {
    var rects: [String: CGRect] = [:]
}

/// 재는 손 — 이 자리의 프레임을 뿌리 좌표계로 적는다(레이아웃 중 동기 호출).
private struct Measure: ViewModifier {
    let name: String
    let into: Frames
    func record(_ g: GeometryProxy) -> Color {
        into.rects[name] = g.frame(in: .named("root"))
        return Color.clear
    }
    func body(content: Content) -> some View {
        content.background(GeometryReader { record($0) })
    }
}

/// 표식을 다는 손 ⟂ 달지 않는 손 — 같은 뷰를 두 벌로 그리려고. 타입으로 가른다(`if` · `AnyView` 로 가르면 그 갈래가 안내선을 삼켜 기준이 헛돈다).
private struct Mark: ViewModifier {
    func body(content: Content) -> some View { content.snapID("probe") }
}
private struct Bare: ViewModifier {
    func body(content: Content) -> some View { content }
}

/// 안쪽 `.alignmentGuide` 가 바깥 정렬에 닿는 자리 셋(overlay · 세로 쌓기 · 가로 쌓기) — 표식은 안쪽 뷰에 붙는다.
/// 반환 = 이름 → 뿌리 좌표 프레임. `tap` 이 참이면 탭 받는 손을 건다(도구의 화면 창과 같은 길).
@MainActor private func layout<M: ViewModifier>(_ mark: M, tap: Bool) -> [String: CGRect] {
    let frames = Frames()
    var handler: (@MainActor (String) -> Void)? = nil
    if tap { handler = { (_: String) in } }
    func inner(_ name: String) -> some View {
        Color.blue.frame(width: 10, height: 10)
            .modifier(Measure(name: name, into: frames))
            .alignmentGuide(.leading) { _ in 3 }
            .alignmentGuide(.top) { _ in 4 }
            .modifier(mark)
    }
    let view = VStack(alignment: .leading, spacing: 0) {
        Color.red.frame(width: 20, height: 10)
            .modifier(Measure(name: "host", into: frames))
            .overlay(alignment: .topLeading) { inner("overlay") }
        Color.red.frame(width: 20, height: 10)
        inner("vstack")
        HStack(alignment: .top, spacing: 0) {
            Color.red.frame(width: 20, height: 10)
            inner("hstack")
        }
    }
    .modifier(Measure(name: "root", into: frames))
    .coordinateSpace(.named("root"))
    .environment(\.snapTap, handler)
    _ = ImageRenderer(content: view).cgImage
    return frames.rects
}

/// 뷰를 벡터 한 쪽(PDF)에 그려 내용 흐름을 꺼낸다 — 쪽의 흐름 + 쪽이 부르는 양식의 흐름(이름 차례).
@MainActor private func vectorPage(_ view: some View) -> [Data] {
    let data = NSMutableData()
    ImageRenderer(content: view).render { size, draw in
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
    }
    guard let provider = CGDataProvider(data: data as CFData), let page = CGPDFDocument(provider)?.page(at: 1), let dict = page.dictionary else { return [] }
    func bytes(_ stream: CGPDFStreamRef) -> Data {
        var format = CGPDFDataFormat.raw
        return CGPDFStreamCopyData(stream, &format).map { $0 as Data } ?? Data()
    }
    var out: [Data] = []
    var contents: CGPDFStreamRef?
    if CGPDFDictionaryGetStream(dict, "Contents", &contents), let contents { out.append(bytes(contents)) }
    var resources: CGPDFDictionaryRef?, forms: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources, CGPDFDictionaryGetDictionary(resources, "XObject", &forms), let forms {
        var named: [(String, Data)] = []
        CGPDFDictionaryApplyBlock(forms, { key, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream { named.append((String(cString: key), bytes(stream))) }
            return true
        }, nil)
        out += named.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return out
}

@Suite struct ScreenMarksTests {
    /// 키의 꼴 — 기본값은 빈 사전 · 빈 값끼리 합쳐도 비어 있다.
    @Test func preferenceKeyStartsEmpty() {
        #expect(SnapPreferenceKey.defaultValue.isEmpty)
        var value = SnapPreferenceKey.defaultValue
        SnapPreferenceKey.reduce(value: &value, nextValue: { [:] })
        #expect(value.isEmpty)
    }

    /// 탭 환경값의 꼴 — 기본은 받는 손 없음(앱의 손을 가리지 않는다) · 걸면 그 손을 그대로 돌려준다.
    @Test @MainActor func tapEnvironmentRoundTrips() {
        #expect(SnapTapKey.defaultValue == nil)
        var env = EnvironmentValues()
        #expect(env.snapTap == nil)
        let seen = Seen()
        env.snapTap = { _ in seen.counts.append(1) }
        env.snapTap?("home.hero")
        #expect(seen.counts == [1])
    }

    /// 표식은 레이아웃을 바꾸지 않는다 — 안쪽 정렬 안내선이 바깥(overlay · 쌓기)에 그대로 닿고 프레임이 같다(탭 받는 손이 있든 없든).
    /// 켜진 빌드에서 표식의 몸이 뷰 타입을 갈래로 나누면(`if` / `else`) overlay 의 안내선이 사라져 빨강이다.
    @Test(arguments: [false, true]) @MainActor func markKeepsLayout(tap: Bool) {
        let bare = layout(Bare(), tap: tap)
        // 기준이 헛돌지 않는다 — 표식 없는 overlay 는 안내선(3 · 4)만큼 바탕 뷰 바깥으로 나간다
        let host = bare["host"] ?? .null, over = bare["overlay"] ?? .null
        #expect(over.minX == host.minX - 3 && over.minY == host.minY - 4)
        #expect(bare.count == 5)
        let marked = layout(Mark(), tap: tap)
        #expect(marked == bare)
    }

    /// 표식은 그린 것을 바꾸지 않는다 — 같은 카드(글줄 둘 · 바탕 · 모서리)를 표식 있음 ⟂ 없음으로 벡터 한 쪽에 그려 내용 흐름(쪽 · 양식)이 같다.
    /// 호스트가 그린 글줄 · 바탕을 이 벡터 장에서 읽으므로(`PreviewHostKit`) 표식을 단 요소의 글자 · 바탕도 표식 없는 앱 빌드와 같은 것이 읽힌다(켜진 빌드 · 꺼진 빌드 둘 다).
    @Test(arguments: [false, true]) @MainActor func markKeepsTheDrawing(tap: Bool) {
        func page<M: ViewModifier>(_ mark: M) -> [Data] {
            var handler: (@MainActor (String) -> Void)? = nil
            if tap { handler = { (_: String) in } }
            let card = VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.system(size: 17, weight: .semibold)).modifier(mark)
                Text("Body").font(.system(size: 12)).foregroundStyle(Color.black.opacity(0.5))
            }
            .padding(12)
            .background(Color(red: 0, green: 0, blue: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .modifier(mark)
            .frame(width: 200, height: 100)
            .environment(\.snapTap, handler)
            return vectorPage(card)
        }
        let bare = page(Bare()), marked = page(Mark())
        #expect(!bare.isEmpty && bare.contains { !$0.isEmpty }, "기준이 헛돌지 않는다 — 벡터 장에 내용이 있다")
        #expect(marked == bare)
    }

    #if ACTIVE_MARKS
    /// 켜진 빌드 — 표식이 제 이름으로 경계를 올린다(레이아웃을 지키려 몸을 고쳐도 표식의 일은 그대로).
    @Test @MainActor func markRaisesBoundsWhenOn() {
        let seen = Seen()
        let view = Color.clear.frame(width: 10, height: 10).snapID("home.hero")
            .backgroundPreferenceValue(SnapPreferenceKey.self) { marks in
                GeometryReader { _ in
                    let _ = seen.counts.append(marks["home.hero"] == nil ? 0 : marks.count)
                    Color.clear
                }
            }
        #expect(ImageRenderer(content: view).cgImage != nil)
        #expect(!seen.counts.isEmpty)
        #expect(seen.counts.allSatisfy { $0 == 1 })
    }
    #endif

    #if !ACTIVE_MARKS
    /// 빈 모디파이어 — 꺼진 빌드에서 `.snapID` 는 받은 뷰를 그 타입 그대로 돌려준다.
    @Test @MainActor func markIsIdentityWhenOff() {
        let marked = Text("x").snapID("home.hero")
        #expect(marked is Text)
    }

    /// 값이 0 — 꺼진 빌드에서는 표식을 달아도 경계가 올라오지 않는다(렌더 안에서 키를 읽어도 빈 사전).
    @Test @MainActor func markRaisesNoBoundsWhenOff() {
        let seen = Seen()
        let view = Color.clear.frame(width: 10, height: 10).snapID("home.hero")
            .backgroundPreferenceValue(SnapPreferenceKey.self) { marks in
                GeometryReader { _ in
                    let _ = seen.counts.append(marks.count)
                    Color.clear
                }
            }
        #expect(ImageRenderer(content: view).cgImage != nil)
        #expect(!seen.counts.isEmpty)
        #expect(seen.counts.allSatisfy { $0 == 0 })
    }
    #endif
}
