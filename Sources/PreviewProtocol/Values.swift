import Foundation

// 프로토콜의 작은 값들 — 프레임 형식 · 요소 경계 · 그린 글줄과 요소 바탕 · 시계 · 소켓 경로. 조절판 값 한 조각은 SDK 의 JSON 값(`ProjectFormat.JSONValue`)이다.

/// 프레임 픽셀 형식 — 하나: **RGBA 8비트 · 알파 앞곱(뒤) · sRGB** —
/// `ImageRenderer.cgImage` 가 내는 꼴 그대로다(premultipliedLast · 기본 바이트 순서 · 줄 바이트 = 폭 × 4).
/// 그 꼴로 보내면 호스트가 픽셀을 다시 쓰지 않는다(BGRA 로 바꾸면 한 장마다 swizzle 복사가 든다).
/// 줄 바이트(stride)는 프레임 머리가 갖는다 — 렌더러가 줄을 맞춰 늘려도 엔진은 머리를 따른다.
public struct FrameFormat: Codable, Hashable, Sendable {
    public var pixel: String
    public var colorSpace: String
    public init(pixel: String, colorSpace: String) { self.pixel = pixel; self.colorSpace = colorSpace }

    public static let rgba8sRGB = FrameFormat(pixel: "RGBA8-premultipliedLast", colorSpace: "sRGB")

    /// 빈틈 없는 줄로 셈한 바이트 — 공유 메모리 칸 크기를 정할 때(실제 크기는 머리의 stride × h).
    public static func tightBytes(width: Int, height: Int) -> Int { width * 4 * height }
}

/// 요소 하나의 경계(pt · 화면 좌상단 원점 · 소수 둘째 자리) — 프로젝트의 화면 코드가 `.snapID`(SDK `ScreenMarks`)로 단 요소를 호스트가 모아(`PreviewHostKit.FrameSink`)
/// 프레임 머리(`FrameHeader.snapFrames`)에 싣는다. 엔진은 이 경계로 요소를 고르고 · 강조하고 · 의견을 단다(`frames.json` 도 같은 꼴).
public struct SnapFrame: Codable, Equatable, Sendable {
    public let id: String
    public let x: Double, y: Double, w: Double, h: Double
    public init(id: String, rect: CGRect) {
        self.id = id
        x = Double(rect.minX).rounded(to: 2); y = Double(rect.minY).rounded(to: 2)
        w = Double(rect.width).rounded(to: 2); h = Double(rect.height).rounded(to: 2)
    }
    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// 화면이 그린 글줄 하나 — 호스트가 그 장을 벡터로 한 번 더 그려 읽은 것(`render.drawn` 을 청한 장의 답에만 · `FrameHeader.texts`).
/// 화면 코드는 아무것도 달지 않는다 — 그린 글자는 표식(`.snapID`)이 있든 없든 다 잡힌다. 경계는 pt · 화면 좌상단 원점 · 소수 둘째 자리.
public struct DrawnText: Codable, Equatable, Sendable {
    /// 한 줄의 글(앞뒤 공백을 걷은 것 — 여러 줄로 감긴 글은 줄마다 하나)
    public var text: String
    /// 줄의 상자 — 글리프의 진행 폭 × 글꼴의 올림 · 내림
    public var x: Double, y: Double, w: Double, h: Double
    /// 글꼴의 PostScript 이름(묶음 표지 · 가변 인스턴스 꼬리를 걷은 것) — `.` 으로 시작하면 플랫폼의 시스템 UI 글꼴이다(읽는 쪽이 제 시스템 글꼴로 옮긴다).
    /// 한 줄에 대체 글꼴이 섞이면(다른 문자 체계) 줄의 첫 조각의 글꼴이다.
    public var font: String
    /// 글자 크기(pt — 그린 크기)
    public var size: Double
    /// 굵기(1–1000 — 글꼴의 굵기 축 값이 있으면 그 값 · 없으면 이름의 굵기 낱말 · 둘 다 없으면 400)
    public var weight: Int
    /// 글자 색(`#rrggbb` ⟂ 불투명이 아니면 `#rrggbbaa` · sRGB · 겹친 불투명도까지 곱한 것) — nil = 단색이 아니다(그라디언트 · 무늬)
    public var color: String?
    /// 이 줄을 품은 가장 안쪽 요소(`snapFrames` 의 id — 줄의 가운데를 품는 경계 중 가장 작은 것) — nil = 어느 요소 안도 아니다
    public var element: String?
    public init(text: String, rect: CGRect, font: String, size: Double, weight: Int, color: String?, element: String?) {
        self.text = text
        x = Double(rect.minX).rounded(to: 2); y = Double(rect.minY).rounded(to: 2)
        w = Double(rect.width).rounded(to: 2); h = Double(rect.height).rounded(to: 2)
        self.font = font; self.size = size.rounded(to: 2); self.weight = weight; self.color = color; self.element = element
    }
    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// 요소 하나의 그린 바탕 — 그 요소의 경계(`SnapFrame`)와 같은 자리를 칠한 면 중 가장 위의 것(`render.drawn` 을 청한 장의 답에만 · `FrameHeader.styles`).
/// 경계와 같은 크기로 칠한 면이 없는 요소는 싣지 않는다.
public struct DrawnStyle: Codable, Equatable, Sendable {
    /// 요소 id(`SnapFrame.id`)
    public var id: String
    /// 바탕 색(`#rrggbb` ⟂ `#rrggbbaa` · sRGB · 겹친 불투명도까지 곱한 것)
    public var background: String
    /// 모서리 반경(pt · 소수 둘째 자리 — 0 = 각진 모서리 · 연속 곡률 모서리면 그 모서리를 낳은 반경)
    public var radius: Double
    public init(id: String, background: String, radius: Double) { self.id = id; self.background = background; self.radius = radius.rounded(to: 2) }
}

private extension Double {
    func rounded(to places: Int) -> Double { let p = pow(10.0, Double(places)); return (self * p).rounded() / p }
}

/// 두 프로세스가 같이 읽는 시계 — `CLOCK_UPTIME_RAW`(잠자기 동안 멈춤 · 단조). 구간을 프로세스 넘어 뺄 수 있다.
public enum PreviewClock {
    @inline(__always) public static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    @inline(__always) public static func ms(_ from: UInt64, _ to: UInt64) -> Double { Double(Int64(bitPattern: to &- from)) / 1e6 }
}

/// 소켓 자리 — `sockaddr_un.sun_path` 는 104바이트(널 포함)라 깊은 폴더 밑에 두면 터진다.
/// 그래서 `/tmp` 아래 **폴더 경로의 해시**로 짧은 고정 이름을 쓴다 — 같은 프로젝트 폴더면 같은 자리, 워크트리마다 다른 자리.
/// 해시는 FNV-1a 64(프로세스마다 씨가 바뀌는 `Hasher` 를 쓰면 엔진 · 호스트가 서로 다른 이름을 낸다).
public enum SocketPath {
    public static let maxBytes = 103

    public static func forFolder(_ folder: String, prefix: String = "mucp") -> String {
        let hex = String(fnv1a64(folder), radix: 16)
        return "/tmp/\(prefix)-\(String(repeating: "0", count: 16 - hex.count) + hex).sock"
    }

    public static func fnv1a64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return h
    }

    public static func fits(_ path: String) -> Bool { path.utf8.count <= maxBytes }
}
