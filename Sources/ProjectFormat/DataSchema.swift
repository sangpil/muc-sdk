import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). SQL 투영 · 생성 · 울타리는 엔진의 몫이다.
//
// 데이터 모델 파일의 스키마 — 층 · 엔티티 · 필드 · 형 · 규칙 · 공통 필드 묶음 · 값 타입.
// 엔티티 · 필드 · 형 · 관계 · 상태 · 규칙 · 공통 필드 묶음 · 값 타입. 값만 담는다(검증은 `SchemaValidation`, 읽고 쓰기는 `DataModelCoding`).

/// 스키마 한 벌 — 모델 파일의 `schema`.
public struct DataSchema: Equatable, Sendable {
    /// 스키마 이름 — 결정적 UUID 의 이름공간(`IsoDataIDs.uuid`).
    public var name: String
    public var layers: [DataLayer] = []
    public var entities: [DataEntity] = []
    public var traits: [DataTrait] = []
    public var values: [DataValueType] = []

    public init(name: String, layers: [DataLayer] = [], entities: [DataEntity] = [],
                traits: [DataTrait] = [], values: [DataValueType] = []) {
        self.name = name
        self.layers = layers
        self.entities = entities
        self.traits = traits
        self.values = values
    }

    public func entity(_ name: String) -> DataEntity? { entities.first { $0.name == name } }
    public func trait(_ name: String) -> DataTrait? { traits.first { $0.name == name } }
    public func valueType(_ name: String) -> DataValueType? { values.first { $0.name == name } }

    /// 엔티티의 필드 — 제 필드 뒤에 `uses` 차례대로 공통 필드 묶음의 필드를 펼친다(SQL · Swift · 레코드가 보는 꼴).
    public func expandedFields(of entity: DataEntity) -> [DataField] {
        var fields = entity.fields
        for use in entity.uses {
            if let trait = trait(use) { fields.append(contentsOf: trait.fields) }
        }
        return fields
    }

    /// `renamedFrom` 을 모두 걷은 스키마 — SQL 생성이 `migrated.sql` 을 올린 순간의 꼴(생성하면 `migrated.sql` 이 이 꼴로 갱신된다).
    public func clearingRenames() -> DataSchema {
        var schema = self
        for e in schema.entities.indices {
            for f in schema.entities[e].fields.indices { schema.entities[e].fields[f].renamedFrom = nil }
        }
        for t in schema.traits.indices {
            for f in schema.traits[t].fields.indices { schema.traits[t].fields[f].renamedFrom = nil }
        }
        return schema
    }
}

/// 층 — 사이드바 · 도식이 엔티티를 묶는 단위(id — `ground` · `shed` 같은 낱말 — 과 사람 말 라벨).
public struct DataLayer: Equatable, Sendable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

/// 구현 거리 — 스키마에 적은 것이 코드에 얼마나 섰는가를 닫힌 낱말 다섯으로 적는다. 없음 = `live`.
public enum DataStatus: String, CaseIterable, Equatable, Sendable {
    case live, seam, mock, unbuilt, dropped

    /// 물리(SQL · Swift) 에 있어야 하는가 — `live` 만.
    public var isPhysical: Bool { self == .live }

    /// 창 · 문서에 서는 한국어 이름.
    public var label: String {
        switch self {
        case .live: "실재"
        case .seam: "예약"
        case .mock: "목업"
        case .unbuilt: "미구현"
        case .dropped: "폐기"
        }
    }
}

/// 보기(`lens`)별 별칭 — 한 엔티티를 보기마다 다른 낱말(`word`)로 부르는 행.
/// `doc` 은 그 낱말이 가리키는 실체의 설명(선택).
public struct DataAlias: Equatable, Sendable {
    public var lens: String
    public var word: String
    public var doc: String = ""
    public init(lens: String, word: String, doc: String = "") { self.lens = lens; self.word = word; self.doc = doc }
}

