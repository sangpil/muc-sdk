#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
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

    private var renderer: ImageRenderer<AnyView>?

    public init() {}

    public func render(_ view: AnyView, size: CGSize, scale: CGFloat) throws -> Frame {
        let r: ImageRenderer<AnyView>
        if let old = renderer { old.content = view; r = old } else { r = ImageRenderer(content: view); renderer = r }
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

    /// PNG 쓰기 — 호스트의 `shot` · 엔진 쪽 프로젝트 도구(찍기 · 격자 · 창 그림)가 함께 쓰는 한 벌(폴더가 없으면 만든다). 메인 액터 밖에서도 부른다.
    nonisolated public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw PreviewHostError.renderFailed("PNG 쓰기 \(url.path)") }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { throw PreviewHostError.renderFailed("PNG 쓰기 \(url.path)") }
    }
}
#endif
