import Foundation

// CloudKit 호환 규칙 — 모델 파일(`DataSchema`)이 CloudKit 프라이빗 컨테이너에 동기화되는 SwiftData 스토어의 스키마로 설 수 있는가를 잰다.
// 엔진(데이터 검사 · 공유 모델 열기)과 프로젝트(스키마 패키지의 시험 · 도구)가 같은 답을 내야 하는 규약이라 SDK 에 든다(한 모델을 여러 프로젝트가 물면
// 프로젝트마다 판정이 갈리면 안 된다). 재는 것은 꼴뿐이다 — 스토어 · 동기화를 띄우지 않는다.
//
//   한 판(`problems`)      : 실재(`live`) 엔티티 · 필드만 잰다(물리에 없는 것은 스토어에 없다).
//     ① 필드는 선택이거나 기본값이 있다(정체 `id` 는 생성물이 기본값을 준다) · ② 참조는 선택이다(관계는 늘 선택) ·
//     ③ 참조의 삭제 규칙은 `setNull` · `cascade`(거절 `restrict` 은 CloudKit 이 받지 않는다) · ④ 고유 규칙(`unique`)이 없다(스토어가 고유를 지키지 못한다 —
//     동기화 병합이 겹친 행을 낼 수 있다) · ⑤ 이 SDK 가 모르는 형 · 낱말이 없다(잴 수 없다).
//     관계 짝(inverse) — 모델 파일의 참조는 한쪽(대상 id)만 적고 짝은 대상 쪽 목록으로 지어진다. 짝을 지을 수 없는 참조 목록은 스키마 검증이 이미 거부한다.
//     생성된 Swift 스키마의 짝 선언은 그 스키마를 띄워 재는 쪽(프로젝트의 스키마 패키지 시험)의 몫이다.
//   두 판 사이(`evolutionProblems`) : 칸 더하기만 — 레코드 종류(엔티티 · `swift.model`) · 칸(필드 · `swift.property`)을 빼거나 이름을 바꾸지 않는다 ·
//     선택 칸을 필수로 바꾸지 않는다 · 형을 바꾸지 않는다(열거 값은 더하기만) · 참조의 대상을 바꾸지 않는다.

/// 스키마의 자리 하나에 붙은 문제 — 경로(`schema.entities[3].fields[7]`)와 까닭.
public struct SchemaIssue: Equatable, Sendable, CustomStringConvertible {
    public var path: String
    public var reason: String
    public init(path: String, reason: String) { self.path = path; self.reason = reason }
    public var description: String { "\(path) — \(reason)" }
}

public enum CloudKitRules {

    /// 한 판의 문제 — 경로 차례.
    public static func problems(_ schema: DataSchema) -> [SchemaIssue] {
        var out: [SchemaIssue] = []
        for (i, e) in schema.entities.enumerated() where e.status.isPhysical {
            let path = "schema.entities[\(i)]"
            for (j, f) in schema.expandedFields(of: e).enumerated() where f.status.isPhysical {
                let fp = j < e.fields.count ? "\(path).fields[\(j)]" : "\(path).uses(\(f.name))"
                if f.type.holdsUnknown { out.append(SchemaIssue(path: fp, reason: "이 SDK 가 모르는 형 — CloudKit 호환을 잴 수 없다")); continue }
                if case .ref(_, let onDelete) = f.type {
                    if !f.optional { out.append(SchemaIssue(path: fp, reason: "참조 ‘\(f.name)’ 이 필수다 — CloudKit 관계는 늘 선택이다")) }
                    if onDelete == .restrict {
                        out.append(SchemaIssue(path: fp, reason: "참조 ‘\(f.name)’ 의 삭제 규칙 restrict — CloudKit 은 거절 규칙을 받지 않는다(setNull · cascade)"))
                    } else if !DataOnDelete.known.contains(onDelete) {
                        out.append(SchemaIssue(path: fp, reason: "참조 ‘\(f.name)’ 의 삭제 규칙 ‘\(onDelete.rawValue)’ 을 이 SDK 가 모른다"))
                    }
                } else if f.type != .id, !f.optional, f.default == nil {
                    out.append(SchemaIssue(path: fp, reason: "필드 ‘\(f.name)’ 이 필수인데 기본값이 없다 — CloudKit 은 선택 칸 또는 기본값을 요구한다"))
                }
            }
            for (k, r) in e.rules.enumerated() {
                if case .unique(let fields)? = r.check {
                    out.append(SchemaIssue(path: "\(path).rules[\(k)]",
                                           reason: "고유 규칙(\(fields.joined(separator: " · "))) — CloudKit 스토어는 고유를 지키지 못한다(동기화 병합이 겹친 행을 낼 수 있다)"))
                }
            }
        }
        return out
    }

