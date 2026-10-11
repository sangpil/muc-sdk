import Testing
import PreviewProtocol

// 최신값 우선 — 진행 중이면 쌓고(칸마다 마지막 값만), 답이 오면 그 묶음 하나를 낸다.

@Suite struct CoalescerTests {
    @Test func sendsImmediatelyWhenIdle() {
        var c = Coalescer<String, Int>()
        let b = c.submit("gap", 1, seq: 1)
        #expect(b?.seq == 1 && b?.items.map(\.value) == [1])
        #expect(c.inFlight == 1)
    }

    @Test func keepsOnlyLatestWhileInFlight() {
        var c = Coalescer<String, Int>()
        _ = c.submit("gap", 1, seq: 1)
        #expect(c.submit("gap", 2, seq: 2) == nil)
        #expect(c.submit("gap", 3, seq: 3) == nil)
        #expect(c.submit("color", 9, seq: 4) == nil)
        #expect(c.dropped == 1)
        let next = c.completed()
        #expect(next?.seq == 4)
        #expect(next?.items.map(\.key) == ["gap", "color"])
        #expect(next?.items.map(\.value) == [3, 9])
        #expect(c.completed() == nil && c.inFlight == 0)
    }

    /// 값 통째를 보내면 쌓인 옛 값은 버린다 — 진행 중은 그대로 · 답이 와도 따라 나갈 묶음이 없다.
    @Test func discardPendingDropsOnlyQueuedValues() {
        var c = Coalescer<String, Int>()
        _ = c.submit("gap", 1, seq: 1)
        #expect(c.submit("gap", 2, seq: 2) == nil)
        c.discardPending()
        #expect(!c.hasPending && c.inFlight == 1)
        #expect(c.completed() == nil && c.inFlight == 0)
        #expect(c.submit("gap", 3, seq: 5)?.seq == 5, "버린 뒤의 새 값은 곧장 나간다")
    }

    @Test func windowOfTwoPipelines() {
        var c = Coalescer<String, Int>(window: 2)
        #expect(c.submit("a", 1, seq: 1) != nil)
        #expect(c.submit("a", 2, seq: 2) != nil)
        #expect(c.submit("a", 3, seq: 3) == nil)
        #expect(c.completed()?.seq == 3)
    }
}
