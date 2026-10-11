import Foundation

// 엔진 SDK `ProjectFormat` — 모델 파일의 형식 계약(꼴 · 인코딩 · 읽기 규율)은 엔진과 프로젝트의 도구 실행물이 같은 한 벌을 문다
// (SDK 문서 §2). SQL 투영 · 생성 · 울타리는 엔진의 몫이다.
//
// 레코드 검증(읽기 규율 ④ — `DataModelCoding` 머리) — 파일을 거부하지 않고 행 번호 · 필드 · 까닭으로 이름을 댄다.
// 값은 클램프하지 않는다(모델의 값에는 그림의 범위가 없다) — 범위는 규칙이 말한다.

/// 레코드 오류 한 줄.
public struct RecordIssue: Equatable, Sendable, CustomStringConvertible {
    public var dataset: String
    public var entity: String
    /// 1 부터 센 행 번호 — 엔티티 전체가 틀리면(모르는 엔티티) 0.
    public var row: Int
    public var field: String?
    /// 규칙 위반이면 그 규칙 id.
    public var rule: String?
    public var reason: String

    public init(dataset: String, entity: String, row: Int, field: String? = nil, rule: String? = nil, reason: String) {
        self.dataset = dataset
        self.entity = entity
        self.row = row
        self.field = field
        self.rule = rule
        self.reason = reason
    }

    public var description: String {
        var s = "\(dataset) · \(entity)"
        if row > 0 { s += " \(row)행" }
        if let field { s += " · \(field)" }
        if let rule { s += " · 규칙 \(rule)" }
        return s + " — " + reason
    }
}

public enum RecordValidation {

    /// 상한으로 자른 파일과 자른 것의 글.
    static func hold(_ file: DataModelFile) -> (file: DataModelFile, cuts: [String]) {
        var file = file
        var cuts: [String] = []
        for name in file.datasetNames {
            for entity in (file.datasets[name]?.records.keys.sorted() ?? []) {
                let rows = file.datasets[name]!.records[entity]!
                if rows.count > IsoDataFormat.maxRowsPerEntity {
                    cuts.append("\(name) · \(entity) — \(rows.count)행이 상한 \(IsoDataFormat.maxRowsPerEntity)행을 넘어 앞 \(IsoDataFormat.maxRowsPerEntity)행만 읽었다.")
                    file.datasets[name]!.records[entity] = Array(rows.prefix(IsoDataFormat.maxRowsPerEntity))
                }
            }
        }
        return (file, cuts)
    }

    /// 파일 전체의 레코드 오류 — 벌 차례(`seed` 먼저) · 엔티티 이름 차례 · 행 차례.
    public static func validate(_ file: DataModelFile) -> [RecordIssue] {
        file.datasetNames.flatMap { validate(file.datasets[$0]!, named: $0, schema: file.schema) }
    }

