import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). SQL 투영 · 생성 · 울타리는 엔진의 몫이다.
//
// 스키마 검증(읽기 규율 ② — `DataModelCoding` 머리) — 틀리면 경로를 대고 파일 전체를 거부한다.
// 막는 것은 형식이 거부하는 것뿐(이름 겹침 · 모르는 형 · 없는 대상 · 닫힌 낱말 밖). 나머지는 경고(노랑)로 알린다 — 막지 않는다.

public enum SchemaValidation {

    /// 거부할 첫 오류를 던진다.
    public static func require(_ schema: DataSchema) throws {
        if let first = errors(schema).first { throw first }
    }

    /// 스키마의 오류 전부 — 경로 차례.
    public static func errors(_ schema: DataSchema) -> [IsoDataError] {
        var out: [IsoDataError] = []
        func fail(_ path: String, _ reason: String) { out.append(.invalid(path: path, reason: reason)) }

        if schema.name.isEmpty { fail("schema.name", "스키마 이름이 비었다") }

        let layerIDs = schema.layers.map(\.id)
        for (i, id) in layerIDs.enumerated() where layerIDs.firstIndex(of: id) != i {
            fail("schema.layers[\(i)].id", "층 ‘\(id)’ 이 겹친다")
        }

        let entityNames = schema.entities.map(\.name)
        let traitNames = schema.traits.map(\.name)
        let valueNames = schema.values.map(\.name)

        for (i, name) in entityNames.enumerated() {
            let path = "schema.entities[\(i)]"
            if entityNames.firstIndex(of: name) != i { fail(path + ".name", "엔티티 이름 ‘\(name)’ 이 겹친다") }
            if !isPascalCase(name) { fail(path + ".name", "엔티티 이름 ‘\(name)’ 은 PascalCase 여야 한다") }
        }
        // 결정적 UUID 의 이름 칸(`uuidKey`)은 스키마 안에서 유일해야 한다 — 겹치면 두 엔티티의 같은 id 가 같은 UUID 가 된다.
        let uuidKeys = schema.entities.map(\.uuidKey)
        for (i, e) in schema.entities.enumerated() {
            let path = "schema.entities[\(i)]"
            if let u = e.uuidName, !isPascalCase(u) { fail(path + ".uuidName", "UUID 이름 ‘\(u)’ 은 PascalCase 여야 한다") }
            if entityNames.firstIndex(of: e.name) == i, uuidKeys.firstIndex(of: e.uuidKey) != i {
                fail(path + (e.uuidName == nil ? ".name" : ".uuidName"), "UUID 이름 ‘\(e.uuidKey)’ 이 다른 엔티티와 겹친다(이름을 바꾼 엔티티의 옛 이름 포함)")
            }
        }
        for (i, name) in traitNames.enumerated() where traitNames.firstIndex(of: name) != i {
            fail("schema.traits[\(i)].name", "공통 필드 묶음 이름 ‘\(name)’ 이 겹친다")
        }
        for (i, name) in valueNames.enumerated() {
            if valueNames.firstIndex(of: name) != i { fail("schema.values[\(i)].name", "값 타입 이름 ‘\(name)’ 이 겹친다") }
            if entityNames.contains(name) { fail("schema.values[\(i)].name", "값 타입 이름 ‘\(name)’ 이 엔티티 이름과 겹친다") }
        }

        func checkType(_ type: DataType, path: String, field: String, inList: Bool = false) {
            switch type {
            case .enumeration(let values):
                if values.isEmpty { fail(path, "필드 ‘\(field)’ 의 열거 값이 비었다") }
                for (i, v) in values.enumerated() where values.firstIndex(of: v) != i {
                    fail(path + ".enum[\(i)]", "필드 ‘\(field)’ 의 열거 값 ‘\(v)’ 이 겹친다")
                }
            case .ref(let target, _):
                if inList { fail(path, "필드 ‘\(field)’ — 참조 목록은 형이 아니라 조인 엔티티로 적는다") }
                if !entityNames.contains(target) { fail(path + ".ref", "필드 ‘\(field)’ 가 없는 엔티티 ‘\(target)’ 을 가리킨다") }
            case .value(let name):
                if !valueNames.contains(name) { fail(path + ".value", "필드 ‘\(field)’ 가 없는 값 타입 ‘\(name)’ 을 가리킨다") }
            case .list(let inner):
                if case .list = inner { fail(path + ".list", "필드 ‘\(field)’ — 목록의 목록은 받지 않는다") }
                if case .id = inner { fail(path + ".list", "필드 ‘\(field)’ — 정체(id)는 목록이 될 수 없다") }
                checkType(inner, path: path + ".list", field: field, inList: true)
            default: break
            }
        }

        func checkFields(_ fields: [DataField], path: String, allowID: Bool) {
            let names = fields.map(\.name)
            for (j, f) in fields.enumerated() {
                let fp = "\(path).fields[\(j)]"
                if names.firstIndex(of: f.name) != j { fail(fp + ".name", "필드 이름 ‘\(f.name)’ 이 겹친다") }
                if !isCamelCase(f.name) { fail(fp + ".name", "필드 이름 ‘\(f.name)’ 은 camelCase 여야 한다") }
                if !allowID, f.type == .id { fail(fp + ".type", "필드 ‘\(f.name)’ — 정체(id)는 엔티티에만 선다") }
                checkType(f.type, path: fp + ".type", field: f.name)
                if f.type == .id, f.optional { fail(fp + ".optional", "정체(id) 필드 ‘\(f.name)’ 는 선택일 수 없다") }
                if let d = f.default, let reason = RecordValidation.typeProblem(d, f.type, schema: schema, idsByEntity: nil) {
                    fail(fp + ".default", "필드 ‘\(f.name)’ 의 기본값 — \(reason)")
                }
            }
        }

        for (i, t) in schema.traits.enumerated() { checkFields(t.fields, path: "schema.traits[\(i)]", allowID: false) }
        for (i, v) in schema.values.enumerated() { checkFields(v.fields, path: "schema.values[\(i)]", allowID: false) }

        for (i, e) in schema.entities.enumerated() {
            let path = "schema.entities[\(i)]"
            if let layer = e.layer, !layerIDs.contains(layer) { fail(path + ".layer", "없는 층 ‘\(layer)’") }
            for (k, use) in e.uses.enumerated() where !traitNames.contains(use) {
                fail("\(path).uses[\(k)]", "없는 공통 필드 묶음 ‘\(use)’")
            }
            checkFields(e.fields, path: path, allowID: true)
            let expanded = schema.expandedFields(of: e)
            let names = expanded.map(\.name)
            for (j, n) in names.enumerated() where names.firstIndex(of: n) != j && j >= e.fields.count {
                fail("\(path).uses", "공통 필드 묶음의 필드 ‘\(n)’ 이 엔티티 필드와 겹친다")
            }
            let ids = expanded.filter { $0.type == .id }
            if ids.count != 1 { fail(path + ".fields", "엔티티 ‘\(e.name)’ 의 정체(id) 필드는 정확히 하나여야 한다 — 지금 \(ids.count)") }
            for (k, rule) in e.rules.enumerated() {
                let rp = "\(path).rules[\(k)]"
                if e.rules.firstIndex(where: { $0.id == rule.id }) != k { fail(rp + ".id", "규칙 id ‘\(rule.id)’ 가 겹친다") }
                guard let check = rule.check else { continue }
                func known(_ field: String, _ key: String) {
                    if !names.contains(field) { fail("\(rp).check.\(key)", "규칙 ‘\(rule.id)’ 이 없는 필드 ‘\(field)’ 를 가리킨다") }
                }
                switch check {
                case .required(let field, let when), .forbidden(let field, let when):
                    known(field, check.word)
                    for key in when.keys.sorted() { known(key, "when") }
                case .unique(let fields):
                    if fields.isEmpty { fail(rp + ".check.unique", "유일 규칙에 필드가 없다") }
                    fields.forEach { known($0, "unique") }
                case .sameAs(let field, let via):
                    known(field, "sameAs.field")
                    let parts = via.split(separator: ".").map(String.init)
                    guard parts.count == 2 else {
                        fail(rp + ".check.sameAs.via", "via 는 ‘참조 필드.대상 필드’ 꼴이다")
                        continue
                    }
                    guard let refField = expanded.first(where: { $0.name == parts[0] }),
                          let target = refField.type.refTarget else {
                        fail(rp + ".check.sameAs.via", "via 의 앞 ‘\(parts[0])’ 이 참조 필드가 아니다")
                        continue
                    }
                    if let targetEntity = schema.entity(target), !schema.expandedFields(of: targetEntity).contains(where: { $0.name == parts[1] }) {
                        fail(rp + ".check.sameAs.via", "‘\(target)’ 에 필드 ‘\(parts[1])’ 가 없다")
                    }
                }
            }
        }
        sqlNameErrors(schema, fail)
        return out
    }

