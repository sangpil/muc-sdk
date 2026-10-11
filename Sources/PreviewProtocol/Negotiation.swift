import Foundation
import ProjectFormat

// 판 맞대기 — 엔진 ⟂ 미리보기 호스트가 서로 다른 SDK 로 빌드돼도(다른 Mac 의 배포본 빌더 ⟂ 그 Mac 이 받은 저장소 HEAD 로 지은 호스트) 말이 어긋나지 않게.
// 정본 `Docs/SDK.md` §5(판 규칙 · 맞대기).
//
//   판     : 메시지 꼴(종류 · 칸 키 · 칸의 뜻)이 바뀌면 판을 올린다(`PreviewProtocolVersion.current`). 꼴의 지문은 시험이 판마다 한 줄 얼려 둔다
//            (`PreviewProtocolTests/protocol-shapes.txt` — 꼴이 바뀌었는데 판이 그대로면 빨강).
//   판정   : **엔진이 판정자**다. 호스트가 먼저 hello 를 보내고, 엔진은 그 첫 줄에서 몸을 풀기 전에 판(`protocolVersion`)만 읽어(`FormatStamp`) 가른다 —
//            같은 판(N) · 한 판 뒤(N-1 — 그 판의 말 `ProtocolDialect` 로 읽고 쓴다)는 받고, 그 밖(N+1 이상 · N-2 이하)은 연결을 닫고 사람 말 한 줄(`ProtocolMismatch`).
//   호스트 : 늘 제 판의 꼴로 말한다(엔진이 호스트의 판에 맞춰 말한다). 엔진 hello 의 판이 제 판보다 옛것이면 거절하고 · 같거나 새것이면 받는다(`hostAccepts`).
//   불변   : hello 의 `type` · `protocolVersion` 두 칸은 판이 올라도 이름 · 자리(줄의 맨 위 객체 · 정수)가 그대로다 — 판 읽개가 이 둘만 본다.
//   기본값 : 판을 공개 손의 기본 인자로 두지 않는다(`Hello.protocolVersion` · `hostAccepts(host:)` 는 필수 인자). 비탄력 모듈의 공개 손의 기본 인자는 부르는 쪽
//            목적 코드에 들어가고 부르는 파일의 소스엔 판의 이름이 없어 증분 빌드의 의존에 안 잡힌다 — 판을 올려도 그 파일은 다시 지어지지 않고 옛 판을 지닌다
//            (실연: 기본 인자로 hello 를 세우던 파일은 판 1 · 판을 직접 부른 파일은 판 2 — 한 실행물에 두 판). 판을 부르는 쪽은 이름을 소스에 적는다.

/// 프로토콜 판 — **한 자리**. 메시지 꼴이 바뀌면 올린다 — 올리는 변경은 꼴 지문 한 줄과 한 판 뒤의 말(`previous`)을 함께 더한다.
public enum PreviewProtocolVersion {
    /// 판 2 — hello 에 프로젝트의 데이터(`ia` · `frames` · `tokensBuilt` · `screens[].fixtureColorUsage` · `layers[].composition`)가 실린다.
    public static let current = 2
    /// 엔진이 지금 판 말고 받는 판의 말 — 한 판 뒤(N-1) 하나(판을 올리는 변경이 옛 판의 말을 여기 둔다).
    public static let previous: [ProtocolDialect] = [.v1]
}

extension ProtocolDialect {
    /// 판 1 의 말 — 판 2 는 hello 에 선택 칸만 더했다: 판 1 의 줄은 그대로 판 2 의 메시지로 읽히고(새 칸이 없을 뿐) ·
    /// 판 2 의 줄을 판 1 로 내리면 hello 의 새 칸을 걷는다(`ia` · `frames` · `tokensBuilt` · 화면마다 `fixtureColorUsage` · 층마다 `composition`).
    public static let v1 = ProtocolDialect(version: 1, lift: { $0 }, lower: { line in
        guard line["type"] as? String == "hello" else { return line }
        var l = line
        for k in ["ia", "frames", "tokensBuilt"] { l.removeValue(forKey: k) }
        if let screens = l["screens"] as? [[String: Any]] { l["screens"] = screens.map { var s = $0; s.removeValue(forKey: "fixtureColorUsage"); return s } }
        if let layers = l["layers"] as? [[String: Any]] { l["layers"] = layers.map { var s = $0; s.removeValue(forKey: "composition"); return s } }
        return l
    })
}

