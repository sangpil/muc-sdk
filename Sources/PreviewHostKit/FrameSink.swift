#if os(macOS)
import Foundation
import LaunchTrace
import PreviewProtocol
import ScreenMarks
import SwiftUI

// 프레임 수집 — 프로젝트의 화면 코드가 `.snapID`(SDK `ScreenMarks`)로 올린 앵커를 뿌리에서 모아 요소 경계(`SnapFrame`)로 낸다.
// 호스트가 프레임 머리(`FrameHeader.snapFrames`)에 싣고 · 찍기가 `frames.json` 으로 쓴다. 앵커는 트레이트 `ActiveMarks` 가 켜진 빌드에서만 찬다.
//
// 프리퍼런스는 `ImageRenderer` 안에서도 돈다. 수집을 `onPreferenceChange`(갱신 루프가 있어야 옴)가 아니라
// `backgroundPreferenceValue` 안의 GeometryReader 본문(레이아웃 중 동기 호출)에서 하기 때문이다.

/// 프레임 수집함 — 레이아웃 스레드에서 쓰고 호출자가 읽는다(위 → 왼쪽 → id 차례).
public final class FrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [SnapFrame] = []
    public init() {}
    public func set(_ frames: [SnapFrame]) { lock.lock(); store = frames; lock.unlock() }
    public var frames: [SnapFrame] { lock.lock(); defer { lock.unlock() }; return store.sorted { ($0.y, $0.x, $0.id) < ($1.y, $1.x, $1.id) } }
}

private struct FrameCollector: ViewModifier {
    let sink: FrameSink
    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(SnapPreferenceKey.self) { prefs in
            GeometryReader { geo -> Color in
                OpenTrace.count("프레임 수집(레이아웃 패스)")
                sink.set(prefs.map { SnapFrame(id: $0.key, rect: geo[$0.value]) })
                return Color.clear
            }
        }
    }
}

extension View {
    /// 뿌리에 한 번 — 이 뷰 좌표계 기준 프레임을 `sink` 에 쓴다.
    public func collectFrames(into sink: FrameSink) -> some View { modifier(FrameCollector(sink: sink)) }
}
#endif
