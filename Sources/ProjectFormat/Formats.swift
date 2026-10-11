// 형식 판 상수 — **한 자리**. 엔진의 형식 판 등록표 · 빌더 코어의 읽는 손 ·
// 모델 파일의 읽개(`IsoDataFile` · 이 모듈) · 데이터 도구 · 엔진의 IA · 배선 · 안 손이 모두 이 값을 읽는다(두 벌이 서지 않는다).
// 판마다의 **뜻**과 판을 올리는 차례는 형식을 읽고 쓰는 엔진(빌더)이 갖는다 — SDK 는 판 번호만 든다.

/// 씬(`.isoscene`).
public enum SceneFormat {
    /// 이 SDK 가 읽는 가장 새 판 — 넘으면 이름 대고 거절(읽기 전용으로만 연다).
    public static let newestReadable = 24
    /// 이 SDK 가 아직 읽는 가장 옛 판 — 업그레이드 사슬의 바닥이다(아래는 사슬 밖 · 이름 대고 거절).
    public static let oldestReadable = 2
    /// 쓰는 손이 찍는 가장 낮은 판 — 새 판의 칸을 하나도 쓰지 않는 씬이 쓰이는 판(빌더 코어의 씬 문서가 이 값을 읽는다).
    /// 업그레이드가 쓰는 판의 바닥이기도 하다.
    public static let lowestWritten = 14
}

/// 모델(`.isomodel`).
public enum ModelFormat {
    /// 이 SDK 가 읽는 가장 새 판.
    public static let newestReadable = 6
    /// 쓰는 손이 새 모델을 찍는 판(빌더 코어의 모델 문서가 이 값을 읽는다) — 업그레이드가 쓰는 판의 바닥.
    public static let lowestWritten = 4
}

/// 데이터(`.isodata`) — 한 형식, 두 모양: 삶 파일(`domain` · `eras` · `series` · `milestones` · `nextIDs`)과 모델 파일(`schema` + `datasets`).
/// 담을 수 있는 가장 낮은 판으로 쓴다 — 모델 절이 없으면 `life`, 있으면 `model`. 그래서 iCloud 의 삶 파일은 어느 손이 열고 써도 `life` 로 남는다.
public enum IsoDataFormat {
    /// 삶 파일의 판.
    public static let life = 3
    /// 모델 절이 서는 판.
    public static let model = 4
    /// 이 SDK 가 읽는 가장 새 판.
    public static let newest = model

    /// 담는 것을 담을 수 있는 가장 낮은 판.
    public static func minimumVersion(hasModel: Bool) -> Int { hasModel ? model : life }

    /// 파일 상한 — 넘으면 이름을 대고 거부한다(바이트를 자를 수는 없다).
    public static let maxBytes = 8 * 1024 * 1024
    /// 엔티티당 행 상한 — 넘으면 앞에서부터 읽고 자른 것을 말한다.
    public static let maxRowsPerEntity = 20_000
}

/// 안(`<화면>/<안>.design.json`) — 판 칸이 없는 형식이다. 모든 안 파일이 이 판이고, 「이 SDK 보다 새 안」은 가를 수 없다
/// (판 칸을 들이는 것은 형식 변경이다).
public enum DesignFormat {
    public static let version = 1
}

/// IA(`ia.json` · 매니페스트 `paths.ia`).
public enum IAFormat {
    public static let version = 1
}

/// 배선(`graph.json` · 매니페스트 `paths.graph`).
public enum GraphFormat {
    public static let version = 1
}
