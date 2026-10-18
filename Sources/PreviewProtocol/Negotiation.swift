import Foundation
import ProjectFormat

// 판 맞대기 — 엔진 ⟂ 미리보기 호스트가 서로 다른 SDK 로 빌드돼도(다른 Mac 의 배포본 빌더 ⟂ 그 Mac 이 받은 저장소 HEAD 로 지은 호스트) 말이 어긋나지 않게.
// 정본 `Docs/SDK.md` §5(판 규칙 · 맞대기).
//
//   판     : 메시지 꼴(종류 · 칸 키 · 칸의 뜻 · 선택 칸의 덧붙임)이 바뀌면 판을 올린다(`PreviewProtocolVersion.current`). 꼴의 지문은 시험이 판마다 한 줄 얼려 둔다
//            (`PreviewProtocolTests/protocol-shapes.txt` — 꼴이 바뀌었는데 판이 그대로면 빨강).
//   판정   : **엔진이 판정자**다. 호스트가 먼저 hello 를 보내고, 엔진은 그 첫 줄에서 몸을 풀기 전에 판(`protocolVersion`)만 읽어(`FormatStamp`) 가른다 —
//            같은 판(N) · 바닥(`PreviewProtocolVersion.oldest`)부터의 옛 판(그 판의 말 `ProtocolDialect` — 스텝을 이은 사슬 — 로 읽고 쓴다)은 받고,
//            그 밖(N+1 이상 · 바닥 아래)은 연결을 닫고 사람 말 한 줄(`ProtocolMismatch`).
//   호스트 : 늘 제 판의 꼴로 말한다(엔진이 호스트의 판에 맞춰 말한다). 엔진 hello 의 판이 제 판보다 옛것이면 거절하고 · 같거나 새것이면 받는다(`hostAccepts`).
//   불변   : hello 의 `type` · `protocolVersion` 두 칸은 판이 올라도 이름 · 자리(줄의 맨 위 객체 · 정수)가 그대로다 — 판 읽개가 이 둘만 본다.
//   기본값 : 판을 공개 손의 기본 인자로 두지 않는다(`Hello.protocolVersion` · `hostAccepts(host:)` 는 필수 인자). 비탄력 모듈의 공개 손의 기본 인자는 부르는 쪽
//            목적 코드에 들어가고 부르는 파일의 소스엔 판의 이름이 없어 증분 빌드의 의존에 안 잡힌다 — 판을 올려도 그 파일은 다시 지어지지 않고 옛 판을 지닌다
//            (실연: 기본 인자로 hello 를 세우던 파일은 판 1 · 판을 직접 부른 파일은 판 2 — 한 실행물에 두 판). 판을 부르는 쪽은 이름을 소스에 적는다.

/// 프로토콜 판 — **한 자리**. 메시지 꼴(선택 칸 포함)이 바뀌면 올린다 — 올리는 변경은 꼴 지문 한 줄과 한 판 사이의 스텝(`ProtocolDialect.Step`)을 함께 더한다.
public enum PreviewProtocolVersion {
    /// 판 5 — Style 서술이 자리 칸 목록(`StyleSchema.slots` — 선택 · 빈 목록이면 줄에 없다)을 싣는다(판 4 — 문구 칸 목록 `texts`).
    /// 자리 · 문구의 값은 Style 값 사전의 글자 칸이라 `render` · `patch` 의 꼴은 그대로다.
    public static let current = 5
    /// 엔진이 받는 가장 옛 판(바닥) — 이 판부터 지금 판까지 전부 받는다(그 아래는 `hostTooOld`).
    public static let oldest = 2
    /// 엔진이 지금 판 말고 받는 판의 말 — 바닥(`oldest`)부터 지금 판 바로 아래까지 전부(판마다 스텝을 이은 사슬).
    public static let previous: [ProtocolDialect] = [.v2, .v3, .v4]
}

