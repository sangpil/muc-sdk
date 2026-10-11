import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). SQL 투영 · 생성 · 울타리는 엔진의 몫이다.
//
// 모델 파일 ⟷ JSON 값. 읽기 규율(다른 파일의 주석이 이 번호로 가리킨다):
//   ① 판을 먼저 읽는다 — 미래 판은 이름 대고 거부(`IsoDataFile.read`).
//   ② 스키마가 먼저 선다 — 틀리면 경로를 대고 파일 전체를 거부(`SchemaValidation`).
//   ③ 모델 파일 안의 모르는 키는 거부한다 — 더 새 판의 흔적이고, 저장하면 사라진다.
//   ④ 레코드 오류는 파일을 거부하지 않는다 — 행 단위로 `issues` 에 싣는다(`RecordValidation`).
// 쓰기: 빈 `doc` · 빈 `aliases` · 기본값인 칸은 키 자체를 쓰지 않는다(빈 칸은 없는 칸과 같다).

enum DataModelCoding {

    // MARK: 읽기

    static func decode(_ top: [String: JSONValue]) throws -> DataModelFile {
        var r = Reader(top, path: "")
        try r.allow(["schema", "datasets", "migrated"])
        let schema = try decodeSchema(r.object("schema"))
        try SchemaValidation.require(schema)
        var file = DataModelFile(schema: schema)
        if let datasets = try r.optionalObject("datasets") {
            for name in datasets.fields.keys.sorted() {
                file.datasets[name] = try decodeDataset(datasets.child(name))
            }
        }
        if let migrated = try r.optionalObject("migrated") {
            file.migrated = try decodeMigrated(migrated)
        }
        let held = RecordValidation.hold(file)
        file = held.file
        file.cuts = held.cuts
        file.issues = RecordValidation.validate(file)
        return file
    }

    static func decodeSchema(_ r: Reader) throws -> DataSchema {
        var r = r
        try r.allow(["name", "layers", "entities", "traits", "values"])
        var schema = DataSchema(name: try r.string("name"))
        for var l in try r.optionalArray("layers") ?? [] {
            try l.allow(["id", "label"])
            schema.layers.append(DataLayer(id: try l.string("id"), label: try l.optionalString("label") ?? ""))
        }
        for e in try r.optionalArray("entities") ?? [] { schema.entities.append(try decodeEntity(e)) }
        for var t in try r.optionalArray("traits") ?? [] {
            try t.allow(["name", "doc", "fields"])
            schema.traits.append(DataTrait(name: try t.string("name"), doc: try t.optionalString("doc") ?? "",
                                           fields: try (t.optionalArray("fields") ?? []).map(decodeField)))
        }
        for var v in try r.optionalArray("values") ?? [] {
            try v.allow(["name", "doc", "fields"])
            schema.values.append(DataValueType(name: try v.string("name"), doc: try v.optionalString("doc") ?? "",
                                               fields: try (v.optionalArray("fields") ?? []).map(decodeField)))
        }
        return schema
    }

    static func decodeEntity(_ r: Reader) throws -> DataEntity {
        var r = r
        try r.allow(["name", "label", "layer", "doc", "aliases", "uses", "sql", "swift", "uuidName", "status", "dropNote", "fields", "rules"])
        var e = DataEntity(name: try r.string("name"))
        e.label = try r.optionalString("label") ?? ""
        e.layer = try r.optionalString("layer")
        e.doc = try r.optionalString("doc") ?? ""
        for var a in try r.optionalArray("aliases") ?? [] {
            try a.allow(["lens", "word", "doc"])
            e.aliases.append(DataAlias(lens: try a.string("lens"), word: try a.string("word"), doc: try a.optionalString("doc") ?? ""))
        }
        e.uses = try r.optionalStrings("uses") ?? []
        if var sql = try r.optionalObject("sql") {
            try sql.allow(["table"])
            e.sqlTable = try sql.optionalString("table")
        }
        if var swift = try r.optionalObject("swift") {
            try swift.allow(["model"])
            e.swiftModel = try swift.optionalString("model")
        }
        e.uuidName = try r.optionalString("uuidName")
        e.status = try decodeStatus(r)
        e.dropNote = try r.optionalString("dropNote") ?? ""
        e.fields = try (r.optionalArray("fields") ?? []).map(decodeField)
        e.rules = try (r.optionalArray("rules") ?? []).map(decodeRule)
        return e
    }

    static func decodeStatus(_ r: Reader) throws -> DataStatus {
        guard let word = try r.optionalString("status") else { return .live }
        guard let status = DataStatus(rawValue: word) else {
            throw r.error("status", "모르는 상태 ‘\(word)’ — live · seam · mock · unbuilt · dropped 중 하나")
        }
        return status
    }