    /// SQL 이름 — 생성 SQL 에 그대로 들어가는 테이블 · 열 이름. 적은 이름(`sql.table` · `sql.column`)은 늘,
    /// 파생 이름은 실재(live)인 것만 잰다. 소유 열 `user_id` 는 생성기가 붙이므로 필드 열이 가질 수 없다. 예약어는 생성기가 인용한다.
    static func sqlNameErrors(_ schema: DataSchema, _ fail: (String, String) -> Void) {
        func name(_ n: String, _ path: String, _ what: String) {
            if !SQLProjection.isValidIdentifier(n) {
                fail(path, "\(what) ‘\(n)’ — SQL 이름은 소문자 · 숫자 · 밑줄(글자나 밑줄로 시작 · 63자 이하)")
            }
        }
        var tables: [String: Int] = [:]
        for (i, e) in schema.entities.enumerated() {
            let path = "schema.entities[\(i)]"
            if let t = e.sqlTable { name(t, path + ".sql.table", "테이블 이름") }
            guard e.status == .live else { continue }
            let table = SQLProjection.tableName(e)
            if e.sqlTable == nil { name(table, path + ".name", "파생 테이블 이름") }
            if let j = tables[table] { fail(path + ".sql.table", "테이블 이름 ‘\(table)’ 이 schema.entities[\(j)] 와 겹친다") } else { tables[table] = i }
            var columns: Set<String> = []
            var seen: Set<String> = []
            for (j, f) in schema.expandedFields(of: e).enumerated() where f.status == .live && seen.insert(f.name).inserted {   // 필드 이름 겹침은 위가 댄다
                let fp = j < e.fields.count ? "\(path).fields[\(j)]" : "\(path).uses"
                let column = SQLProjection.columnName(f)
                name(column, fp + (f.sqlColumn == nil ? ".name" : ".sql.column"), "열 이름")
                if column == SQLProjection.ownerColumn {
                    fail(fp + (f.sqlColumn == nil ? ".name" : ".sql.column"), "열 ‘\(column)’ 은 소유 열(생성기가 모든 테이블에 붙인다)과 겹친다 — 다른 SQL 열 이름(sql.column)을 적는다")
                }
                if !columns.insert(column).inserted { fail(fp + ".sql.column", "테이블 ‘\(table)’ 에 열 ‘\(column)’ 이 둘이다") }
            }
        }
        for (i, t) in schema.traits.enumerated() {
            for (j, f) in t.fields.enumerated() { if let c = f.sqlColumn { name(c, "schema.traits[\(i)].fields[\(j)].sql.column", "열 이름") } }
        }
        for (i, e) in schema.entities.enumerated() {
            for (j, f) in e.fields.enumerated() where e.status != .live || f.status != .live {
                if let c = f.sqlColumn { name(c, "schema.entities[\(i)].fields[\(j)].sql.column", "열 이름") }
            }
        }
    }

