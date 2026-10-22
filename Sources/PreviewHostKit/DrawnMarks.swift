#if os(macOS)
import CoreGraphics
import Foundation
import PDFKit
import PreviewProtocol

// 그린 글줄 · 요소 바탕 — 호스트가 그 장을 벡터(PDF 한 장)로 한 번 더 그려(`ImageRenderer.render` — 공개 손) 읽는다(`render.drawn`).
// 화면 코드는 아무것도 달지 않는다 — SwiftUI 가 그린 글자는 표식이 있든 없든 다 잡히고, 소속 요소 · 바탕은 이미 모은 요소 경계(`snapFrames`)로 가린다.
//
//   읽는 손 : 쪽의 내용 흐름을 `CGPDFScanner`(공개 · ISO 32000 의 연산자)로 걷는다 — 그래픽 상태(변환 · 채움 색 · 불투명도) · 글 상태(글꼴 · 크기 · 행렬) ·
//             채운 경로. 글의 문자열은 `PDFKit`(공개)이 글꼴의 문자표로 푼 글자와 그 상자를 쓴다(대체 글꼴 · CID 글꼴까지) — 글자는 상자의 가운데를 품는
//             글 조각에 붙는다.
//   글줄    : 같은 기준선 · 같은 크기 · 같은 색으로 이어진 조각을 한 줄로 묶는다(한 줄에 섞인 대체 글꼴은 이어 붙는다) · 감긴 글은 줄마다 하나.
//   공백    : 그린 공백 글자는 그린 낱마다 하나 — PDFKit 의 글이 잇닿은 공백 글자를 낱 하나로 접으므로 그 낱의 상자 안에 그린 글자 수로 편다(줄바꿈 없는 공백 ·
//             탭은 PDFKit 이 U+0020 으로 푼다 — 탭은 공백 글자 하나 + 탭 자리까지의 벌림으로 그려진다). 그리지 않은 공백 — 글꼴 대체 경계에서 공백만인 런
//             (시스템 글꼴의 한글 낱말 사이)은 그려지지 않고 벌림만 남는다 — 이어 붙이는 두 조각 사이가 (앞 조각의 자간을 빼고) 0.15 em 이상 벌고 양쪽 끝이 공백이 아니면 공백 하나
//             (몇 칸이었는지는 PDF 에 남지 않는다 · 0.6 em 을 넘는 벌림은 줄을 가른다 — 붙어 선 다른 글과 가를 수 없다). 줄의 앞뒤 공백은 다듬는다.
//   굵기    : 글꼴 이름의 굵기 축 값(`wght<16진 고정소수>` — 가변 인스턴스 이름) ⟂ 이름 꼬리의 굵기 낱말 ⟂ 400.
//   바탕    : 요소 경계와 네 변이 0.5 pt 안으로 맞는 채운 면 중 가장 위(마지막에 칠한 것) — 색 · 모서리(위 변의 곧은 선이 모서리에서 떨어진 거리 —
//             모서리마다 곡선이 셋 이상이면 연속 곡률 모서리라 그 거리를 그 곡률의 비(`continuousExtent`)로 나눈다).
//             색은 그 경계에 겹친 칠을 위에서부터 불투명해질 때까지 합성한 것이다(`composite`).
//   못 잡는 것 : 래스터로만 그리는 것(이미지 안의 글 · AppKit 을 감싼 뷰) · 단색이 아닌 글(그라디언트 — 색 nil) · 테두리만 그린 바탕(채움 아님).
//   효과    : 이 그림에서만 머티리얼을 비활성 외양으로 그린다(`FrameRenderer.DrawnRoot` · macOS 15 이상) — 머티리얼 요소의 바탕은 그 단색 근사다(PNG 의
//             흐림이 아니다) · macOS 14 에서는 머티리얼이 있는 장이 래스터 한 장이라 글줄 · 바탕이 0. 유리는 공개 손으로 끌 수 없다 — 창이 하나라도 선
//             프로세스(호스트의 자기 창)에서는 유리가 진짜로 그려지고 그 장이 통째로 래스터 한 장(글줄 · 바탕 0) · 창이 없는 프로세스에서는 유리와 그 안의
//             내용이 PNG 에도 여기에도 없다(실측 · macOS 27 · 시험 밖 — 한 프로세스에서 선 창은 되돌릴 수 없어 창 없는 상태는 시험이 붙들지 못한다). 프로젝트가 창 없는 장(`RenderContext.offscreen`)에서 유리를 근사로 그려야 선다.
//
// 앱 빌드에는 값이 0이다 — 이 모듈(런타임)은 앱이 링크하지 않고, 엔진이 `drawn` 을 청한 장에서만 돈다.

enum DrawnMarks {
    /// 연속 곡률 모서리(SwiftUI `RoundedCornerStyle.continuous`)의 곧은 선이 모서리에서 떨어진 거리 ÷ 반경.
    static let continuousExtent = 1.528665

    /// 그린 것 한 장 — 글줄 · 요소 바탕.
    struct Page: Equatable {
        var texts: [DrawnText]
        var styles: [DrawnStyle]
    }

