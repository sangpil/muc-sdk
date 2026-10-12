import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). 저장 백엔드(스토어 · 동기화 · 생성물)의 뜻은 이 꼴에 없다 — 읽고 쓰는 쪽의 몫이다.
//
// 데이터 모델 파일의 스키마 — 층 · 엔티티 · 필드 · 형 · 규칙 · 공통 필드 묶음 · 값 타입. 값만 담는다(검증은 `SchemaValidation` · `CloudKitRules`,
// 읽고 쓰기는 `DataModelCoding`). 꼴마다 `extra` = 이 SDK 가 모르는 칸(읽은 그대로 들고 되쓴다 — 읽기 규율 ③).
// 낱말 칸(상태 · 삭제 규칙)은 열린 꼴이고 형 · 규칙은 모르는 갈래(`DataType.unknown` · `DataRuleCheck.other`)를 하나씩 든다 — 더 새 판의 낱말도 글자 그대로 읽고 쓴다.

/// 스키마 한 벌 — 모델 파일의 `schema`.
public struct DataSchema: Equatable, Sendable {
    /// 스키마 이름 — 결정적 UUID 의 이름공간 끝(`IsoDataIDs.uuid`).
    public var name: String
    /// 결정적 UUID 의 이름공간 머리(파일 키 `idNamespace`) — 선택 칸 · nil = SDK 의 기본(`IsoDataIDs.defaultNamespace`).
    /// 이미 앉은 행의 UUID 를 지키려는 스키마가 옛 머리를 적는다(바꾸면 모든 파생 UUID 가 바뀐다).
    public var idNamespace: String?
    /// 스키마 판(파일 키 `revision`) — 선택 칸 · 정수 1 이상. 같은 모델을 여럿이 무는 프로젝트(`SharedDataModel`)가 이 판으로 맞물린다
    /// (프로젝트가 채택한 판 ⟂ 모델의 판 — `SharedModelLockstep`). 앱 스키마 패키지의 판과 같은 수를 적는다.
    public var revision: Int?
    public var layers: [DataLayer] = []
    public var entities: [DataEntity] = []
    public var traits: [DataTrait] = []
    public var values: [DataValueType] = []
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]

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

    /// 엔티티의 필드 — 제 필드 뒤에 `uses` 차례대로 공통 필드 묶음의 필드를 펼친다(Swift · 레코드가 보는 꼴).
    public func expandedFields(of entity: DataEntity) -> [DataField] {
        var fields = entity.fields
        for use in entity.uses {
            if let trait = trait(use) { fields.append(contentsOf: trait.fields) }
        }
        return fields
    }

    /// `renamedFrom` 을 모두 걷은 스키마 — 이름 바꿈을 생성물에 반영한 뒤의 꼴.
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

/// 이름 낱말 규칙 — 코드 이름(PascalCase · camelCase)을 소문자 낱말로 가른다. 이름에서 무엇을 파생하는가(id 접두 · 생성물의 이름)는 쓰는 쪽이 정한다.
public enum DataNames {
    /// 이름 → 낱말(소문자) — `HarvestLogEntry` → harvest · log · entry · `hoursOfSun` → hours · of · sun · 대문자 묶음은 한 낱말(`URLPath` → url · path).
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
}

/// 층 — 사이드바 · 도식이 엔티티를 묶는 단위(id — `ground` · `shed` 같은 낱말 — 과 사람 말 라벨).
public struct DataLayer: Equatable, Sendable {
    public var id: String
    public var label: String
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(id: String, label: String) { self.id = id; self.label = label }
}

/// 구현 거리 — 스키마에 적은 것이 코드에 얼마나 섰는가. 열린 꼴: 아는 낱말 다섯(`known`) · 모르는 낱말은 글자 그대로 든다. 없음 = `live`.
public struct DataStatus: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let live = DataStatus(rawValue: "live")
    public static let seam = DataStatus(rawValue: "seam")
    public static let mock = DataStatus(rawValue: "mock")
    public static let unbuilt = DataStatus(rawValue: "unbuilt")
    public static let dropped = DataStatus(rawValue: "dropped")
    /// 이 SDK 가 아는 낱말 — 차례 그대로.
    public static let known: [DataStatus] = [.live, .seam, .mock, .unbuilt, .dropped]

    /// 물리(스토어 · 생성물)에 있어야 하는가 — `live` 만(모르는 낱말은 아니다).
    public var isPhysical: Bool { self == .live }
}