    /// 경고(노랑) — 막지 않는다. 편집 창의 즉시 알림과 데이터 검사가 싣는다.
    public static func warnings(_ schema: DataSchema) -> [String] {
        var out: [String] = []
        for e in schema.entities {
            if e.status == .live, e.sqlTable == nil {
                out.append("\(e.name) — SQL 테이블 이름(sql.table)이 없어 ‘\(SQLProjection.tableName(e))’ 로 파생한다")
            }
            // CloudKit 규약 — 필드는 선택이거나 기본값이 있어야 한다(CloudKit 동기화가 필수 칸에 기본값을 요구한다).
            for f in schema.expandedFields(of: e) where f.status == .live && f.type != .id && !f.optional && f.default == nil {
                out.append("\(e.name).\(f.name) — 필수인데 기본값이 없다: CloudKit 전환에서 막힌다")
            }
            if e.status == .dropped, e.dropNote.isEmpty { out.append("\(e.name) — 폐기인데 결정 링크(dropNote)가 없다") }
            for f in e.fields where f.status == .dropped && f.dropNote.isEmpty {
                out.append("\(e.name).\(f.name) — 폐기인데 결정 링크(dropNote)가 없다")
            }
        }
        return out
    }

    static func isPascalCase(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }

    static func isCamelCase(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }
}

extension DataRuleCheck {
    var word: String {
        switch self {
        case .required: "required"
        case .forbidden: "forbidden"
        case .unique: "unique"
        case .sameAs: "sameAs"
        }
    }
}
