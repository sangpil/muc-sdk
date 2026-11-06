import CryptoKit
import Foundation

// 엔진 SDK `ProjectFormat` — 공유 데이터의 변경 기록 규약. 여러 앱이 같은 데이터(공유 데이터 모델 — `SharedDataModel`)를 함께 고칠 때
// 「누가 · 언제 · 무엇을 고치고 지웠나」를 같은 꼴 · 같은 바이트로 남기게 하는 **순수 규약**이다(SDK 문서 §2).
//
//   표지 둘(모델 파일 · 형식 판 그대로 — 키 더하기):
//     공통 필드 묶음 `"role" : "provenance"` = 레코드 출처 세 칸(쓴 앱 · 쓴 판 · 고친 때 — `ChangeLog.provenanceFields`)
//     엔티티 `"log" : "edit"` = 고침 줄(칸 하나의 고침 = 한 줄 — `EditLine` · `ChangeLog.editFields`)
//     엔티티 `"log" : "deletion"` = 지움 줄(지운 레코드 하나 = 한 줄 · 지운 때의 값 — `DeletionLine` · `ChangeLog.deletionFields`)
//   값의 꼴 — 기록 줄의 전 값 · 새 값 · 스냅샷은 모델 파일 레코드 값 꼴의 JSON 글 한 줄이다. 두 앱이 같은 값에 같은 글자를 내야 충돌 대조가 서므로
//     정규화(`canonical`)와 요약(`digest` — `"sha256:<hex>"`)은 이 한 벌만 쓴다. 정규화는 JSON 글 → 읽기(수는 십진) → 키 정렬 · 빗금 그대로의 한 줄이다.
//     정규화가 하지 않는 것 — 시각은 레코드 값 꼴의 글자(오프셋 포함) 그대로다(같은 때라도 오프셋이 다르면 다른 글이다 · 시각으로 읽어 맞추지 않는다) ·
//     글자는 유니코드 정규화하지 않는다(미리 합친 글자 ⟂ 분해한 글자는 다른 바이트 · 다른 요약). 같은 글자를 내는 것은 쓰는 쪽의 몫이다.
//   판정 — 보관(`lapsed` — 고침 줄 `at` · 지움 줄 `deletedAt` 이 비었거나 보관 기간보다 이르면 지난 줄) · 합치기(`coalesceTarget` — 같은 기기 · 기록 · 칸의
//     창 안 연속 고침은 한 줄) · 충돌(`conflicts` — 같은 칸을 두 곳이 서로 모르고 고쳤다 · 지운 기록을 다른 곳이 고쳤다 · 값만 본다).
//
// 이 규약에 들지 않는 것 — 저장 손(스토어의 저장 직전 변경을 읽어 줄을 넣는 손) · 스토어 · 동기화. 그것은 쓰는 쪽(앱)의 몫이다(SDK 문서 §4).
// 쓴 쪽의 값(`ChangeWriter` — 앱 식별자 · 판 · 기기)을 채우는 것도 앱이다 — 기기는 설치마다 하나인 무작위 id 를 쓴다(기기 이름은 쓰지 않는다).

/// 쓴 쪽 — 앱 식별자(번들 id 꼴) · 앱의 판 · 기기(설치마다 하나인 무작위 id).
public struct ChangeWriter: Hashable, Sendable {
    public var app: String
    public var version: String
    public var device: String
    public init(app: String, version: String, device: String) { self.app = app; self.version = version; self.device = device }
}

/// 공통 필드 묶음의 역할(파일 키 `role`) — 열린 꼴: 아는 낱말 `provenance`(`known`) · 모르는 낱말은 글자 그대로 든다.
public struct DataTraitRole: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// 레코드 출처 세 칸 — `ChangeLog.provenanceFields`.
    public static let provenance = DataTraitRole(rawValue: "provenance")
    /// 이 SDK 가 아는 낱말 — 차례 그대로.
    public static let known: [DataTraitRole] = [.provenance]
}

