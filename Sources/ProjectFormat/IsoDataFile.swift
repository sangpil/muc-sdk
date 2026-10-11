import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). SQL 투영 · 생성 · 울타리는 엔진의 몫이다.
//
// `.isodata` 4 — 한 형식, 두 모양.
//   삶 파일   : `domain` · `eras` · `series` · `milestones` · `nextIDs` — 빌더가 고치는 파일. 이 모듈은 **통째로 나르기만** 한다(뜻은 빌더의 것).
//   모델 파일 : `schema` + `datasets` + `migrated` — 데이터 창이 고치는 파일.
// 최소 판으로 쓴다 — 모델 절이 없으면 3, 있으면 4. 그래서 iCloud 의 삶 파일은 이 코드로 열고 써도 3 으로 남는다.
// 판 번호 · 상한은 엔진 SDK 의 한 자리(`ProjectFormat.IsoDataFormat`) · 판 읽개는 `FormatStamp.version` — 빌더 코어의 읽는 손과 같은 값이다.

/// 읽기 오류 — 파일 전체를 거부하는 것만(레코드 오류는 `RecordIssue` 로 싣는다 · 읽기 규율 ④).
public enum IsoDataError: Error, Equatable, LocalizedError, Sendable {
    /// 판이 이 도구보다 새롭다.
    case tooNew(Int)
    /// JSON 이 아니거나 최상위가 객체가 아니다.
    case notJSON(String)
    /// 파일이 상한을 넘는다.
    case tooLarge(Int)
    /// 형식이 틀린 자리 — 경로(`schema.entities[3].fields[7].type`)와 까닭.
    case invalid(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .tooNew(let v):
            return "이 데이터 파일은 더 새 판(형식 \(v))으로 쓰였다 — 이 빌드는 형식 \(IsoDataFormat.newest) 까지 읽는다 · 다음: 새 빌드로 연다"
        case .notJSON(let why):
            return "데이터 파일을 JSON 으로 읽지 못한다 — \(why)"
        case .tooLarge(let bytes):
            return "데이터 파일이 \(bytes) 바이트로 상한 \(IsoDataFormat.maxBytes) 바이트(8 MB)를 넘는다"
        case .invalid(let path, let reason):
            return "\(path) — \(reason)"
        }
    }
}

/// 디스크의 `.isodata` 한 장 — 삶 파일 또는 모델 파일.
public enum IsoDataFile: Equatable, Sendable {
    case life(LifeFile)
    case model(DataModelFile)

    /// 스키마가 있는가 — 모델 파일을 가르는 선(파일 머리의 `schema` 유무로 가른다).
    public var isModel: Bool { if case .model = self { return true } else { return false } }

    /// 이 파일을 쓸 때 찍힐 판 — 삶 파일은 읽은 판을 넘지 않는다(옛 판 몸을 이관 없이 새 판으로 찍지 않는다).
    public var writtenVersion: Int {
        switch self {
        case .life(let life): min(life.version, IsoDataFormat.life)
        case .model: IsoDataFormat.model
        }
    }

    // MARK: 읽기