    /// 두 판 사이의 문제 — `old` 에서 `new` 로 가는 변경이 칸 더하기만인가. 엔티티는 레코드 종류 이름(`swiftModel` ?? `name`) · 필드는 칸 이름
    /// (`swiftProperty` ?? `name`)으로 맞춘다 — 스토어가 보는 이름이다(이름을 바꾼 것은 뺌 + 더함이다).
    public static func evolutionProblems(from old: DataSchema, to new: DataSchema) -> [SchemaIssue] {
        var out: [SchemaIssue] = []
        func record(_ e: DataEntity) -> String { e.swiftModel ?? e.name }
        func column(_ f: DataField) -> String { f.swiftProperty ?? f.name }
        let newEntities = Dictionary(new.entities.filter(\.status.isPhysical).map { (record($0), $0) }, uniquingKeysWith: { a, _ in a })
        for oldEntity in old.entities where oldEntity.status.isPhysical {
            let name = record(oldEntity)
            guard let newEntity = newEntities[name] else {
                out.append(SchemaIssue(path: "schema.entities(\(name))", reason: "레코드 종류 ‘\(name)’ 이 빠졌다(빼거나 이름을 바꾸거나 실재가 아니게) — 칸 더하기만 받는다"))
                continue
            }
            let newFields = Dictionary(new.expandedFields(of: newEntity).filter(\.status.isPhysical).map { (column($0), $0) }, uniquingKeysWith: { a, _ in a })
            for of in old.expandedFields(of: oldEntity) where of.status.isPhysical {
                let fp = "schema.entities(\(name)).fields(\(column(of)))"
                guard let nf = newFields[column(of)] else {
                    out.append(SchemaIssue(path: fp, reason: "칸 ‘\(column(of))’ 이 빠졌다(빼거나 이름을 바꾸거나 실재가 아니게) — 칸 더하기만 받는다")); continue
                }
                let oldRequired = !of.optional && of.default == nil, newRequired = !nf.optional && nf.default == nil
                if of.optional && !nf.optional { out.append(SchemaIssue(path: fp, reason: "선택 칸이 필수가 됐다")) }
                else if !oldRequired && newRequired && of.type != .id { out.append(SchemaIssue(path: fp, reason: "기본값이 빠져 필수가 됐다")) }
                switch (of.type, nf.type) {
                case (.enumeration(let a), .enumeration(let b)):
                    let gone = a.filter { !b.contains($0) }
                    if !gone.isEmpty { out.append(SchemaIssue(path: fp, reason: "열거 값이 빠졌다 — \(gone.joined(separator: " · "))(더하기만 받는다)")) }
                case (.ref(let a, _), .ref(let b, _)):
                    if a != b { out.append(SchemaIssue(path: fp, reason: "참조 대상이 바뀌었다 — \(a) → \(b)")) }
                default:
                    if of.type != nf.type { out.append(SchemaIssue(path: fp, reason: "형이 바뀌었다")) }
                }
            }
        }
        return out
    }
}
