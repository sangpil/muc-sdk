import Foundation

// 형식 업그레이드 사슬의 **꼴** — 옛 판 문서를 한 판씩 올리는 스텝(`UpgradeStep`)과 형식마다 그 스텝을 잇는 사슬(`UpgradeChain`).
// SDK 에는 꼴만 든다 — 스텝의 몸(형식마다 판 간격 하나에 무엇을 하는가)은 엔진 쪽 별도 타깃이 갖는다(출시 앱은 그 타깃을 물지 않는다).
// 판을 올리는 차례와 판마다의 뜻은 형식을 읽고 쓰는 엔진(빌더)이 갖는다 — SDK 는 사슬의 꼴과 아래 규칙만 든다.

/// 스텝 하나가 문서에 하는 일의 갈래.
public enum UpgradeEffect: Hashable, Sendable {
    /// 디코더가 옛 판의 꼴을 그대로 받는다 — 칸이 더해졌을 뿐이고 없는 칸은 뜻이 같다.
    case identity
    /// 칸은 남고 값이 바뀐다(번호를 찍는다 · 셈을 채운다 …).
    case valueChange
    /// 새 판이 더 읽지 않는 칸이 있다 — 잃는 칸을 이름 댄다.
    case lossy(fields: [String])

    /// 이 갈래가 잃는 칸(잃음이 아니면 빈 목록).
    public var lostFields: [String] {
        if case .lossy(let fields) = self { return fields }
        return []
    }

    /// 사람 말 낱말 — 「항등」 · 「값 바꿈」 · 「잃음」.
    public var word: String {
        switch self {
        case .identity: "항등"
        case .valueChange: "값 바꿈"
        case .lossy: "잃음"
        }
    }

    /// 기계 낱말 — `identity` · `valueChange` · `lossy`(`--json`).
    public var key: String {
        switch self {
        case .identity: "identity"
        case .valueChange: "valueChange"
        case .lossy: "lossy"
        }
    }
}

/// 한 판(`from`) → 다음 판(`from + 1`) 스텝 하나. **순수** — 파일 · 시계 · 환경을 보지 않는다(같은 입력 = 같은 출력).
/// 판 칸은 스텝이 찍지 않는다 — 사슬이 스텝마다 찍는다(`UpgradeChain.upgrade`).
public protocol UpgradeStep: Sendable {
    /// 이 스텝이 받는 판. 내는 판은 `from + 1`.
    var from: Int { get }
    /// 이 간격의 갈래.
    var effect: UpgradeEffect { get }
    /// 사람 말 요약 한 줄 — 다음 판이 무엇을 더했고 이 스텝이 무엇을 하는가.
    var summary: String { get }
    /// 문서 한 장(`from` 판의 꼴) → 다음 판의 꼴.
    func apply(_ document: JSONValue) throws -> JSONValue
    /// 이 문서가 실제로 잃는 칸 — 갈래가 이름 댄 칸 가운데 이 문서에 내용이 든 것. 기본은 맨 위의 칸을 본다.
    func lostFields(in document: JSONValue) -> [String]
}

extension UpgradeStep {
    /// 이 스텝이 내는 판.
    public var to: Int { from + 1 }

    public func lostFields(in document: JSONValue) -> [String] {
        guard case .object(let top) = document else { return [] }
        return effect.lostFields.filter { top[$0]?.holdsSomething == true }
    }
}

extension JSONValue {
    /// 칸에 내용이 들었나 — 널 · 빈 배열 · 빈 글자 · 빈 객체는 든 것이 아니다(옛 판이 빈 칸을 늘 쓰던 꼴).
    public var holdsSomething: Bool {
        switch self {
        case .null: false
        case .array(let a): !a.isEmpty
        case .string(let s): !s.isEmpty
        case .object(let o): !o.isEmpty
        case .bool, .number: true
        }
    }
}