/// 보기(`lens`)별 별칭 — 한 엔티티를 보기마다 다른 낱말(`word`)로 부르는 행.
/// `doc` 은 그 낱말이 가리키는 실체의 설명(선택).
public struct DataAlias: Equatable, Sendable {
    public var lens: String
    public var word: String
    public var doc: String = ""
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(lens: String, word: String, doc: String = "") { self.lens = lens; self.word = word; self.doc = doc }
}

/// 엔티티 하나.
public struct DataEntity: Equatable, Sendable {
    /// 코드 이름 — PascalCase · 스키마 안 유일.
    public var name: String
    /// 사람 말 이름.
    public var label: String = ""
    public var layer: String?
    public var doc: String = ""
    public var aliases: [DataAlias] = []
    /// 공통 필드 묶음(`traits`) 이름들.
    public var uses: [String] = []
    /// Swift `@Model` 이름(파일 키 `swift.model`) — 없으면 `name`. 스토어 · 동기화의 레코드 종류 이름이 이것이다.
    public var swiftModel: String?
    /// 결정적 UUID 의 이름 칸(`<uuidName>/<id>` · `IsoDataIDs`) — 없으면 `name`. 엔티티 이름을 바꿀 때 도구가 옛 이름으로 고정해
    /// 행 UUID(씬 plot · 앱 스토어의 결합)가 이름을 따라 바뀌지 않게 한다.
    public var uuidName: String?
    public var status: DataStatus = .live
    /// `dropped` 의 결정 링크.
    public var dropNote: String = ""
    public var fields: [DataField] = []
    public var rules: [DataRule] = []
    /// 이 SDK 가 모르는 칸(아는 하위 객체 안의 모르는 칸은 그 키 아래 객체로 — `swift` 안의 새 칸이면 `extra["swift"]`).
    public var extra: [String: JSONValue] = [:]

    public init(name: String, label: String = "", layer: String? = nil, doc: String = "",
                aliases: [DataAlias] = [], uses: [String] = [], swiftModel: String? = nil,
                uuidName: String? = nil, status: DataStatus = .live, dropNote: String = "", fields: [DataField] = [], rules: [DataRule] = []) {
        self.name = name
        self.label = label
        self.layer = layer
        self.doc = doc
        self.aliases = aliases
        self.uses = uses
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
    /// Swift 속성 이름(파일 키 `swift.property`) — 없으면 `name`. 스토어 · 동기화의 칸 이름이 이것이다.
    public var swiftProperty: String?
    /// 이름을 바꾼 순간 도구가 적는 옛 이름 — 생성물이 이름 바꿈을 반영하고 걷는다.
    public var renamedFrom: String?
    /// 이 SDK 가 모르는 칸(아는 하위 객체 안의 모르는 칸은 그 키 아래 객체로).
    public var extra: [String: JSONValue] = [:]

    public init(name: String, type: DataType, optional: Bool = false, default: JSONValue? = nil, doc: String = "",
                status: DataStatus = .live, dropNote: String = "", swiftProperty: String? = nil, renamedFrom: String? = nil) {
        self.name = name
        self.type = type
        self.optional = optional
        self.default = `default`
        self.doc = doc
        self.status = status
        self.dropNote = dropNote
        self.swiftProperty = swiftProperty
        self.renamedFrom = renamedFrom
    }
}

/// 참조의 삭제 규칙 — 열린 꼴: 아는 낱말 셋(`known`) · 모르는 낱말은 글자 그대로 든다.
public struct DataOnDelete: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let setNull = DataOnDelete(rawValue: "setNull")
    public static let cascade = DataOnDelete(rawValue: "cascade")
    public static let restrict = DataOnDelete(rawValue: "restrict")
    /// 이 SDK 가 아는 낱말 — 차례 그대로.
    public static let known: [DataOnDelete] = [.setNull, .cascade, .restrict]
}

