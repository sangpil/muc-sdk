import Foundation
import ProjectFormat

// 엔진 ⟂ 미리보기 호스트의 말 — 호스트(프로젝트가 자기 코드로 빌드한 별도 프로세스) · 엔진이 이 모듈 하나를 문다(정본 `Docs/SDK.md`).
//
//   흐름   : 엔진이 호스트를 띄운다 → 호스트 `hello`(화면 등록부 · 층 · 프레임 형식) → 엔진 `hello`(전송 선택 · 공유 메모리 자리) →
//            `render`(화면 · 상태 · Style 값 · 층 · 테마 · 크기 · 배율) → `frame` … 조절판을 움직이면 `patch`(최신값 우선) → `frame` …
//   값     : 안 파일(프로젝트 문서)은 **엔진만** 읽고 쓴다 — 호스트는 문서를 열지 않고 `render` 의 값(Style · 층의 값과 자료)과 `patch` 를 받는다.
//            호스트 자기 창 모드(Xcode Previews 방식)면 `window`(창 자리 안내) → `patch` → `ack`(창에 반영 끝) · 끝 `bye`.
//   줄 꼴  : JSON 한 줄 = 메시지 하나 · `{"type":"render", …payload 칸}` 평평한 꼴(nc 로 읽힌다). 프레임 바이트는 줄 뒤에 길이 접두로
//            따라온다(`Framing.swift`) — 공유 메모리면 칸 번호만 실린다.
//   시각   : 전부 `PreviewClock`(CLOCK_UPTIME_RAW ns) — 같은 기계의 두 프로세스가 같은 시계를 읽으므로 구간을 프로세스 넘어 뺄 수 있다.

// 판(`PreviewProtocolVersion`) · 맞대기(`ProtocolJudge` — 엔진이 판정자 · N 과 N-1 을 받는다)는 `Negotiation.swift`.

public struct Size: Codable, Hashable, Sendable {
    public var w: Double, h: Double
    public init(w: Double, h: Double) { self.w = w; self.h = h }
}

// MARK: 등록부 — `hello.screens` · `hello.layers`

/// 화면 하나 — 등록부 이름 · 상태(픽스처) · Style 서술(절 · 칸 · 기본값 — 엔진이 안 파일을 재는 잣대와 같은 한 벌).
/// 안의 이름 · 값은 싣지 않는다 — 안 파일은 엔진이 읽는다(`RenderRequest.style`).
public struct ScreenInfo: Codable, Equatable, Sendable {
    public var name: String
    public var states: [String]
    public var style: StyleSchema
    /// 픽스처가 **데이터로** 고른 색 역할(정본 실명 → 수 · 상태 전부의 합) — 안 파일 쓰임에 더해 세는 몫(엔진은 픽스처의 꼴을 모른다) · nil = 싣지 않음.
    public var fixtureColorUsage: [String: Int]?
    public init(name: String, states: [String], style: StyleSchema, fixtureColorUsage: [String: Int]? = nil) {
        self.name = name; self.states = states; self.style = style; self.fixtureColorUsage = fixtureColorUsage
    }
}

/// 화면 위에 겹치는 층(크롬 · 콜아웃) — 칸은 화면과 같은 꼴(서술).
public struct LayerInfo: Codable, Equatable, Sendable {
    public var name: String
    public var style: StyleSchema
    /// 층이 IA 문서에서 읽는 구성 칸의 서술(`LayerComposition`) — nil = 구성을 읽지 않는 층(또는 싣지 않음).
    public var composition: LayerComposition?
    public init(name: String, style: StyleSchema, composition: LayerComposition? = nil) {
        self.name = name; self.style = style; self.composition = composition
    }
}

/// 이번 장에 겹칠 층 하나 — 이름(`hello.layers`) · Style 값(엔진이 그 층의 안 파일에서 읽어 서술로 잰 것 · nil = 서술의 기본값) ·
/// 자료(엔진이 IA 문서에서 채운 `LayerContext` 의 JSON — 그 문서에서 무엇을 셈하는가는 프로젝트가 정한다 · 엔진은 뜻을 모른다).
public struct LayerState: Codable, Hashable, Sendable {
    public var name: String
    public var style: StyleValues?
    public var data: JSONValue?
    public init(name: String, style: StyleValues? = nil, data: JSONValue? = nil) { self.name = name; self.style = style; self.data = data }
}

