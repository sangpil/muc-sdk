// 배선 고르기 — **규칙의 한 벌**. 화면의 안(`*.design.json`)과 씬(`*.isoscene`)을 무엇으로 여는가를 여기 하나가 정한다 —
// 앱(프로젝트의 셸 · 번들 씬)과 엔진의 도구(안 창의 기본 안 · 씬 다리)가 같은 답을 내야 해서 SDK 에 산다.
// 파일은 읽지 않는다 — 배선 칸의 값(`graph.json` `wired[screen]`)과 후보는 부르는 쪽이 읽어 넘긴다(안의 머리는 `DesignFile.head`).

/// 배선 → 확정 → 가장 최근(안) ⟂ 배선 → 이름 순 첫(씬).
public enum IAWiring {
    /// 안 하나의 머리 — 확정 여부와 만든 때(비교만 하면 되므로 꼴은 부르는 쪽 것 · `Date` 등).
    public struct Head<Stamp: Comparable> {
        public let name: String
        public let confirmed: Bool
        public let createdAt: Stamp
        public init(name: String, confirmed: Bool, createdAt: Stamp) { self.name = name; self.confirmed = confirmed; self.createdAt = createdAt }
    }

    /// 첫 단 — 배선 칸의 이름이 후보(그 파일이 있다)이면 그 이름, 아니면 nil.
    public static func wired(_ name: String?, isCandidate: (String) -> Bool) -> String? {
        name.flatMap { isCandidate($0) ? $0 : nil }
    }

    /// 배선을 뺀 안 규칙 — 확정(후보 차례의 첫) → 가장 최근(만든 때 · 같으면 이름이 뒤인 것). 후보가 없으면 nil.
    public static func rule<Stamp>(_ heads: [Head<Stamp>]) -> String? {
        if let c = heads.first(where: \.confirmed) { return c.name }
        return heads.max { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }?.name
    }

    /// 화면의 안 — 배선(그 안이 있을 때) → 확정 → 가장 최근. `heads` 는 배선이 비었을 때만 부른다(안 파일을 다 읽지 않게).
    public static func design<Stamp>(wired name: String?, names: [String], heads: () -> [Head<Stamp>]) -> String? {
        wired(name, isCandidate: names.contains) ?? rule(heads())
    }

    /// 씬 — 배선(그 씬이 있을 때) → 이름 순 첫. 씬에는 확정 · 만든 때가 없어 둘째 단이 이름 순이다. `names` 는 이름 순.
    public static func scene(wired name: String?, among names: [String]) -> String? {
        wired(name, isCandidate: names.contains) ?? names.first
    }
}
