import SwiftUI

// 요소 식별자 — `.snapID("home.hero")` 를 붙인 요소를 엔진의 도구가 집어낼 수 있게 하는 표식. 이름은 요소 id 다(의견 · 구성요소 id 와 같은 낱말).
//
// **이 모디파이어는 제품 화면에 남는다**(뷰 코드에 도구용 갈래를 파지 않는다). 대신 하는 일은 빌드 플래그로 갈린다:
//   · `ACTIVE_MARKS` 켜짐 — 앵커 프리퍼런스(`SnapPreferenceKey`)로 경계를 올리고 탭을 받는다(`snapTap`) — 도구 빌드.
//   · 꺼짐(앱 빌드) — `content` 를 **그대로** 돌려준다. 프리퍼런스도 제스처도 없다 = 값이 0이다.
//
// 플래그 규칙: 제품 타깃을 두 벌로 컴파일할 수 없으니 이 패키지의 트레이트 `ActiveMarks` 가 켜진 그래프에서만 선다(macOS ∧ 트레이트 ·
// `Package.swift`). 트레이트를 넘기는 것은 프로젝트 패키지의 도구 트레이트다 — 앱 빌드는 넘기지 않고, iOS 는 플랫폼 조건으로 늘 꺼진다.
//
// 모아 담기 · 강조 · 의견 오버레이는 엔진의 도구 쪽이 이 키를 읽어 그린다. 키 · 탭 환경값(계약의 **꼴**)은 플래그와 무관하게 늘 선다 —
// 읽는 쪽(엔진의 도구 패키지)이 플래그 없이 컴파일되게. 꺼진 빌드에서는 아무도 키에 쓰지 않으므로 값은 늘 비어 있다(갈리는 것은 표식의 **몸**뿐).

public struct SnapPreferenceKey: PreferenceKey {
    public static let defaultValue: [String: Anchor<CGRect>] = [:]
    public static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 요소 탭 → 식별자(도구의 화면 창이 조절판 스크롤 · 강조에 쓴다). 없으면 탭은 아무것도 안 한다.
public struct SnapTapKey: EnvironmentKey {
    public static let defaultValue: (@MainActor (String) -> Void)? = nil
}
extension EnvironmentValues {
    public var snapTap: (@MainActor (String) -> Void)? {
        get { self[SnapTapKey.self] }
        set { self[SnapTapKey.self] = newValue }
    }
}

#if ACTIVE_MARKS
private struct SnapIDModifier: ViewModifier {
    let id: String
    @Environment(\.snapTap) private var tap
    func body(content: Content) -> some View {
        // transform 이어야 한다 — `anchorPreference` 는 자식의 값을 **덮어써서** 뿌리 두 개만 남는다(자식의 표지가 사라진다).
        let marked = content.transformAnchorPreference(key: SnapPreferenceKey.self, value: .bounds) { $0[id] = $1 }
        // 탭은 받는 손(`snapTap`)이 있을 때만 건다 — 없는데도 걸면 앱의 손(펼침 `onTapGesture`)이 가려진다(미리보기 호스트의 자기 창 · 만지며 보기)
        if let tap {
            marked.contentShape(Rectangle()).onTapGesture { tap(id) }
        } else {
            marked
        }
    }
}
#endif

extension View {
    /// 요소 표식 — 도구 빌드에서만 값이 있다(앱 빌드에서는 이 줄이 통째로 사라진다).
    public func snapID(_ id: String) -> some View {
        #if ACTIVE_MARKS
        return modifier(SnapIDModifier(id: id))
        #else
        return self
        #endif
    }
}
