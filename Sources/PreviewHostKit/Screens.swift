#if os(macOS)
import Foundation
import PreviewProtocol
import ProjectFormat
import SwiftUI

// 프로젝트가 호스트에 화면을 꽂는 자리 — 호스트 런타임의 표면. 엔진은 이 타입들을 모른다(프로토콜 메시지로만 본다).
// 프로젝트는 자기 등록부를 이 꼴로 옮기는 어댑터 하나만 쓴다(호스트 실행물은 프로젝트 패키지 안 — 프로젝트가 자기 코드로 빌드한다).

/// 한 장을 그리는 데 필요한 바깥 조건 — 화면 값(Style)이 아니라 틀(크기 · 테마 · 층 · 창 여부).
public struct RenderContext: Sendable {
    public var size: CGSize
    public var theme: String?
    public var layers: [String]
    /// 창 없는 렌더(`ImageRenderer`)인가 — 유리 · 머티리얼은 근사로 그려야 한다(진짜 백드롭 블러는 창 없이 서지 않는다).
    public var offscreen: Bool
    /// 앱처럼 손을 받는가(탭 · 펼침 · 호버) — 자기 창 모드에서만 의미가 있다.
    public var interactive: Bool
    /// 창 없는 렌더의 스크롤 흉내(pt) — 콘텐츠를 그만큼 올려 그린다(`RenderRequest.scroll`)
    public var scrollY: CGFloat
    /// 층만 — 화면 본체 · 바탕 없이 투명한 장에 층만 그린다(`RenderRequest.layersOnly`)
    public var layersOnly: Bool
    /// 자기 창에서 요소(snapID)를 눌렀다 — 엔진의 「고르기」로 넘긴다(창 없는 렌더는 엔진이 경계로 직접 가린다)
    public var onElementTap: (@MainActor @Sendable (String) -> Void)?
    public init(size: CGSize, theme: String? = nil, layers: [String] = [], offscreen: Bool = true, interactive: Bool = false, scrollY: CGFloat = 0,
                layersOnly: Bool = false, onElementTap: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.size = size; self.theme = theme; self.layers = layers; self.offscreen = offscreen; self.interactive = interactive; self.scrollY = scrollY
        self.layersOnly = layersOnly; self.onElementTap = onElementTap
    }
}

/// 화면 하나의 살아 있는 값 — 상태(픽스처) 하나로 서고, `render` 마다 값(엔진이 안 파일에서 읽은 것)을 받고 `patch` 를 그 위에 쌓는다. 메인 스레드에서만.
/// 호스트는 프로젝트 문서(안 파일)를 열지 않는다 — 값은 언제나 엔진이 보낸다.
@MainActor
public protocol PreviewSession: AnyObject {
    /// 이번 장의 값 — 화면의 Style 값(nil = 서술의 기본값) · 겹칠 층의 값과 자료 · 픽스처 갈아 끼우기(nil = 상태의 픽스처 · `RenderRequest.fixture`).
    /// 같은 값이 다시 오면 아무것도 바꾸지 않아도 된다(렌더러 캐시).
    func load(style: StyleValues?, layers: [LayerState], fixture: JSONValue?) throws
    /// 칸 하나를 바꾼다(모르는 칸 · 꼴이 틀린 값이면 던진다).
    func apply(_ edit: Edit) throws
    /// 지금 값으로 그린 화면 — 틀(크기 · 모서리 · 층)까지 합친 것.
    func view(_ context: RenderContext) -> AnyView
    /// 마지막 레이아웃의 요소 경계(pt · 화면 좌상단 원점).
    func snapFrames() -> [SnapFrame]
    /// 지금 값으로 화면이 내는 요소 id 전부(층 포함) — 엔진이 경계 수와 대조한다(`FrameHeader.elements`).
    func elementIDs() -> [String]
    /// 지금 겹친 층마다 낸 것 — 요소 id · 푼 자료(`FrameHeader.layers`).
    func layerReports() -> [LayerReport]
}

public protocol PreviewScreen: Sendable {
    var name: String { get }
    /// `hello.screens` 의 한 칸 — 상태 · Style 서술.
    @MainActor func info() throws -> ScreenInfo
    @MainActor func session(state: String) throws -> any PreviewSession
}

public enum PreviewHostError: Error, CustomStringConvertible {
    case noSocket
    case unknownScreen(String)
    case unknownLayer(String)
    case noSession
    case renderFailed(String)
    public var description: String {
        switch self {
        case .noSocket: "소켓 자리가 없다 — --socket <경로> 또는 --folder <프로젝트 폴더>"
        case .unknownScreen(let n): "모르는 화면: \(n)"
        case .unknownLayer(let n): "모르는 층: \(n)"
        case .noSession: "render 전에 patch · window · shot 이 왔다"
        case .renderFailed(let why): "렌더 실패 — \(why)"
        }
    }
}
#endif