/// 층 자료의 엔진 쪽 꼴 — 층이 얹힐 화면과 그 프로젝트의 IA 문서(`paths.ia`). 엔진이 IA 문서에서 채워 `LayerState.data` 로 싣고(호스트는 문서를 열지 않는다)
/// 그 문서에서 무엇을 셈하는가는 프로젝트가 정한다(크롬이면 그 화면의 구성 · 탭 슬롯 — 프로젝트의 낱말 · 유도 규칙은 호스트에 산다).
public struct LayerContext: Codable, Equatable, Sendable {
    /// 층이 얹힐 화면 — IA 마디 id(등록부 이름과 같은 글자)
    public var screen: String
    public var ia: IADoc
    public init(screen: String, ia: IADoc) { self.screen = screen; self.ia = ia }
    /// 층 자료(JSON) — `LayerState.data`.
    public func data() throws -> JSONValue { try JSONValue.from(self) }
    public init(data: JSONValue) throws { self = try data.decode(LayerContext.self) }
}

/// 가장자리 띠(pt) — 위 · 왼쪽 · 아래 · 오른쪽.
public struct Insets: Codable, Hashable, Sendable {
    public var top: Double, left: Double, bottom: Double, right: Double
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) { self.top = top; self.left = left; self.bottom = bottom; self.right = right }
}

// MARK: 전송

/// 공유 메모리 자리 — 엔진이 만들고(호스트가 죽어도 남는다) 호스트가 연다.
public struct SharedMemoryInfo: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// POSIX `shm_open` — 이름(`/…` · 31바이트 한계)
        case posix
        /// `/tmp` 파일 mmap — 경로
        case file
    }
    public var kind: Kind
    public var name: String
    public var slotBytes: Int
    public var slots: Int
    public init(kind: Kind, name: String, slotBytes: Int, slots: Int) { self.kind = kind; self.name = name; self.slotBytes = slotBytes; self.slots = slots }
    public var totalBytes: Int { slotBytes * slots }
}

// MARK: 메시지 몸

public struct Hello: Codable, Equatable, Sendable {
    public enum Role: String, Codable, CaseIterable, Sendable { case host, engine }
    public var role: Role
    /// 보내는 쪽의 판 — 판정은 엔진이 한다(`ProtocolJudge`). 이 칸의 이름 · 자리는 판이 올라도 그대로다(판 읽개가 몸을 풀기 전에 읽는다).
    public var protocolVersion: Int
    public var pid: Int32
    public var name: String
    /// host → engine
    public var screens: [ScreenInfo]?
    public var layers: [LayerInfo]?
    public var formats: [FrameFormat]?
    /// host → engine — 프로젝트의 데이터(`HelloProject.swift`): IA 낱말 · 기기 틀 · 빌드된 표 요약. 셋 다 선택(nil = 싣지 않음 · 엔진은 그 칸 없는 길로).
    public var ia: IAInfo?
    public var frames: [DeviceFrameInfo]?
    public var tokensBuilt: BuiltTokens?
    /// engine → host — nil 이면 프레임 바이트를 소켓으로(전송 A) · 있으면 칸 번호만(전송 B)
    public var shared: SharedMemoryInfo?
    /// `protocolVersion` 은 필수다 — 기본 인자로 두면 판이 부르는 쪽 목적 코드에 묻혀 증분 빌드가 판의 변경을 놓친다(`Negotiation.swift` 「기본값」).
    public init(role: Role, protocolVersion: Int, pid: Int32, name: String,
                screens: [ScreenInfo]? = nil, layers: [LayerInfo]? = nil, formats: [FrameFormat]? = nil, shared: SharedMemoryInfo? = nil,
                ia: IAInfo? = nil, frames: [DeviceFrameInfo]? = nil, tokensBuilt: BuiltTokens? = nil) {
        self.role = role; self.protocolVersion = protocolVersion; self.pid = pid; self.name = name
        self.screens = screens; self.layers = layers; self.formats = formats; self.shared = shared
        self.ia = ia; self.frames = frames; self.tokensBuilt = tokensBuilt
    }
}