    /// 벌 하나의 레코드 오류.
    public static func validate(_ set: DataSet, named name: String, schema: DataSchema) -> [RecordIssue] {
        var out: [RecordIssue] = []
        // 참조 검사에 쓰는 엔티티별 id 모음(같은 벌 안).
        var idsByEntity: [String: Set<String>] = [:]
        for e in schema.entities {
            guard let idField = schema.expandedFields(of: e).first(where: { $0.type == .id }) else { continue }
            idsByEntity[e.name] = Set((set.records[e.name] ?? []).compactMap { row in
                if case .string(let s)? = row[idField.name] { return s } else { return nil }
            })
        }

        for entityName in set.records.keys.sorted() {
            let rows = set.records[entityName]!
            guard let entity = schema.entity(entityName) else {
                out.append(RecordIssue(dataset: name, entity: entityName, row: 0, reason: "스키마에 없는 엔티티의 레코드 \(rows.count)행"))
                continue
            }
            if entity.status == .dropped, !rows.isEmpty {
                out.append(RecordIssue(dataset: name, entity: entityName, row: 0, reason: "폐기된 엔티티는 레코드를 받지 않는다 — \(rows.count)행"))
            }
            let fields = schema.expandedFields(of: entity)
            let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
            var seenIDs: Set<String> = []
            for (i, row) in rows.enumerated() {
                let n = i + 1
                func issue(_ field: String?, _ reason: String, rule: String? = nil) {
                    out.append(RecordIssue(dataset: name, entity: entityName, row: n, field: field, rule: rule, reason: reason))
                }
                for key in row.keys.sorted() where byName[key] == nil {
                    issue(key, "스키마에 없는 필드")
                }
                for f in fields {
                    let value = row[f.name]
                    let present = value.map { !$0.isNull } ?? false
                    if f.status == .dropped {
                        if present { issue(f.name, "폐기된 필드는 값을 받지 않는다") }
                        continue
                    }
                    guard present, let value else {
                        if !f.optional, f.status == .live || f.status == .mock { issue(f.name, "필수 필드가 비었다") }
                        continue
                    }
                    if f.type == .id, case .string(let id) = value {
                        if id.isEmpty { issue(f.name, "id 가 비었다"); continue }
                        if !seenIDs.insert(id).inserted { issue(f.name, "id ‘\(id)’ 가 겹친다") }
                    }
                    if let problem = typeProblem(value, f.type, schema: schema, idsByEntity: idsByEntity) {
                        issue(f.name, problem)
                    }
                }
            }
            out.append(contentsOf: ruleIssues(entity, rows: rows, set: set, named: name, schema: schema))
        }
        return out
    }

    /// 규칙(`check`) 위반.
    static func ruleIssues(_ entity: DataEntity, rows: [DataRecord], set: DataSet, named name: String, schema: DataSchema) -> [RecordIssue] {
        var out: [RecordIssue] = []
        func has(_ row: DataRecord, _ field: String) -> Bool { row[field].map { !$0.isNull } ?? false }
        func matches(_ row: DataRecord, _ when: [String: [JSONValue]]) -> Bool {
            when.allSatisfy { key, values in values.contains(row[key] ?? .null) }
        }
        for rule in entity.rules {
            guard let check = rule.check else { continue }
            let why = rule.doc.isEmpty ? "" : " — \(rule.doc)"
            switch check {
            case .required(let field, let when):
                for (i, row) in rows.enumerated() where matches(row, when) && !has(row, field) {
                    out.append(RecordIssue(dataset: name, entity: entity.name, row: i + 1, field: field, rule: rule.id,
                                           reason: "값이 있어야 한다" + why))
                }
            case .forbidden(let field, let when):
                for (i, row) in rows.enumerated() where matches(row, when) && has(row, field) {
                    out.append(RecordIssue(dataset: name, entity: entity.name, row: i + 1, field: field, rule: rule.id,
                                           reason: "값이 없어야 한다" + why))
                }
            case .unique(let fields):
                var seen: [String: Int] = [:]
                for (i, row) in rows.enumerated() {
                    guard fields.allSatisfy({ has(row, $0) }) else { continue }
                    let key = JSONValue.array(fields.map { row[$0]! }).text(pretty: false)
                    if let first = seen[key] {
                        out.append(RecordIssue(dataset: name, entity: entity.name, row: i + 1, field: fields.joined(separator: "·"),
                                               rule: rule.id, reason: "\(first)행과 값이 겹친다" + why))
                    } else {
                        seen[key] = i + 1
                    }
                }
            case .sameAs(let field, let via):
                let parts = via.split(separator: ".").map(String.init)
                guard parts.count == 2,
                      let refField = schema.expandedFields(of: entity).first(where: { $0.name == parts[0] }),
                      let target = refField.type.refTarget,
                      let targetEntity = schema.entity(target),
                      let targetID = schema.expandedFields(of: targetEntity).first(where: { $0.type == .id }) else { continue }
                var targets: [String: DataRecord] = [:]
                for row in set.records[target] ?? [] {
                    if case .string(let id)? = row[targetID.name] { targets[id] = row }
                }
                for (i, row) in rows.enumerated() {
                    guard case .string(let ref)? = row[parts[0]], let targetRow = targets[ref] else { continue }
                    let mine = row[field] ?? .null
                    let theirs = targetRow[parts[1]] ?? .null
                    if mine != theirs {
                        out.append(RecordIssue(dataset: name, entity: entity.name, row: i + 1, field: field, rule: rule.id,
                                               reason: "\(target) ‘\(ref)’ 의 \(parts[1]) ‘\(theirs.plain)’ 와 다르다(‘\(mine.plain)’)" + why))
                    }
                }
            }
        }
        return out
    }