    /// JSON 이 멈춘 자리 — 「JSON 문법이 깨졌다 · 줄 3 · 칸 14 근처」(파서의 말에서 줄 · 칸만 읽는다). 시스템의 영어 · 「올바른 포맷이 아니기
    /// 때문에…」를 그대로 싣지 않는다(엔진의 씬 파일 검사와 같은 꼴).
    public static func jsonPlace(_ data: Data) -> String {
        if data.isEmpty { return "빈 파일" }
        do { _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]); return "최상위가 객체가 아니다" } catch {
            let note = ((error as NSError).userInfo.values.compactMap { $0 as? String }).joined(separator: " ")
            let number = { (word: String) -> Int? in
                guard let r = note.range(of: "\(word) ") else { return nil }
                return Int(note[r.upperBound...].prefix { $0.isNumber })
            }
            if let line = number("line"), let column = number("column") { return "JSON 문법이 깨졌다 · 줄 \(line) · 칸 \(column) 근처" }
            return "JSON 문법이 깨졌다"
        }
    }

    /// 바이트 → 파일. 판을 먼저 읽고(미래 판 거부) · 스키마 유무로 모양을 가른다.
    /// 모델 파일의 레코드 오류는 거부가 아니라 `DataModelFile.issues` 로 실린다.
    /// `allowingNewer` — 미래 판도 이 빌드가 아는 칸까지 읽는다(읽기 전용 창 · 단독 열기 검사). 그렇게 읽은 것은 쓰지 않는다
    /// (엔진의 쓰기 손이 디스크의 미래 판을 덮지 않는다).
    public static func read(_ data: Data, allowingNewer: Bool = false) throws -> IsoDataFile {
        guard data.count <= IsoDataFormat.maxBytes else { throw IsoDataError.tooLarge(data.count) }
        let root: JSONValue
        do { root = try JSONDecoder().decode(JSONValue.self, from: data) } catch {
            throw IsoDataError.notJSON(jsonPlace(data))
        }
        guard case .object(var top) = root else { throw IsoDataError.notJSON("최상위가 객체가 아니다") }
        guard case .number(let raw)? = top["version"], raw == raw.rounded(), raw >= 1 else {
            throw IsoDataError.invalid(path: "version", reason: "판 번호(정수)가 없다")
        }
        // `Int(exactly:)` — Int 로 담기지 않는 큰 판(1e20)은 트랩이 아니라 거부한다.
        guard let version = Int(exactly: raw) else {
            throw IsoDataError.invalid(path: "version", reason: "판 번호가 너무 크다")
        }
        guard allowingNewer || version <= IsoDataFormat.newest else { throw IsoDataError.tooNew(version) }
        top["version"] = nil
        if top["schema"] == nil {
            return .life(LifeFile(body: top, version: version))
        }
        guard version >= IsoDataFormat.model else {
            throw IsoDataError.invalid(path: "schema", reason: "모델 절(schema)은 형식 \(IsoDataFormat.model) 부터다 — 이 파일은 형식 \(version)")
        }
        return .model(try DataModelCoding.decode(top))
    }

    // MARK: 쓰기

    /// 파일 → 바이트. 최소 판을 찍는다.
    public func encoded() throws -> Data {
        switch self {
        case .life(let life):
            var top = life.body
            top["version"] = .number(Double(writtenVersion))
            // 빌더의 `JSONEncoder.gitFriendly()`(prettyPrinted · sortedKeys) 와 같은 깃발 — 삶 파일은 빌더가 쓴 바이트와 같아야 한다.
            return try IsoDataFile.encoder(escapingSlashes: true).encode(JSONValue.object(top))
        case .model(let model):
            var top = DataModelCoding.encode(model)
            top["version"] = .number(Double(IsoDataFormat.model))
            // 모델 파일은 필드 `doc` 의 링크 · 경로가 diff 에서 읽히게 슬래시를 풀어 쓴다.
            return try IsoDataFile.encoder(escapingSlashes: false).encode(JSONValue.object(top))
        }
    }

    static func encoder(escapingSlashes: Bool) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = escapingSlashes ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

/// 삶 파일 — 판(`version`)을 뺀 최상위 그대로 + 읽은 판. 뜻(날짜 · 값 클램프 · id · 판 이관)은 빌더가 갖는다 —
/// 이 모듈은 이관하지 않으니 판 1 · 2 몸은 그 판 그대로 다시 찍는다(3 이상은 최소 판 3).
public struct LifeFile: Equatable, Sendable {
    public var body: [String: JSONValue]
    /// 읽은 판 — 새로 만든 삶 파일은 3.
    public var version: Int
    public init(body: [String: JSONValue], version: Int = IsoDataFormat.life) {
        self.body = body
        self.version = version
    }
}