/// 기록 엔티티의 갈래(파일 키 `log`) — 열린 꼴: 아는 낱말 `edit` · `deletion`(`known`) · 모르는 낱말은 글자 그대로 든다.
public struct DataLogKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// 고침 줄 — `EditLine` · `ChangeLog.editFields`.
    public static let edit = DataLogKind(rawValue: "edit")
    /// 지움 줄 — `DeletionLine` · `ChangeLog.deletionFields`.
    public static let deletion = DataLogKind(rawValue: "deletion")
    /// 이 SDK 가 아는 낱말 — 차례 그대로.
    public static let known: [DataLogKind] = [.edit, .deletion]
}

/// 고침 줄 한 줄 — 칸 하나의 고침(기록 · 칸 · 전 값 → 새 값 · 쓴 앱 · 판 · 기기 · 때). 칸은 고침 줄 엔티티의 칸과 하나씩 맞는다(`ChangeLog.editFields`).
/// 기록이 빈 칸을 들 수 있어 모두 선택이다 — 종류 · 기록 · 칸 · 때 가운데 하나라도 빈 줄은 판정이 읽지 않는다.
public struct EditLine: Hashable, Sendable {
    /// 고친 기록의 종류 — 스토어의 레코드 종류 이름(모델 파일의 `swift.model` · 없으면 엔티티 이름).
    public var kind: String?
    /// 고친 기록의 id(칸 `targetId`).
    public var targetID: UUID?
    /// 고친 칸 — 스토어의 칸 이름(`swift.property` · 없으면 필드 이름).
    public var field: String?
    /// 전 값 · 새 값 — 레코드 값 꼴의 JSON 글 한 줄 · nil = 빈 칸. 요약할 칸이면 요약 글의 JSON(`"\"sha256:…\""`).
    public var before: String?
    public var after: String?
    public var app: String?
    public var appVersion: String?
    public var device: String?
    public var at: Date?

    public init(kind: String? = nil, targetID: UUID? = nil, field: String? = nil, before: String? = nil, after: String? = nil,
                app: String? = nil, appVersion: String? = nil, device: String? = nil, at: Date? = nil) {
        self.kind = kind; self.targetID = targetID; self.field = field; self.before = before; self.after = after
        self.app = app; self.appVersion = appVersion; self.device = device; self.at = at
    }

    /// 쓴 쪽의 값을 채운 줄.
    public init(kind: String, targetID: UUID, field: String, before: String?, after: String?, writer: ChangeWriter, at: Date) {
        self.init(kind: kind, targetID: targetID, field: field, before: before, after: after,
                  app: writer.app, appVersion: writer.version, device: writer.device, at: at)
    }
}

/// 지움 줄 한 줄 — 지운 기록 하나(종류 · 기록 · 묶음 · 지운 때의 값 · 쓴 앱 · 판 · 기기 · 때). 칸은 지움 줄 엔티티의 칸과 하나씩 맞는다(`ChangeLog.deletionFields`).
public struct DeletionLine: Hashable, Sendable {
    public var kind: String?
    public var targetID: UUID?
    /// 한 번에 지운 묶음(칸 `batchId`) — 저장 한 번의 지우기 전부(연쇄 지우기 포함). 함께 되살리는 단위다.
    public var batchID: UUID?
    /// 지운 때의 값 — JSON 객체 글 한 줄(스토어 칸 이름 → 레코드 값 · 빈 칸은 키째 없다). 지운 기록의 `id`(소문자 UUID 글)를 늘 든다 —
    /// 되살리는 쪽이 스냅샷 하나로 같은 기록을 다시 세운다.
    public var snapshot: String?
    /// 스냅샷을 뜬 스키마 판(`schema.revision`) — 꼴이 바뀐 뒤 옛 스냅샷을 읽는 열쇠.
    public var snapshotRevision: Int?
    public var deletedAt: Date?
    public var app: String?
    public var appVersion: String?
    public var device: String?