    /// PDF 한 쪽(첫 쪽)을 읽는다 — `frames` = 같은 장의 요소 경계(화면 좌상단 원점).
    static func read(pdf: Data, frames: [SnapFrame]) -> Page {
        // 머리(`%PDF`)가 없는 바이트는 열지 않는다 — 열면 CoreGraphics 가 stderr 에 오류 한 줄을 남긴다
        guard pdf.starts(with: Data("%PDF".utf8)), let provider = CGDataProvider(data: pdf as CFData), let doc = CGPDFDocument(provider),
              let page = doc.page(at: 1) else {
            return Page(texts: [], styles: [])
        }
        let box = page.getBoxRect(.mediaBox)
        let walk = PageWalk(height: box.height)
        walk.scan(page)
        let chars = PDFDocument(data: pdf)?.page(at: 0).map(Self.characters) ?? []
        let texts = lines(walk.pieces, chars: chars, glyphs: walk.glyphs, height: box.height, frames: frames)
        let styles = frames.compactMap { f -> DrawnStyle? in
            let stack = walk.fills.filter { $0.matches(f.rect, height: box.height) }
            guard let top = stack.last, let color = Self.composite(stack) else { return nil }
            return DrawnStyle(id: f.id, background: PageWalk.hex(color), radius: top.radius)
        }
        return Page(texts: texts, styles: styles)
    }

    /// 같은 자리에 겹친 칠의 보이는 색 — 가장 위(마지막) 칠부터 아래로 「위에 얹기」로 합성하다 불투명해지면 멈춘다(불투명한 맨 위 칠이면 그 색 그대로).
    /// 맨 위가 반투명이고 아래에 같은 자리 칠이 없으면 반투명 색 그대로다. 맨 위 칠의 색을 모르면(무늬) nil — 아래 칠로 내려가지 않는다(가려진 색을 바탕으로 삼지 않는다).
    /// 중간 · 아래 칠의 색을 모르면 거기서 멈추고 그때까지 합성한 색을 낸다(반투명일 수 있다 — 모르는 칠 밑은 보지 않는다).
    /// 근거: 비활성 외양의 머티리얼(`FrameRenderer.DrawnRoot`)은 불투명 칠 + 같은 자리의 옅은 겹칠(불투명도 0.05)로 그려진다 — 맨 위만 읽으면 겹칠의 색이 바탕이 된다.
    static func composite(_ stack: [Fill]) -> [CGFloat]? {
        var out: [CGFloat]?
        for fill in stack.reversed() {
            guard let c = fill.rgba else { return out }   // 색을 모르는 칠 — 맨 위면 nil · 아래면 지금까지의 합성(반투명일 수 있다)
            guard let o = out else { out = c; if c[3] >= 1 { break } else { continue } }
            // o 가 c 위에 얹힌다(앞곱 아님 · sRGB 성분 그대로)
            let a = o[3] + c[3] * (1 - o[3])
            guard a > 0 else { continue }
            let under = c[3] * (1 - o[3])
            let rgb: [CGFloat] = (0..<3).map { k in (o[k] * o[3] + c[k] * under) / a }
            out = rgb + [a]
            if a >= 1 { break }
        }
        return out
    }