    static func decodeField(_ r: Reader) throws -> DataField {
        var r = r
        try r.allow(["name", "type", "optional", "default", "doc", "status", "dropNote", "sql", "swift", "renamedFrom"])
        let name = try r.string("name")
        var f = DataField(name: name, type: try decodeType(r.value("type"), path: r.path + ".type", field: name))
        f.optional = try r.optionalBool("optional") ?? false
        f.default = r.fields["default"]
        f.doc = try r.optionalString("doc") ?? ""
        f.status = try decodeStatus(r)
        f.dropNote = try r.optionalString("dropNote") ?? ""
        if var sql = try r.optionalObject("sql") {
            try sql.allow(["column"])
            f.sqlColumn = try sql.optionalString("column")
        }
        if var swift = try r.optionalObject("swift") {
            try swift.allow(["property"])
            f.swiftProperty = try swift.optionalString("property")
        }
        f.renamedFrom = try r.optionalString("renamedFrom")
        return f
    }

    /// 형 — 닫힌 낱말. 모르는 낱말은 필드 이름을 대고 거부한다.
    static func decodeType(_ value: JSONValue, path: String, field: String) throws -> DataType {
        switch value {
        case .string(let word):
            guard let type = DataType.words[word] else {
                throw IsoDataError.invalid(path: path, reason: "필드 ‘\(field)’ 의 형 ‘\(word)’ 을 모른다")
            }
            return type
        case .object(let o):
            var r = Reader(o, path: path)
            if o["enum"] != nil {
                try r.allow(["enum"])
                guard let values = try r.optionalStrings("enum") else { throw r.error("enum", "열거 값 목록이 없다") }
                return .enumeration(values)
            }
            if o["ref"] != nil {
                try r.allow(["ref", "onDelete"])
                let word = try r.optionalString("onDelete") ?? DataOnDelete.setNull.rawValue
                guard let onDelete = DataOnDelete(rawValue: word) else {
                    throw r.error("onDelete", "삭제 규칙 ‘\(word)’ 을 모른다 — setNull · cascade · restrict 중 하나")
                }
                return .ref(try r.string("ref"), onDelete: onDelete)
            }
            if o["value"] != nil {
                try r.allow(["value"])
                return .value(try r.string("value"))
            }
            if let inner = o["list"] {
                try r.allow(["list"])
                return .list(try decodeType(inner, path: path + ".list", field: field))
            }
            throw IsoDataError.invalid(path: path, reason: "필드 ‘\(field)’ 의 형 객체는 enum · ref · value · list 중 하나다")
        default:
            throw IsoDataError.invalid(path: path, reason: "필드 ‘\(field)’ 의 형은 낱말 또는 객체다")
        }
    }

    static func decodeRule(_ r: Reader) throws -> DataRule {
        var r = r
        try r.allow(["id", "check", "doc", "code"])
        var rule = DataRule(id: try r.string("id"))
        rule.doc = try r.optionalString("doc") ?? ""
        rule.code = try r.optionalString("code")
        if var c = try r.optionalObject("check") {
            func when() throws -> [String: [JSONValue]] {
                guard let w = try c.optionalObject("when") else { return [:] }
                var out: [String: [JSONValue]] = [:]
                for key in w.fields.keys {
                    guard case .array(let values) = w.fields[key]! else { throw w.error(key, "조건 값은 배열이다") }
                    out[key] = values
                }
                return out
            }
            if c.fields["required"] != nil {
                try c.allow(["required", "when"])
                rule.check = .required(field: try c.string("required"), when: try when())
            } else if c.fields["forbidden"] != nil {
                try c.allow(["forbidden", "when"])
                rule.check = .forbidden(field: try c.string("forbidden"), when: try when())
            } else if c.fields["unique"] != nil {
                try c.allow(["unique"])
                rule.check = .unique(try c.optionalStrings("unique") ?? [])
            } else if c.fields["sameAs"] != nil {
                try c.allow(["sameAs"])
                var s = try c.object("sameAs")
                try s.allow(["field", "via"])
                rule.check = .sameAs(field: try s.string("field"), via: try s.string("via"))
            } else {
                throw c.error("", "규칙 낱말은 required · forbidden · unique · sameAs 중 하나다")
            }
        }
        return rule
    }