extension ProtocolDialect.Step {
    /// 판 1 → 2 — 판 2 는 hello 에 선택 칸만 더했다: 판 1 의 줄은 그대로 판 2 의 줄이고(새 칸이 없을 뿐) ·
    /// 판 2 의 줄을 판 1 로 내리면 hello 의 새 칸을 걷는다(`ia` · `frames` · `tokensBuilt` · 화면마다 `fixtureColorUsage` · 층마다 `composition`).
    public static let v1to2 = ProtocolDialect.Step(from: 1, lift: { $0 }, lower: { line in
        guard line["type"] as? String == "hello" else { return line }
        var l = line
        for k in ["ia", "frames", "tokensBuilt"] { l.removeValue(forKey: k) }
        if let screens = l["screens"] as? [[String: Any]] { l["screens"] = screens.map { var s = $0; s.removeValue(forKey: "fixtureColorUsage"); return s } }
        if let layers = l["layers"] as? [[String: Any]] { l["layers"] = layers.map { var s = $0; s.removeValue(forKey: "composition"); return s } }
        return l
    })

    /// 판 2 → 3 — 판 2 의 줄은 그대로 판 3 의 줄이다(칸이 다 차 있다). 판 3 의 줄을 판 2 로 내리면 이름 없는 조절판 칸에 칸 키를 이름으로 채운다
    /// (판 2 는 이름을 필수로 읽는다 — 프로젝트 데이터 칸은 쓰는 손이 늘 다 채우므로 손댈 것이 없다).
    public static let v2to3 = ProtocolDialect.Step(from: 2, lift: { $0 }, lower: { line in
        guard line["type"] as? String == "hello" else { return line }
        var l = line
        func labeled(_ entries: [[String: Any]]) -> [[String: Any]] {
            entries.map { entry in
                guard var style = entry["style"] as? [String: Any], let fields = style["fields"] as? [[String: Any]] else { return entry }
                style["fields"] = fields.map { f in var f = f; if f["label"] == nil { f["label"] = f["name"] }; return f }
                var e = entry; e["style"] = style; return e
            }
        }
        if let screens = l["screens"] as? [[String: Any]] { l["screens"] = labeled(screens) }
        if let layers = l["layers"] as? [[String: Any]] { l["layers"] = labeled(layers) }
        return l
    })

    /// 판 3 → 4 — 판 3 의 줄은 그대로 판 4 의 줄이다(문구 목록이 없을 뿐 — 빈 목록으로 읽는다). 판 4 의 줄을 판 3 으로 내리면 hello 의 Style 서술마다
    /// 문구 목록(`texts`)을 걷는다. `render` · `patch` 는 그대로다 — 문구 값은 Style 값 사전의 칸 하나라 판 3 의 호스트에게는 서술 밖 칸이다
    /// (그 호스트의 서술에 문구가 없으니 엔진의 조절판에 문구 칸이 서지 않고 · 안 파일에서 실려 온 값은 호스트가 서술로 잴 때 빠진다 — 화면은 기본 글).
    public static let v3to4 = ProtocolDialect.Step(from: 3, lift: { $0 }, lower: { line in
        guard line["type"] as? String == "hello" else { return line }
        var l = line
        func untexted(_ entries: [[String: Any]]) -> [[String: Any]] {
            entries.map { entry in
                guard var style = entry["style"] as? [String: Any] else { return entry }
                style.removeValue(forKey: "texts")
                var e = entry; e["style"] = style; return e
            }
        }
        if let screens = l["screens"] as? [[String: Any]] { l["screens"] = untexted(screens) }
        if let layers = l["layers"] as? [[String: Any]] { l["layers"] = untexted(layers) }
        return l
    })