/// 판 하나의 말 — 그 판의 줄(JSON 한 줄) ⟂ 지금 판의 메시지(`Message`). 지금 판의 말은 `Message` 의 Codable 그대로다.
/// 옛 판의 말은 줄 하나(맨 위 객체)를 지금 판의 꼴로 올리는 손(`lift`)과 그 판의 꼴로 내리는 손(`lower`) 한 쌍이다 — 정수는 정수 그대로 옮긴다
/// (`JSONSerialization` 의 수 — `seq` · 시각(ns)이 Double 로 깎이지 않게).
public struct ProtocolDialect: Sendable {
    /// 줄 하나의 맨 위 객체.
    public typealias Line = [String: Any]
    public let version: Int
    private let lift: (@Sendable (Line) throws -> Line)?
    private let lower: (@Sendable (Line) throws -> Line)?

    /// 옛 판의 말 — `lift`: 그 판의 줄 → 지금 판의 줄 · `lower`: 지금 판의 줄 → 그 판의 줄.
    public init(version: Int, lift: @escaping @Sendable (Line) throws -> Line, lower: @escaping @Sendable (Line) throws -> Line) {
        self.version = version; self.lift = lift; self.lower = lower
    }
    private init(native version: Int) { self.version = version; lift = nil; lower = nil }

    /// 지금 판의 말 — `Message` 의 Codable 그대로.
    public static let current = ProtocolDialect(native: PreviewProtocolVersion.current)

    /// 줄 하나(줄 끝 없이) → 메시지. 지금 판의 말이면 디코더 하나로 곧장(옮기는 값 없음).
    public func decode(_ line: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> Message {
        guard let lift else { return try decoder.decode(Message.self, from: line) }
        guard let top = try JSONSerialization.jsonObject(with: line) as? Line else { throw ProtocolDialectError.notObject }
        return try decoder.decode(Message.self, from: JSONSerialization.data(withJSONObject: try lift(top)))
    }

    /// 메시지 → 줄 하나(줄 끝 없이 · 키 정렬).
    public func encode(_ message: Message) throws -> Data {
        let native = try Framing.encoder.encode(message)
        guard let lower else { return native }
        guard let top = try JSONSerialization.jsonObject(with: native) as? Line else { throw ProtocolDialectError.notObject }
        return try JSONSerialization.data(withJSONObject: try lower(top), options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

public enum ProtocolDialectError: Error, CustomStringConvertible {
    case notObject
    public var description: String { "줄의 맨 위가 JSON 객체가 아니다" }
}

/// 판이 맞지 않는다 — 사람 말 한 줄(`description` — 엔진의 창이 그대로 보인다 · 호스트가 엔진에 오류로 보낸다).
public enum ProtocolMismatch: Error, Equatable, Sendable, CustomStringConvertible {
    /// 호스트가 엔진보다 새 판 — 빌더(엔진)를 올려야 한다.
    case hostNewer(host: Int, engine: Int)
    /// 호스트가 엔진이 받는 판보다 옛 판(N-2 이하 · 판을 못 읽음) — 프로젝트(호스트를 짓는 SDK)를 받아 와야 한다.
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

/// 판정자 — 엔진 쪽 판(N)과 받는 말(N · N-1). 엔진은 `engine` 하나를 쓴다 · 시험은 다른 판의 엔진(가짜 판 2 — 한 판 뒤 1 을 받는다)을 세운다.
public struct ProtocolJudge: Sendable {
    /// 이 엔진의 판(N) — 엔진 hello 의 `protocolVersion` 으로 나간다.
    public let version: Int
    /// 받는 판의 말 — 판 → 말.
    public let dialects: [Int: ProtocolDialect]

    /// `dialects` 에 제 판(`version`)의 말이 든다(한 판 뒤의 말은 있으면).
    public init(version: Int, dialects: [ProtocolDialect]) {
        self.version = version
        self.dialects = Dictionary(dialects.map { ($0.version, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 이 엔진 — 지금 판 + 한 판 뒤의 말(`PreviewProtocolVersion.previous`).
    public static let engine = ProtocolJudge(version: PreviewProtocolVersion.current, dialects: [.current] + PreviewProtocolVersion.previous)

    /// 호스트의 판 하나를 가른다 — 같은 판 · 한 판 뒤(말이 있을 때)면 그 판의 말 · 새 판이면 `hostNewer` · 그 밖(옛 판 · 판 없음)은 `hostTooOld`.
    public func judge(host: Int?) -> Result<ProtocolDialect, ProtocolMismatch> {
        guard let host else { return .failure(.hostTooOld(host: nil, engine: version)) }
        if host > version { return .failure(.hostNewer(host: host, engine: version)) }
        if host >= version - 1, let d = dialects[host] { return .success(d) }
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
