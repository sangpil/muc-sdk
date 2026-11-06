// 모듈 `ProjectFormat` — 계약 갈래(플랫폼 중립 · iOS · macOS). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : 프로젝트 문서의 형식 — 모델 파일(`.isodata`) · 안 파일 · IA 문서의 꼴과 판 상수 · 판 읽개 · 업그레이드 사슬의 꼴 ·
//                CloudKit 호환 규칙 · 공유 데이터 모델 칸 · 공유 데이터의 고침 기록 규약(`ChangeLog`) · 폼팩터 낱말 · JSON 값.
//   누가 부르나 : 엔진의 도구 · 프로젝트(앱 제품 · 코어 · 미리보기 호스트 · 프로젝트 도구) · SDK 의 `PreviewProtocol` · `PreviewHostKit`.
//   지키는 것   : 판을 몸보다 먼저 읽는다(`FormatStamp`) · 모르는 키는 보존해 되쓴다(형식 꼴은 `extra` 칸 · 사전 기반 꼴은 사전째) · SDK 가 읽고 쓰는 형식의 판 상수는
//                이 파일 한 자리 · Foundation · CoreGraphics(값 꼴) · CryptoKit 만 문다.
//   시작점     : `IsoDataFile` · `DesignFile` · `IADoc` · `FormatStamp` · `JSONValue`
//
// 형식 판 상수 — **SDK 가 직접 읽고 쓰는 형식의 판만** 여기 산다(모델 파일 `IsoDataFile` · 안 파일 `DesignFile` · IA 문서 `IADoc` — 그 꼴이 이 모듈에 있다).
// 판 상수는 그 형식을 디코드하는 모듈과 함께 산다 — 씬 · 모델(렌더 코어가 디코드) · 배선(엔진의 도구가 읽는다)의 판은 그 쪽이 갖는다
// (SDK 가 디코드하지 않는 형식의 칸 하나가 SDK 판을 올리지 않게). 엔진의 형식 판 등록표 · 데이터 도구 · IA · 안 손이 이 값을 읽는다(두 벌이 서지 않는다).
// 판마다의 **뜻**과 판을 올리는 차례는 형식을 읽고 쓰는 엔진(빌더)이 갖는다 — SDK 는 판 번호만 든다.
// 형식마다 같은 꼴 한 벌(`FormatVersions` — 사슬의 바닥 · 디코더의 바닥 · 최신 · 쓰는 바닥 · 판 칸 이름)이 업그레이드 사슬(`UpgradeChain(versions:steps:)`)의 범위다.

/// 형식 하나의 판 범위 — 사슬이 받는 가장 옛 판 · 디코더가 읽는 가장 옛 판 · 읽는 최신 판 · 쓰는 손이 찍는 가장 낮은 판 · 판 칸 이름.
/// 읽는 범위는 둘이다 — 업그레이드 사슬은 `oldest` 부터 돌고, 디코더 · 열기 판정은 `decodeOldest` 부터 읽는다(그 아래는 「업그레이드가 필요함」 —
/// 사슬이 한 번 고쳐 쓴 뒤에 연다). 둘이 같으면 디코더가 사슬의 바닥까지 읽는다.
public struct FormatVersions: Equatable, Sendable {
    /// 업그레이드 사슬이 받는 가장 옛 판 — 사슬의 바닥(그 아래는 사슬 밖).
    public let oldest: Int
    /// 디코더가 읽는 가장 옛 판 — 그 아래는 디코더가 열지 않고 사슬이 먼저 올린다(`oldest` ≤ 이 값 ≤ `writeFloor`).
    public let decodeOldest: Int
    /// 읽는 가장 새 판 — 넘으면 이름 대고 거절(읽기 전용으로만 연다).
    public let newest: Int
    /// 쓰는 손이 찍는 가장 낮은 판 — 업그레이드가 쓰는 판의 바닥이기도 하다.
    public let writeFloor: Int
    /// 판 칸 이름(문서 맨 위의 정수 칸).
    public let stampKey: String
    /// 디코더가 사슬의 바닥까지 읽는 형식(`decodeOldest` = `oldest`).
    public init(oldest: Int, newest: Int, writeFloor: Int, stampKey: String) throws(FormatVersionsError) {
        try self.init(oldest: oldest, decodeOldest: oldest, newest: newest, writeFloor: writeFloor, stampKey: stampKey)
    }
    /// 판 차례(사슬의 바닥 ≤ 디코더의 바닥 ≤ 쓰는 바닥 ≤ 최신)가 어긋나면 만들지 않는다 — 쓴 문서를 디코더가 못 읽는 범위는 서지 않는다.
    public init(oldest: Int, decodeOldest: Int, newest: Int, writeFloor: Int, stampKey: String) throws(FormatVersionsError) {
        guard oldest <= decodeOldest, decodeOldest <= writeFloor, writeFloor <= newest else {
            throw .outOfOrder(oldest: oldest, decodeOldest: decodeOldest, writeFloor: writeFloor, newest: newest)
        }
        self.oldest = oldest; self.decodeOldest = decodeOldest; self.newest = newest; self.writeFloor = writeFloor; self.stampKey = stampKey
    }

