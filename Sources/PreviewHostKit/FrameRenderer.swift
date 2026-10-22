#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import PreviewProtocol
import SwiftUI
import UniformTypeIdentifiers

// 창 없는 렌더 — `ImageRenderer.cgImage` 를 **그 바이트 그대로** 프레임으로 쓴다(`FrameFormat.rgba8sRGB`).
//
// 고른 길:
//   · `render(rasterizationScale:renderer:)` 로 우리 CGContext(= 칸 메모리)에 바로 그리면 복사는 0 이지만 CoreGraphics 소프트웨어
//     래스터라 그림자 많은 화면에서 `cgImage` 보다 훨씬 느리다. 그래서 `cgImage` 를 쓴다.
//   · `cgImage` 의 꼴(RGBA premultipliedLast · sRGB · 줄 = 폭×4)을 그대로 프로토콜 형식으로 삼는다 — 픽셀을 다시 쓰지 않는다.
//   · 렌더러는 같은 render 와 그 위의 patch 사이에서 다시 쓴다(내용만 갈아 끼움 — 값이 같으면 렌더러가 제 캐시를 낸다) ·
//     다른 render 는 새 렌더러로 그린다(앞 장의 뷰 그래프가 새지 않게 — 부르는 쪽 `HostServer`).

@MainActor
public final class FrameRenderer {
    /// 렌더 한 장 — 이미지와 그 바이트(CFData 가 붙든다). 보내기가 끝날 때까지 이 값을 들고 있어야 바이트가 산다.
    public struct Frame {
        public let image: CGImage
        public let data: CFData
        public let w: Int, h: Int, stride: Int
        public var bytes: Int { stride * h }
        public var base: UnsafeRawPointer { UnsafeRawPointer(CFDataGetBytePtr(data)!) }
    }

    private var renderer: ImageRenderer<DrawnRoot>?
    /// The view of the frame just rendered — `drawn` puts it back into the same renderer with only the material appearance changed.
    private var view: AnyView?

    public init() {}

    public func render(_ view: AnyView, size: CGSize, scale: CGFloat) throws -> Frame {
        let r: ImageRenderer<DrawnRoot>
        let root = DrawnRoot(content: view, collecting: false)
        if let old = renderer { old.content = root; r = old } else { r = ImageRenderer(content: root); renderer = r }
        self.view = view
        r.proposedSize = ProposedViewSize(size)
        r.scale = scale
        guard let img = r.cgImage else { throw PreviewHostError.renderFailed("ImageRenderer 가 이미지를 내지 않았다") }
        // 꼴이 바뀌면(다른 OS · 넓은 색역 설정) 조용히 바꿔 쓰지 않고 멈춘다 — 프로토콜 형식이 곧 이 꼴이다
        guard img.bitsPerPixel == 32, img.bitsPerComponent == 8, img.alphaInfo == .premultipliedLast,
              img.bitmapInfo.intersection(.byteOrderMask).rawValue == 0, img.colorSpace?.name == CGColorSpace.sRGB,
              let data = img.dataProvider?.data, CFDataGetLength(data) >= img.bytesPerRow * img.height
        else { throw PreviewHostError.renderFailed("ImageRenderer 꼴이 RGBA8 앞곱 sRGB 가 아니다: \(img.bitmapInfo.rawValue) · \(String(describing: img.colorSpace?.name))") }
        return Frame(image: img, data: data, w: img.width, h: img.height, stride: img.bytesPerRow)
    }

    /// 방금 그린 장을 벡터(PDF 한 쪽)로 한 번 더 그려 그린 글줄 · 요소 바탕을 읽는다(`DrawnMarks` · `render.drawn`) — `render(_:size:scale:)` 뒤에 같은 렌더러로.
    /// `frames` = 그 장의 요소 경계(소속 요소 · 바탕을 가린다). 그린 장이 없으면 빈 것.
    /// Only this vector pass draws materials in their inactive appearance (solid fills — vector, `DrawnRoot`): with a real material the PDF becomes one
    /// raster image of the whole frame, so no lines and no backgrounds. The rendered PNG (`render`) is untouched. The renderer's content is restored
    /// afterwards (same root type — the view graph and its state stay).
    func drawn(frames: [SnapFrame]) -> DrawnMarks.Page {
        guard let r = renderer, let view else { return DrawnMarks.Page(texts: [], styles: []) }
        r.content = DrawnRoot(content: view, collecting: true)
        defer { r.content = DrawnRoot(content: view, collecting: false) }
        let data = NSMutableData()
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return DrawnMarks.read(pdf: data as Data, frames: frames)
    }

    /// The renderer's root — the PNG pass leaves the content as it is (the environment is not touched); the vector pass draws materials in their
    /// inactive appearance (`materialActiveAppearance` — public, macOS 15+). Measured on macOS 27: with any real material, the PDF from
    /// `ImageRenderer.render` is the whole frame as one image (`/Im1 Do` — no text, no fills); with the inactive appearance the material is an opaque
    /// fill plus a faint veil of the same shape and everything else stays vector. The root type never changes, so toggling does not rebuild the graph.
    struct DrawnRoot: View {
        let content: AnyView
        let collecting: Bool
        var body: some View {
            if #available(macOS 15, *) {
                content.transformEnvironment(\.materialActiveAppearance) { if collecting { $0 = .inactive } }
            } else {
                content
            }
        }
    }

    /// PNG 쓰기 — 호스트의 `shot` 이 쓴다(SDK 안 손 · 폴더가 없으면 만든다). 메인 액터 밖에서도 부른다.
    /// 공개 표면이 아니다 — 호스트 밖에서 그림을 파일로 쓰는 손은 쓰는 쪽(엔진의 도구)이 제 것을 든다.
    nonisolated package static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw PreviewHostError.renderFailed("PNG 쓰기 \(url.path)") }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { throw PreviewHostError.renderFailed("PNG 쓰기 \(url.path)") }
    }
}
#endif
