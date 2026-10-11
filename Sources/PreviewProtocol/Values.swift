import Foundation

// 프로토콜의 작은 값들 — 프레임 형식 · 요소 경계 · 시계 · 소켓 경로. 조절판 값 한 조각은 SDK 의 JSON 값(`ProjectFormat.JSONValue`)이다.

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