/// 형식 하나의 사슬 — 가장 옛 읽는 판(`oldest`)에서 읽는 최신 판(`newest`)까지 판 간격마다 스텝이 **정확히 하나**.
public struct UpgradeChain: Sendable {
    /// 판 칸의 이름(문서 맨 위의 정수 칸 — 보통 `version` · 매니페스트는 `schema`).
    public let stampKey: String
    /// 이 엔진이 아직 읽는 가장 옛 판.
    public let oldest: Int
    /// 이 엔진이 읽는 가장 새 판(형식 판 상수를 읽은 값).
    public let newest: Int
    /// 그 형식의 쓰는 손이 찍는 가장 낮은 판(씬 `SceneFormat.lowestWritten` · 데이터 삶 파일 `IsoDataFormat.life` …) — 업그레이드가 쓰는 판의 바닥.
    /// 업그레이드는 최신까지 쓰지 않는다 — 판이 뒤진 빌더(다른 Mac 의 배포본)가 그 파일을 계속 열게.
    public let writeFloor: Int
    /// 판 간격마다 스텝 하나(차례는 상관없다 — `from` 으로 찾는다).
    public let steps: [any UpgradeStep]

    public init(stampKey: String = "version", oldest: Int, newest: Int, writeFloor: Int, steps: [any UpgradeStep]) {
        self.stampKey = stampKey; self.oldest = oldest; self.newest = newest; self.writeFloor = writeFloor; self.steps = steps
    }

    /// 불변식 위반 — 빈 간격 · 겹친 간격 · 범위 밖 스텝 · 판 차례(옛 판 > 최신 판) · 쓰는 바닥이 범위 밖. 비었으면 선다.
    public var violations: [String] {
        var out: [String] = []
        if oldest > newest { out.append("가장 옛 판 \(oldest) 이 최신 판 \(newest) 보다 높다") }
        if writeFloor < oldest || writeFloor > newest { out.append("쓰는 바닥 판 \(writeFloor) 이 사슬 범위(\(oldest)…\(newest)) 밖이다") }
        let froms = steps.map(\.from)
        for v in Set(froms).sorted() where froms.filter({ $0 == v }).count > 1 {
            out.append("\(v) → \(v + 1) 간격에 스텝이 둘 이상이다")
        }
        for v in Set(froms).sorted() where v < oldest || v >= newest {
            out.append("\(v) → \(v + 1) 스텝이 사슬 범위(\(oldest)…\(newest)) 밖이다")
        }
        if oldest <= newest {
            for v in oldest..<newest where !froms.contains(v) { out.append("\(v) → \(v + 1) 간격에 스텝이 없다") }
        }
        return out
    }

    /// 판 `version` 에서 최신까지 밟을 스텝 — 차례대로. 최신이면 빈 목록.
    public func path(from version: Int) throws -> [any UpgradeStep] {
        guard version >= oldest else { throw UpgradeError.belowOldest(version: version, oldest: oldest) }
        guard version <= newest else { throw UpgradeError.aboveNewest(version: version, newest: newest) }
        return try (version..<newest).map { v in
            guard let s = steps.first(where: { $0.from == v }) else { throw UpgradeError.missingStep(from: v) }
            return s
        }
    }

    /// 문서 한 장을 사슬로 올린다 — 판을 읽고 최신까지의 스텝을 차례로 돌며(스텝마다 판 칸을 찍는다) 잃는 칸을 재고, **쓸 판**의 꼴을 낸다.
    /// 순수(디스크를 보지 않는다).
    ///
    /// - **올릴 것**(`needsUpgrade`) = 이 문서가 실제로 잃는 칸이 있다 ∨ 길에 값 바꿈 스텝이 있다. 항등만 · 내용 없는 잃음만 밟는 문서는
    ///   판 번호만 뒤진 것이다 — 쓸 판 = 지금 판 · 문서 그대로.
    /// - **쓸 판**(`to`) = max(길의 마지막 값 바꿈 · 잃음 스텝이 내는 판, `writeFloor`) — 최신이 아니다. 그 위 간격은 항등뿐이라 잃는 것이 없다.
    /// - **잃음 스텝의 가드** — 잃음 스텝의 몸이 낸 문서가 그 스텝이 이름 댄 칸을 아직 (내용째) 들고 있으면 `UpgradeError.lossyStepKept` —
    ///   사슬은 잃는 칸이 남은 문서를 「올린 결과」로 내지 않는다(판 칸만 올라 디코더의 알림이 꺼진 채 조용히 잃는 꼴).
    public func upgrade(_ document: JSONValue) throws -> UpgradeOutcome {
        guard case .object(let top) = document else { throw UpgradeError.notObject }
        guard case .number(let raw)? = top[stampKey], let version = Int(exactly: raw) else {
            throw UpgradeError.unstamped(key: stampKey)
        }
        var doc = document
        var lost: [String] = []
        let walked = try path(from: version)
        var stages: [JSONValue] = [document]   // stages[i] = 판 version + i 의 꼴
        for step in walked {
            lost += step.lostFields(in: doc).filter { !lost.contains($0) }
            doc = try step.apply(doc)
            if case .lossy = step.effect {
                let kept = step.lostFields(in: doc)
                if !kept.isEmpty { throw UpgradeError.lossyStepKept(from: step.from, fields: kept) }
            }
            guard case .object(var next) = doc else { throw UpgradeError.notObject }
            next[stampKey] = .number(Double(step.to))
            doc = .object(next)
            stages.append(doc)
        }
        let needs = !lost.isEmpty || walked.contains { $0.effect == .valueChange }
        let target = needs ? max(walked.last { $0.effect != .identity }?.to ?? version, writeFloor) : version
        return UpgradeOutcome(document: stages[target - version], from: version, to: target, newest: walked.last?.to ?? version,
                              steps: Array(walked.prefix(target - version)), lost: lost, needsUpgrade: needs)
    }
}

