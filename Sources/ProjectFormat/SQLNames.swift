import Foundation

// 모델 파일의 SQL 절 꼴(`migrated.sql` 의 테이블 → 열) · 이름 규칙 — 스키마 읽기 규율(`SchemaValidation` — 테이블 · 열 이름이 서는가)과
// 모델 파일 읽기(`DataModelCoding` — `migrated` 절)가 문다. 투영(스키마 → 사본) · SQL 글자(열 정의 · 예약어 인용) · 차이 · 생성은 엔진의 데이터 도구가 갖는다
// (`SQLProjection` 의 확장 · 차이 · 생성).

/// 마지막 생성 순간의 사본(`migrated.sql`) 또는 지금 스키마의 투영.
public struct SQLSnapshot: Equatable, Sendable {
    public var tables: [SQLTable] = []
    public init(tables: [SQLTable] = []) { self.tables = tables }
    public func table(_ name: String) -> SQLTable? { tables.first { $0.name == name } }

    /// 파일에 쓰는 꼴과 같게 — 이름 차례 · 이름 표시(`renamedFrom`) 없이.
    public var stored: SQLSnapshot {
        SQLSnapshot(tables: tables.sorted { $0.name < $1.name }.map { t in
            SQLTable(name: t.name, columns: t.columns.sorted { $0.name < $1.name }.map { var c = $0; c.renamedFrom = nil; c.referencedColumn = nil; return c })
        })
    }
}

public struct SQLTable: Equatable, Sendable {
    public var name: String
    /// 투영에서는 스키마 차례(정체 먼저), 사본에서는 이름 차례.
    public var columns: [SQLColumn] = []
    public init(name: String, columns: [SQLColumn] = []) { self.name = name; self.columns = columns }
    public func column(_ name: String) -> SQLColumn? { columns.first { $0.name == name } }
}

public struct SQLColumn: Equatable, Sendable {
    public var name: String
    /// `text` · `integer` · `numeric` · `boolean` · `date` · `timestamptz` · `jsonb`.
    public var type: String
    public var notNull: Bool = false
    public var primaryKey: Bool = false
    /// SQL 글자 그대로의 기본값(`'draft'` · `0` · `true`).
    public var `default`: String?
    /// 참조 대상 테이블.
    public var references: String?
    /// `set null` · `cascade` · `restrict`.
    public var onDelete: String?
    /// 열거 값 — `check (열 in (…))`.
    public var check: [String]?
    /// 투영에만 — 필드의 `renamedFrom` 이 가리키는 옛 열 이름(사본에는 쓰지 않는다).
    public var renamedFrom: String?
    /// 투영에만 — 참조 대상 테이블의 정체 열(대상 id 필드의 열 이름). 없으면 `id`.
    public var referencedColumn: String?
    /// 사본에만 — 파괴적 변경(이 열 · 이 열의 테이블 지우기)을 한 번 생성으로 냈고 사람 적용을 기다린다. 다음 생성이 걷는다.
    public var dropPending: Bool = false

    public init(name: String, type: String, notNull: Bool = false, primaryKey: Bool = false, default: String? = nil,
                references: String? = nil, onDelete: String? = nil, check: [String]? = nil, renamedFrom: String? = nil,
                referencedColumn: String? = nil, dropPending: Bool = false) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.primaryKey = primaryKey
        self.default = `default`
        self.references = references
        self.onDelete = onDelete
        self.check = check
        self.renamedFrom = renamedFrom
        self.referencedColumn = referencedColumn
        self.dropPending = dropPending
    }
}

/// SQL 이름 규칙 — 테이블 · 열 이름의 파생(snake_case)과 식별자 규칙. 투영 · 글자는 엔진이 이 열거에 확장으로 얹는다.
public enum SQLProjection {
    public static func tableName(_ e: DataEntity) -> String { e.sqlTable ?? snake(e.name) }

    public static func columnName(_ f: DataField) -> String { f.sqlColumn ?? snake(f.name) }

    /// 이름 → 낱말(소문자) — `HarvestLogEntry` → harvest · log · entry · `hoursOfSun` → hours · of · sun.
    public static func words(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(name)
        for (i, ch) in chars.enumerated() {
            let upper = ch.isUppercase
            let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
            let prevLower = i > 0 && (chars[i - 1].isLowercase || chars[i - 1].isNumber)
            if upper, !current.isEmpty, prevLower || nextLower {
                words.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    public static func snake(_ name: String) -> String { words(name).joined(separator: "_") }

    /// SQL 이름 규칙 — 소문자 · 숫자 · 밑줄, 글자나 밑줄로 시작, 63자 이하(PostgreSQL 식별자 한도).
    public static func isValidIdentifier(_ name: String) -> Bool {
        name.range(of: #"^[a-z_][a-z0-9_]{0,62}$"#, options: .regularExpression) != nil
    }

    /// 생성기가 모든 새 테이블에 붙이는 소유 열 — 필드 열이 이 이름이면 겹친다.
    public static let ownerColumn = "user_id"
}