public struct RenderRequest: Codable, Equatable, Sendable {
    public var seq: UInt64
    public var screen: String
    public var state: String
    /// 화면의 Style 값(엔진이 안 파일에서 읽어 서술로 잰 것 — 칸 이름 → 저장 꼴) — nil = 서술의 기본값. 이 render 가 화면의 값을 갈아 끼운다(뒤의 `patch` 는 그 위에)
    public var style: StyleValues?
    /// 테마 이름 — nil = 라이트
    public var theme: String?
    public var size: Size
    public var scale: Double
    /// 겹칠 층(`hello.layers` 의 이름 · 값 · 자료) — nil = 없음
    public var layers: [LayerState]?
    /// snap 프레임(요소 경계)을 실을까 — 의견 · 선택 층이 쓴다
    public var frames: Bool?
    /// 창 없는 렌더의 스크롤 흉내(pt) — 콘텐츠를 그만큼 올려 그린다(엔진이 휠을 받아 보낸다 · 관성 · 고무줄은 없다)
    public var scroll: Double?
    /// 픽스처 갈아 끼우기 — 상태(`state`)의 픽스처 대신 이 값(프로젝트가 뜻을 정하는 JSON — 화면의 픽스처 꼴 · 엔진이 데이터셋 · 손이 옮긴 자리에서 만든다) ·
    /// nil = 상태의 픽스처. 이 render 가 갈아 끼우고 뒤의 `patch` 는 그대로 둔다.
    public var fixture: JSONValue?
    /// 층만 그린다 — 화면 본체 · 바탕 없이 투명한 장에 `layers` 만(엔진이 본체와 층 사이에 제 그림 — 구성요소 — 을 끼울 때). nil = 본체 + 층.
    public var layersOnly: Bool?
    public init(seq: UInt64, screen: String, state: String, style: StyleValues? = nil, theme: String? = nil, size: Size, scale: Double,
                layers: [LayerState]? = nil, frames: Bool? = nil, scroll: Double? = nil, fixture: JSONValue? = nil, layersOnly: Bool? = nil) {
        self.seq = seq; self.screen = screen; self.state = state; self.style = style; self.theme = theme
        self.size = size; self.scale = scale; self.layers = layers; self.frames = frames; self.scroll = scroll
        self.fixture = fixture; self.layersOnly = layersOnly
    }
}

/// 층 하나가 이번 장에 낸 것 — 그 층의 요소 id(`FrameHeader.elements` 의 부분) · 푼 자료(프로젝트가 뜻을 정하는 JSON — 엔진이 보낸 자료를 화면 값 · 픽스처와
/// 합쳐 실제로 그린 꼴. 엔진은 뜻을 모른 채 프로젝트의 엔진 쪽 손에 넘긴다 — 크롬이면 본체가 그린 조각을 비켜선 구성 · 픽스처의 도구).
public struct LayerReport: Codable, Hashable, Sendable {
    public var name: String
    public var elements: [String]
    public var data: JSONValue?
    /// 층이 화면 가장자리에서 덮는 띠(pt · 이번 장의 크기에서) — 엔진이 본체와 층 사이에 제 그림(씬 같은 구성요소)을 끼울 때 그 그림이 피할 자리.
    /// nil = 덮지 않는다.
    public var cover: Insets?
    public init(name: String, elements: [String], data: JSONValue? = nil, cover: Insets? = nil) {
        self.name = name; self.elements = elements; self.data = data; self.cover = cover
    }
}

public struct Edit: Codable, Hashable, Sendable {
    public var field: String
    public var value: JSONValue
    /// nil = 화면 칸 · 이름이 있으면 그 층의 칸
    public var layer: String?
    public init(field: String, value: JSONValue, layer: String? = nil) { self.field = field; self.value = value; self.layer = layer }
}

/// 조절판 값 바꿈 — 칸 여럿을 한 번에(최신값 우선으로 모인 것이 한 프레임이 되게 · 칸 하나면 `{field,value}` 하나).
/// `seq` = 엔진이 매긴 입력 번호(단조 증가) — 호스트는 프레임 `applied` 에 반영한 가장 큰 번호를 돌려준다.
public struct Patch: Codable, Equatable, Sendable {
    public var seq: UInt64
    public var edits: [Edit]
    public init(seq: UInt64, edits: [Edit]) { self.seq = seq; self.edits = edits }
}

/// 프레임 바이트가 어디 있나.
public enum FramePayload: Equatable, Sendable {
    /// 이 줄 뒤에 길이 접두(u32 LE)로 따라온다
    case inline(bytes: Int)
    /// 공유 메모리 칸 — 다음다음 프레임까지 유효(호스트는 칸 셋을 차례로 돌려 쓴다 · 진행 중 요청이 하나면 엔진이 보는 칸은 건드리지 않는다)
    case slot(index: Int, bytes: Int)

    public var bytes: Int { switch self { case .inline(let b), .slot(_, let b): return b } }
}

extension FramePayload: Codable {
    private enum Keys: String, CodingKey { case inline, slot, bytes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let n = try c.decodeIfPresent(Int.self, forKey: .inline) { self = .inline(bytes: n); return }
        self = .slot(index: try c.decode(Int.self, forKey: .slot), bytes: try c.decode(Int.self, forKey: .bytes))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .inline(let n): try c.encode(n, forKey: .inline)
        case .slot(let i, let n): try c.encode(i, forKey: .slot); try c.encode(n, forKey: .bytes)
        }
    }
}