    /// 디코더가 이 판을 읽는가 — `decodeOldest`…`newest`.
    public func decodes(_ version: Int) -> Bool { version >= decodeOldest && version <= newest }
}

/// 판 범위를 만들 수 없다 — 판 차례가 어긋났다.
public enum FormatVersionsError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 사슬의 바닥 ≤ 디코더의 바닥 ≤ 쓰는 바닥 ≤ 최신 이 아니다.
    case outOfOrder(oldest: Int, decodeOldest: Int, writeFloor: Int, newest: Int)

    public var description: String {
        switch self {
        case .outOfOrder(let o, let d, let w, let n):
            "판 차례가 어긋났다 — 사슬의 바닥 \(o) ≤ 디코더의 바닥 \(d) ≤ 쓰는 바닥 \(w) ≤ 최신 \(n) 이어야 한다"
        }
    }
}

/// 데이터(`.isodata`) — 한 형식, 두 모양: 삶 파일(`domain` · `eras` · `series` · `milestones` · `people` · `nextIDs`)과 모델 파일(`schema` + `datasets`).
/// 판은 한 줄이다 — 두 모양 모두 `version` 으로 쓰고, 디코더는 이 판만 읽는다(옛 판은 업그레이드 사슬이 한 번 고쳐 쓴다).
public enum IsoDataFormat {
    /// 이 SDK 가 읽고 쓰는 판(삶 파일 · 모델 파일 같은 판).
    public static let version = 6
    /// 판 범위 한 벌 — 사슬의 바닥 1 · 디코더의 바닥 = 최신 = 쓰는 바닥 = `version`.
    public static let versions = try! FormatVersions(oldest: 1, decodeOldest: version, newest: version, writeFloor: version, stampKey: "version")

    /// 파일 상한 — 넘으면 이름을 대고 거부한다(바이트를 자를 수는 없다).
    public static let maxBytes = 8 * 1024 * 1024
    /// 엔티티당 행 상한 — 넘으면 앞에서부터 읽고 자른 것을 말한다.
    public static let maxRowsPerEntity = 20_000
}

/// 안(`<화면>/<안>.design.json`) — 맨 위 정수 칸 `version`(`DesignFile.version`) · 칸이 없으면 이 판이다(판 칸을 들이기 전의 안 파일 전부).
public enum DesignFormat {
    public static let version = 1
    /// 판 범위 한 벌.
    public static let versions = try! FormatVersions(oldest: 1, newest: version, writeFloor: 1, stampKey: "version")
}

/// IA(`ia.json` · 매니페스트 `paths.ia`).
public enum IAFormat {
    public static let version = 1
    /// 판 범위 한 벌.
    public static let versions = try! FormatVersions(oldest: 1, newest: version, writeFloor: 1, stampKey: "version")
}