/// 사슬 한 번 돈 결과.
public struct UpgradeOutcome: Sendable {
    /// 쓸 판의 문서(판 칸 = `to`) — 올릴 것이 아니면 받은 문서 그대로.
    public let document: JSONValue
    public let from: Int
    /// 쓸 판 — 올릴 것이면 max(마지막 값 바꿈 · 잃음 스텝이 내는 판, 쓰는 바닥) · 아니면 `from`.
    public let to: Int
    /// 사슬의 최신 — 잃는 칸은 여기까지의 길로 쟀다(`to` 위는 항등뿐).
    public let newest: Int
    /// `from` → `to` 사이 밟은 스텝 — 차례대로(올릴 것이 아니면 빈 목록).
    public let steps: [any UpgradeStep]
    /// 이 문서가 실제로 잃는 칸 — 최신까지의 길에서 스텝 차례 · 겹침 없이(스텝마다 그 스텝이 받은 문서로 잰다). 잃음 스텝의 몸이 걷은 칸이다.
    public let lost: [String]
    /// 올릴 것인가 — 실제로 잃는 칸이 있다 ∨ 길에 값 바꿈 스텝이 있다(디코더가 읽으며 값을 바꾸거나 칸을 버리는 문서).
    public let needsUpgrade: Bool
}

public enum UpgradeError: Error, Equatable, CustomStringConvertible {
    /// 문서 맨 위가 JSON 객체가 아니다.
    case notObject
    /// 판 칸이 없거나 정수가 아니다.
    case unstamped(key: String)
    /// 이 엔진이 더 읽지 않는 옛 판 — 사슬 밖.
    case belowOldest(version: Int, oldest: Int)
    /// 이 엔진보다 새 판 — 올릴 수 없다(읽기 전용).
    case aboveNewest(version: Int, newest: Int)
    /// 사슬에 그 간격의 스텝이 없다(불변식 위반 — 시험이 먼저 잡는다).
    case missingStep(from: Int)
    /// 잃음 스텝의 몸이 그 스텝이 이름 댄 칸을 걷지 않았다 — 잃는 칸이 남은 문서를 올린 결과로 내지 않는다.
    case lossyStepKept(from: Int, fields: [String])

    public var description: String {
        switch self {
        case .notObject: "문서 맨 위가 JSON 객체가 아니다"
        case .unstamped(let key): "판 칸(\(key))이 없거나 정수가 아니다"
        case .belowOldest(let v, let oldest): "판 \(v) 은 이 엔진이 더 읽지 않는 옛 판이다(가장 옛 판 \(oldest)) — 사슬 밖"
        case .aboveNewest(let v, let newest): "판 \(v) 은 이 엔진(\(newest) 까지)보다 새롭다 — 올릴 수 없다(읽기 전용)"
        case .missingStep(let from): "\(from) → \(from + 1) 간격에 스텝이 없다"
        case .lossyStepKept(let from, let fields):
            "\(from) → \(from + 1) 잃음 스텝이 \(fields.joined(separator: " · ")) 을 걷지 않았다 — 잃는 칸이 남은 문서는 올린 결과가 아니다"
        }
    }
}