    static func decodeDataset(_ r: Reader) throws -> DataSet {
        var r = r
        try r.allow(["label", "clock", "records", "nextIDs", "life"])
        var set = DataSet(label: try r.optionalString("label") ?? "")
        if var clock = try r.optionalObject("clock") {
            try clock.allow(["now", "tz"])
            set.clock = DataClock(now: try clock.string("now"), tz: try clock.string("tz"))
        }
        if let records = try r.optionalObject("records") {
            for entity in records.fields.keys {
                guard case .array(let rows) = records.fields[entity]! else {
                    throw records.error(entity, "레코드는 행의 배열이다")
                }
                var out: [DataRecord] = []
                for (i, row) in rows.enumerated() {
                    guard case .object(let o) = row else {
                        throw IsoDataError.invalid(path: "\(records.path).\(entity)[\(i)]", reason: "행은 객체다")
                    }
                    out.append(o)
                }
                set.records[entity] = out
            }
        }
        if let next = try r.optionalObject("nextIDs") {
            for key in next.fields.keys {
                guard case .number(let n) = next.fields[key]!, n >= 1, let i = Int(exactly: n) else {
                    throw next.error(key, "다음 번호는 1 이상의 정수다")
                }
                set.nextIDs[key] = i
            }
        }
        if let life = try r.optionalObject("life") {
            // 삶 블록의 뜻은 빌더 · 프로젝트 코드의 것 — 여기서는 최상위 키만 닫는다(모르는 키 거부 · 읽기 규율 ③).
            //   키는 모두 선택이다 — 빈 칸은 키째 없을 수 있다(`forks` 가 그렇다).
            var l = life
            try l.allow(["derived", "domain", "eras", "series", "milestones", "forks", "nextIDs"])
            set.life = life.fields
        }
        return set
    }

    static func decodeMigrated(_ r: Reader) throws -> DataMigrated {
        var r = r
        try r.allow(["sql", "swift"])
        var m = DataMigrated()
        if var sql = try r.optionalObject("sql") {
            try sql.allow(["tables"])
            var snapshot = SQLSnapshot()
            if let tables = try sql.optionalObject("tables") {
                for table in tables.fields.keys.sorted() {
                    var t = SQLTable(name: table)
                    let columns = try tables.object(table)
                    for column in columns.fields.keys.sorted() {
                        t.columns.append(try decodeColumn(column, columns.fields[column]!, path: "\(columns.path).\(column)"))
                    }
                    snapshot.tables.append(t)
                }
            }
            m.sql = snapshot
        }
        if var swift = try r.optionalObject("swift") {
            try swift.allow(["schemaVersion"])
            m.swiftSchemaVersion = try swift.optionalInt("schemaVersion")
        }
        return m
    }

    /// 열 사본 — `{ type, notNull?, primaryKey?, default?, references?, onDelete?, check?, dropPending? }`. 형 글자 하나(`"text"`)는 널 허용 열의 줄임.
    static func decodeColumn(_ name: String, _ value: JSONValue, path: String) throws -> SQLColumn {
        if case .string(let type) = value { return SQLColumn(name: name, type: type) }
        guard case .object(let o) = value else { throw IsoDataError.invalid(path: path, reason: "열 사본은 형 글자 또는 객체다") }
        var r = Reader(o, path: path)
        try r.allow(["type", "notNull", "primaryKey", "default", "references", "onDelete", "check", "dropPending"])
        var c = SQLColumn(name: name, type: try r.string("type"))
        c.notNull = try r.optionalBool("notNull") ?? false
        c.primaryKey = try r.optionalBool("primaryKey") ?? false
        c.default = try r.optionalString("default")
        c.references = try r.optionalString("references")
        c.onDelete = try r.optionalString("onDelete")
        c.check = try r.optionalStrings("check")
        c.dropPending = try r.optionalBool("dropPending") ?? false
        return c
    }

    // MARK: 쓰기

    static func encode(_ file: DataModelFile) -> [String: JSONValue] {
        var top: [String: JSONValue] = ["schema": .object(encodeSchema(file.schema))]
        if !file.datasets.isEmpty {
            top["datasets"] = .object(file.datasets.mapValues { .object(encodeDataset($0)) })
        }
        var migrated: [String: JSONValue] = [:]
        if let sql = file.migrated.sql {
            var tables: [String: JSONValue] = [:]
            for t in sql.tables {
                tables[t.name] = .object(Dictionary(uniqueKeysWithValues: t.columns.map { ($0.name, encodeColumn($0)) }))
            }
            migrated["sql"] = .object(["tables": .object(tables)])
        }
        if let v = file.migrated.swiftSchemaVersion {
            migrated["swift"] = .object(["schemaVersion": .number(Double(v))])
        }
        if !migrated.isEmpty { top["migrated"] = .object(migrated) }
        return top
    }