/// 모델 파일 — 스키마 · 데이터셋 · 마지막 생성 사본.
public struct DataModelFile: Equatable, Sendable {
    public var schema: DataSchema
    /// 이름 → 벌. 이름은 화면 픽스처의 상태 이름과 같은 낱말(`seed` · `normal` · `empty` · `long` …).
    public var datasets: [String: DataSet] = [:]
    public var migrated: DataMigrated = DataMigrated()

    /// 읽을 때 잰 레코드 오류 — 파일에 쓰지 않는다. 창이 열 때 한 번 알린다(읽기 규율 ④).
    public var issues: [RecordIssue] = []
    /// 읽을 때 상한으로 자른 것 — 한 줄씩.
    public var cuts: [String] = []

    public init(schema: DataSchema, datasets: [String: DataSet] = [:], migrated: DataMigrated = DataMigrated()) {
        self.schema = schema
        self.datasets = datasets
        self.migrated = migrated
    }

    /// 파일이 담는 값만 맞댄다(읽을 때의 알림은 빼고).
    public static func == (a: DataModelFile, b: DataModelFile) -> Bool {
        a.schema == b.schema && a.datasets == b.datasets && a.migrated == b.migrated
    }

    /// 벌 이름의 차례 — 규약의 이름(`seed` → 화면 상태 셋 `normal` · `empty` · `long` — 화면 상태 낱말과 같은 차례) → 나머지 이름 차례.
    /// 이름 차례만 쓰면 `empty` · `long` · `normal` · `seed` 로 서서 명령의 설명 차례와 어긋난다.
    public static let datasetOrder = ["seed", "normal", "empty", "long"]

    public var datasetNames: [String] {
        datasets.keys.sorted { a, b in
            let ra = Self.datasetOrder.firstIndex(of: a) ?? Int.max, rb = Self.datasetOrder.firstIndex(of: b) ?? Int.max
            return ra != rb ? ra < rb : a < b
        }
    }
}

/// 레코드 한 행 — 필드 이름 → JSON 값(엔티티 꼴 · 뷰모델 꼴 아님).
public typealias DataRecord = [String: JSONValue]

/// 이름 붙은 레코드 벌.
public struct DataSet: Equatable, Sendable {
    public var label: String = ""
    public var clock: DataClock?
    /// 엔티티 이름 → 행(적힌 차례).
    public var records: [String: [DataRecord]] = [:]
    /// 엔티티 이름 → 다음에 내줄 번호(올라가기만 한다).
    public var nextIDs: [String: Int] = [:]
    /// 레코드에서 계산된 삶(포맷 3 의 `domain` · `eras` · `series` · `milestones` + `derived: true`) — 계산은 프로젝트의 코드(프로젝트 도구),
    /// 이 모듈은 나르기만 한다.
    public var life: [String: JSONValue]?

    public init(label: String = "", clock: DataClock? = nil, records: [String: [DataRecord]] = [:],
                nextIDs: [String: Int] = [:], life: [String: JSONValue]? = nil) {
        self.label = label
        self.clock = clock
        self.records = records
        self.nextIDs = nextIDs
        self.life = life
    }
}

/// 벌의 시계 — 파생이 무는 「지금」.
public struct DataClock: Equatable, Sendable {
    public var now: String
    public var tz: String
    public init(now: String, tz: String) { self.now = now; self.tz = tz }
}

/// 마지막으로 생성한 순간의 물리 사본(SQL 차이의 기준).
public struct DataMigrated: Equatable, Sendable {
    public var sql: SQLSnapshot?
    /// 프로젝트 앱 모델의 스키마 판 번호(마지막 Swift 생성 때).
    public var swiftSchemaVersion: Int?
    public init(sql: SQLSnapshot? = nil, swiftSchemaVersion: Int? = nil) {
        self.sql = sql
        self.swiftSchemaVersion = swiftSchemaVersion
    }
}