/// 엔티티 하나.
public struct DataEntity: Equatable, Sendable {
    /// 코드 이름 — PascalCase · 스키마 안 유일.
    public var name: String
    /// 한국어 이름.
    public var label: String = ""
    public var layer: String?
    public var doc: String = ""
    public var aliases: [DataAlias] = []
    /// 공통 필드 묶음(`traits`) 이름들.
    public var uses: [String] = []
    /// SQL 테이블 이름 — 없으면 이름의 snake_case(`SQLProjection.tableName`).
    public var sqlTable: String?
    /// Swift `@Model` 이름 — 없으면 `name`.
    public var swiftModel: String?
    /// 결정적 UUID 의 이름 칸(`<uuidName>/<id>` · `IsoDataIDs`) — 없으면 `name`. 엔티티 이름을 바꿀 때 도구가 옛 이름으로 고정해
    /// 행 UUID(씬 plot · 앱 스토어의 결합)가 이름을 따라 바뀌지 않게 한다.
    public var uuidName: String?
    public var status: DataStatus = .live
    /// `dropped` 의 결정 링크.
    public var dropNote: String = ""
    public var fields: [DataField] = []
    public var rules: [DataRule] = []

    public init(name: String, label: String = "", layer: String? = nil, doc: String = "",
                aliases: [DataAlias] = [], uses: [String] = [], sqlTable: String? = nil, swiftModel: String? = nil,
                uuidName: String? = nil, status: DataStatus = .live, dropNote: String = "", fields: [DataField] = [], rules: [DataRule] = []) {
        self.name = name
        self.label = label
        self.layer = layer
        self.doc = doc
        self.aliases = aliases
        self.uses = uses
        self.sqlTable = sqlTable
        self.swiftModel = swiftModel
        self.uuidName = uuidName
        self.status = status
        self.dropNote = dropNote
        self.fields = fields
        self.rules = rules
    }

    public func field(_ name: String) -> DataField? { fields.first { $0.name == name } }

    /// 결정적 UUID 가 무는 이름 — `uuidName` · 없으면 `name`.
    public var uuidKey: String { uuidName ?? name }
}

/// 필드 하나.
public struct DataField: Equatable, Sendable {
    /// camelCase · 엔티티 안 유일.
    public var name: String
    public var type: DataType
    public var optional: Bool = false
    /// 기본값 — 레코드 값과 같은 JSON 꼴.
    public var `default`: JSONValue?
    public var doc: String = ""
    public var status: DataStatus = .live
    public var dropNote: String = ""
    /// SQL 열 이름 — 없으면 이름의 snake_case.
    public var sqlColumn: String?
    /// Swift 속성 이름 — 없으면 `name`.
    public var swiftProperty: String?
    /// 이름을 바꾼 순간 도구가 적는 옛 이름 — SQL 생성이 읽고 걷는다.
    public var renamedFrom: String?

    public init(name: String, type: DataType, optional: Bool = false, default: JSONValue? = nil, doc: String = "",
                status: DataStatus = .live, dropNote: String = "", sqlColumn: String? = nil,
                swiftProperty: String? = nil, renamedFrom: String? = nil) {
        self.name = name
        self.type = type
        self.optional = optional
        self.default = `default`
        self.doc = doc
        self.status = status
        self.dropNote = dropNote
        self.sqlColumn = sqlColumn
        self.swiftProperty = swiftProperty
        self.renamedFrom = renamedFrom
    }
}

/// 참조의 삭제 규칙.
public enum DataOnDelete: String, CaseIterable, Equatable, Sendable {
    case setNull, cascade, restrict

    public var sql: String {
        switch self {
        case .setNull: "set null"
        case .cascade: "cascade"
        case .restrict: "restrict"
        }
    }
}