    static func encodeSchema(_ s: DataSchema) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["name": .string(s.name)]
        if !s.layers.isEmpty {
            o["layers"] = .array(s.layers.map { l in
                var lo: [String: JSONValue] = ["id": .string(l.id)]
                if !l.label.isEmpty { lo["label"] = .string(l.label) }
                return .object(lo)
            })
        }
        if !s.entities.isEmpty { o["entities"] = .array(s.entities.map { .object(encodeEntity($0)) }) }
        if !s.traits.isEmpty {
            o["traits"] = .array(s.traits.map { t in
                var to: [String: JSONValue] = ["name": .string(t.name)]
                if !t.doc.isEmpty { to["doc"] = .string(t.doc) }
                if !t.fields.isEmpty { to["fields"] = .array(t.fields.map { .object(encodeField($0)) }) }
                return .object(to)
            })
        }
        if !s.values.isEmpty {
            o["values"] = .array(s.values.map { v in
                var vo: [String: JSONValue] = ["name": .string(v.name)]
                if !v.doc.isEmpty { vo["doc"] = .string(v.doc) }
                if !v.fields.isEmpty { vo["fields"] = .array(v.fields.map { .object(encodeField($0)) }) }
                return .object(vo)
            })
        }
        return o
    }

    static func encodeEntity(_ e: DataEntity) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["name": .string(e.name)]
        if !e.label.isEmpty { o["label"] = .string(e.label) }
        if let layer = e.layer { o["layer"] = .string(layer) }
        if !e.doc.isEmpty { o["doc"] = .string(e.doc) }
        if !e.aliases.isEmpty {
            o["aliases"] = .array(e.aliases.map { a in
                var ao: [String: JSONValue] = ["lens": .string(a.lens), "word": .string(a.word)]
                if !a.doc.isEmpty { ao["doc"] = .string(a.doc) }
                return .object(ao)
            })
        }
        if !e.uses.isEmpty { o["uses"] = .array(e.uses.map { .string($0) }) }
        if let t = e.sqlTable { o["sql"] = .object(["table": .string(t)]) }
        if let m = e.swiftModel { o["swift"] = .object(["model": .string(m)]) }
        if let u = e.uuidName { o["uuidName"] = .string(u) }
        if e.status != .live { o["status"] = .string(e.status.rawValue) }
        if !e.dropNote.isEmpty { o["dropNote"] = .string(e.dropNote) }
        if !e.fields.isEmpty { o["fields"] = .array(e.fields.map { .object(encodeField($0)) }) }
        if !e.rules.isEmpty { o["rules"] = .array(e.rules.map { .object(encodeRule($0)) }) }
        return o
    }

    static func encodeField(_ f: DataField) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["name": .string(f.name), "type": encodeType(f.type)]
        if f.optional { o["optional"] = .bool(true) }
        if let d = f.default { o["default"] = d }
        if !f.doc.isEmpty { o["doc"] = .string(f.doc) }
        if f.status != .live { o["status"] = .string(f.status.rawValue) }
        if !f.dropNote.isEmpty { o["dropNote"] = .string(f.dropNote) }
        if let c = f.sqlColumn { o["sql"] = .object(["column": .string(c)]) }
        if let p = f.swiftProperty { o["swift"] = .object(["property": .string(p)]) }
        if let r = f.renamedFrom { o["renamedFrom"] = .string(r) }
        return o
    }

    static func encodeType(_ t: DataType) -> JSONValue {
        switch t {
        case .id: "id"
        case .text: "text"
        case .longText: "longText"
        case .int: "int"
        case .decimal: "decimal"
        case .money: "money"
        case .bool: "bool"
        case .date: "date"
        case .instant: "instant"
        case .enumeration(let values): .object(["enum": .array(values.map { .string($0) })])
        case .ref(let target, let onDelete): .object(["ref": .string(target), "onDelete": .string(onDelete.rawValue)])
        case .value(let name): .object(["value": .string(name)])
        case .list(let inner): .object(["list": encodeType(inner)])
        }
    }

    static func encodeRule(_ r: DataRule) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["id": .string(r.id)]
        if !r.doc.isEmpty { o["doc"] = .string(r.doc) }
        if let code = r.code { o["code"] = .string(code) }
        func when(_ w: [String: [JSONValue]]) -> JSONValue { .object(w.mapValues { .array($0) }) }
        switch r.check {
        case nil: break
        case .required(let field, let w)?:
            var c: [String: JSONValue] = ["required": .string(field)]
            if !w.isEmpty { c["when"] = when(w) }
            o["check"] = .object(c)
        case .forbidden(let field, let w)?:
            var c: [String: JSONValue] = ["forbidden": .string(field)]
            if !w.isEmpty { c["when"] = when(w) }
            o["check"] = .object(c)
        case .unique(let fields)?:
            o["check"] = .object(["unique": .array(fields.map { .string($0) })])
        case .sameAs(let field, let via)?:
            o["check"] = .object(["sameAs": .object(["field": .string(field), "via": .string(via)])])
        }
        return o
    }

    static func encodeDataset(_ d: DataSet) -> [String: JSONValue] {
        var o: [String: JSONValue] = [:]
        if !d.label.isEmpty { o["label"] = .string(d.label) }
        if let c = d.clock { o["clock"] = .object(["now": .string(c.now), "tz": .string(c.tz)]) }
        if !d.records.isEmpty { o["records"] = .object(d.records.mapValues { .array($0.map { .object($0) }) }) }
        if !d.nextIDs.isEmpty { o["nextIDs"] = .object(d.nextIDs.mapValues { .number(Double($0)) }) }
        if let life = d.life { o["life"] = .object(life) }
        return o
    }

    static func encodeColumn(_ c: SQLColumn) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string(c.type)]
        if c.notNull { o["notNull"] = .bool(true) }
        if c.primaryKey { o["primaryKey"] = .bool(true) }
        if let d = c.default { o["default"] = .string(d) }
        if let r = c.references { o["references"] = .string(r) }
        if let d = c.onDelete { o["onDelete"] = .string(d) }
        if let check = c.check { o["check"] = .array(check.map { .string($0) }) }
        if c.dropPending { o["dropPending"] = .bool(true) }
        return .object(o)
    }
}

