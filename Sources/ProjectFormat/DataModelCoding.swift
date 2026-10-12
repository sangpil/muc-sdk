import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다(SDK 문서 §2).
//
// 모델 파일 ⟷ JSON 값. 읽기 규율(다른 파일의 주석이 이 번호로 가리킨다):
//   ① 판을 먼저 읽는다 — 미래 판은 이름 대고 거부(`IsoDataFile.read` · 읽기 전용 창은 `allowingNewer`).
//   ② 스키마가 먼저 선다 — 틀리면 경로를 대고 파일 전체를 거부(`SchemaValidation`).
//   ③ 모르는 키는 **보존하고 알린다** — 그 객체의 꼴이 `extra` 로 들고 쓸 때 되쓴다(아는 하위 객체 안의 모르는 키는 그 키 아래 객체로) ·
//      경로마다 한 줄(`DataModelFile.unknownKeys`). 모르는 낱말(형 · 상태 · 삭제 규칙 · 규칙)도 글자 그대로 든다(경고는 `SchemaValidation.warnings`).
//      물러난 키(`retired` — 옛 판의 계약 칸)는 알리지 않고 그대로 들고 되쓴다(그 파일이 그 칸을 쓰던 시절의 값).
//   ④ 레코드 오류는 파일을 거부하지 않는다 — 행 단위로 `issues` 에 싣는다(`RecordValidation`).
// 쓰기: 빈 `doc` · 빈 `aliases` · 기본값인 칸은 키 자체를 쓰지 않는다(빈 칸은 없는 칸과 같다).

enum DataModelCoding {

    /// 물러난 키 — 판 4 의 계약 칸이었으나 이 SDK 의 계약이 아닌 것(저장 백엔드의 생성 사본 · 그 이름 칸). 읽은 그대로 들고 되쓴다 · 알리지 않는다.
    static let retiredTop: Set<String> = ["migrated"]
    static let retiredEntity: Set<String> = ["sql"]
    static let retiredField: Set<String> = ["sql"]

    // MARK: 읽기

    static func decode(_ top: [String: JSONValue]) throws -> DataModelFile {
        let notes = Notes()
        let r = Reader(top, path: "", notes: notes)
        let extra = r.keep(["schema", "datasets"], retired: retiredTop)
        let schema = try decodeSchema(r.object("schema"))
        try SchemaValidation.require(schema)
        var file = DataModelFile(schema: schema)
        file.extra = extra
        if let datasets = try r.optionalObject("datasets") {
            for name in datasets.fields.keys.sorted() {
                file.datasets[name] = try decodeDataset(datasets.child(name))
            }
        }
        let held = RecordValidation.hold(file)
        file = held.file
        file.cuts = held.cuts
        file.issues = RecordValidation.validate(file)
        file.unknownKeys = notes.lines
        return file
    }

    static func decodeSchema(_ r: Reader) throws -> DataSchema {
        let extra = r.keep(["name", "idNamespace", "revision", "layers", "entities", "traits", "values"])
        var schema = DataSchema(name: try r.string("name"))
        schema.extra = extra
        schema.idNamespace = try r.optionalString("idNamespace")
        schema.revision = try r.optionalInt("revision")
        if let v = schema.revision, v < 1 { throw r.error("revision", "스키마 판은 1 이상의 정수다") }
        for l in try r.optionalArray("layers") ?? [] {
            let le = l.keep(["id", "label"])
            var layer = DataLayer(id: try l.string("id"), label: try l.optionalString("label") ?? "")
            layer.extra = le
            schema.layers.append(layer)
        }
        for e in try r.optionalArray("entities") ?? [] { schema.entities.append(try decodeEntity(e)) }
        for t in try r.optionalArray("traits") ?? [] {
            let te = t.keep(["name", "doc", "fields"])
            var trait = DataTrait(name: try t.string("name"), doc: try t.optionalString("doc") ?? "",
                                  fields: try (t.optionalArray("fields") ?? []).map(decodeField))
            trait.extra = te
            schema.traits.append(trait)
        }
        for v in try r.optionalArray("values") ?? [] {
            let ve = v.keep(["name", "doc", "fields"])
            var value = DataValueType(name: try v.string("name"), doc: try v.optionalString("doc") ?? "",
                                      fields: try (v.optionalArray("fields") ?? []).map(decodeField))
            value.extra = ve
            schema.values.append(value)
        }
        return schema
    }

