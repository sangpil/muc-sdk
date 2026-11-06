import Foundation
@testable import ProjectFormat
import Testing

// 고침 기록 규약(`ChangeLog`) — 정규화 · 요약의 바이트 · 보관 · 합치기 · 충돌 · 표지 둘의 꼴과 읽고 쓰기.
// 정규화 · 요약의 기대 글자는 이 규약을 먼저 쓴 쪽의 셈(JSON 글 → 읽기(수는 십진) → 키 정렬 · 빗금 그대로 → SHA-256)으로 따로 잰 값이다 —
// 두 앱이 같은 값에 같은 바이트를 내는 것이 이 규약의 몫이라 글자째 붙든다.

@Suite("고침 기록 — 정규화 · 요약")
struct ChangeLogValueTests {

    /// (입력 JSON 글, 정규화 글, 요약)
    static let cases: [(String, String?, String?)] = [
        (#"{"b":1,"a":"x/y"}"#, #"{"a":"x/y","b":1}"#, "sha256:0acee55b8e12ac14a243a8be247ca94cba02af907fcb0ed2e6f23ee33ed2ea11"),
        ("0.1", "0.1", "sha256:14be4b45f18e0d8c67b4f719b5144eee88497e413709d11d85b096d8e2346310"),
        ("1.50", "1.5", "sha256:9f29a130438b81170b92a42650f9a94291ecad60bd47af2a3886e75f7f728725"),
        (#""물 주기""#, #""물 주기""#, "sha256:c02a74d5441970e3fda955faae28528139558ba6479318e4304bab882fa5146a"),
        ("[3,1.25,null]", "[3,1.25,null]", "sha256:11855f3ed16444e710052542d413c84ce0de3be89345ae2402c1b68c026299e0"),
        ("2000000", "2000000", "sha256:dd80d7a873341d491936c851964a9793195f37e646f6809dd546e2946f46d283"),
        (#"{"z":[{"y":true}],"a":-0.5}"#, #"{"a":-0.5,"z":[{"y":true}]}"#, "sha256:daf02895d1aa973464fe30946e7e3906954112a145cdeaac97db6dcdc5c71c45"),
        ("12345678901234567890", "12345678901234567890", "sha256:6ed645ef0e1abea1bf1e4e935ff04f9e18d39812387f63cda3415b46240f0405"),
        ("1e3", "1000", "sha256:40510175845988f13f6162ed8526f0b09f73384467fa855e1e79b44a56562a58"),
        // 수는 읽개가 내는 십진 글자(유효 숫자 15)로 선다 — 부동소수의 끝자리 글자가 아니다
        ("0.30000000000000004", "0.3", "sha256:221764976efe04132774d96b0253cc31434c5261737469324f222621baf34b20"),
        (#""a\"b\\cé\n""#, #""a\"b\\cé\n""#, "sha256:1f550f48637c3f5d89dc33aa1bde7cbb5d28c3d97ac2a64337cdb793bba038e6"),
        (#"{"pot":"창가","ml":200}"#, #"{"ml":200,"pot":"창가"}"#, "sha256:52deb450b9762aadf9c22136abca0683c564c6bf959d8576f0f0573cd89028a2"),
        ("null", nil, nil),
        ("not json", nil, nil),
    ]

    @Test func 정규화와_요약은_글자째_같다() {
        for (input, canon, digest) in Self.cases {
            #expect(ChangeLog.canonical(input) == canon, "정규화 — \(input)")
            #expect(ChangeLog.digest(input) == digest, "요약 — \(input)")
        }
        #expect(ChangeLog.canonical(nil as String?) == nil && ChangeLog.digest(nil as String?) == nil)
    }

    /// 정규화는 한 번이면 선다 — 정규화한 글을 다시 넣어도 같은 글 · 같은 요약.
    @Test func 정규화는_되풀이해도_같다() {
        for (input, canon, _) in Self.cases {
            #expect(ChangeLog.canonical(canon) == canon, "\(input)")
            #expect(ChangeLog.digest(canon) == ChangeLog.digest(input), "\(input)")
        }
    }

    @Test func JSON_값도_같은_글() {
        let v: JSONValue = ["pot": "창가", "ml": 200]
        #expect(ChangeLog.canonical(v) == #"{"ml":200,"pot":"창가"}"#)
        #expect(ChangeLog.digest(v) == "sha256:52deb450b9762aadf9c22136abca0683c564c6bf959d8576f0f0573cd89028a2")
        #expect(ChangeLog.canonical(JSONValue.null) == nil && ChangeLog.digest(JSONValue.null) == nil)
    }

    @Test func 요약_글은_JSON_글자_값() {
        let text = ChangeLog.digestText("2000000")
        #expect(text == #""sha256:dd80d7a873341d491936c851964a9793195f37e646f6809dd546e2946f46d283""#)
        #expect(ChangeLog.isDigest(text) && !ChangeLog.isDigest("2000000") && !ChangeLog.isDigest(nil) && !ChangeLog.isDigest(#""sha1:00""#))
        #expect(ChangeLog.digestText(nil) == nil)
    }
}

@Suite("고침 기록 — 보관 · 합치기")
struct ChangeLogKeepTests {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func 보관은_30일() {
        #expect(ChangeLog.retention == 30 * 24 * 60 * 60 && ChangeLog.coalesceWindow == 30)
        #expect(!ChangeLog.expired(Self.now.addingTimeInterval(-ChangeLog.retention), now: Self.now))
        #expect(ChangeLog.expired(Self.now.addingTimeInterval(-ChangeLog.retention - 1), now: Self.now))
        #expect(ChangeLog.expired(nil, now: Self.now), "때가 빈 줄은 지난 줄")
        #expect(!ChangeLog.expired(Self.now.addingTimeInterval(-100), now: Self.now, keep: 200))
    }

    static let pot = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    static func line(_ device: String, _ field: String, _ ago: TimeInterval, kind: String = "Pot", id: UUID = pot) -> EditLine {
        EditLine(kind: kind, targetID: id, field: field, before: "1", after: "2", app: "com.example.garden", device: device, at: now.addingTimeInterval(-ago))
    }

    @Test func 창_안의_같은_칸_마지막_줄과_합친다() {
        let lines = [Self.line("d1", "label", 20), Self.line("d1", "label", 10), Self.line("d1", "glaze", 5), Self.line("d2", "label", 50)]
        #expect(ChangeLog.coalesceTarget(in: lines, kind: "Pot", targetID: Self.pot, field: "label", device: "d1", now: Self.now) == 1)
        #expect(ChangeLog.coalesceTarget(in: lines, kind: "Pot", targetID: Self.pot, field: "glaze", device: "d1", now: Self.now) == 2)
        // 창 밖 · 다른 기기 · 다른 기록은 새 줄
        #expect(ChangeLog.coalesceTarget(in: [Self.line("d1", "label", 31)], kind: "Pot", targetID: Self.pot, field: "label", device: "d1", now: Self.now) == nil)
        #expect(ChangeLog.coalesceTarget(in: lines, kind: "Pot", targetID: Self.pot, field: "label", device: "d3", now: Self.now) == nil)
        #expect(ChangeLog.coalesceTarget(in: lines, kind: "Plant", targetID: Self.pot, field: "label", device: "d1", now: Self.now) == nil)
    }

    @Test func 그_뒤에_다른_기기의_같은_칸_줄이_있으면_합치지_않는다() {
        let lines = [Self.line("d1", "label", 20), Self.line("d2", "label", 10)]
        #expect(ChangeLog.coalesceTarget(in: lines, kind: "Pot", targetID: Self.pot, field: "label", device: "d1", now: Self.now) == nil)
        // 다른 기기의 줄이 그 앞이면 합친다
        let before = [Self.line("d2", "label", 25), Self.line("d1", "label", 20)]
        #expect(ChangeLog.coalesceTarget(in: before, kind: "Pot", targetID: Self.pot, field: "label", device: "d1", now: Self.now) == 1)
    }

    @Test func 쓴_쪽의_값을_채운_줄() {
        let w = ChangeWriter(app: "com.example.garden", version: "1.2", device: "d1")
        let e = EditLine(kind: "Pot", targetID: Self.pot, field: "label", before: nil, after: #""창가""#, writer: w, at: Self.now)
        #expect(e.app == "com.example.garden" && e.appVersion == "1.2" && e.device == "d1" && e.at == Self.now)
        let batch = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!
        let d = DeletionLine(kind: "Pot", targetID: Self.pot, batchID: batch, snapshot: "{}", snapshotRevision: 2, writer: w, at: Self.now)
        #expect(d.appVersion == "1.2" && d.deletedAt == Self.now && d.batchID == batch && d.snapshotRevision == 2)
    }
}

@Suite("고침 기록 — 충돌")
struct ChangeLogConflictTests {
    static let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    static let pot = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    static let plant = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!

    static func edit(_ device: String, _ field: String, _ before: String?, _ after: String?, at: TimeInterval, id: UUID = pot, app: String = "com.example.garden") -> EditLine {
        EditLine(kind: "Pot", targetID: id, field: field, before: before, after: after, app: app, device: device, at: t0.addingTimeInterval(at))
    }
    static func deletion(_ device: String, _ snapshot: String?, id: UUID = pot, app: String = "com.example.garden") -> DeletionLine {
        DeletionLine(kind: "Pot", targetID: id, snapshot: snapshot, deletedAt: t0.addingTimeInterval(100), app: app, device: device)
    }

    @Test func 같은_칸을_서로_모르고_고치면_충돌() {
        let l = Self.edit("d1", "label", #""a""#, #""b""#, at: 1), i = Self.edit("d2", "label", #""a""#, #""c""#, at: 2)
        #expect(ChangeLog.conflicts(local: .init(edits: [l]), incoming: .init(edits: [i])) == [.sameField(local: l, incoming: i)])
    }

    @Test func 같은_새_값_이어_고침_같은_쪽은_충돌이_아니다() {
        let l = Self.edit("d1", "label", #""a""#, #""b""#, at: 1)
        // 새 값이 같다(정규화 — 키 차례 · 수 글자 무관)
        #expect(ChangeLog.conflicts(local: .init(edits: [Self.edit("d1", "n", "1", "1.50", at: 1)]), incoming: .init(edits: [Self.edit("d2", "n", "1", "1.5", at: 2)])).isEmpty)
        // 이어 고침 — 들어온 쪽의 전 값이 이 기기의 새 값
        #expect(ChangeLog.conflicts(local: .init(edits: [l]), incoming: .init(edits: [Self.edit("d2", "label", #""b""#, #""c""#, at: 2)])).isEmpty)
        // 이어 고침 — 이 기기의 전 값이 들어온 새 값
        #expect(ChangeLog.conflicts(local: .init(edits: [Self.edit("d1", "label", #""c""#, #""d""#, at: 3)]), incoming: .init(edits: [Self.edit("d2", "label", #""a""#, #""c""#, at: 2)])).isEmpty)
        // 같은 쪽(앱 · 기기)
        #expect(ChangeLog.conflicts(local: .init(edits: [l]), incoming: .init(edits: [Self.edit("d1", "label", #""a""#, #""z""#, at: 2)])).isEmpty)
        // 빈 칸 = null
        #expect(ChangeLog.conflicts(local: .init(edits: [Self.edit("d1", "note", "1", nil, at: 1)]), incoming: .init(edits: [Self.edit("d2", "note", "1", "null", at: 2)])).isEmpty)
    }

    @Test func 마지막_고침끼리_맞댄다() {
        // 이 기기의 마지막 고침이 들어온 값을 이어 고쳤다 — 앞선 줄은 대조에 들지 않는다
        let early = Self.edit("d1", "label", #""a""#, #""b""#, at: 1), last = Self.edit("d1", "label", #""c""#, #""d""#, at: 5)
        let theirs = Self.edit("d2", "label", #""a""#, #""c""#, at: 3)
        #expect(ChangeLog.conflicts(local: .init(edits: [last, early]), incoming: .init(edits: [theirs])).isEmpty)
        // 읽을 수 없는 줄(때 없음)은 대조에 들지 않는다
        var blank = Self.edit("d2", "label", #""a""#, #""z""#, at: 9)
        blank.at = nil
        #expect(ChangeLog.conflicts(local: .init(edits: [last]), incoming: .init(edits: [theirs, blank])).isEmpty)
    }

    @Test func 지운_기록을_다른_곳이_고치면_충돌() {
        let e = Self.edit("d1", "label", #""a""#, #""b""#, at: 1)
        let unseen = Self.deletion("d2", #"{"id":"x","label":"a"}"#)
        #expect(ChangeLog.conflicts(local: .init(edits: [e]), incoming: .init(deletions: [unseen])) == [.editDeleted(edit: e, deletion: unseen, editIsLocal: true)])
        // 지운 쪽이 그 고침을 보고 지웠다
        let seen = Self.deletion("d2", #"{"id":"x","label":"b"}"#)
        #expect(ChangeLog.conflicts(local: .init(edits: [e]), incoming: .init(deletions: [seen])).isEmpty)
        // 이 기기가 지운 기록을 들어온 고침이 고쳤다
        let theirs = Self.edit("d2", "label", #""a""#, #""c""#, at: 1)
        let mine = Self.deletion("d1", #"{"label":"a"}"#)
        #expect(ChangeLog.conflicts(local: .init(deletions: [mine]), incoming: .init(edits: [theirs])) == [.editDeleted(edit: theirs, deletion: mine, editIsLocal: false)])
        // 양쪽이 다 지운 것 · 다른 기록은 충돌이 아니다
        #expect(ChangeLog.conflicts(local: .init(deletions: [mine]), incoming: .init(deletions: [unseen])).isEmpty)
        #expect(ChangeLog.conflicts(local: .init(edits: [Self.edit("d1", "label", nil, "1", at: 1, id: Self.plant)]), incoming: .init(deletions: [unseen])).isEmpty)
    }

    @Test func 요약_칸은_스냅샷을_같은_요약으로_맞댄다() {
        let secret = #""긴 메모""#
        let e = Self.edit("d1", "note", nil, ChangeLog.digestText(secret), at: 1)
        let d = Self.deletion("d2", #"{"note":"긴 메모"}"#)
        // 요약 대상 칸이면 스냅샷의 평문을 요약해 맞댄다(보고 지웠다)
        #expect(ChangeLog.conflicts(local: .init(edits: [e]), incoming: .init(deletions: [d]), digestible: { $1 == "note" }).isEmpty)
        // 요약 대상이 아니면 평문 ⟂ 요약 글이라 다른 값
        #expect(ChangeLog.conflicts(local: .init(edits: [e]), incoming: .init(deletions: [d])).count == 1)
    }

    @Test func 결과는_종류_기록_칸_차례() {
        let a = Self.edit("d1", "b", "1", "2", at: 1), b = Self.edit("d2", "b", "1", "3", at: 1)
        let c = Self.edit("d1", "a", "1", "2", at: 1), d = Self.edit("d2", "a", "1", "3", at: 1)
        let out = ChangeLog.conflicts(local: .init(edits: [a, c]), incoming: .init(edits: [b, d]))
        #expect(out == [.sameField(local: c, incoming: d), .sameField(local: a, incoming: b)])
    }

    @Test func 이_기기_것과_들어온_것으로_가른다() {
        let all = ChangeLines(edits: [Self.edit("d1", "a", nil, "1", at: 1), Self.edit("d2", "a", nil, "1", at: 1)], deletions: [Self.deletion("d2", nil)])
        let (local, incoming) = all.split(device: "d1")
        #expect(local.edits.count == 1 && local.deletions.isEmpty && incoming.edits.count == 1 && incoming.deletions.count == 1)
    }
}

@Suite("고침 기록 — 표지 둘의 꼴")
struct ChangeLogShapeTests {

    static func marked(edit: [DataField] = ChangeLog.editFields, deletion: [DataField] = ChangeLog.deletionFields,
                       provenance: [DataField] = ChangeLog.provenanceFields) -> DataSchema {
        var stamp = DataTrait(name: "Stamped", fields: provenance)
        stamp.role = .provenance
        var edits = DataEntity(name: "EditTrail", fields: edit)
        edits.log = .edit
        var removals = DataEntity(name: "RemovalTrail", fields: deletion)
        removals.log = .deletion
        return DataSchema(name: "garden", entities: [DataEntity(name: "Pot", uses: ["Stamped"], fields: [DataField(name: "id", type: .id)]), edits, removals],
                          traits: [stamp])
    }

    @Test func 규약의_꼴이면_문제_0() {
        #expect(ChangeLog.problems(Self.marked()) == [])
        #expect(ChangeLog.problems(DataSchema(name: "plain")) == [], "표지가 없으면 재지 않는다")
        // 뒤에 더한 칸(`appVersion`)은 없어도 된다
        #expect(ChangeLog.problems(Self.marked(edit: ChangeLog.editFields.filter { $0.name != "appVersion" },
                                               deletion: ChangeLog.deletionFields.filter { $0.name != "appVersion" })) == [])
        #expect(SchemaValidation.errors(Self.marked()).isEmpty && CloudKitRules.problems(Self.marked()).isEmpty)
    }

    @Test func 칸이_어긋나면_자리를_댄다() {
        var edit = ChangeLog.editFields.filter { $0.name != "field" }
        edit[1].type = .longText                                   // kind
        edit.append(DataField(name: "potId", type: .ref("Pot", onDelete: .setNull), optional: true))
        var prov = ChangeLog.provenanceFields
        prov[2].optional = false                                   // updatedAt
        let issues = ChangeLog.problems(Self.marked(edit: edit, provenance: prov))
        #expect(issues.map(\.path) == ["schema.traits[0].fields[2]", "schema.entities[1].fields[1]", "schema.entities[1].fields[9]", "schema.entities[1].fields"])
        #expect(issues[1].reason.contains("text") && issues[2].reason.contains("potId") && issues[3].reason.contains("field"))
    }

    @Test func 모르는_낱말과_두_벌() {
        var s = Self.marked()
        s.entities[2].log = .edit
        var odd = DataTrait(name: "Odd")
        odd.role = DataTraitRole(rawValue: "audit")
        s.traits.append(odd)
        s.entities[0].log = DataLogKind(rawValue: "archive")
        let paths = ChangeLog.problems(s).map(\.path)
        #expect(paths.contains("schema.traits[1]") && paths.contains("schema.entities[0]") && paths.contains("schema.entities[2]"))
        #expect(DataTraitRole.known == [.provenance] && DataLogKind.known == [.edit, .deletion])
    }

    @Test func 표지는_읽고_되쓴다() throws {
        let bytes = try IsoDataFile.model(DataModelFile(schema: Self.marked())).encoded()
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(#""role" : "provenance""#) && text.contains(#""log" : "edit""#) && text.contains(#""log" : "deletion""#))
        guard case .model(let m) = try IsoDataFile.read(bytes) else { Issue.record("모델 파일로 읽혀야 한다"); return }
        #expect(m.schema == Self.marked() && m.unknownKeys.isEmpty)
        #expect(try IsoDataFile.model(m).encoded() == bytes)
        // 모르는 낱말도 글자 그대로
        let odd = Data(#"{ "version" : \#(IsoDataFormat.version), "schema" : { "name" : "g", "traits" : [ { "name" : "T", "role" : "audit" } ], "entities" : [ { "name" : "E", "log" : "archive", "fields" : [ { "name" : "id", "type" : "id" } ] } ] } }"#.utf8)
        guard case .model(let o) = try IsoDataFile.read(odd) else { Issue.record("모델 파일로 읽혀야 한다"); return }
        #expect(o.schema.traits[0].role?.rawValue == "audit" && o.schema.entities[0].log?.rawValue == "archive" && o.unknownKeys.isEmpty)
    }
}