    /// 글자 하나 — 쪽 글(`PDFPage.string`)의 UTF-16 낱 차례 · 상자(쪽 좌표 · 아래 원점 — 줄바꿈 · 상자 없는 낱은 nil).
    struct Character {
        var unit: String
        var box: CGRect?
        var center: CGPoint? { box.map { CGPoint(x: $0.midX, y: $0.midY) } }
        /// 공백 낱 — 가로 공백(U+0020 · U+00A0 · 탭 · U+3000 …)
        var isSpace: Bool { !unit.isEmpty && unit.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) } }
    }

    /// 낱마다 그 범위의 선택(`selection(for: NSRange)`)으로 상자를 얻는다 — `characterBounds(at:)` 의 번호는 지어 넣은 줄바꿈을 세지 않아 글의 번호와 어긋난다.
    static func characters(_ page: PDFPage) -> [Character] {
        let s = (page.string ?? "") as NSString
        return (0..<s.length).map { i in
            let unit = s.substring(with: NSRange(location: i, length: 1))
            guard unit != "\n", unit != "\r", let sel = page.selection(for: NSRange(location: i, length: 1)) else { return Character(unit: unit, box: nil) }
            let b = sel.bounds(for: page)
            return Character(unit: unit, box: b.width > 0 && b.height > 0 ? b : nil)
        }
    }

    /// 조각에 글자를 붙이고 줄로 묶는다 — `glyphs` = 조각마다 그린 글자의 진행 폭 가운데(쪽 좌표 · 조각과 같은 차례 · 공백 낱을 그린 수만큼 편다).
    static func lines(_ pieces: [Piece], chars: [Character], glyphs: [[CGPoint]], height: CGFloat, frames: [SnapFrame]) -> [DrawnText] {
        var text = Array(repeating: "", count: pieces.count)
        var last: Int?
        for c in chars {
            guard let b = c.box, let p = c.center else {
                // 상자 없는 낱 — 짝 대리 낱(그림 문자)의 뒷낱은 앞낱의 조각에 · 지어 넣은 줄바꿈은 버린다
                if let l = last, let u = c.unit.utf16.first, UTF16.isTrailSurrogate(u) { text[l] += c.unit }
                last = nil
                continue
            }
            let hits = pieces.indices.filter { pieces[$0].box.insetBy(dx: -0.5, dy: -0.5).contains(p) }
            guard let i = hits.min(by: { pieces[$0].box.width * pieces[$0].box.height < pieces[$1].box.width * pieces[$1].box.height }) else { last = nil; continue }
            // 공백 낱은 상자 안에 그린 글자 수만큼(PDFKit 이 잇닿은 공백을 낱 하나로 접는다 — 못 세면 하나)
            let n = c.isSpace && i < glyphs.count ? glyphs[i].filter { b.insetBy(dx: -0.5, dy: -0.5).contains($0) }.count : 1
            text[i] += String(repeating: c.unit, count: max(1, n))
            last = i
        }
        /// 화면 좌표(위 원점)의 상자.
        func top(_ box: CGRect) -> CGRect { CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height) }
        /// 소속 — 가운데를 품는 경계 중 가장 작은 것(같은 면적이면 경계 목록에서 앞선 것 — `min(by:)` 는 처음 만난 최소를 낸다).
        func owner(_ box: CGRect) -> String? {
            let r = top(box), mid = CGPoint(x: r.midX, y: r.midY)
            return frames.filter { $0.rect.contains(mid) }.min { $0.w * $0.h < $1.w * $1.h }?.id
        }
        var out: [DrawnText] = []
        var cur: (piece: Piece, box: CGRect, text: String, end: CGFloat, tracking: CGFloat, owner: String?)?
        func flush() {
            guard let c = cur else { return }
            cur = nil
            let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            out.append(DrawnText(text: t, rect: top(c.box), font: c.piece.font.name, size: c.piece.size, weight: c.piece.font.weight,
                                 color: c.piece.color, element: c.owner))
        }
        // 조각마다 소속을 먼저 정하고 같은 소속끼리만 잇는다 — 붙어 선 형제 요소의 같은 꼴 글이 한 줄로 합쳐져 한쪽에 붙지 않게(둘 다 nil 이면 잇는다)
        for (i, p) in pieces.enumerated() {
            let o = owner(p.box)
            if let c = cur, c.owner == o, abs(c.piece.baseline - p.baseline) <= 0.5, abs(c.piece.size - p.size) < 0.01, c.piece.color == p.color,
               p.start >= c.end - 1, p.start - c.end - c.tracking <= p.size * 0.6 {
                // 그리지 않은 공백 — 벌림만 남은 자리(양쪽 끝에 그린 공백이 있으면 그것이 그 자리다). 벌림에서 앞 조각의 자간(`Tc`)을 뺀다 —
                // 그리지 않은 공백 낱도 자간을 받는다. 0.15 em 근거(실측 · 13 pt 시스템 글꼴): 그리지 않은 공백 0.275 em(SF 공백 0.281 em + Tc) ⟂
                // 붙어 그린 조각 사이(대체 경계 · 커닝) 0.001 em · 간격 0 으로 붙여 놓은 글자 조각 0.02–0.05 em — 둘 사이.
                let gap = p.start - c.end - c.tracking >= p.size * 0.15 && c.text.last?.isWhitespace == false && text[i].first?.isWhitespace == false
                cur = (c.piece, c.box.union(p.box), c.text + (gap ? " " : "") + text[i], p.end, p.tracking, o)
            } else {
                flush()
                cur = (p, p.box, text[i], p.end, p.tracking, o)
            }
        }
        flush()
        return out
    }

    // MARK: 읽은 조각

    /// 글 보이기 연산 하나 — 쪽 좌표(아래 원점).
    struct Piece {
        var box: CGRect
        var baseline: CGFloat
        var start: CGFloat, end: CGFloat
        var font: Font
        var size: Double
        var color: String?
        /// 글자마다 더한 자간(`Tc` — 쪽 좌표 · 그리지 않은 공백의 벌림에서 뺀다)
        var tracking: CGFloat = 0
    }

    /// 채운 면 하나 — 쪽 좌표(아래 원점).
    struct Fill {
        var box: CGRect
        /// sRGB 성분 넷(0–1) — 무늬 · 모르는 공간은 nil
        var rgba: [CGFloat]?
        var radius: Double
        func matches(_ r: CGRect, height: CGFloat) -> Bool {
            let top = height - box.maxY
            return abs(box.minX - r.minX) <= 0.5 && abs(top - r.minY) <= 0.5 && abs(box.width - r.width) <= 0.5 && abs(box.height - r.height) <= 0.5
        }
    }

    /// 글꼴 하나 — 이름 · 굵기 · 진행 폭(1/1000 글꼴 단위) · 올림 · 내림.
    struct Font {
        var name: String
        var weight: Int
        var bytesPerCode: Int
        var widths: [Int: CGFloat]
        var defaultWidth: CGFloat
        var ascent: CGFloat, descent: CGFloat

        func width(_ code: Int) -> CGFloat { widths[code] ?? defaultWidth }

        static let unknown = Font(name: "", weight: 400, bytesPerCode: 1, widths: [:], defaultWidth: 500, ascent: 800, descent: -200)

        init(name: String, weight: Int, bytesPerCode: Int, widths: [Int: CGFloat], defaultWidth: CGFloat, ascent: CGFloat, descent: CGFloat) {
            self.name = name; self.weight = weight; self.bytesPerCode = bytesPerCode; self.widths = widths; self.defaultWidth = defaultWidth
            self.ascent = ascent; self.descent = descent
        }

        /// 글꼴 사전(`/Type /Font`) — 단순 글꼴(`FirstChar` · `Widths`) ⟂ 합성 글꼴(`Type0` — 자손의 `W` · `DW` · 두 바이트 부호).
        init(_ dict: CGPDFDictionaryRef) {
            let base = Self.name(dict, "BaseFont") ?? ""
            var widths: [Int: CGFloat] = [:]
            var dw: CGFloat = 0
            var descriptor: CGPDFDictionaryRef?
            var bytes = 1
            if Self.name(dict, "Subtype") == "Type0" {
                bytes = 2
                var kids: CGPDFArrayRef?
                var kid: CGPDFDictionaryRef?
                if CGPDFDictionaryGetArray(dict, "DescendantFonts", &kids), let kids, CGPDFArrayGetDictionary(kids, 0, &kid), let kid {
                    dw = Self.number(kid, "DW") ?? 1000
                    var w: CGPDFArrayRef?
                    if CGPDFDictionaryGetArray(kid, "W", &w), let w { widths = Self.cidWidths(w) }
                    CGPDFDictionaryGetDictionary(kid, "FontDescriptor", &descriptor)
                }
            } else {
                let first = Int(Self.number(dict, "FirstChar") ?? 0)
                var w: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dict, "Widths", &w), let w {
                    for i in 0..<CGPDFArrayGetCount(w) { var v: CGPDFReal = 0; if CGPDFArrayGetNumber(w, i, &v) { widths[first + i] = v } }
                }
                CGPDFDictionaryGetDictionary(dict, "FontDescriptor", &descriptor)
                dw = descriptor.flatMap { Self.number($0, "MissingWidth") } ?? 0
            }
            let ascent = descriptor.flatMap { Self.number($0, "Ascent") } ?? 800
            let descent = descriptor.flatMap { Self.number($0, "Descent") } ?? -200
            let declared = descriptor.flatMap { Self.number($0, "FontWeight") }.map { Int($0) }
            self.init(name: Self.display(base), weight: declared ?? Self.weight(base), bytesPerCode: bytes, widths: widths, defaultWidth: dw,
                      ascent: ascent, descent: descent)
        }

        /// 보이는 이름 — 묶음 표지(`ABCDEF+`)와 가변 인스턴스 꼬리(`_wdth…` 처럼 `_` 뒤)를 걷는다.
        static func display(_ base: String) -> String {
            var s = Substring(base)
            if let plus = s.firstIndex(of: "+"), s.distance(from: s.startIndex, to: plus) == 6, s[..<plus].allSatisfy({ $0.isUppercase && $0.isASCII }) {
                s = s[s.index(after: plus)...]
            }
            if let bar = s.firstIndex(of: "_") { s = s[..<bar] }
            return String(s)
        }

        /// 굵기 — 이름의 굵기 축 값(`wght` 뒤의 16진 · 16.16 고정소수) ⟂ 이름 꼬리의 낱말 ⟂ 400.
        static func weight(_ base: String) -> Int {
            if let r = base.range(of: "wght") {
                let hex = base[r.upperBound...].prefix { $0.isHexDigit }
                if !hex.isEmpty, let v = Int(hex, radix: 16) { return min(1000, max(1, Int((Double(v) / 65536).rounded()))) }
            }
            let style = display(base).split(separator: "-").last.map { $0.lowercased() } ?? ""
            let words: [(String, Int)] = [("extralight", 200), ("ultralight", 200), ("semibold", 600), ("demibold", 600), ("extrabold", 800),
                                          ("ultrabold", 800), ("thin", 100), ("light", 300), ("medium", 500), ("bold", 700), ("heavy", 800),
                                          ("black", 900)]
            return words.first { style.contains($0.0) }?.1 ?? 400
        }

        static func cidWidths(_ w: CGPDFArrayRef) -> [Int: CGFloat] {
            var out: [Int: CGFloat] = [:]
            var i = 0
            let n = CGPDFArrayGetCount(w)
            while i < n {
                var first: CGPDFInteger = 0
                guard CGPDFArrayGetInteger(w, i, &first) else { break }
                var list: CGPDFArrayRef?
                if CGPDFArrayGetArray(w, i + 1, &list), let list {
                    for k in 0..<CGPDFArrayGetCount(list) { var v: CGPDFReal = 0; if CGPDFArrayGetNumber(list, k, &v) { out[first + k] = v } }
                    i += 2
                } else {
                    var last: CGPDFInteger = 0
                    var v: CGPDFReal = 0
                    guard CGPDFArrayGetInteger(w, i + 1, &last), CGPDFArrayGetNumber(w, i + 2, &v), last >= first, last - first < 65536 else { break }
                    for c in first...last { out[c] = v }
                    i += 3
                }
            }
            return out
        }

        static func name(_ d: CGPDFDictionaryRef, _ key: String) -> String? {
            var p: UnsafePointer<CChar>?
            return CGPDFDictionaryGetName(d, key, &p) ? p.map { String(cString: $0) } : nil
        }
        static func number(_ d: CGPDFDictionaryRef, _ key: String) -> CGFloat? {
            var v: CGPDFReal = 0
            return CGPDFDictionaryGetNumber(d, key, &v) ? v : nil
        }
    }
}

