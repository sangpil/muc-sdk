import Foundation

// 토큰 정본(`tokens.json` 의 `semantic`)의 두 곁 칸 — 씬 칸 → 씬 역할 규칙(`SceneSlotNaming`)과 색 역할의 묶음(`ColorRoleGroups`).
// 규칙은 한 줄이고 예외 · 묶음은 **데이터**(정본 곁 칸)다 — 엔진의 씬 해소기 · 토큰 창이 프로젝트의 코드 없이 같은 답을 낸다.
// 정본의 꼴은 생성기가 잰다(`--check` — 프로젝트의 몫).

/// 씬 칸 이름 → 정본 씬 역할 — 규칙: **`scene-` + kebab(칸)**(`lawn` → `scene-lawn` · `fenceTall` → `scene-fence-tall`).
/// 규칙을 벗어나는 칸은 정본의 별칭 칸 `semantic.$sceneSlots`(칸 → 역할 이름)가 든다(`hedgeMark` → `scene-hedge-grid` 처럼).
/// 칸 = 렌더 코어 잉크 칸의 파일 철자 + 프로젝트가 더한 칸(예: 바탕 · 눈금). 렌더 코어의 씬 색 해소기(칸 → 기본 색)에 답하는 쪽이 쓴다.
public enum SceneSlotNaming {
    /// 역할 이름의 앞머리.
    public static let prefix = "scene-"
    /// 칸 하나의 역할 — 별칭이 먼저 · 없으면 규칙.
    public static func tokenName(forSlot slot: String, aliases: [String: String] = [:]) -> String {
        aliases[slot] ?? prefix + ColorRoleNaming.kebab(slot)
    }
    /// 정본의 별칭 칸(`semantic.$sceneSlots` — `$` 로 시작하는 키는 설명이라 뺀다). 칸이 없으면 빈 표.
    public static func aliases(semantic: [String: Any]) -> [String: String] {
        guard let raw = semantic["$sceneSlots"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw where !k.hasPrefix("$") { if let s = v as? String { out[k] = s } }
        return out
    }
}

/// 색 역할의 묶음(토큰 창 · 색 고르기의 절과 차례) — 정본 곁 칸 `semantic.$group`:
/// `$order`(묶음 이름의 차례) · `$fallback`(어디에도 들지 않는 역할의 묶음) · 역할 이름 → 묶음 이름(끝이 `*` 인 키는 앞머리 — `chip-*`).
/// 고르는 차례: 이름이 같은 키 → 가장 긴 앞머리 → `$fallback`.
public struct ColorRoleGroups: Equatable, Sendable {
    public var order: [String]
    public var fallback: String?
    public var exact: [String: String]
    /// 앞머리 → 묶음(가장 긴 것이 먼저).
    public var prefixes: [(prefix: String, group: String)]

    public init(order: [String] = [], fallback: String? = nil, exact: [String: String] = [:], prefixes: [(prefix: String, group: String)] = []) {
        self.order = order; self.fallback = fallback; self.exact = exact
        self.prefixes = prefixes.sorted { ($0.prefix.count, $1.prefix) > ($1.prefix.count, $0.prefix) }
    }

    /// 칸이 없는 정본 — 묶음 없음(`group(of:)` 이 늘 nil).
    public static let none = ColorRoleGroups()

    /// 정본의 `semantic` 에서. 칸이 없으면 `none`.
    public init(semantic: [String: Any]) {
        guard let raw = semantic["$group"] as? [String: Any] else { self = .none; return }
        var exact: [String: String] = [:], prefixes: [(String, String)] = []
        for (k, v) in raw where !k.hasPrefix("$") {
            guard let g = v as? String else { continue }
            if k.hasSuffix("*") { prefixes.append((String(k.dropLast()), g)) } else { exact[k] = g }
        }
        self.init(order: raw["$order"] as? [String] ?? [], fallback: raw["$fallback"] as? String, exact: exact,
                  prefixes: prefixes.map { (prefix: $0.0, group: $0.1) })
    }

    /// 역할 하나의 묶음 — 없으면 nil(칸이 없는 정본 · `$fallback` 이 없고 아무 키에도 안 든다).
    public func group(of role: String) -> String? {
        exact[role] ?? prefixes.first { role.hasPrefix($0.prefix) }?.group ?? fallback
    }

    /// 역할들을 묶음 차례로 — 비지 않은 묶음만 · `$order` 밖 묶음은 뒤에 이름 차례로 · 묶음이 없는 역할은 빠진다.
    public func grouped(_ roles: [String]) -> [(group: String, roles: [String])] {
        let named = roles.compactMap { r in group(of: r).map { (r, $0) } }
        let extra = Set(named.map(\.1)).subtracting(order).sorted()
        return (order + extra).compactMap { g in
            let xs = named.filter { $0.1 == g }.map(\.0)
            return xs.isEmpty ? nil : (g, xs)
        }
    }

    public static func == (a: ColorRoleGroups, b: ColorRoleGroups) -> Bool {
        a.order == b.order && a.fallback == b.fallback && a.exact == b.exact
            && a.prefixes.map(\.prefix) == b.prefixes.map(\.prefix) && a.prefixes.map(\.group) == b.prefixes.map(\.group)
    }
}