    /// 판 4 → 5 — 판 4 의 줄은 그대로 판 5 의 줄이다(자리 목록이 없을 뿐 — 빈 목록으로 읽는다). 판 5 의 줄을 판 4 로 내리면 hello 의 Style 서술마다
    /// 자리 목록(`slots`)을 걷는다. `render` · `patch` 는 그대로다 — 자리 값은 Style 값 사전의 칸 하나라 판 4 의 호스트에게는 서술 밖 칸이다
    /// (그 호스트의 서술에 자리가 없으니 엔진의 조절판에 자리 칸이 서지 않고 · 안 파일에서 실려 온 값은 호스트가 서술로 잴 때 빠진다 — 화면은 원래 이미지).
    public static let v4to5 = ProtocolDialect.Step(from: 4, lift: { $0 }, lower: { line in
        guard line["type"] as? String == "hello" else { return line }
        var l = line
        func unslotted(_ entries: [[String: Any]]) -> [[String: Any]] {
            entries.map { entry in
                guard var style = entry["style"] as? [String: Any] else { return entry }
                style.removeValue(forKey: "slots")
                var e = entry; e["style"] = style; return e
            }
        }
        if let screens = l["screens"] as? [[String: Any]] { l["screens"] = unslotted(screens) }
        if let layers = l["layers"] as? [[String: Any]] { l["layers"] = unslotted(layers) }
        return l
    })
}

extension ProtocolDialect {
    /// 판 4 의 말(스텝 4 → 5).
    public static let v4 = ProtocolDialect.chain([.v4to5])
    /// 판 3 의 말(스텝 3 → 4 → 5).
    public static let v3 = ProtocolDialect.chain([.v3to4, .v4to5])
    /// 판 2 의 말(스텝 2 → 3 → 4 → 5).
    public static let v2 = ProtocolDialect.chain([.v2to3, .v3to4, .v4to5])
    /// 판 1 의 말(스텝 1 → 2 → 3 → 4 → 5) — 엔진은 받지 않는다(바닥 아래 · `hostTooOld`) · 사슬의 시험과 옛 줄 읽기에 쓴다.
    public static let v1 = ProtocolDialect.chain([.v1to2, .v2to3, .v3to4, .v4to5])
}

/// 판 하나의 말 — 그 판의 줄(JSON 한 줄) ⟂ 지금 판의 메시지(`Message`). 지금 판의 말은 `Message` 의 Codable 그대로다.
/// 옛 판의 말은 줄 하나(맨 위 객체)를 지금 판의 꼴로 올리는 손(`lift`)과 그 판의 꼴로 내리는 손(`lower`) 한 쌍이다 — 정수는 정수 그대로 옮긴다
/// (`JSONSerialization` 의 수 — `seq` · 시각(ns)이 Double 로 깎이지 않게). 내리는 손이 nil 을 내면 그 메시지는 그 판에 없다(보내지 않는다).
/// 판을 올리는 변경은 한 판 사이의 스텝(`Step` — 그 판 ⟂ 다음 판) 하나를 더하고, 옛 판마다의 말은 스텝을 이어 짓는다(`chain`).
public struct ProtocolDialect: Sendable {
    /// 줄 하나의 맨 위 객체.
    public typealias Line = [String: Any]
    public let version: Int
    /// 이 말이 올려 닿는 판 — 지금 판의 메시지(`Message`)로 읽으려면 `PreviewProtocolVersion.current` 여야 한다(사슬은 마지막 스텝의 도착 판).
    public let reaches: Int
    private let lift: (@Sendable (Line) throws -> Line)?
    private let lower: (@Sendable (Line) throws -> Line?)?

    /// 한 판(`from`) ⟂ 다음 판(`from + 1`) 사이의 스텝 — `lift`: `from` 의 줄 → 다음 판의 줄 · `lower`: 다음 판의 줄 → `from` 의 줄(nil = 그 판에 없는 메시지).
    public struct Step: Sendable {
        public let from: Int
        public var to: Int { from + 1 }
        public let lift: @Sendable (Line) throws -> Line
        public let lower: @Sendable (Line) throws -> Line?
        public init(from: Int, lift: @escaping @Sendable (Line) throws -> Line, lower: @escaping @Sendable (Line) throws -> Line?) {
            self.from = from; self.lift = lift; self.lower = lower
        }
    }