    public init(kind: String? = nil, targetID: UUID? = nil, batchID: UUID? = nil, snapshot: String? = nil, snapshotRevision: Int? = nil,
                deletedAt: Date? = nil, app: String? = nil, appVersion: String? = nil, device: String? = nil) {
        self.kind = kind; self.targetID = targetID; self.batchID = batchID; self.snapshot = snapshot; self.snapshotRevision = snapshotRevision
        self.deletedAt = deletedAt; self.app = app; self.appVersion = appVersion; self.device = device
    }

    /// 쓴 쪽의 값을 채운 줄.
    public init(kind: String, targetID: UUID, batchID: UUID, snapshot: String?, snapshotRevision: Int?, writer: ChangeWriter, at: Date) {
        self.init(kind: kind, targetID: targetID, batchID: batchID, snapshot: snapshot, snapshotRevision: snapshotRevision,
                  deletedAt: at, app: writer.app, appVersion: writer.version, device: writer.device)
    }
}

/// 한쪽의 변경 — 고침 줄 · 삭제 줄.
public struct ChangeLines: Hashable, Sendable {
    public var edits: [EditLine]
    public var deletions: [DeletionLine]
    public init(edits: [EditLine] = [], deletions: [DeletionLine] = []) { self.edits = edits; self.deletions = deletions }

    /// 이 기기(`device`)의 것 ⟂ 들어온 것으로 가른다 — 동기화가 켜지면 다른 기기의 줄이 같은 표로 들어온다.
    public func split(device: String) -> (local: ChangeLines, incoming: ChangeLines) {
        (ChangeLines(edits: edits.filter { $0.device == device }, deletions: deletions.filter { $0.device == device }),
         ChangeLines(edits: edits.filter { $0.device != device }, deletions: deletions.filter { $0.device != device }))
    }
}

/// 충돌 하나.
public enum ChangeConflict: Hashable, Sendable {
    /// 같은 기록 · 같은 칸을 두 곳이 서로 모르고 고쳤다(각 쪽의 마지막 고침).
    case sameField(local: EditLine, incoming: EditLine)
    /// 한쪽이 지운 기록을 다른 쪽이 고쳤다(`editIsLocal` = 고친 쪽이 이 기기).
    case editDeleted(edit: EditLine, deletion: DeletionLine, editIsLocal: Bool)
}

public enum ChangeLog {

    // MARK: 상수

    /// 기록 둘(고침 · 삭제)의 보관 — 30일. 지난 줄은 쓰는 쪽이 지운다(언제 지우나는 쓰는 쪽의 몫).
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// 같은 기기 · 기록 · 칸의 연속 고침을 한 줄로 합치는 창 — 30초(마지막 때에서 미끄러진다).
    public static let coalesceWindow: TimeInterval = 30
    /// 요약 글의 머리.
    public static let digestPrefix = "sha256:"

    /// 출처 묶음(`"role" : "provenance"`)의 칸 — 쓴 앱 · 쓴 판 · 고친 때. 모두 선택(빈 값 = 모름 — 시드 · 옛 레코드).
    /// 이 칸들은 고침 줄에서 빠진다(저장마다 바뀐다).
    public static let provenanceFields: [DataField] = [
        DataField(name: "writerApp", type: .text, optional: true),
        DataField(name: "writerVersion", type: .text, optional: true),
        DataField(name: "updatedAt", type: .instant, optional: true),
    ]

    /// 고침 줄 엔티티(`"log" : "edit"`)의 칸 — `EditLine` 의 칸과 하나씩. 관계 칸이 없다(가리키는 기록은 종류 + id).
    public static let editFields: [DataField] = [
        DataField(name: "id", type: .id),
        DataField(name: "kind", type: .text, optional: true),
        DataField(name: "targetId", type: .text, optional: true, swiftProperty: "targetID"),
        DataField(name: "field", type: .text, optional: true),
        DataField(name: "before", type: .longText, optional: true),
        DataField(name: "after", type: .longText, optional: true),
        DataField(name: "app", type: .text, optional: true),
        DataField(name: "appVersion", type: .text, optional: true),
        DataField(name: "device", type: .text, optional: true),
        DataField(name: "at", type: .instant, optional: true),
    ]