/// 형 — 닫힌 낱말(아래 갈래가 전부다).
public indirect enum DataType: Equatable, Sendable {
    case id, text, longText, int, decimal, money, bool, date, instant
    case enumeration([String])
    case ref(String, onDelete: DataOnDelete)
    case value(String)
    case list(DataType)

    /// 낱말 형의 이름 — 모르는 낱말을 거부하는 닫힌 목록.
    public static let words: [String: DataType] = [
        "id": .id, "text": .text, "longText": .longText, "int": .int, "decimal": .decimal,
        "money": .money, "bool": .bool, "date": .date, "instant": .instant,
    ]

    /// 창의 형 팝업 · 오류 글에 서는 한국어 이름.
    public var label: String {
        switch self {
        case .id: "정체"
        case .text: "글"
        case .longText: "긴 글"
        case .int: "정수"
        case .decimal: "소수"
        case .money: "돈"
        case .bool: "참거짓"
        case .date: "날짜"
        case .instant: "시각"
        case .enumeration: "열거"
        case .ref: "참조"
        case .value: "값 타입"
        case .list: "목록"
        }
    }

    public var refTarget: String? {
        if case .ref(let target, _) = self { return target }
        return nil
    }
}

/// 공통 필드 묶음 — 여러 엔티티에 같은 필드를 얹는 자리(예: 만든 때 · 고친 때를 적는 필드).
public struct DataTrait: Equatable, Sendable {
    public var name: String
    public var doc: String = ""
    public var fields: [DataField] = []
    public init(name: String, doc: String = "", fields: [DataField] = []) { self.name = name; self.doc = doc; self.fields = fields }
}

/// 값 타입 — 작은 구조체(길이 · 범위 …). SQL 은 jsonb, Swift 는 Codable 임베드.
public struct DataValueType: Equatable, Sendable {
    public var name: String
    public var doc: String = ""
    public var fields: [DataField] = []
    public init(name: String, doc: String = "", fields: [DataField] = []) { self.name = name; self.doc = doc; self.fields = fields }
}

/// 규칙(불변식) — `check` 가 있으면 도구가 레코드마다 재고, 없으면 산문(문서에만).
public struct DataRule: Equatable, Sendable {
    public var id: String
    public var check: DataRuleCheck?
    public var doc: String = ""
    /// 식으로 적을 수 없는 규칙을 지키는 코드 자리(프로젝트 코드의 파일 · 테스트) — 식 대신 코드 위치만 적는 키.
    public var code: String?

    public init(id: String, check: DataRuleCheck? = nil, doc: String = "", code: String? = nil) {
        self.id = id
        self.check = check
        self.doc = doc
        self.code = code
    }
}

/// 규칙의 닫힌 낱말 — 표현식 언어는 두지 않는다.
public enum DataRuleCheck: Equatable, Sendable {
    /// `when` 의 조건이 맞으면(없으면 늘) 그 필드에 값이 있어야 한다.
    case required(field: String, when: [String: [JSONValue]])
    /// `when` 의 조건이 맞으면(없으면 늘) 그 필드에 값이 없어야 한다.
    case forbidden(field: String, when: [String: [JSONValue]])
    /// 이 필드들의 값 짝이 벌 안에서 유일하다.
    case unique([String])
    /// `field` 는 `via` 가 가리키는 값과 같다 — `via` = `"<참조 필드>.<대상 필드>"`(예: `plantId.potId`).
    case sameAs(field: String, via: String)

    /// 창 검사관의 요약 한 줄.
    public var summary: String {
        func condition(_ when: [String: [JSONValue]]) -> String {
            guard !when.isEmpty else { return "" }
            let parts = when.keys.sorted().map { key in
                "\(key) ∈ \(when[key]!.map { $0.plain }.joined(separator: "·"))"
            }
            return " (" + parts.joined(separator: ", ") + " 일 때)"
        }
        switch self {
        case .required(let field, let when): return "\(field) 필수" + condition(when)
        case .forbidden(let field, let when): return "\(field) 금지" + condition(when)
        case .unique(let fields): return fields.joined(separator: " · ") + " 유일"
        case .sameAs(let field, let via): return "\(field) = \(via)"
        }
    }
}

extension JSONValue {
    /// 글에 서는 값 — 문자열은 따옴표 없이.
    var plain: String {
        switch self {
        case .string(let s): return s
        case .null: return "null"
        default: return text(pretty: false)
        }
    }

    var isNull: Bool { if case .null = self { return true } else { return false } }
}