    static func decodeEntity(_ r: Reader) throws -> DataEntity {
        var extra = r.keep(["name", "label", "layer", "doc", "aliases", "uses", "swift", "uuidName", "status", "dropNote", "fields", "rules"],
                           retired: retiredEntity)
        var e = DataEntity(name: try r.string("name"))
        e.label = try r.optionalString("label") ?? ""
        e.layer = try r.optionalString("layer")
        e.doc = try r.optionalString("doc") ?? ""
        for a in try r.optionalArray("aliases") ?? [] {
            let ae = a.keep(["lens", "word", "doc"])
            var alias = DataAlias(lens: try a.string("lens"), word: try a.string("word"), doc: try a.optionalString("doc") ?? "")
            alias.extra = ae
            e.aliases.append(alias)
        }
        e.uses = try r.optionalStrings("uses") ?? []
        if let swift = try r.optionalObject("swift") {
            let se = swift.keep(["model"])
            if !se.isEmpty { extra["swift"] = .object(se) }
            e.swiftModel = try swift.optionalString("model")
        }
        e.uuidName = try r.optionalString("uuidName")
        e.status = try decodeStatus(r)
        e.dropNote = try r.optionalString("dropNote") ?? ""
        e.fields = try (r.optionalArray("fields") ?? []).map(decodeField)
        e.rules = try (r.optionalArray("rules") ?? []).map(decodeRule)
        e.extra = extra
        return e
    }

    static func decodeStatus(_ r: Reader) throws -> DataStatus {
        guard let word = try r.optionalString("status") else { return .live }
        return DataStatus(rawValue: word)
    }

    static func decodeField(_ r: Reader) throws -> DataField {
        var extra = r.keep(["name", "type", "optional", "default", "doc", "status", "dropNote", "swift", "renamedFrom"], retired: retiredField)
        let name = try r.string("name")
        var typeExtra: JSONValue?
        var f = DataField(name: name, type: try decodeType(r.value("type"), path: r.at("type"), field: name, notes: r.notes, extra: &typeExtra))
        if let typeExtra { extra["type"] = typeExtra }
        f.optional = try r.optionalBool("optional") ?? false
        f.default = r.fields["default"]
        f.doc = try r.optionalString("doc") ?? ""
        f.status = try decodeStatus(r)
        f.dropNote = try r.optionalString("dropNote") ?? ""
        if let swift = try r.optionalObject("swift") {
            let se = swift.keep(["property"])
            if !se.isEmpty { extra["swift"] = .object(se) }
            f.swiftProperty = try swift.optionalString("property")
        }
        f.renamedFrom = try r.optionalString("renamedFrom")
        f.extra = extra
        return f
    }

    /// 형 — 아는 낱말 · 아는 객체 꼴(`enum` · `ref` · `value` · `list`)은 그 규칙대로 · 아는 꼴 안의 모르는 키는 `extra`(형 칸 아래 객체) ·
    /// 모르는 낱말과 아는 키가 하나도 없는 객체는 `unknown`(그대로 든다). 낱말도 객체도 아니면 필드 이름을 대고 거부한다.
    static func decodeType(_ value: JSONValue, path: String, field: String, notes: Notes, extra: inout JSONValue?) throws -> DataType {
        switch value {
        case .string(let word):
            return DataType.words[word] ?? .unknown(value)
        case .object(let o):
            let r = Reader(o, path: path, notes: notes)
            func kept(_ keys: Set<String>) { let k = r.keep(keys); if !k.isEmpty { extra = .object(k) } }
            if o["enum"] != nil {
                kept(["enum"])
                guard let values = try r.optionalStrings("enum") else { throw r.error("enum", "열거 값 목록이 없다") }
                return .enumeration(values)
            }
            if o["ref"] != nil {
                kept(["ref", "onDelete"])
                let word = try r.optionalString("onDelete") ?? DataOnDelete.setNull.rawValue
                return .ref(try r.string("ref"), onDelete: DataOnDelete(rawValue: word))
            }
            if o["value"] != nil {
                kept(["value"])
                return .value(try r.string("value"))
            }
            if let inner = o["list"] {
                kept(["list"])
                var innerExtra: JSONValue?
                let t = try decodeType(inner, path: path + ".list", field: field, notes: notes, extra: &innerExtra)
                if let innerExtra {
                    var e: [String: JSONValue] = { if case .object(let x)? = extra { return x } else { return [:] } }()
                    e["list"] = innerExtra
                    extra = .object(e)
                }
                return .list(t)
            }
            return .unknown(value)
        default:
            throw IsoDataError.invalid(path: path, reason: "필드 ‘\(field)’ 의 형은 낱말 또는 객체다")
        }
    }

