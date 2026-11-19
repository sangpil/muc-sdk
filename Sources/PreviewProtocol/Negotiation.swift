import Foundation
import ProjectFormat

// 판 맞대기 — 엔진 ⟂ 미리보기 호스트가 서로 다른 SDK 로 빌드돼도(다른 Mac 의 배포본 빌더 ⟂ 그 Mac 이 받은 저장소 HEAD 로 지은 호스트) 말이 어긋나지 않게.
// 정본 `Docs/SDK.md` §5(판 규칙 · 맞대기).
//
//   판     : 메시지 꼴(종류 · 칸 키 · 칸의 뜻 · 선택 칸의 덧붙임)이 바뀌면 판을 올린다(`PreviewProtocolVersion.current`). 꼴의 지문은 시험이 판마다 한 줄 얼려 둔다
//            (`PreviewProtocolTests/protocol-shapes.txt` — 꼴이 바뀌었는데 판이 그대로면 빨강).
//   판정   : **엔진이 판정자**다. 호스트가 먼저 hello 를 보내고, 엔진은 그 첫 줄에서 몸을 풀기 전에 판(`protocolVersion`)만 읽어(`FormatStamp`) 가른다 —
//            같은 판만 받고, 그 밖(새 판 · 옛 판 · 판 없음)은 연결을 닫고 사람 말 한 줄(`ProtocolMismatch`). 줄은 늘 지금 판의 꼴(`Message` 의 Codable)이다.
//   호스트 : 늘 제 판의 꼴로 말한다. 엔진 hello 의 판이 제 판과 같을 때만 받는다(`hostAccepts` — 판이 다른 호스트는 엔진이 먼저 끊으므로 방어선이다).
//   불변   : hello 의 `type` · `protocolVersion` 두 칸은 판이 올라도 이름 · 자리(줄의 맨 위 객체 · 정수)가 그대로다 — 판 읽개가 이 둘만 본다.
//   기본값 : 판을 공개 손의 기본 인자로 두지 않는다(`Hello.protocolVersion` · `hostAccepts(host:)` 는 필수 인자). 비탄력 모듈의 공개 손의 기본 인자는 부르는 쪽
//            목적 코드에 들어가고 부르는 파일의 소스엔 판의 이름이 없어 증분 빌드의 의존에 안 잡힌다 — 판을 올려도 그 파일은 다시 지어지지 않고 옛 판을 지닌다
//            (실연: 기본 인자로 hello 를 세우던 파일은 판 1 · 판을 직접 부른 파일은 판 2 — 한 실행물에 두 판). 판을 부르는 쪽은 이름을 소스에 적는다.

/// 프로토콜 판 — **한 자리**. 메시지 꼴(선택 칸 포함 · 층 보고에 실리는 콜아웃 값의 꼴 포함)이 바뀌면 올리고 꼴 지문 한 줄을 더한다.
/// 엔진은 이 판의 호스트만 받는다 — 호스트는 같은 SDK 판으로 함께 옮긴다.
public enum PreviewProtocolVersion {
    /// 판 10 — hello 의 IA 낱말(`IAInfo`)에 옛 낱말 별칭 칸이 없다.
    public static let current = 10
}

/// 판이 맞지 않는다 — 사람 말 한 줄(`description` — 엔진의 창이 그대로 보인다 · 호스트가 엔진에 오류로 보낸다).
public enum ProtocolMismatch: Error, Equatable, Sendable, CustomStringConvertible {
    /// 호스트가 엔진보다 새 판 — 빌더(엔진)를 올려야 한다.
    case hostNewer(host: Int, engine: Int)
    /// 호스트가 엔진보다 옛 판(또는 판을 못 읽음) — 프로젝트의 SDK 판(호스트를 짓는 SDK)을 올려야 한다.
    case hostTooOld(host: Int?, engine: Int)

    public var description: String {
        switch self {
        case .hostNewer(let h, let e):
            "미리보기 호스트가 이 빌더보다 새 판입니다 — 빌더를 업데이트하세요 (프로토콜 판 호스트 \(h) · 빌더 \(e))"
        case .hostTooOld(let h, let e):
            "미리보기 호스트가 이 빌더보다 옛 판입니다 — 프로젝트의 SDK 판을 올린 뒤 다시 여세요 (프로토콜 판 호스트 \(h.map(String.init) ?? "없음") · 빌더 \(e))"
        }
    }
}

/// 판정자 — 엔진 쪽 판(N) 하나. 엔진은 `engine` 하나를 쓴다 · 시험은 다른 판의 엔진(가짜 다음 판)을 세운다.
public struct ProtocolJudge: Sendable {
    /// 이 엔진의 판(N) — 엔진 hello 의 `protocolVersion` 으로 나가고, 받는 호스트의 판이다.
    public let version: Int

    public init(version: Int) { self.version = version }

    /// 이 엔진 — 지금 판(`PreviewProtocolVersion.current`).
    public static let engine = ProtocolJudge(version: PreviewProtocolVersion.current)

    /// 호스트의 판 하나를 가른다 — 같은 판이면 nil(받는다) · 새 판이면 `hostNewer` · 그 밖(옛 판 · 판 없음)은 `hostTooOld`.
    public func judge(host: Int?) -> ProtocolMismatch? {
        guard let host else { return .hostTooOld(host: nil, engine: version) }
        if host > version { return .hostNewer(host: host, engine: version) }
        if host < version { return .hostTooOld(host: host, engine: version) }
        return nil
    }

    /// 호스트의 첫 줄(hello · 줄 끝 없이)에서 판을 읽어 가른다 — 몸은 풀지 않는다(판 읽개 `FormatStamp`).
    /// 첫 줄이 hello 가 아니면 `Framing.Failure.badJSON` · 판이 맞지 않으면 `ProtocolMismatch`.
    public func check(greeting line: Data) throws {
        let top = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        guard let type = top?["type"] as? String else { throw Framing.Failure.badJSON("첫 줄이 메시지가 아니다") }
        guard type == "hello" else { throw Framing.Failure.badJSON("첫 줄이 hello 가 아니다 — \(type)") }
        if let mismatch = judge(host: FormatStamp.integer("protocolVersion", in: line)) { throw mismatch }
    }

    /// 호스트 쪽 규칙 — 엔진 hello 의 판이 호스트의 판과 같을 때만 받는다. 거절하는 쪽은 엔진(판정자)이다 — 판이 다른 호스트는 엔진이 hello 를 보내기 전에 끊으므로
    /// 이 규칙은 판정자 없는 상대에 대한 방어선이다(그 사람 말은 `ProtocolJudge(version: <엔진의 판>).judge(host: <호스트의 판>)`).
    public static func hostAccepts(engine: Int, host: Int) -> Bool { engine == host }
}