// MARK: 내용 흐름 걷기

/// 쪽 하나의 내용 흐름을 걷는 상태 — 그래픽 상태 더미 · 글 상태 · 지금 경로 · 읽은 조각과 면.
final class PageWalk {
    struct State {
        var ctm: CGAffineTransform = .identity
        var space: CGColorSpace? = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        var components: [CGFloat] = [0]
        var pattern = false
        var alpha: CGFloat = 1
        /// 이 양식에 들어올 때의 불투명도 — `gs` 의 `ca` 는 대입이라 그 위에 곱한다(양식 밖이면 1)
        var groupAlpha: CGFloat = 1
        var font: DrawnMarks.Font = .unknown
        var fontSize: CGFloat = 0
        var charSpacing: CGFloat = 0, wordSpacing: CGFloat = 0, hScale: CGFloat = 1, leading: CGFloat = 0, rise: CGFloat = 0
    }

    let height: CGFloat
    var state = State()
    var saved: [State] = []
    var tm: CGAffineTransform = .identity, tlm: CGAffineTransform = .identity
    /// 지금 경로의 점(쪽 좌표 — 제어점 포함 · 상자를 잰다) · 곡선 위의 점(선분 · 곡선의 끝 — 모서리를 잰다) · 곡선 수
    var path: [CGPoint] = []
    var ends: [CGPoint] = []
    var curves = 0
    var streams: [CGPDFContentStreamRef] = []
    var fonts: [CGPDFDictionaryRef: DrawnMarks.Font] = [:]
    var pieces: [DrawnMarks.Piece] = []
    /// 조각마다 그린 글자의 진행 폭 가운데(쪽 좌표 · `pieces` 와 같은 차례 — 공백 낱을 편다)
    var glyphs: [[CGPoint]] = []
    var fills: [DrawnMarks.Fill] = []
    /// 겹친 양식의 깊이 — 스스로를 부르는 양식에서 멈춘다
    var depth = 0

