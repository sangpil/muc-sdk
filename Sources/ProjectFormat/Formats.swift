// 모듈 `ProjectFormat` — 계약 갈래(플랫폼 중립 · iOS · macOS). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : 프로젝트 문서의 형식 — 모델 파일(`.isodata`) · 안 파일 · IA 문서의 꼴과 판 상수 · 판 읽개 ·
//                CloudKit 호환 규칙 · 공유 데이터 모델 칸 · 공유 데이터의 변경 기록 규약(`ChangeLog`) · 폼팩터 낱말 · JSON 값.
//   누가 부르나 : 엔진의 도구 · 프로젝트(앱 제품 · 코어 · 미리보기 호스트 · 프로젝트 도구) · SDK 의 `PreviewProtocol` · `PreviewHostKit`.
//   지키는 것   : 판을 몸보다 먼저 읽는다(`FormatStamp`) · 모르는 키는 보존해 되쓴다(형식 꼴은 `extra` 칸 · 사전 기반 꼴은 사전째) · SDK 가 읽고 쓰는 형식의 판 상수는
//                이 파일 한 자리 · Foundation · CoreGraphics(값 꼴) · CryptoKit 만 문다.
//   시작점     : `IsoDataFile` · `DesignFile` · `IADoc` · `FormatStamp` · `JSONValue`
//
// 형식 판 상수 — **SDK 가 직접 읽고 쓰는 형식의 판만** 여기 산다(모델 파일 `IsoDataFile` · 안 파일 `DesignFile` · IA 문서 `IADoc` — 그 꼴이 이 모듈에 있다).
// 판 상수는 그 형식을 디코드하는 모듈과 함께 산다 — 씬 · 모델(렌더 코어가 디코드) · 배선(엔진의 도구가 읽는다)의 판은 그 쪽이 갖는다
// (SDK 가 디코드하지 않는 형식의 칸 하나가 SDK 판을 올리지 않게). 엔진의 형식 판 등록표 · 데이터 도구 · IA · 안 손이 이 값을 읽는다(두 벌이 서지 않는다).
// 판마다의 **뜻**과 판을 올리는 차례는 형식을 읽고 쓰는 엔진(빌더)이 갖는다 — SDK 는 판 번호만 든다.
// 형식마다 판은 하나다 — 읽개는 그 판만 읽고 쓰개는 그 판으로 쓴다. 더 옛 판은 「지원하지 않는 판」으로 거절하고, 더 새 판은 「새 판」으로 거절한다.

/// 데이터(`.isodata`) — 한 형식, 두 모양: 삶 파일(`domain` · `eras` · `series` · `milestones` · `people` · `nextIDs`)과 모델 파일(`schema` + `datasets`).
/// 판은 한 줄이다 — 두 모양 모두 `version` 으로 쓰고, 디코더는 이 판만 읽는다(다른 판은 이름 대고 거절한다 — `IsoDataError`).
public enum IsoDataFormat {
    /// 이 SDK 가 읽고 쓰는 판(삶 파일 · 모델 파일 같은 판).
    public static let version = 6

    /// 파일 상한 — 넘으면 이름을 대고 거부한다(바이트를 자를 수는 없다).
    public static let maxBytes = 8 * 1024 * 1024
    /// 엔티티당 행 상한 — 넘으면 앞에서부터 읽고 자른 것을 말한다.
    public static let maxRowsPerEntity = 20_000
}

/// 안(`<화면>/<안>.design.json`) — 맨 위 정수 칸 `version`(`DesignFile.version`) · 칸이 없으면 이 판이다(판 칸을 들이기 전의 안 파일 전부).
public enum DesignFormat {
    public static let version = 1
}

/// IA(`ia.json` · 매니페스트 `paths.ia`).
public enum IAFormat {
    public static let version = 1
}
