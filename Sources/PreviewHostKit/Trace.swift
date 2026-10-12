#if os(macOS)
import Foundation
import PreviewProtocol

/// 호스트의 기동 · 첫 프레임 구간 추적(창 열기 실측 `LaunchTrace.OpenTrace` 와 쓰임이 다르다 — 이것은 미리보기 호스트 프로세스의 표지) — `PREVIEW_TRACE=1` 일 때만 stderr 에 `PreviewClock` ms 를 찍는다(엔진의 띄움 시각과 같은 시계).
public enum HostTrace {
    static let on = ProcessInfo.processInfo.environment["PREVIEW_TRACE"] == "1"
    public static func mark(_ what: @autoclosure () -> String) {
        guard on else { return }
        FileHandle.standardError.write(Data(String(format: "[trace] %.3f %@\n", Double(PreviewClock.now()) / 1e6, what()).utf8))
    }
}
#endif