    init(height: CGFloat) { self.height = height }

    func scan(_ page: CGPDFPage) {
        let cs = CGPDFContentStreamCreateWithPage(page)
        run(cs)
        CGPDFContentStreamRelease(cs)
    }

    private func run(_ cs: CGPDFContentStreamRef) {
        streams.append(cs)
        defer { streams.removeLast() }
        let scanner = CGPDFScannerCreate(cs, Self.table, Unmanaged.passUnretained(self).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
    }

    private func resource(_ kind: String, _ name: String) -> CGPDFObjectRef? {
        guard let cs = streams.last else { return nil }
        return CGPDFContentStreamGetResource(cs, kind, name)
    }

    // MARK: 색

    var fillColor: String? { fillRGBA.map(Self.hex) }

    /// 지금 채움 색 — sRGB 성분 넷(빨강 · 초록 · 파랑 · 불투명도 · 0–1). 무늬 · 모르는 공간은 nil.
    var fillRGBA: [CGFloat]? {
        guard !state.pattern, let space = state.space, space.numberOfComponents == state.components.count else { return nil }
        guard let color = CGColor(colorSpace: space, components: state.components + [state.alpha]) else { return nil }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB), let c = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let v = c.components, v.count == 4 else { return nil }
        return v.map { min(1, max(0, $0)) }
    }

    static func hex(_ v: [CGFloat]) -> String {
        let b = v.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        let rgb = String(format: "#%02x%02x%02x", b[0], b[1], b[2])
        return b[3] == 255 ? rgb : rgb + String(format: "%02x", b[3])
    }