    /// 지움 줄 엔티티(`"log" : "deletion"`)의 칸 — `DeletionLine` 의 칸과 하나씩.
    public static let deletionFields: [DataField] = [
        DataField(name: "id", type: .id),
        DataField(name: "kind", type: .text, optional: true),
        DataField(name: "targetId", type: .text, optional: true, swiftProperty: "targetID"),
        DataField(name: "batchId", type: .text, optional: true, swiftProperty: "batchID"),
        DataField(name: "snapshot", type: .longText, optional: true),
        DataField(name: "snapshotRevision", type: .int, optional: true),
        DataField(name: "deletedAt", type: .instant, optional: true),
        DataField(name: "app", type: .text, optional: true),
        DataField(name: "appVersion", type: .text, optional: true),
        DataField(name: "device", type: .text, optional: true),
    ]

    /// 기록 엔티티에 아직 없어도 되는 칸 — 규약에 뒤에 더한 칸(칸 더하기 · 빈 칸 = 모름).
    public static let laterFields: Set<String> = ["appVersion"]

    // MARK: 값

    /// 정규화 — JSON 글 → 읽기(수는 십진) → 키 정렬 · 빗금 그대로의 한 줄. 빈 값(nil · `null` · 읽지 못하는 글)은 nil.
    /// 같은 값은 같은 글자다(`1.50` → `1.5` · `1e3` → `1000` · `-0` → `0` · 키 차례 무관) — 두 앱이 비교 · 요약하는 바이트가 이것이다.
    /// 빈 글자(`""`)는 빈 값이 아니다. 시각 글은 오프셋까지 글자 그대로 · 글자는 유니코드 정규화하지 않는다(미리 합친 `é` ⟂ 분해한 `é` 는 다른 글).
    public static func canonical(_ json: String?) -> String? {
        guard let value = CanonicalValue.parse(json) else { return nil }
        return value.text
    }

    /// 정규화 — JSON 값.
    public static func canonical(_ value: JSONValue) -> String? { canonical(value.text(pretty: false)) }

