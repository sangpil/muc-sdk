import Foundation
import LaunchTrace
import Testing

// 창 열기 실측 훅 — 꺼져 있을 때(`MUC_OPEN_TRACE` 없음 · 시험의 기본) 재는 손은 몸을 그대로 돌리고 아무것도 남기지 않는다.
// 켜진 때의 출력(표준 오류 한 줄씩)은 사람이 읽는 실측이라 시험하지 않는다 — 시험은 「꺼짐 = 투명」만 지킨다(화면 코드 · 도구가 늘 부르는 자리다).

private struct Boom: Error {}

@Suite struct OpenTraceTests {
    @Test func offByDefault() {
        #if DEBUG
        #expect(ProcessInfo.processInfo.environment["MUC_OPEN_TRACE"] == "1" || !OpenTrace.on)
        #endif
    }

    /// 꺼짐 — `span` 은 몸의 값을 그대로 돌려주고 던짐도 그대로 넘긴다 · 표지 · 세기는 부르는 자리에서 아무 일도 하지 않는다.
    @Test func spanIsTransparent() throws {
        #expect(OpenTrace.span("값", { 41 + 1 }) == 42)
        #expect(throws: Boom.self) { try OpenTrace.span("던짐", { throw Boom() }) }
        OpenTrace.mark("표지")
        OpenTrace.first("열쇠", "첫 표지")
        OpenTrace.count("세기")
        OpenTrace.arm()
    }

    /// 표지 글은 자동 클로저다 — 꺼져 있으면 글을 셈하지 않는다(계측이 그리기를 세우지 않게).
    @Test func labelsAreNotEvaluatedWhenOff() {
        guard ProcessInfo.processInfo.environment["MUC_OPEN_TRACE"] != "1" else { return }
        var evaluated = false
        func label() -> String { evaluated = true; return "x" }
        OpenTrace.mark(label())
        OpenTrace.first("k", label())
        _ = OpenTrace.span(label(), { 0 })
        #expect(!evaluated)
    }
}