    func setSpace(_ name: String) {
        state.pattern = false
        switch name {
        case "DeviceGray", "G": state.space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2); state.components = [0]
        case "DeviceRGB", "RGB": state.space = CGColorSpace(name: CGColorSpace.sRGB); state.components = [0, 0, 0]
        case "DeviceCMYK", "CMYK": state.space = CGColorSpace(name: CGColorSpace.genericCMYK); state.components = [0, 0, 0, 1]
        case "Pattern": state.pattern = true; state.space = nil
        default:
            state.space = nil
            guard let obj = resource("ColorSpace", name) else { return }
            var arr: CGPDFArrayRef?
            var direct: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(obj, .name, &direct), let direct { setSpace(String(cString: direct)); return }
            guard CGPDFObjectGetValue(obj, .array, &arr), let arr else { return }
            var family: UnsafePointer<CChar>?
            guard CGPDFArrayGetName(arr, 0, &family), let family else { return }
            switch String(cString: family) {
            case "ICCBased":
                var stream: CGPDFStreamRef?
                var format = CGPDFDataFormat.raw
                if CGPDFArrayGetStream(arr, 1, &stream), let stream, let data = CGPDFStreamCopyData(stream, &format), format == .raw {
                    state.space = CGColorSpace(iccData: data)
                }
            case "Pattern": state.pattern = true
            case "DeviceRGB", "CalRGB": state.space = CGColorSpace(name: CGColorSpace.sRGB)
            case "DeviceGray", "CalGray": state.space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            default: break
            }
            state.components = Array(repeating: 0, count: state.space?.numberOfComponents ?? 0)
        }
    }

    func setGState(_ name: String) {
        guard let obj = resource("ExtGState", name) else { return }
        var d: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(obj, .dictionary, &d), let d else { return }
        var ca: CGPDFReal = 1
        if CGPDFDictionaryGetNumber(d, "ca", &ca) { state.alpha = state.groupAlpha * ca }
    }

    // MARK: 글

    func setFont(_ name: String, size: CGFloat) {
        state.fontSize = size
        guard let obj = resource("Font", name) else { state.font = .unknown; return }
        var d: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(obj, .dictionary, &d), let d else { state.font = .unknown; return }
        let key = d
        if let f = fonts[key] { state.font = f; return }
        let f = DrawnMarks.Font(d)
        fonts[key] = f
        state.font = f
    }

    /// 글 보이기 — 글자열(바이트)과 TJ 의 수(1/1000 글자 크기만큼 왼쪽으로)를 차례로.
    func show(_ parts: [ShowPart]) {
        let f = state.font
        let fs = state.fontSize, th = state.hScale
        let start = tm
        let m = start.concatenating(state.ctm)
        let lo = f.descent / 1000 * fs + state.rise, hi = f.ascent / 1000 * fs + state.rise
        var advance: CGFloat = 0
        var points: [CGPoint] = []
        for part in parts {
            switch part {
            case .adjust(let n): advance -= n / 1000 * fs * th
            case .bytes(let bytes):
                var i = 0
                while i + f.bytesPerCode <= bytes.count {
                    var code = 0
                    for k in 0..<f.bytesPerCode { code = code << 8 | Int(bytes[i + k]) }
                    let word = f.bytesPerCode == 1 && code == 32 ? state.wordSpacing : 0
                    let w = f.width(code) / 1000 * fs * th
                    points.append(CGPoint(x: advance + w / 2, y: (lo + hi) / 2).applying(m))
                    advance += w + (state.charSpacing + word) * th
                    i += f.bytesPerCode
                }
            }
        }
        tm = CGAffineTransform(translationX: advance, y: 0).concatenating(tm)
        let corners = [CGPoint(x: 0, y: lo), CGPoint(x: advance, y: lo), CGPoint(x: 0, y: hi), CGPoint(x: advance, y: hi)].map { $0.applying(m) }
        let origin = CGPoint(x: 0, y: state.rise).applying(m), end = CGPoint(x: advance, y: state.rise).applying(m)
        let size = Double(fs * (m.c * m.c + m.d * m.d).squareRoot())
        pieces.append(DrawnMarks.Piece(box: Self.bounds(corners), baseline: origin.y, start: min(origin.x, end.x), end: max(origin.x, end.x),
                                       font: f, size: size, color: fillColor,
                                       tracking: state.charSpacing * th * (m.a * m.a + m.b * m.b).squareRoot()))
        glyphs.append(points)
    }

    enum ShowPart { case bytes([UInt8]), adjust(CGFloat) }

    func nextLine(_ tx: CGFloat, _ ty: CGFloat) {
        tlm = CGAffineTransform(translationX: tx, y: ty).concatenating(tlm)
        tm = tlm
    }

    // MARK: 경로

    /// 경로에 점 하나 — `end` = 곡선 위의 점(제어점이 아니다).
    func add(_ p: CGPoint, end: Bool = true) {
        let q = p.applying(state.ctm)
        path.append(q)
        if end { ends.append(q) }
    }

    func clearPath() { path.removeAll(); ends.removeAll(); curves = 0 }

    func fill() {
        defer { clearPath() }
        guard path.count >= 3 else { return }
        let box = Self.bounds(path)
        guard box.width > 0, box.height > 0 else { return }
        fills.append(DrawnMarks.Fill(box: box, rgba: fillRGBA, radius: Double(radius(box))))
    }

    /// 모서리 반경 — 위 변 위의 곡선 위 점 중 가장 왼쪽이 모서리에서 떨어진 거리(곧은 선의 시작) · 모서리마다 곡선 셋 이상이면 연속 곡률.
    func radius(_ box: CGRect) -> CGFloat {
        guard curves > 0 else { return 0 }
        let onTop = ends.filter { abs($0.y - box.maxY) <= 0.01 }.map(\.x)
        guard let left = onTop.min() else { return 0 }
        let extent = max(0, left - box.minX)
        let r = curves >= 12 ? extent / CGFloat(DrawnMarks.continuousExtent) : extent
        return min(r, min(box.width, box.height) / 2)
    }

    static func bounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: 양식

    func form(_ name: String) {
        guard depth < 32, let obj = resource("XObject", name) else { return }
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(obj, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return }
        guard DrawnMarks.Font.name(dict, "Subtype") == "Form" else { return }
        var matrix: CGPDFArrayRef?
        var m = CGAffineTransform.identity
        if CGPDFDictionaryGetArray(dict, "Matrix", &matrix), let matrix, CGPDFArrayGetCount(matrix) == 6 {
            var v = [CGPDFReal](repeating: 0, count: 6)
            for i in 0..<6 { CGPDFArrayGetNumber(matrix, i, &v[i]) }
            m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
        guard let parent = streams.last else { return }
        // 자원이 없는 양식은 제 사전으로 세운다 — 찾는 이름이 없으면 부모의 자원으로 간다
        let cs = CGPDFContentStreamCreateWithStream(stream, resources ?? dict, parent)
        saved.append(state)
        let (savedTM, savedTLM, savedPath, savedEnds, savedCurves) = (tm, tlm, path, ends, curves)
        state.ctm = m.concatenating(state.ctm)
        state.groupAlpha = state.alpha
        depth += 1
        run(cs)
        depth -= 1
        CGPDFContentStreamRelease(cs)
        state = saved.removeLast()
        (tm, tlm, path, ends, curves) = (savedTM, savedTLM, savedPath, savedEnds, savedCurves)
    }

    // MARK: 연산자 표

    nonisolated(unsafe) static let table: CGPDFOperatorTableRef = {
        let t = CGPDFOperatorTableCreate()!
        func on(_ op: String, _ body: @escaping CGPDFOperatorCallback) { CGPDFOperatorTableSetCallback(t, op, body) }
        on("q") { _, i in let w = PageWalk.of(i); w.saved.append(w.state) }
        on("Q") { _, i in let w = PageWalk.of(i); if let s = w.saved.popLast() { w.state = s } }
        on("cm") { s, i in let w = PageWalk.of(i); if let m = PageWalk.matrix(s) { w.state.ctm = m.concatenating(w.state.ctm) } }
        on("gs") { s, i in if let n = PageWalk.popName(s) { PageWalk.of(i).setGState(n) } }
        on("cs") { s, i in if let n = PageWalk.popName(s) { PageWalk.of(i).setSpace(n) } }
        let sc: CGPDFOperatorCallback = { s, i in
            // 지금 색 공간의 성분 수만큼만 꺼낸다 — 빈 더미에서 꺼내면 CoreGraphics 가 「stack underflow」를 남기고 stderr 에
            // 「CoreGraphics PDF has logged an error」 한 줄을 찍는다. 무늬 · 모르는 공간은 꺼내지 않는다(색 nil — 연산자마다 제 수만 꺼내므로 남은 것이 다른 연산자의 값을 흐리지 않는다).
            let w = PageWalk.of(i)
            guard !w.state.pattern, let n = w.state.space?.numberOfComponents else { return }
            if let v = PageWalk.numbers(s, n) { w.state.components = v } else { w.state.pattern = true }
        }
        on("sc", sc); on("scn", sc)
        on("g") { s, i in let w = PageWalk.of(i); let v = PageWalk.numbers(s, 1); w.setSpace("DeviceGray"); if let v { w.state.components = v } }
        on("rg") { s, i in let w = PageWalk.of(i); let v = PageWalk.numbers(s, 3); w.setSpace("DeviceRGB"); if let v { w.state.components = v } }
        on("k") { s, i in let w = PageWalk.of(i); let v = PageWalk.numbers(s, 4); w.setSpace("DeviceCMYK"); if let v { w.state.components = v } }
        on("BT") { _, i in let w = PageWalk.of(i); w.tm = .identity; w.tlm = .identity }
        on("Tf") { s, i in
            var size: CGPDFReal = 0
            guard CGPDFScannerPopNumber(s, &size), let n = PageWalk.popName(s) else { return }
            PageWalk.of(i).setFont(n, size: size)
        }
        on("Tc") { s, i in if let v = PageWalk.numbers(s, 1) { PageWalk.of(i).state.charSpacing = v[0] } }
        on("Tw") { s, i in if let v = PageWalk.numbers(s, 1) { PageWalk.of(i).state.wordSpacing = v[0] } }
        on("Tz") { s, i in if let v = PageWalk.numbers(s, 1) { PageWalk.of(i).state.hScale = v[0] / 100 } }
        on("TL") { s, i in if let v = PageWalk.numbers(s, 1) { PageWalk.of(i).state.leading = v[0] } }
        on("Ts") { s, i in if let v = PageWalk.numbers(s, 1) { PageWalk.of(i).state.rise = v[0] } }
        on("Tm") { s, i in let w = PageWalk.of(i); if let m = PageWalk.matrix(s) { w.tm = m; w.tlm = m } }
        on("Td") { s, i in if let v = PageWalk.numbers(s, 2) { PageWalk.of(i).nextLine(v[0], v[1]) } }
        on("TD") { s, i in if let v = PageWalk.numbers(s, 2) { let w = PageWalk.of(i); w.state.leading = -v[1]; w.nextLine(v[0], v[1]) } }
        on("T*") { _, i in let w = PageWalk.of(i); w.nextLine(0, -w.state.leading) }
        on("Tj") { s, i in if let b = PageWalk.popBytes(s) { PageWalk.of(i).show([.bytes(b)]) } }
        on("'") { s, i in
            let w = PageWalk.of(i)
            w.nextLine(0, -w.state.leading)
            if let b = PageWalk.popBytes(s) { w.show([.bytes(b)]) }
        }
        on("\"") { s, i in
            let w = PageWalk.of(i)
            let b = PageWalk.popBytes(s)
            if let v = PageWalk.numbers(s, 2) { w.state.wordSpacing = v[0]; w.state.charSpacing = v[1] }
            w.nextLine(0, -w.state.leading)
            if let b { w.show([.bytes(b)]) }
        }
        on("TJ") { s, i in
            var arr: CGPDFArrayRef?
            guard CGPDFScannerPopArray(s, &arr), let arr else { return }
            var parts: [ShowPart] = []
            for k in 0..<CGPDFArrayGetCount(arr) {
                var str: CGPDFStringRef?
                var n: CGPDFReal = 0
                if CGPDFArrayGetString(arr, k, &str), let str { parts.append(.bytes(PageWalk.bytes(str))) } else if CGPDFArrayGetNumber(arr, k, &n) { parts.append(.adjust(n)) }
            }
            PageWalk.of(i).show(parts)
        }
        on("m") { s, i in if let v = PageWalk.numbers(s, 2) { PageWalk.of(i).add(CGPoint(x: v[0], y: v[1])) } }
        on("l") { s, i in if let v = PageWalk.numbers(s, 2) { PageWalk.of(i).add(CGPoint(x: v[0], y: v[1])) } }
        on("c") { s, i in
            guard let v = PageWalk.numbers(s, 6) else { return }
            let w = PageWalk.of(i)
            w.add(CGPoint(x: v[0], y: v[1]), end: false); w.add(CGPoint(x: v[2], y: v[3]), end: false); w.add(CGPoint(x: v[4], y: v[5])); w.curves += 1
        }
        let short: CGPDFOperatorCallback = { s, i in
            guard let v = PageWalk.numbers(s, 4) else { return }
            let w = PageWalk.of(i)
            w.add(CGPoint(x: v[0], y: v[1]), end: false); w.add(CGPoint(x: v[2], y: v[3])); w.curves += 1
        }
        on("v", short); on("y", short)
        on("re") { s, i in
            guard let v = PageWalk.numbers(s, 4) else { return }
            let w = PageWalk.of(i)
            for p in [(v[0], v[1]), (v[0] + v[2], v[1]), (v[0] + v[2], v[1] + v[3]), (v[0], v[1] + v[3])] { w.add(CGPoint(x: p.0, y: p.1)) }
        }
        let fill: CGPDFOperatorCallback = { _, i in PageWalk.of(i).fill() }
        for op in ["f", "F", "f*", "B", "B*", "b", "b*"] { on(op, fill) }
        let drop: CGPDFOperatorCallback = { _, i in PageWalk.of(i).clearPath() }
        for op in ["n", "S", "s"] { on(op, drop) }
        on("Do") { s, i in if let n = PageWalk.popName(s) { PageWalk.of(i).form(n) } }
        return t
    }()

    static func of(_ info: UnsafeMutableRawPointer?) -> PageWalk { Unmanaged<PageWalk>.fromOpaque(info!).takeUnretainedValue() }

    static func popName(_ s: CGPDFScannerRef) -> String? {
        var p: UnsafePointer<CChar>?
        return CGPDFScannerPopName(s, &p) ? p.map { String(cString: $0) } : nil
    }

    /// 수 n 개(뒤에서부터 꺼내 차례대로 돌려준다).
    static func numbers(_ s: CGPDFScannerRef, _ n: Int) -> [CGFloat]? {
        var v = [CGFloat](repeating: 0, count: n)
        for k in stride(from: n - 1, through: 0, by: -1) {
            var x: CGPDFReal = 0
            guard CGPDFScannerPopNumber(s, &x) else { return nil }
            v[k] = x
        }
        return v
    }

    static func matrix(_ s: CGPDFScannerRef) -> CGAffineTransform? {
        numbers(s, 6).map { CGAffineTransform(a: $0[0], b: $0[1], c: $0[2], d: $0[3], tx: $0[4], ty: $0[5]) }
    }

    static func popBytes(_ s: CGPDFScannerRef) -> [UInt8]? {
        var str: CGPDFStringRef?
        return CGPDFScannerPopString(s, &str) ? str.map(bytes) : nil
    }

    static func bytes(_ str: CGPDFStringRef) -> [UInt8] {
        guard let p = CGPDFStringGetBytePtr(str) else { return [] }
        return Array(UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(str)))
    }
}
#endif