    /// 요약 — 정규화한 글의 SHA-256(`"sha256:<hex>"` · 소문자). 빈 값은 nil. 민감한 칸 · 긴 글 칸의 고침 줄이 평문 대신 이것을 JSON 글로 든다.
    public static func digest(_ json: String?) -> String? {
        guard let text = canonical(json) else { return nil }
        return digestPrefix + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 요약 — JSON 값.
    public static func digest(_ value: JSONValue) -> String? { digest(value.text(pretty: false)) }

    /// 기록 줄에 싣는 요약 값의 JSON 글(`"\"sha256:…\""`) — 빈 값은 nil.
    public static func digestText(_ json: String?) -> String? {
        digest(json).flatMap { JSONValue.string($0).text(pretty: false) }
    }

    /// 요약 글의 꼴인가 — JSON 글자 값이 머리 `sha256:` 로 선다(그 칸이 요약 대상인지는 쓰는 쪽이 가른다).
    public static func isDigest(_ json: String?) -> Bool {
        if case .string(let s)? = CanonicalValue.parse(json) { return s.hasPrefix(digestPrefix) }
        return false
    }

    // MARK: 판정

    /// 보관이 지난 줄인가 — 때가 비었거나 `now - keep` 보다 이르다. 고침 줄은 `at` · 지움 줄은 `deletedAt` 을 준다.
    public static func lapsed(_ at: Date?, now: Date, keep: TimeInterval = retention) -> Bool {
        (at ?? .distantPast) < now.addingTimeInterval(-keep)
    }

    /// 합칠 줄 — 이 기기(`device`)가 창 안(`now - window` 이후)에 남긴 같은 기록 · 칸의 마지막 줄의 번호(`lines` 안). 없으면 nil(새 줄).
    /// 그 줄 뒤에 다른 기기의 같은 칸 줄이 있으면 합치지 않는다(들어온 값을 이어 고친 것이 사라지지 않게). `lines` = 쓰는 쪽이 아는 고침 줄 전부(저장된 것 + 이번 저장에서 지은 것).
    /// 합칠 때 쓰는 쪽은 처음 전 값을 두고 새 값 · 때 · 쓴 앱 · 판을 바꾼다. 전 값으로 돌아와도 줄은 지우지 않는다(되돌림이 다른 기기의 고침을 덮는지 충돌 대조가 보게).
    public static func coalesceTarget(in lines: [EditLine], kind: String, targetID: UUID, field: String, device: String, now: Date,
                                      window: TimeInterval = coalesceWindow) -> Int? {
        let since = now.addingTimeInterval(-window)
        let recent = lines.indices
            .filter { lines[$0].device == device && (lines[$0].at ?? .distantPast) >= since }
            .sorted { (lines[$0].at ?? .distantPast, $0) < (lines[$1].at ?? .distantPast, $1) }
        guard let i = recent.last(where: { lines[$0].kind == kind && lines[$0].targetID == targetID && lines[$0].field == field }) else { return nil }
        let from = lines[i].at ?? .distantPast
        let others = lines.contains {
            $0.kind == kind && $0.targetID == targetID && $0.field == field && $0.device != device && ($0.at ?? .distantPast) >= from
        }
        return others ? nil : i
    }

    /// 충돌 대조 — 이 기기의 변경 ⟂ 들어온 변경. 「두 곳」 = 쓴 쪽(앱 · 기기)이 다르다(같은 쪽끼리는 제 이력이다).
    /// 대조는 열쇠(종류 · 기록 · 칸)마다 양쪽의 **마지막** 고침 하나씩이다(때 차례 · 같은 때면 새 값의 정규화 글 차례).
    ///   ① 같은 칸 — 새 값이 같거나 한쪽의 전 값이 다른 쪽의 새 값이면(이어 고침) 충돌이 아니다. 그 밖은 충돌.
    ///   ② 지움 대 고침 — 지운 때의 값(스냅샷)에 그 고침의 새 값이 들어 있으면(지운 쪽이 고침을 보고 지웠다) 충돌이 아니다. 그 밖은 충돌.
    /// 판정은 값만 본다(정규화한 글 — 빈 칸 · 없는 키는 같은 빈 값) — 시각은 기기마다의 시계라 마지막 줄을 고르는 데만 쓴다.
    /// `digestible`(종류, 칸) — 요약 대상 칸인가(쓰는 쪽의 스키마가 가른다). 참이고 그 줄의 값이 요약 꼴이면 스냅샷의 값을 같은 요약으로 바꿔 맞댄다.
    /// 양쪽이 다 지운 것은 충돌이 아니다. 결과는 종류 · 기록 · 칸 차례(같은 자리면 같은 칸 → 이 기기의 고침 → 들어온 고침).
    public static func conflicts(local: ChangeLines, incoming: ChangeLines,
                                 digestible: (_ kind: String, _ field: String) -> Bool = { _, _ in false }) -> [ChangeConflict] {
        let mine = latest(local.edits), theirs = latest(incoming.edits)
        var out: [ChangeConflict] = []
        for (key, l) in mine {
            guard let i = theirs[key], Source(l) != Source(i), canonical(l.after) != canonical(i.after) else { continue }
            let continues = canonical(i.before) == canonical(l.after) || canonical(l.before) == canonical(i.after)
            if !continues { out.append(.sameField(local: l, incoming: i)) }
        }
        func against(_ deletions: [DeletionLine], _ edits: [Key: EditLine], editIsLocal: Bool) {
            for d in deletions {
                guard let kind = d.kind, let id = d.targetID, d.deletedAt != nil else { continue }
                let snapshot = CanonicalValue.parse(d.snapshot)?.objectFields ?? [:]
                for (key, e) in edits where key.kind == kind && key.id == id && Source(e) != Source(app: d.app, device: d.device) {
                    let had = snapshot[key.field]?.text
                    let digested = digestible(kind, key.field) && (isDigest(e.after) || isDigest(e.before))
                    let seen = (digested ? canonical(digestText(had)) : canonical(had)) == canonical(e.after)
                    if !seen { out.append(.editDeleted(edit: e, deletion: d, editIsLocal: editIsLocal)) }
                }
            }
        }
        against(incoming.deletions, mine, editIsLocal: true)
        against(local.deletions, theirs, editIsLocal: false)
        return out.sorted { a, b in
            let x = sortKey(a), y = sortKey(b)
            return (x.0, x.1, x.2, x.3) < (y.0, y.1, y.2, y.3)
        }
    }

    // MARK: 꼴

    /// 표지가 단 꼴의 문제 — 출처 묶음 · 기록 엔티티의 칸이 이 규약의 칸(`provenanceFields` · `editFields` · `deletionFields`)과 이름 · 형 · 선택이 맞는가 ·
    /// 규약에 없는 칸 · 기본값을 둔 칸(빈 값 = 모름을 지킨다 — 정체 칸 밖) · 모르는 낱말 · 같은 표지가 두 벌. 표지가 없는 스키마는 문제 0 이다. 막지 않는다(읽는 쪽이 경고로 싣는다) — 경로 차례.
    public static func problems(_ schema: DataSchema) -> [SchemaIssue] {
        var out: [SchemaIssue] = []
        var provenance: [Int] = []
        for (i, t) in schema.traits.enumerated() {
            guard let role = t.role else { continue }
            let path = "schema.traits[\(i)]"
            guard role == .provenance else {
                out.append(SchemaIssue(path: path, reason: "역할 ‘\(role.rawValue)’ 을 이 SDK 가 모른다(재지 않는다)")); continue
            }
            provenance.append(i)
            shape(t.fields, want: provenanceFields, later: [], path: path, what: "출처 묶음", into: &out)
        }
        if provenance.count > 1 {
            out.append(SchemaIssue(path: "schema.traits[\(provenance[1])]", reason: "출처 묶음이 둘 이상이다(schema.traits[\(provenance[0])] 와 겹친다)"))
        }
        var seen: [DataLogKind: Int] = [:]
        for (i, e) in schema.entities.enumerated() {
            guard let log = e.log else { continue }
            let path = "schema.entities[\(i)]"
            let want: [DataField]
            switch log {
            case .edit: want = editFields
            case .deletion: want = deletionFields
            default: out.append(SchemaIssue(path: path, reason: "기록 갈래 ‘\(log.rawValue)’ 을 이 SDK 가 모른다(재지 않는다)")); continue
            }
            if let first = seen[log] {
                out.append(SchemaIssue(path: path, reason: "\(log.rawValue) 기록 엔티티가 둘 이상이다(schema.entities[\(first)] 와 겹친다)"))
            } else {
                seen[log] = i
            }
            if !e.uses.isEmpty { out.append(SchemaIssue(path: path + ".uses", reason: "기록 엔티티는 공통 필드 묶음을 쓰지 않는다(\(e.uses.joined(separator: " · ")))")) }
            shape(e.fields, want: want, later: laterFields, path: path, what: "\(log.rawValue) 기록", into: &out)
        }
        return out
    }

    // MARK: 안쪽

    struct Key: Hashable { var kind: String; var id: UUID; var field: String }

    /// 쓴 쪽 — 앱 · 기기(판은 가르지 않는다 — 같은 기기의 판 올림은 제 이력이다).
    struct Source: Hashable {
        var app: String?
        var device: String?
        init(app: String?, device: String?) { self.app = app; self.device = device }
        init(_ e: EditLine) { self.init(app: e.app, device: e.device) }
    }

    /// 열쇠마다 마지막 고침(같은 때면 새 값의 정규화 글 차례 — 결정적). 종류 · 기록 · 칸 · 때 가운데 하나라도 빈 줄은 읽지 않는다.
    static func latest(_ edits: [EditLine]) -> [Key: EditLine] {
        var out: [Key: (at: Date, after: String, line: EditLine)] = [:]
        for e in edits {
            guard let kind = e.kind, let id = e.targetID, let field = e.field, let at = e.at else { continue }
            let key = Key(kind: kind, id: id, field: field), after = canonical(e.after) ?? ""
            if let have = out[key], (have.at, have.after) >= (at, after) { continue }
            out[key] = (at, after, e)
        }
        return out.mapValues(\.line)
    }

    static func sortKey(_ c: ChangeConflict) -> (String, String, String, Int) {
        switch c {
        case .sameField(let l, _): (l.kind ?? "", l.targetID?.uuidString ?? "", l.field ?? "", 0)
        case .editDeleted(let e, _, let local): (e.kind ?? "", e.targetID?.uuidString ?? "", e.field ?? "", local ? 1 : 2)
        }
    }

    static func shape(_ fields: [DataField], want: [DataField], later: Set<String>, path: String, what: String, into out: inout [SchemaIssue]) {
        for (j, f) in fields.enumerated() {
            let fp = "\(path).fields[\(j)]"
            guard let w = want.first(where: { $0.name == f.name }) else {
                out.append(SchemaIssue(path: fp, reason: "\(what)의 꼴에 없는 칸 ‘\(f.name)’")); continue
            }
            if f.type != w.type {
                out.append(SchemaIssue(path: fp, reason: "\(what)의 칸 ‘\(f.name)’ 의 형은 \(DataModelCoding.encodeType(w.type).plain) 이다(\(DataModelCoding.encodeType(f.type).plain))"))
            }
            if f.optional != w.optional {
                out.append(SchemaIssue(path: fp, reason: "\(what)의 칸 ‘\(f.name)’ 은 \(w.optional ? "선택" : "필수") 칸이다"))
            }
            if f.default != nil && w.type != .id {
                out.append(SchemaIssue(path: fp, reason: "\(what)의 칸 ‘\(f.name)’ 은 기본값을 두지 않는다(빈 값 = 모름)"))
            }
        }
        for w in want where !later.contains(w.name) && !fields.contains(where: { $0.name == w.name }) {
            out.append(SchemaIssue(path: path + ".fields", reason: "\(what)의 칸 ‘\(w.name)’ 이 없다"))
        }
    }
}

/// 정규화의 값 — 수를 십진으로 든다(JSON 글의 수 글자를 읽은 그대로 · 부동소수로 흐리지 않는다).
enum CanonicalValue: Encodable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([CanonicalValue])
    case object([String: CanonicalValue])

    /// JSON 글 → 값. 빈 값(nil · `null` · 읽지 못하는 글)은 nil.
    static func parse(_ json: String?) -> CanonicalValue? {
        guard let json, let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        let v = CanonicalValue(any)
        if case .null = v { return nil }
        return v
    }

    init(_ any: Any) {
        switch any {
        case is NSNull: self = .null
        case let s as String: self = .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue); return }
            self = .number(Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX")) ?? n.decimalValue)
        case let a as [Any]: self = .array(a.map(CanonicalValue.init))
        case let o as [String: Any]: self = .object(o.mapValues(CanonicalValue.init))
        default: self = .null
        }
    }

    var objectFields: [String: CanonicalValue]? { if case .object(let o) = self { o } else { nil } }

    /// 키 정렬 · 빗금 그대로의 한 줄 · 빈 값은 nil.
    var text: String? {
        if case .null = self { return nil }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