/// 호스트 쪽 구간 시각(`PreviewClock` ns) — 받음 · 메인에서 시작 · 렌더 끝 · 보냄.
public struct HostTiming: Codable, Equatable, Sendable {
    public var recv: UInt64, start: UInt64, rendered: UInt64, sent: UInt64
    public init(recv: UInt64, start: UInt64, rendered: UInt64, sent: UInt64) { self.recv = recv; self.start = start; self.rendered = rendered; self.sent = sent }
}

public struct FrameHeader: Codable, Equatable, Sendable {
    /// 답하는 요청(render · patch)의 번호
    public var seq: UInt64
    /// 이 프레임이 반영한 입력 번호 중 가장 큰 것(호스트 쪽에서 모인 patch 포함)
    public var applied: UInt64
    /// 픽셀 크기 · 줄 바이트
    public var w: Int, h: Int, stride: Int
    public var scale: Double
    public var format: FrameFormat
    public var snapFrames: [SnapFrame]
    /// 그린 요소 id 전부(지금 값 · 층 포함 · `layersOnly` 면 층만 · `frames` 를 청한 render 의 답에만) — 엔진이 경계 수와 대조한다(빠진 경계 = 그리지 못한 요소)
    public var elements: [String]?
    /// 층마다 낸 것(요소 · 푼 자료 — `frames` 를 청한 render 의 답에만) — 화면 본체의 요소 = `elements` 에서 층의 것을 뺀 나머지
    public var layers: [LayerReport]?
    /// 호스트 렌더 소요(ms)
    public var ms: Double
    public var payload: FramePayload
    public var timing: HostTiming?
    public init(seq: UInt64, applied: UInt64, w: Int, h: Int, stride: Int, scale: Double, format: FrameFormat, snapFrames: [SnapFrame],
                elements: [String]? = nil, layers: [LayerReport]? = nil, ms: Double, payload: FramePayload, timing: HostTiming? = nil) {
        self.seq = seq; self.applied = applied; self.w = w; self.h = h; self.stride = stride; self.scale = scale; self.format = format
        self.snapFrames = snapFrames; self.elements = elements; self.layers = layers; self.ms = ms; self.payload = payload; self.timing = timing
    }

    /// 화면 본체가 낸 요소 — 그린 요소에서 층의 것을 뺀 것(차례 그대로).
    public var screenElements: [String]? {
        guard let elements else { return nil }
        let layered = Set((layers ?? []).flatMap(\.elements))
        return layered.isEmpty ? elements : elements.filter { !layered.contains($0) }
    }
}

/// 토큰 정본이 바뀌었다 — 호스트는 공급자를 다시 읽고 지금 화면을 다시 그린다.
public struct TokensChanged: Codable, Equatable, Sendable {
    public var seq: UInt64
    public init(seq: UInt64) { self.seq = seq }
}

/// 지금 화면을 PNG 로(리뷰 · 찍기) — 경로는 엔진이 정한다.
public struct ShotRequest: Codable, Equatable, Sendable {
    public var seq: UInt64, path: String
    public init(seq: UInt64, path: String) { self.seq = seq; self.path = path }
}

/// 호스트 자기 창(Xcode Previews 방식) — 엔진은 창 자리만 안내한다(화면 좌표 · AppKit 아래-왼쪽 원점). `show == false` 면 창을 내린다.
/// `w` · `h` = 창 크기(pt · nil = 지금 render 의 크기) · `above` = 엔진 창의 번호(`NSWindow.windowNumber`) — 그 창 바로 위 보통 층에 선다
/// (엔진이 뒤로 가면 다른 앱 창 밑으로 · 엔진 창이 앞으로 오면 엔진이 다시 보낸다) · nil = 떠 있는 층(측정 하니스).
public struct WindowRequest: Codable, Equatable, Sendable {
    public var seq: UInt64
    public var x: Double, y: Double
    public var show: Bool
    public var w: Double?, h: Double?
    public var above: Int?
    /// 보이는 부분 — 화면(x · y · w · h) 안의 자리(pt · 위-왼쪽 원점). 엔진의 미리보기 자리가 스크롤 · 창 끝에 잘렸으면 호스트 창은 그 부분만 덮는다
    /// (화면은 제 크기 그대로 그리고 창이 그 부분을 보이는 틀이 된다). nil = 전부.
    public var clip: CGRect?
    public init(seq: UInt64, x: Double, y: Double, show: Bool, w: Double? = nil, h: Double? = nil, above: Int? = nil, clip: CGRect? = nil) {
        self.seq = seq; self.x = x; self.y = y; self.show = show; self.w = w; self.h = h; self.above = above; self.clip = clip
    }
}

