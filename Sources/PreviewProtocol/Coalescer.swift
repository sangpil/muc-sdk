import Foundation

// 최신값 우선(coalescing) — 조절판을 끄는 동안 값이 60–120 Hz 로 쏟아진다. 호스트가 한 장을 그리는 동안 쌓인 값은
// **버리고 칸마다 마지막 값만** 다음 patch 하나로 보낸다. 처리량이 아니라 **뒤처짐**(입력 시각 → 그 값(또는 더 새 값)이
// 반영된 프레임 도착)을 줄이는 정책이다 — 줄을 세우면 손을 멈춘 뒤에도 밀린 값이 차례로 그려져 화면이 손보다 늦게 따라온다.
//
// 진행 중 요청 한도(`window`)는 1 이 기본이다. 2 로 겹쳐 보내도 뒤처짐이 줄지 않는다 — 호스트는 한 번에 한 장만 그리고
// 그사이 온 patch 는 우편함이 합친다.
// 스레드 안전은 쓰는 쪽이 진다(클라이언트가 락 하나로 감싼다).

public struct Coalescer<Key: Hashable, Value> {
    public struct Batch {
        /// 이 묶음의 입력 번호 = 묶음에 든 가장 새 입력의 번호
        public let seq: UInt64
        /// 칸 하나에 값 하나 — 처음 들어온 차례대로
        public let items: [(key: Key, value: Value)]
    }

    public let window: Int
    public private(set) var inFlight = 0
    /// 보내지 않고 덮어써서 버린 입력 수(통계)
    public private(set) var dropped = 0
    private var order: [Key] = []
    private var pending: [Key: Value] = [:]
    private var pendingSeq: UInt64 = 0

    public init(window: Int = 1) { precondition(window >= 1); self.window = window }

    public var hasPending: Bool { !order.isEmpty }

    /// 새 입력. 지금 보낼 수 있으면 묶음을 돌려준다(그러면 진행 중 +1) · 아니면 쌓아 두고 nil.
    public mutating func submit(_ key: Key, _ value: Value, seq: UInt64) -> Batch? {
        if pending.updateValue(value, forKey: key) == nil { order.append(key) } else { dropped += 1 }
        pendingSeq = max(pendingSeq, seq)
        return inFlight < window ? take() : nil
    }

    /// 쌓인 값을 버린다(진행 중은 그대로) — 값 통째(`render`)를 보낼 때: 그 render 가 모든 칸을 싣으니 쌓인 옛 값이 뒤따라 덮으면 안 된다.
    public mutating func discardPending() {
        order.removeAll(keepingCapacity: true); pending.removeAll(keepingCapacity: true)
    }

    /// 진행 중 요청 하나가 끝났다(프레임 · ack 도착). 쌓인 값이 있으면 다음 묶음.
    public mutating func completed() -> Batch? {
        inFlight = max(0, inFlight - 1)
        return hasPending && inFlight < window ? take() : nil
    }

    private mutating func take() -> Batch {
        let items = order.map { (key: $0, value: pending[$0]!) }
        order.removeAll(keepingCapacity: true); pending.removeAll(keepingCapacity: true)
        inFlight += 1
        return Batch(seq: pendingSeq, items: items)
    }
}
