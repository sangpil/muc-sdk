import CoreGraphics
import ScreenMarks
import SwiftUI
import Testing

// 화면 요소 표식 — 이 모듈이 약속하는 것만 잰다: 키 · 탭 환경값의 꼴은 트레이트와 무관하게 늘 서고 비어 있다 ·
// 표식이 꺼진 빌드(트레이트 `ActiveMarks` 없음 — 시험의 기본)에서 `.snapID` 는 뷰를 그대로 돌려주고 경계를 올리지 않는다(값이 0).
// 켜진 빌드의 경계 수집은 표식을 단 화면 코드가 있는 쪽(프로젝트 · 엔진의 도구)의 시험이 잰다.

/// 렌더 중에 읽은 표식 수 — 레이아웃 중 동기 호출로 찬다.
private final class Seen: @unchecked Sendable {
    var counts: [Int] = []
}

@Suite struct ScreenMarksTests {
    /// 키의 꼴 — 기본값은 빈 사전 · 빈 값끼리 합쳐도 비어 있다.
    @Test func preferenceKeyStartsEmpty() {
        #expect(SnapPreferenceKey.defaultValue.isEmpty)
        var value = SnapPreferenceKey.defaultValue
        SnapPreferenceKey.reduce(value: &value, nextValue: { [:] })
        #expect(value.isEmpty)
    }

    /// 탭 환경값의 꼴 — 기본은 받는 손 없음(앱의 손을 가리지 않는다) · 걸면 그 손을 그대로 돌려준다.
    @Test @MainActor func tapEnvironmentRoundTrips() {
        #expect(SnapTapKey.defaultValue == nil)
        var env = EnvironmentValues()
        #expect(env.snapTap == nil)
        let seen = Seen()
        env.snapTap = { _ in seen.counts.append(1) }
        env.snapTap?("home.hero")
        #expect(seen.counts == [1])
    }

    #if !ACTIVE_MARKS
    /// 빈 모디파이어 — 꺼진 빌드에서 `.snapID` 는 받은 뷰를 그 타입 그대로 돌려준다.
    @Test @MainActor func markIsIdentityWhenOff() {
        let marked = Text("x").snapID("home.hero")
        #expect(marked is Text)
    }

    /// 값이 0 — 꺼진 빌드에서는 표식을 달아도 경계가 올라오지 않는다(렌더 안에서 키를 읽어도 빈 사전).
    @Test @MainActor func markRaisesNoBoundsWhenOff() {
        let seen = Seen()
        let view = Color.clear.frame(width: 10, height: 10).snapID("home.hero")
            .backgroundPreferenceValue(SnapPreferenceKey.self) { marks in
                GeometryReader { _ in
                    let _ = seen.counts.append(marks.count)
                    Color.clear
                }
            }
        #expect(ImageRenderer(content: view).cgImage != nil)
        #expect(!seen.counts.isEmpty)
        #expect(seen.counts.allSatisfy { $0 == 0 })
    }
    #endif
}