/// 창 모드의 답 — 프레임 바이트 없이 「창에 반영(커밋) 끝」만. shot 의 답도 이 꼴(`ms` = 쓰기 소요).
public struct Ack: Codable, Equatable, Sendable {
    public var seq: UInt64
    public var applied: UInt64
    public var ms: Double
    public var timing: HostTiming?
    /// 창 모드 — 그 커밋에서 레이아웃(요소 경계)이 실제로 바뀌었나(가려진 창이 갱신을 건너뛰는지 가리는 확인 칸)
    public var changed: Bool?
    public init(seq: UInt64, applied: UInt64, ms: Double, timing: HostTiming? = nil, changed: Bool? = nil) {
        self.seq = seq; self.applied = applied; self.ms = ms; self.timing = timing; self.changed = changed
    }
}

public struct Bye: Codable, Equatable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

public struct ErrorMessage: Codable, Equatable, Sendable {
    public var seq: UInt64?
    public var message: String
    public init(seq: UInt64?, message: String) { self.seq = seq; self.message = message }
}

// MARK: 메시지

public enum Message: Equatable, Sendable {
    case hello(Hello)
    case render(RenderRequest)
    case frame(FrameHeader)
    case patch(Patch)
    case tokensChanged(TokensChanged)
    case shot(ShotRequest)
    case window(WindowRequest)
    case ack(Ack)
    case error(ErrorMessage)
    case bye(Bye)

    public var type: String {
        switch self {
        case .hello: "hello"; case .render: "render"; case .frame: "frame"; case .patch: "patch"
        case .tokensChanged: "tokensChanged"; case .shot: "shot"; case .window: "window"; case .ack: "ack"
        case .error: "error"; case .bye: "bye"
        }
    }
    /// 요청 · 답의 번호(번호가 없는 hello · error · bye 는 nil).
    public var seq: UInt64? {
        switch self {
        case .render(let m): m.seq; case .frame(let m): m.seq; case .patch(let m): m.seq; case .tokensChanged(let m): m.seq
        case .shot(let m): m.seq; case .window(let m): m.seq; case .ack(let m): m.seq
        case .hello, .error, .bye: nil
        }
    }
    /// 이 줄 뒤에 따라오는 바이너리 길이(없으면 nil).
    public var inlineBytes: Int? {
        if case .frame(let f) = self, case .inline(let n) = f.payload { return n }
        return nil
    }
}

/// 평평한 꼴 — `type` 칸 하나 + 몸의 칸. 몸 타입은 모르는 칸(`type`)을 무시하므로 같은 컨테이너에서 디코드한다.
extension Message: Codable {
    private enum Keys: String, CodingKey { case type }
    public enum DecodeError: Error, CustomStringConvertible {
        case unknownType(String)
        public var description: String { switch self { case .unknownType(let t): "모르는 메시지 종류: \(t)" } }
    }
    public init(from decoder: Decoder) throws {
        let t = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .type)
        switch t {
        case "hello": self = .hello(try Hello(from: decoder))
        case "render": self = .render(try RenderRequest(from: decoder))
        case "frame": self = .frame(try FrameHeader(from: decoder))
        case "patch": self = .patch(try Patch(from: decoder))
        case "tokensChanged": self = .tokensChanged(try TokensChanged(from: decoder))
        case "shot": self = .shot(try ShotRequest(from: decoder))
        case "window": self = .window(try WindowRequest(from: decoder))
        case "ack": self = .ack(try Ack(from: decoder))
        case "error": self = .error(try ErrorMessage(from: decoder))
        case "bye": self = .bye(try Bye(from: decoder))
        default: throw DecodeError.unknownType(t)
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .hello(let m): try m.encode(to: encoder)
        case .render(let m): try m.encode(to: encoder)
        case .frame(let m): try m.encode(to: encoder)
        case .patch(let m): try m.encode(to: encoder)
        case .tokensChanged(let m): try m.encode(to: encoder)
        case .shot(let m): try m.encode(to: encoder)
        case .window(let m): try m.encode(to: encoder)
        case .ack(let m): try m.encode(to: encoder)
        case .error(let m): try m.encode(to: encoder)
        case .bye(let m): try m.encode(to: encoder)
        }
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(type, forKey: .type)
    }
}