    /// 옛 판의 말 — `lift`: 그 판의 줄 → 지금 판의 줄 · `lower`: 지금 판의 줄 → 그 판의 줄(nil = 그 판에 없는 메시지 — 보내지 않는다).
    /// 손 한 쌍은 지금 판(`PreviewProtocolVersion.current`)의 줄과 오간다.
    public init(version: Int, lift: @escaping @Sendable (Line) throws -> Line, lower: @escaping @Sendable (Line) throws -> Line?) {
        self.init(version: version, reaches: PreviewProtocolVersion.current, lift: lift, lower: lower)
    }
    private init(version: Int, reaches: Int, lift: @escaping @Sendable (Line) throws -> Line, lower: @escaping @Sendable (Line) throws -> Line?) {
        self.version = version; self.reaches = reaches; self.lift = lift; self.lower = lower
    }
    private init(native version: Int) { self.version = version; reaches = version; lift = nil; lower = nil }

    /// 스텝을 이은 말 — 첫 스텝의 판의 말 · 마지막 스텝의 판에 닿는다(`reaches`)(올리기는 차례대로 · 내리기는 거꾸로 · 어느 스텝이 nil 을 내면 nil).
    /// 스텝은 판이 하나씩 이어져야 한다.
    public static func chain(_ steps: [Step]) -> ProtocolDialect {
        precondition(!steps.isEmpty, "스텝이 없다")
        for (a, b) in zip(steps, steps.dropFirst()) { precondition(b.from == a.to, "스텝이 이어지지 않는다 — \(a.from)→\(a.to) 뒤에 \(b.from)") }
        return ProtocolDialect(version: steps[0].from, reaches: steps[steps.count - 1].to, lift: { line in
            try steps.reduce(line) { try $1.lift($0) }
        }, lower: { line in
            var l: Line? = line
            for s in steps.reversed() { guard let x = l else { return nil }; l = try s.lower(x) }
            return l
        })
    }

    /// 지금 판의 말 — `Message` 의 Codable 그대로.
    public static let current = ProtocolDialect(native: PreviewProtocolVersion.current)

