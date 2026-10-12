import Foundation
import ProjectFormat
import Testing

// 공유 데이터 모델 — 매니페스트 칸의 꼴과 값 규칙 · 프로젝트들의 맞물림(판 · 저장 컨테이너) · CloudKit 호환 규칙(한 판 · 두 판 사이) · 이름 낱말 규칙.

@Suite struct SharedDataModelTests {
    static let ref = SharedDataModel(id: "com.example.garden.data", model: "../garden-data/garden.isodata", package: "../garden-data/GardenModel",
                                     revision: 2, cloudKitContainer: "iCloud.com.example.garden", appGroup: "group.com.example.garden")

    /// 칸 — 왕복 · 선택 칸은 없으면 쓰지 않는다 · 모르는 칸은 보존.
    @Test func roundTripsAndKeepsUnknownCells() throws {
        #expect(try JSONDecoder().decode(SharedDataModel.self, from: JSONEncoder().encode(Self.ref)) == Self.ref)
        let thin = try JSONDecoder().decode(SharedDataModel.self, from: Data(#"{"id":"com.example.d","model":"m.isodata","revision":1,"sync":"x"}"#.utf8))
        #expect(thin.package == nil && thin.cloudKitContainer == nil && thin.extra == ["sync": "x"])
        let back = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(thin))
        #expect(back == ["id": "com.example.d", "model": "m.isodata", "revision": 1, "sync": "x"])
    }

    /// 값 규칙 — 역 DNS id · 상대 경로(폴더 밖 허용) · 모델은 `.isodata` · 판 1 이상 · 컨테이너 머리.
    @Test func valueRules() {
        #expect(Self.ref.problems.isEmpty, "폴더 밖을 가리키는 상대 경로는 받는다")
        var r = Self.ref
        r.id = "garden"; r.model = "/abs/garden.isodata"; r.package = "~shared"; r.revision = 0
        r.cloudKitContainer = "com.example.garden"; r.appGroup = "example.garden"
        #expect(r.problems.count == 6, "\(r.problems)")
        r = Self.ref; r.model = "garden.json"
        #expect(r.problems == ["model ‘garden.json’ — 모델 파일(.isodata)이어야 한다"])
        r = Self.ref; r.appGroup = "ABCDE12345.com.example.garden"
        #expect(r.problems.isEmpty, "macOS 의 팀 id 머리 앱 그룹")
    }

    /// 맞물림 — 같은 id · 모델의 판 = 프로젝트마다 채택한 판 · 저장 컨테이너가 같다.
    @Test func lockstep() {
        var schema = DataSchema(name: "garden")
        schema.revision = 2
        let a = SharedModelLockstep.Member(project: "notes", reference: Self.ref)
        var other = Self.ref
        #expect(SharedModelLockstep.problems(model: schema, members: [a, .init(project: "atlas", reference: other)]).isEmpty)
        other.revision = 1
        #expect(SharedModelLockstep.problems(model: schema, members: [a, .init(project: "atlas", reference: other)]).map(\.path) == ["atlas.revision"])
        other = Self.ref; other.cloudKitContainer = "iCloud.com.example.other"; other.id = "com.example.other"
        #expect(SharedModelLockstep.problems(model: schema, members: [a, .init(project: "atlas", reference: other)]).map(\.path) == ["atlas.id", "atlas.cloudKitContainer"])
        schema.revision = nil
        #expect(SharedModelLockstep.problems(model: schema, members: [a]).map(\.path) == ["schema.revision"])
        #expect(SharedModelLockstep.problems(model: nil, members: [a]).map(\.path) == ["model"])
        #expect(SharedModelLockstep.problems(model: schema, members: []).isEmpty)
    }
}

@Suite struct CloudKitRulesTests {
    static func entity(_ fields: [DataField], rules: [DataRule] = [], status: DataStatus = .live) -> DataEntity {
        DataEntity(name: "Pot", status: status, fields: [DataField(name: "id", type: .id)] + fields, rules: rules)
    }