// MARK: - 경로를 아는 읽개

/// JSON 객체 하나와 그 경로 — 틀린 자리를 `schema.entities[3].fields[7].type` 꼴로 댄다.
struct Reader {
    let fields: [String: JSONValue]
    let path: String

    init(_ fields: [String: JSONValue], path: String) {
        self.fields = fields
        self.path = path
    }

    func at(_ key: String) -> String { path.isEmpty ? key : (key.isEmpty ? path : "\(path).\(key)") }

    func error(_ key: String, _ reason: String) -> IsoDataError { .invalid(path: at(key), reason: reason) }

    /// 모르는 키 거부(읽기 규율 ③).
    mutating func allow(_ keys: Set<String>) throws {
        let unknown = Set(fields.keys).subtracting(keys).sorted()
        if let first = unknown.first {
            throw error(first, "모르는 키 — 더 새 판의 흔적이거나 오타다(모델 파일은 모르는 키를 받지 않는다)")
        }
    }

    func value(_ key: String) throws -> JSONValue {
        guard let v = fields[key] else { throw error(key, "빠졌다") }
        return v
    }

    func string(_ key: String) throws -> String {
        guard case .string(let s) = try value(key) else { throw error(key, "글자여야 한다") }
        return s
    }

    func optionalString(_ key: String) throws -> String? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .string(let s) = v else { throw error(key, "글자여야 한다") }
        return s
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .bool(let b) = v else { throw error(key, "참거짓이어야 한다") }
        return b
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let v = fields[key], !v.isNull else { return nil }
        // `Int(exactly:)` — 소수 · Int 로 담기지 않는 큰 수(1e20)는 트랩이 아니라 거부.
        guard case .number(let n) = v, let i = Int(exactly: n) else { throw error(key, "정수여야 한다") }
        return i
    }

    func optionalStrings(_ key: String) throws -> [String]? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .array(let a) = v else { throw error(key, "글자 배열이어야 한다") }
        return try a.enumerated().map { i, item in
            guard case .string(let s) = item else { throw error("\(key)[\(i)]", "글자여야 한다") }
            return s
        }
    }

    func object(_ key: String) throws -> Reader {
        guard case .object(let o) = try value(key) else { throw error(key, "객체여야 한다") }
        return Reader(o, path: at(key))
    }

    func optionalObject(_ key: String) throws -> Reader? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .object(let o) = v else { throw error(key, "객체여야 한다") }
        return Reader(o, path: at(key))
    }

    func child(_ key: String) throws -> Reader { try object(key) }

    func optionalArray(_ key: String) throws -> [Reader]? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .array(let a) = v else { throw error(key, "배열이어야 한다") }
        return try a.enumerated().map { i, item in
            guard case .object(let o) = item else { throw error("\(key)[\(i)]", "객체여야 한다") }
            return Reader(o, path: at("\(key)[\(i)]"))
        }
    }
}
