#if os(macOS)
import Foundation
import PreviewProtocol
import ProjectFormat
import SwiftUI

// 프로젝트가 호스트에 화면을 꽂는 자리 — 호스트 런타임의 표면. 엔진은 이 타입들을 모른다(프로토콜 메시지로만 본다).
// 프로젝트는 자기 등록부를 이 꼴로 옮기는 어댑터 하나만 쓴다(호스트 실행물은 프로젝트 패키지 안 — 프로젝트가 자기 코드로 빌드한다).

/// 한 장을 그리는 데 필요한 바깥 조건 — 화면 값(Style)이 아니라 틀(크기 · 테마 · 층 · 창 여부 · 쪽 여부).
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
    /// 이 장은 쪽이다(`RenderRequest.page`) — 종이 한 쪽을 그린다: 기기 틀(디스플레이 코너 · 안전 영역)을 대지 않는다 · 크기에서 기기 꼴을 고르지 않는다(코너 0 · 안전 영역 0).
    /// 기본 false(기기 화면).
    public var page: Bool = false
    /// 자기 창에서 요소(snapID)를 눌렀다 — 엔진의 「고르기」로 넘긴다(창 없는 렌더는 엔진이 경계로 직접 가린다)
    public var onElementTap: (@MainActor @Sendable (String) -> Void)?
    public init(size: CGSize, theme: String? = nil, layers: [String] = [], offscreen: Bool = true, interactive: Bool = false, scrollY: CGFloat = 0,
                layersOnly: Bool = false, onElementTap: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.size = size; self.theme = theme; self.layers = layers; self.offscreen = offscreen; self.interactive = interactive; self.scrollY = scrollY
        self.layersOnly = layersOnly; self.onElementTap = onElementTap
    }
    /// 쪽 표지를 함께 주는 꼴 — `page` 는 기본값 없이 받는다(위의 손과 겹치지 않게 · 1.x 의 공개 손은 그대로 둔다).
    public init(size: CGSize, theme: String? = nil, layers: [String] = [], offscreen: Bool = true, interactive: Bool = false, scrollY: CGFloat = 0,
                layersOnly: Bool = false, page: Bool, onElementTap: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.init(size: size, theme: theme, layers: layers, offscreen: offscreen, interactive: interactive, scrollY: scrollY,
                  layersOnly: layersOnly, onElementTap: onElementTap)
        self.page = page
    }
}

/// 화면 하나의 살아 있는 값 — 상태(픽스처) 하나로 서고, `render` 마다 값(엔진이 안 파일에서 읽은 것)을 받고 `patch` 를 그 위에 쌓는다 · 그리기 전에 비동기 원천을 기다린다(`prepare`). 메인 스레드에서만.
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
    /// 이번 장을 그리기 전에 기다릴 것 — 지금 값(`load` · `apply` 뒤)을 그 틀(`context` — 이번 장의 크기 · 테마 · 창 없는 렌더인가)로 그린 그림이
    /// 비동기 원천(모델 그림 · 파일 읽기)을 기다리면 그것이 다 찰 때 돌아온다. 외양(테마)마다 다른 그림은 그 외양의 것을 데운다(캐시는 이름과 외양으로 잡는다).
    /// 호스트는 장을 그리기 전마다(`render` · `patch` · 토큰 바뀜 · `shot` · 자기 창) 이것을 기다리고, 그동안 온 메시지는 차례대로 뒤에 선다(patch 는 합쳐진다) —
    /// 창 없는 렌더(`ImageRenderer` — 동기 · 그 장 뒤의 그림을 기다리지 못한다)도 첫 장부터 그 값의 그림이다. 시간으로 기다리지 않는다 — 원천의 끝(성공 ⟂ 실패)이 신호다.
    /// 실패한 원천은 그 값의 대체 그림(원래 이미지)으로 서게 두고 돌아온다(던지지 않는다). 호스트의 시한(20 초 — 엔진이 장을 기다리는 시한 안)을 넘기거나 세션이 닫히면
    /// 호스트는 그 준비를 취소하고(`Task.isCancelled` — 협력 취소) 기다림을 놓는다 — 시한을 넘긴 장은 그때의 값 그대로 그린다.
    /// 시한을 넘긴 장은 **끝난 장**이다 — 반쯤 찬 그림(빈 자리)이 그 요청의 답이 되고, 원천이 나중에 차도 호스트는 다시 그리라는 신호를 보내지 않는다(다음 요청이 그 그림을 쓴다).
    /// 지킬 것: 원천은 취소(`Task.isCancelled`)를 보고 놓는다 — 취소를 무시하는 준비는 호스트가 기다림만 놓으므로 돌아올 때까지 살아서 다음 장의 준비와 **겹쳐 불릴 수 있다**
    /// (같은 원천을 두 번 부르지 않게 — 진행 중인 일을 이름 · 외양으로 나눠 기다린다).
    /// `context.offscreen` 은 그 요청이 내는 장 기준이다 — `render` 는 자기 창이 서 있어도 창 없는 장(답 프레임)의 틀로 준비한다 · 자기 창(`window`)만 창의 틀이다.
    /// 그림 캐시의 열쇠는 이름 + 외양(테마의 바탕)으로 잡고 `offscreen` 을 쓰지 않는다.
    /// 기본 = 기다릴 것 없음(곧장) — 이것을 구현하지 않은 세션은 이 손이 없던 판과 같은 장을 낸다(장마다 준비를 세우는 짧은 차례 하나가 더 든다).
    func prepare(_ context: RenderContext) async
}

extension PreviewSession {
    /// 기다릴 것 없음 — 그림이 값만으로 서는 세션(비동기 원천이 없다).
    public func prepare(_ context: RenderContext) async {}
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