/// 형 — 아는 갈래 + 이 SDK 가 모르는 형 하나(`unknown` — 파일의 형 칸을 읽은 그대로 들고 그대로 쓴다 · 그 값은 재지 않는다).
public indirect enum DataType: Equatable, Sendable {
    case id, text, longText, int, decimal, money, bool, date, instant
    case enumeration([String])
    case ref(String, onDelete: DataOnDelete)
    case value(String)
    case list(DataType)
    /// 이 SDK 가 모르는 형 — 형 칸의 JSON 값 그대로(낱말 ⟂ 객체). 더 새 판의 형이다 — 읽는 쪽은 읽기 전용으로 다룬다.
    case unknown(JSONValue)

    /// 낱말 형의 이름 — 이 SDK 가 아는 낱말.
    public static let words: [String: DataType] = [
        "id": .id, "text": .text, "longText": .longText, "int": .int, "decimal": .decimal,
        "money": .money, "bool": .bool, "date": .date, "instant": .instant,
    ]

    public var refTarget: String? {
        if case .ref(let target, _) = self { return target }
        return nil
    }

    /// 이 형(목록 안 포함)에 이 SDK 가 모르는 갈래가 드는가.
    public var holdsUnknown: Bool {
        switch self {
        case .unknown: true
        case .list(let inner): inner.holdsUnknown
        default: false
        }
    }
}

/// 공통 필드 묶음 — 여러 엔티티에 같은 필드를 얹는 자리(예: 만든 때 · 고친 때를 적는 필드).
public struct DataTrait: Equatable, Sendable {
    public var name: String
    public var doc: String = ""
    public var fields: [DataField] = []
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(name: String, doc: String = "", fields: [DataField] = []) { self.name = name; self.doc = doc; self.fields = fields }
}

/// 값 타입 — 작은 구조체(길이 · 범위 …). 스토어에는 한 칸에 임베드된다.
public struct DataValueType: Equatable, Sendable {
    public var name: String
    public var doc: String = ""
    public var fields: [DataField] = []
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]
    public init(name: String, doc: String = "", fields: [DataField] = []) { self.name = name; self.doc = doc; self.fields = fields }
}

/// 규칙(불변식) — `check` 가 있으면 도구가 레코드마다 재고, 없으면 산문(문서에만).
public struct DataRule: Equatable, Sendable {
    public var id: String
    public var check: DataRuleCheck?
    public var doc: String = ""
    /// 식으로 적을 수 없는 규칙을 지키는 코드 자리(프로젝트 코드의 파일 · 테스트) — 식 대신 코드 위치만 적는 키.
    public var code: String?
    /// 이 SDK 가 모르는 칸(아는 `check` 꼴 안의 모르는 칸은 `extra["check"]` 아래 객체로).
    public var extra: [String: JSONValue] = [:]

    public init(id: String, check: DataRuleCheck? = nil, doc: String = "", code: String? = nil) {
        self.id = id
        self.check = check
        self.doc = doc
        self.code = code
    }
}

/// 규칙의 낱말 — 표현식 언어는 두지 않는다. 아는 갈래 넷 + 이 SDK 가 모르는 규칙 하나(`other` — 들고 되쓴다 · 재지 않는다).
public enum DataRuleCheck: Equatable, Sendable {
    /// `when` 의 조건이 맞으면(없으면 늘) 그 필드에 값이 있어야 한다.
    case required(field: String, when: [String: [JSONValue]])
    /// `when` 의 조건이 맞으면(없으면 늘) 그 필드에 값이 없어야 한다.
    case forbidden(field: String, when: [String: [JSONValue]])
    /// 이 필드들의 값 짝이 벌 안에서 유일하다.
    case unique([String])
    /// `field` 는 `via` 가 가리키는 값과 같다 — `via` = `"<참조 필드>.<대상 필드>"`(예: `plantId.potId`).
    case sameAs(field: String, via: String)
    /// 이 SDK 가 모르는 규칙 — 낱말(`check` 객체의 키 차례 첫 키)과 `check` 객체 통째.
    case other(kind: String, body: [String: JSONValue])

    /// 규칙의 낱말 — `required` · `forbidden` · `unique` · `sameAs` · 모르는 규칙은 그 낱말.
    public var word: String {
        switch self {
        case .required: "required"
        case .forbidden: "forbidden"
        case .unique: "unique"
        case .sameAs: "sameAs"
        case .other(let kind, _): kind
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