    /// 값이 형에 맞지 않으면 까닭, 맞으면 nil. `idsByEntity` 가 nil 이면 참조 대상 존재는 재지 않는다(기본값 검사).
    static func typeProblem(_ value: JSONValue, _ type: DataType, schema: DataSchema, idsByEntity: [String: Set<String>]?) -> String? {
        switch type {
        case .id, .text, .longText:
            if case .string = value { return nil }
            return "글자여야 한다"
        case .int:
            if case .number(let n) = value, n == n.rounded(), n.isFinite { return nil }
            return "정수여야 한다"
        case .decimal, .money:
            if case .number(let n) = value, n.isFinite { return nil }
            return "수여야 한다"
        case .bool:
            if case .bool = value { return nil }
            return "참거짓이어야 한다"
        case .date:
            if case .string(let s) = value, DataDates.isDate(s) { return nil }
            return "날짜(YYYY-MM-DD)가 아니다: \(value.plain)"
        case .instant:
            if case .string(let s) = value, DataDates.isInstant(s) { return nil }
            return "시각(ISO 8601 + 오프셋)이 아니다: \(value.plain)"
        case .enumeration(let values):
            if case .string(let s) = value, values.contains(s) { return nil }
            return "열거 밖 값 ‘\(value.plain)’ — \(values.joined(separator: " | "))"
        case .ref(let target, _):
            guard case .string(let id) = value else { return "참조는 대상 id 글자여야 한다" }
            if let ids = idsByEntity, !(ids[target]?.contains(id) ?? false) { return "없는 \(target) ‘\(id)’ 를 가리킨다" }
            return nil
        case .value(let name):
            guard case .object(let o) = value else { return "값 타입 ‘\(name)’ 은 객체여야 한다" }
            guard let v = schema.valueType(name) else { return nil }
            for key in o.keys.sorted() where !v.fields.contains(where: { $0.name == key }) {
                return "값 타입 ‘\(name)’ 에 없는 칸 ‘\(key)’"
            }
            for f in v.fields {
                guard let inner = o[f.name], !inner.isNull else {
                    if !f.optional { return "값 타입 ‘\(name)’ 의 필수 칸 ‘\(f.name)’ 이 비었다" }
                    continue
                }
                if let p = typeProblem(inner, f.type, schema: schema, idsByEntity: idsByEntity) { return "\(f.name): \(p)" }
            }
            return nil
        case .list(let inner):
            guard case .array(let items) = value else { return "목록은 배열이어야 한다" }
            for (i, item) in items.enumerated() {
                if let p = typeProblem(item, inner, schema: schema, idsByEntity: idsByEntity) { return "[\(i)] \(p)" }
            }
            return nil
        }
    }
}

/// 날짜 · 시각 글자 규율 — 레코드 검증과 엔진의 칸 입력이 같은 잣대 한 벌을 쓴다.
/// 포매터 · 달력은 한 번만 만든다(검증이 행 × 칸마다 부른다 · `ISO8601DateFormatter` 는 스레드 안전).
public enum DataDates {
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    public static func isDate(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return false }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return c.isValidDate(in: utc)
    }

    /// 시각 — 오프셋 필수(`Z` 또는 `±hh:mm`) · 소수 초 받음.
    public static func isInstant(_ s: String) -> Bool {
        guard s.hasSuffix("Z") || s.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return false }
        return plain.date(from: s) != nil || fractional.date(from: s) != nil
    }
}