    /// 줄 하나(줄 끝 없이) → 메시지. 지금 판의 말이면 디코더 하나로 곧장(옮기는 값 없음).
    public func decode(_ line: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> Message {
        guard let lift else { return try decoder.decode(Message.self, from: line) }
        guard let top = try JSONSerialization.jsonObject(with: line) as? Line else { throw ProtocolDialectError.notObject }
        return try decoder.decode(Message.self, from: JSONSerialization.data(withJSONObject: try lift(top)))
    }

    /// 메시지 → 줄 하나(줄 끝 없이 · 키 정렬) · 그 판에 없는 메시지면 nil(보내지 않는다).
    public func encodeIfSpoken(_ message: Message) throws -> Data? {
        let native = try Framing.encoder.encode(message)
        guard let lower else { return native }
        guard let top = try JSONSerialization.jsonObject(with: native) as? Line else { throw ProtocolDialectError.notObject }
        guard let down = try lower(top) else { return nil }
        return try JSONSerialization.data(withJSONObject: down, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// 메시지 → 줄 하나(줄 끝 없이 · 키 정렬) — 그 판에 없는 메시지면 `ProtocolDialectError.notSpoken`.
    public func encode(_ message: Message) throws -> Data {
        guard let d = try encodeIfSpoken(message) else { throw ProtocolDialectError.notSpoken(type: message.type, version: version) }
        return d
    }
}

public enum ProtocolDialectError: Error, Hashable, CustomStringConvertible {
    case notObject
    /// 그 판에 없는 메시지 — 내리는 손이 nil 을 냈다.
    case notSpoken(type: String, version: Int)
    public var description: String {
        switch self {
        case .notObject: "줄의 맨 위가 JSON 객체가 아니다"
        case .notSpoken(let t, let v): "메시지 \(t) 는 프로토콜 판 \(v) 에 없다"
        }
    }
}

/// 판이 맞지 않는다 — 사람 말 한 줄(`description` — 엔진의 창이 그대로 보인다 · 호스트가 엔진에 오류로 보낸다).
public enum ProtocolMismatch: Error, Equatable, Sendable, CustomStringConvertible {
    /// 호스트가 엔진보다 새 판 — 빌더(엔진)를 올려야 한다.
    case hostNewer(host: Int, engine: Int)
    /// 호스트가 엔진이 받는 판보다 옛 판(바닥 아래 · 판을 못 읽음) — 프로젝트(호스트를 짓는 SDK)를 받아 와야 한다.
    case hostTooOld(host: Int?, engine: Int)

    public var description: String {
        switch self {
        case .hostNewer(let h, let e):
            "미리보기 호스트가 이 빌더보다 새 판입니다 — 빌더를 업데이트하세요 (프로토콜 판 호스트 \(h) · 빌더 \(e))"
        case .hostTooOld(let h, let e):
            "미리보기 호스트가 이 빌더보다 옛 판입니다 — 프로젝트를 pull 하고 다시 여세요 (프로토콜 판 호스트 \(h.map(String.init) ?? "없음") · 빌더 \(e))"
        }
    }
}

/// 판정자 — 엔진 쪽 판(N)과 받는 말(N · 바닥까지의 옛 판). 엔진은 `engine` 하나를 쓴다 · 시험은 다른 판의 엔진(가짜 다음 판)을 세운다.
public struct ProtocolJudge: Sendable {
    /// 이 엔진의 판(N) — 엔진 hello 의 `protocolVersion` 으로 나간다.
    public let version: Int
    /// 받는 판의 말 — 판 → 말.
    public let dialects: [Int: ProtocolDialect]

    /// `dialects` 에 제 판(`version`)의 말이 든다(옛 판의 말은 받는 만큼).
    public init(version: Int, dialects: [ProtocolDialect]) {
        self.version = version
        self.dialects = Dictionary(dialects.map { ($0.version, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 이 엔진 — 지금 판 + 바닥까지의 옛 판의 말(`PreviewProtocolVersion.previous`).
    public static let engine = ProtocolJudge(version: PreviewProtocolVersion.current, dialects: [.current] + PreviewProtocolVersion.previous)

    /// 호스트의 판 하나를 가른다 — 그 판의 말이 있으면 그 말 · 새 판이면 `hostNewer` · 그 밖(말이 없는 옛 판 · 판 없음)은 `hostTooOld`.
    public func judge(host: Int?) -> Result<ProtocolDialect, ProtocolMismatch> {
        guard let host else { return .failure(.hostTooOld(host: nil, engine: version)) }
        if host > version { return .failure(.hostNewer(host: host, engine: version)) }
        if let d = dialects[host] { return .success(d) }
        return .failure(.hostTooOld(host: host, engine: version))
    }

    /// 호스트의 첫 줄(hello · 줄 끝 없이)에서 판을 읽어 그 판의 말을 고른다 — 몸은 풀지 않는다(판 읽개 `FormatStamp`).
    /// 첫 줄이 hello 가 아니면 `Framing.Failure.badJSON` · 판이 맞지 않으면 `ProtocolMismatch`.
    public func dialect(greeting line: Data) throws -> ProtocolDialect {
        let top = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        guard let type = top?["type"] as? String else { throw Framing.Failure.badJSON("첫 줄이 메시지가 아니다") }
        guard type == "hello" else { throw Framing.Failure.badJSON("첫 줄이 hello 가 아니다 — \(type)") }
        return try judge(host: FormatStamp.integer("protocolVersion", in: line)).get()
    }

    /// 호스트 쪽 규칙 — 엔진 hello 의 판이 호스트의 판과 같거나 새것이면 받는다(새 엔진은 호스트의 판으로 말한다 — 엔진이 판정자).
    /// 엔진이 옛 판이면 거절한다(그 엔진은 이 호스트의 꼴을 모른다 — 빌더를 올려야 한다).
    public static func hostAccepts(engine: Int, host: Int) -> Bool { engine >= host }
}