    static func decodeRule(_ r: Reader) throws -> DataRule {
        var extra = r.keep(["id", "check", "doc", "code"])
        var rule = DataRule(id: try r.string("id"))
        rule.doc = try r.optionalString("doc") ?? ""
        rule.code = try r.optionalString("code")
        if let c = try r.optionalObject("check") {
            func when() throws -> [String: [JSONValue]] {
                guard let w = try c.optionalObject("when") else { return [:] }
                var out: [String: [JSONValue]] = [:]
                for key in w.fields.keys {
                    guard case .array(let values) = w.fields[key]! else { throw w.error(key, "조건 값은 배열이다") }
                    out[key] = values
                }
                return out
            }
            func kept(_ keys: Set<String>) -> [String: JSONValue] { c.keep(keys) }
            var checkExtra: [String: JSONValue] = [:]
            if c.fields["required"] != nil {
                checkExtra = kept(["required", "when"])
                rule.check = .required(field: try c.string("required"), when: try when())
            } else if c.fields["forbidden"] != nil {
                checkExtra = kept(["forbidden", "when"])
                rule.check = .forbidden(field: try c.string("forbidden"), when: try when())
            } else if c.fields["unique"] != nil {
                checkExtra = kept(["unique"])
                rule.check = .unique(try c.optionalStrings("unique") ?? [])
            } else if c.fields["sameAs"] != nil {
                checkExtra = kept(["sameAs"])
                let s = try c.object("sameAs")
                let se = s.keep(["field", "via"])
                if !se.isEmpty { checkExtra["sameAs"] = .object(se) }
                rule.check = .sameAs(field: try s.string("field"), via: try s.string("via"))
            } else {
                guard let kind = c.fields.keys.sorted().first else { throw c.error("", "규칙 객체가 비었다") }
                rule.check = .other(kind: kind, body: c.fields)
            }
            if !checkExtra.isEmpty { extra["check"] = .object(checkExtra) }
        }
        rule.extra = extra
        return rule
    }

    static func decodeDataset(_ r: Reader) throws -> DataSet {
        var extra = r.keep(["label", "clock", "records", "nextIDs", "life"])
        var set = DataSet(label: try r.optionalString("label") ?? "")
        if let clock = try r.optionalObject("clock") {
            let ce = clock.keep(["now", "tz"])
            if !ce.isEmpty { extra["clock"] = .object(ce) }
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
                guard let n = next.fields[key]!.integerValue, n >= 1, let i = Int(exactly: n) else {
                    throw next.error(key, "다음 번호는 1 이상의 정수다")
                }
                set.nextIDs[key] = i
            }
        }
        if let life = try r.optionalObject("life") {
            // 삶 블록의 뜻은 빌더 · 프로젝트 코드의 것 — 통째로 나른다(키를 닫는 것은 그 블록을 푸는 쪽의 몫).
            set.life = life.fields
        }
        set.extra = extra
        return set
    }

    // MARK: 쓰기

    static func encode(_ file: DataModelFile) -> [String: JSONValue] {
        var top: [String: JSONValue] = ["schema": .object(encodeSchema(file.schema))]
        if !file.datasets.isEmpty {
            top["datasets"] = .object(file.datasets.mapValues { .object(encodeDataset($0)) })
        }
        return ExtraKeys.merge(top, file.extra)
    }

    static func encodeSchema(_ s: DataSchema) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["name": .string(s.name)]
        if let ns = s.idNamespace { o["idNamespace"] = .string(ns) }
        if let v = s.revision { o["revision"] = .number(Double(v)) }
        if !s.layers.isEmpty {
            o["layers"] = .array(s.layers.map { l in
                var lo: [String: JSONValue] = ["id": .string(l.id)]
                if !l.label.isEmpty { lo["label"] = .string(l.label) }
                return .object(ExtraKeys.merge(lo, l.extra))
            })
        }
        if !s.entities.isEmpty { o["entities"] = .array(s.entities.map { .object(encodeEntity($0)) }) }
        if !s.traits.isEmpty {
            o["traits"] = .array(s.traits.map { t in
                var to: [String: JSONValue] = ["name": .string(t.name)]
                if !t.doc.isEmpty { to["doc"] = .string(t.doc) }
                if !t.fields.isEmpty { to["fields"] = .array(t.fields.map { .object(encodeField($0)) }) }
                return .object(ExtraKeys.merge(to, t.extra))
            })
        }
        if !s.values.isEmpty {
            o["values"] = .array(s.values.map { v in
                var vo: [String: JSONValue] = ["name": .string(v.name)]
                if !v.doc.isEmpty { vo["doc"] = .string(v.doc) }
                if !v.fields.isEmpty { vo["fields"] = .array(v.fields.map { .object(encodeField($0)) }) }
                return .object(ExtraKeys.merge(vo, v.extra))
            })
        }
        return ExtraKeys.merge(o, s.extra)
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
                return .object(ExtraKeys.merge(ao, a.extra))
            })
        }
        if !e.uses.isEmpty { o["uses"] = .array(e.uses.map { .string($0) }) }
        if let m = e.swiftModel { o["swift"] = .object(["model": .string(m)]) }
        if let u = e.uuidName { o["uuidName"] = .string(u) }
        if e.status != .live { o["status"] = .string(e.status.rawValue) }
        if !e.dropNote.isEmpty { o["dropNote"] = .string(e.dropNote) }
        if !e.fields.isEmpty { o["fields"] = .array(e.fields.map { .object(encodeField($0)) }) }
        if !e.rules.isEmpty { o["rules"] = .array(e.rules.map { .object(encodeRule($0)) }) }
        return ExtraKeys.merge(o, e.extra)
    }

    static func encodeField(_ f: DataField) -> [String: JSONValue] {
        var o: [String: JSONValue] = ["name": .string(f.name), "type": encodeType(f.type)]
        if f.optional { o["optional"] = .bool(true) }
        if let d = f.default { o["default"] = d }
        if !f.doc.isEmpty { o["doc"] = .string(f.doc) }
        if f.status != .live { o["status"] = .string(f.status.rawValue) }
        if !f.dropNote.isEmpty { o["dropNote"] = .string(f.dropNote) }
        if let p = f.swiftProperty { o["swift"] = .object(["property": .string(p)]) }
        if let r = f.renamedFrom { o["renamedFrom"] = .string(r) }
        return ExtraKeys.merge(o, f.extra)
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
        case .unknown(let raw): raw
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
        case .other(_, let body)?:
            o["check"] = .object(body)
        }
        return ExtraKeys.merge(o, r.extra)
    }

    static func encodeDataset(_ d: DataSet) -> [String: JSONValue] {
        var o: [String: JSONValue] = [:]
        if !d.label.isEmpty { o["label"] = .string(d.label) }
        if let c = d.clock { o["clock"] = .object(["now": .string(c.now), "tz": .string(c.tz)]) }
        if !d.records.isEmpty { o["records"] = .object(d.records.mapValues { .array($0.map { .object($0) }) }) }
        if !d.nextIDs.isEmpty { o["nextIDs"] = .object(d.nextIDs.mapValues { .number(Double($0)) }) }
        if let life = d.life { o["life"] = .object(life) }
        return ExtraKeys.merge(o, d.extra)
    }
}