    /// 한 판 — 필수인데 기본값 없음 · 필수 참조 · 거절 삭제 규칙 · 고유 규칙 · 모르는 형. 실재가 아닌 엔티티 · 필드는 재지 않는다.
    @Test func oneVersion() {
        let schema = DataSchema(name: "g", entities: [
            Self.entity([DataField(name: "title", type: .text),
                         DataField(name: "note", type: .text, optional: true),
                         DataField(name: "size", type: .int, default: 1),
                         DataField(name: "owner", type: .ref("Pot", onDelete: .setNull)),
                         DataField(name: "parent", type: .ref("Pot", onDelete: .restrict), optional: true),
                         DataField(name: "site", type: .unknown("url"), optional: true),
                         DataField(name: "draft", type: .text, status: .seam)],
                        rules: [DataRule(id: "u", check: .unique(["title"]))]),
            DataEntity(name: "Old", status: .mock, fields: [DataField(name: "id", type: .id), DataField(name: "x", type: .text)]),
        ])
        let got = CloudKitRules.problems(schema)
        #expect(got.map(\.path) == ["schema.entities[0].fields[1]", "schema.entities[0].fields[4]", "schema.entities[0].fields[5]",
                                    "schema.entities[0].fields[6]", "schema.entities[0].rules[0]"], "\(got)")
        #expect(CloudKitRules.problems(DataSchema(name: "g", entities: [Self.entity([DataField(name: "n", type: .text, optional: true)])])).isEmpty)
    }

    /// 두 판 사이 — 칸 더하기만: 빠진 레코드 종류 · 칸 · 선택 → 필수 · 형 바뀜 · 열거 값 빠짐 · 참조 대상 바뀜. 칸 · 열거 값 · 엔티티 더하기는 받는다.
    @Test func betweenVersions() {
        let old = DataSchema(name: "g", entities: [
            Self.entity([DataField(name: "note", type: .text, optional: true), DataField(name: "kind", type: .enumeration(["a", "b"]), default: "a"),
                         DataField(name: "n", type: .int, optional: true), DataField(name: "up", type: .ref("Pot", onDelete: .setNull), optional: true),
                         DataField(name: "gone", type: .text, optional: true)]),
            DataEntity(name: "Shed", fields: [DataField(name: "id", type: .id)]),
        ])
        let grown = DataSchema(name: "g", entities: [
            Self.entity([DataField(name: "note", type: .text, optional: true), DataField(name: "kind", type: .enumeration(["a", "b", "c"]), default: "a"),
                         DataField(name: "n", type: .int, optional: true), DataField(name: "up", type: .ref("Pot", onDelete: .setNull), optional: true),
                         DataField(name: "gone", type: .text, optional: true), DataField(name: "more", type: .text, optional: true)]),
            DataEntity(name: "Shed", fields: [DataField(name: "id", type: .id)]),
            DataEntity(name: "Tool", fields: [DataField(name: "id", type: .id)]),
        ])
        #expect(CloudKitRules.evolutionProblems(from: old, to: grown).isEmpty, "더하기만")
        let broken = DataSchema(name: "g", entities: [
            Self.entity([DataField(name: "note", type: .text), DataField(name: "kind", type: .enumeration(["a"]), default: "a"),
                         DataField(name: "n", type: .decimal, optional: true), DataField(name: "up", type: .ref("Shed", onDelete: .setNull), optional: true)]),
            DataEntity(name: "Shed", swiftModel: "Barn", fields: [DataField(name: "id", type: .id)]),
            DataEntity(name: "Pot2", fields: [DataField(name: "id", type: .id)]),
        ])
        #expect(CloudKitRules.evolutionProblems(from: old, to: broken).map(\.reason).count == 6, "\(CloudKitRules.evolutionProblems(from: old, to: broken))")
    }

    @Test func dataNameWords() {
        #expect(DataNames.words("HarvestLogEntry") == ["harvest", "log", "entry"])
        #expect(DataNames.words("hoursOfSun") == ["hours", "of", "sun"])
        #expect(DataNames.words("URLPath") == ["url", "path"])
    }
}