// MARK: - 경로를 아는 읽개

/// 읽는 동안 모은 모르는 키의 자리 — 읽개들이 함께 쓴다.
final class Notes {
    private(set) var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}

/// JSON 객체 하나와 그 경로 — 틀린 자리를 `schema.entities[3].fields[7].type` 꼴로 댄다.
struct Reader {
    let fields: [String: JSONValue]
    let path: String
    let notes: Notes

    init(_ fields: [String: JSONValue], path: String, notes: Notes) {
        self.fields = fields
        self.path = path
        self.notes = notes
    }

    func at(_ key: String) -> String { path.isEmpty ? key : (key.isEmpty ? path : "\(path).\(key)") }

    func error(_ key: String, _ reason: String) -> IsoDataError { .invalid(path: at(key), reason: reason) }

    /// 아는 키 밖의 칸을 돌려준다(읽기 규율 ③ — 보존) · 물러난 키가 아니면 자리마다 한 줄을 남긴다.
    func keep(_ keys: Set<String>, retired: Set<String> = []) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for k in fields.keys.sorted() where !keys.contains(k) {
            out[k] = fields[k]
            if !retired.contains(k) { notes.add("\(at(k)) — 이 빌드가 모르는 키(더 새 판의 칸 · 보존해 되쓴다)") }
        }
        return out
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
        guard let n = v.integerValue, let i = Int(exactly: n) else { throw error(key, "정수여야 한다") }
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
        return Reader(o, path: at(key), notes: notes)
    }

    func optionalObject(_ key: String) throws -> Reader? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .object(let o) = v else { throw error(key, "객체여야 한다") }
        return Reader(o, path: at(key), notes: notes)
    }

    func child(_ key: String) throws -> Reader { try object(key) }

    func optionalArray(_ key: String) throws -> [Reader]? {
        guard let v = fields[key], !v.isNull else { return nil }
        guard case .array(let a) = v else { throw error(key, "배열이어야 한다") }
        return try a.enumerated().map { i, item in
            guard case .object(let o) = item else { throw error("\(key)[\(i)]", "객체여야 한다") }
            return Reader(o, path: at("\(key)[\(i)]"), notes: notes)
        }
    }
}
