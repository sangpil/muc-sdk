import Foundation
@testable import ProjectFormat
import Testing

// 형식 4 — 읽기 · 최소 판 쓰기 · 읽기 규율(`DataModelCoding` 머리).

@Suite("isodata 4 — 읽기와 최소 판 쓰기")
struct IsoDataFileTests {

    /// 삶 파일(포맷 3)은 읽고 쓰면 바이트가 같다 — 새 판에서 열고 저장해도 3 으로 남는다.
    /// 표본 삶은 시험 자원(`Fixtures/sample-life.isodata`)이다 — 엔진 쪽 삶 파일은 엔진의 시험이 잰다.
    @Test func 삶_파일은_바이트_그대로_3으로() throws {
        let bytes = try IsoDataFixture.data("sample-life.isodata")
        let file = try IsoDataFile.read(bytes)
        #expect(!file.isModel)
        #expect(file.writtenVersion == 3)
        #expect(try file.encoded() == bytes)
    }

    @Test func 모델_파일은_4로_읽고_바이트_그대로_쓴다() throws {
        let bytes = try IsoDataFixture.data("sample-model.isodata")
        let file = try IsoDataFile.read(bytes)
        guard case .model(let m) = file else { Issue.record("모델 파일로 읽혀야 한다"); return }
        #expect(m.schema.name == "sample")
        #expect(m.schema.entities.map(\.name) == ["Pot", "Plant", "Watering", "Harvest"])
        #expect(m.datasetNames == ["bare", "spring"])
        #expect(m.issues == [])
        #expect(m.schema.revision == 1 && m.schema.idNamespace == nil)
        #expect(m.unknownKeys == [] && m.extra.isEmpty)
        #expect(file.writtenVersion == 4)
        // 표본은 쓰개가 쓴 꼴 그대로다(키 정렬 · 빈 칸 없음) — 표본은 SDK `qa/sample-model.mjs` 가 짓는다(손으로 고치지 않는다).
        #expect(try IsoDataFixture.golden("sample-model.isodata", String(decoding: try file.encoded(), as: UTF8.self)))
    }

    /// 벌 이름 차례 — 규약의 이름(`DataModelFile.datasetOrder`)이 그 차례로 먼저 · 나머지는 이름 차례.
    @Test func 벌_이름은_규약_차례_다음_이름_차례() {
        let names = ["spring", "long", "bare", "seed"]
        let file = DataModelFile(schema: DataSchema(name: "x"), datasets: Dictionary(uniqueKeysWithValues: names.map { ($0, DataSet()) }))
        #expect(file.datasetNames == ["seed", "long", "bare", "spring"])
    }

    @Test func 판_4로_찍혀도_모델_절이_없으면_3으로_쓴다() throws {
        let json = #"{ "version" : 4, "domain" : { "birth" : "2040-01-01", "lifeExpectancy" : 90 } }"#
        let file = try IsoDataFile.read(Data(json.utf8))
        #expect(!file.isModel)
        let back = try JSONDecoder().decode(JSONValue.self, from: try file.encoded())
        guard case .object(let o) = back else { Issue.record(); return }
        #expect(o["version"] == .number(3))
    }

    @Test func 미래_판은_이름을_대고_거부() {
        #expect(throws: IsoDataError.tooNew(5)) { try IsoDataFile.read(Data(#"{ "version" : 5 }"#.utf8)) }
    }

    @Test func 판_3에_모델_절은_거부() {
        #expect(throws: IsoDataError.self) {
            try IsoDataFile.read(Data(#"{ "version" : 3, "schema" : { "name" : "x" } }"#.utf8))
        }
    }

    @Test func 판이_없으면_거부() {
        #expect(throws: IsoDataError.invalid(path: "version", reason: "판 번호(정수)가 없다")) {
            try IsoDataFile.read(Data(#"{ "domain" : {} }"#.utf8))
        }
    }

    @Test func 상한을_넘는_파일은_거부() {
        let big = Data(repeating: 0x20, count: IsoDataFormat.maxBytes + 1)
        #expect(throws: IsoDataError.tooLarge(IsoDataFormat.maxBytes + 1)) { try IsoDataFile.read(big) }
    }

    /// 모델 파일 안의 모르는 키는 보존하고 알린다(읽기 규율 ③) — 맨 위 · 엔티티 · 필드 · 아는 하위 객체 안 · 형 객체 안 · 규칙 안 · 벌 · 시계.
    /// 다시 쓰면 그 키가 그대로 남는다(옛 읽개가 열어 저장해도 새 판의 칸이 사라지지 않는다). 삶 파일은 지금처럼 나른다.
    @Test func 모델_파일의_모르는_키는_보존하고_알린다() throws {
        let json = #"""
        { "version" : 4, "tags" : [ 1 ], "schema" : { "name" : "j", "flavor" : "x",
          "layers" : [ { "id" : "g", "tint" : 1 } ],
          "entities" : [ { "name" : "A", "layer" : "g", "icon" : "a", "swift" : { "model" : "A", "module" : "M" },
            "fields" : [ { "name" : "id", "type" : "id", "color" : "red" },
                         { "name" : "b", "type" : { "ref" : "A", "onDelete" : "cascade", "inverse" : "bs" }, "optional" : true } ],
            "rules" : [ { "id" : "r", "level" : 2, "check" : { "required" : "b", "severity" : "warn" } } ] } ] },
          "datasets" : { "s" : { "label" : "S", "mood" : 3, "clock" : { "now" : "2050-01-01T00:00:00Z", "tz" : "UTC", "dst" : false } } } }
        """#
        let file = try IsoDataFile.read(Data(json.utf8))
        guard case .model(let m) = file else { Issue.record("모델 파일로 읽혀야 한다"); return }
        #expect(m.unknownKeys.map { $0.components(separatedBy: " — ")[0] } == [
            "tags", "schema.flavor", "schema.layers[0].tint", "schema.entities[0].icon", "schema.entities[0].swift.module",
            "schema.entities[0].fields[0].color", "schema.entities[0].fields[1].type.inverse",
            "schema.entities[0].rules[0].level", "schema.entities[0].rules[0].check.severity",
            "datasets.s.mood", "datasets.s.clock.dst",
        ])
        #expect(m.extra == ["tags": [1]] && m.schema.extra == ["flavor": "x"] && m.schema.entities[0].extra["icon"] == "a")
        #expect(m.schema.entities[0].fields[1].type == .ref("A", onDelete: .cascade))
        // 다시 쓰면 모르는 키가 그 자리에 남는다 — 다시 읽은 값이 같고 알림도 같다
        let again = try IsoDataFile.read(try file.encoded())
        #expect(again == file)
        guard case .model(let m2) = again else { Issue.record(); return }
        #expect(m2.unknownKeys == m.unknownKeys)
        let life = #"{ "version" : 3, "domain" : { "birth" : "2040-01-01", "lifeExpectancy" : 90 }, "future" : true }"#
        guard case .life(let l) = try IsoDataFile.read(Data(life.utf8)) else { Issue.record(); return }
        #expect(l.body["future"] == .bool(true))
    }

    /// 아는 칸이 이긴다 — 모르는 칸 주머니에 아는 이름이 들어 있어도 쓰는 값은 꼴의 값 · 아는 하위 객체 안에서는 모르는 칸만 얹는다.
    @Test func 아는_칸이_모르는_칸을_이긴다() throws {
        var e = DataEntity(name: "A", swiftModel: "A", fields: [DataField(name: "id", type: .id)])
        e.extra = ["name": "X", "swift": ["model": "Q", "module": "M"], "icon": "a"]
        let file = IsoDataFile.model(DataModelFile(schema: DataSchema(name: "j", entities: [e])))
        let back = try JSONDecoder().decode(JSONValue.self, from: try file.encoded())
        guard case .object(let top) = back, case .object(let schema)? = top["schema"], case .array(let ents)? = schema["entities"],
              case .object(let ent)? = ents.first else { Issue.record("꼴이 아니다"); return }
        #expect(ent["name"] == "A" && ent["icon"] == "a")
        #expect(ent["swift"] == ["model": "A", "module": "M"])
    }

    /// 물러난 키(판 4 의 `migrated` · 엔티티와 필드의 `sql` — 저장 백엔드의 생성 사본)는 알리지 않고 들고 되쓴다 — 옛 파일이 그대로 읽히고 바이트가 남는다.
    @Test func 물러난_키는_알리지_않고_바이트_그대로() throws {
        let json = #"""
        { "version" : 4, "migrated" : { "sql" : { "tables" : { "as" : { "id" : { "type" : "text", "primaryKey" : true } } } }, "swift" : { "schemaVersion" : 1 } },
          "schema" : { "name" : "j", "entities" : [ { "name" : "A", "sql" : { "table" : "as" },
            "fields" : [ { "name" : "id", "type" : "id", "sql" : { "column" : "id" } } ] } ] } }
        """#
        let file = try IsoDataFile.read(Data(json.utf8))
        guard case .model(let m) = file else { Issue.record(); return }
        #expect(m.unknownKeys.isEmpty, "물러난 키는 더 새 판의 흔적이 아니다")
        #expect(m.extra["migrated"] != nil && m.schema.entities[0].extra["sql"] == ["table": "as"])
        let back = try JSONDecoder().decode(JSONValue.self, from: try file.encoded())
        #expect(back == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))), "값이 그대로 남는다")
    }

    /// 모르는 낱말 — 형 · 상태 · 삭제 규칙 · 규칙은 글자 그대로 들고(파일을 거부하지 않는다) 경고 한 줄씩 · 다시 쓰면 글자 그대로.
    @Test func 모르는_낱말은_읽고_경고하고_그대로_쓴다() throws {
        let json = #"""
        { "version" : 4, "schema" : { "name" : "j", "entities" : [ { "name" : "A", "status" : "archived",
          "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "site", "type" : "url" }, { "name" : "span", "type" : { "range" : "int" } },
                       { "name" : "up", "type" : { "ref" : "A", "onDelete" : "noAction" }, "optional" : true } ],
          "rules" : [ { "id" : "r", "check" : { "pattern" : "site", "regex" : "^h" } } ] } ] },
          "datasets" : { "s" : { "records" : { "A" : [ { "id" : "a-1", "site" : 3, "span" : "x" } ] } } } }
        """#
        let file = try IsoDataFile.read(Data(json.utf8))
        guard case .model(let m) = file else { Issue.record(); return }
        let e = m.schema.entities[0]
        #expect(e.status.rawValue == "archived" && !DataStatus.known.contains(e.status) && !e.status.isPhysical)
        #expect(e.fields[1].type == .unknown("url") && e.fields[2].type == .unknown(["range": "int"]))
        #expect(e.fields[3].type == .ref("A", onDelete: DataOnDelete(rawValue: "noAction")))
        #expect(e.rules[0].check == .other(kind: "pattern", body: ["pattern": "site", "regex": "^h"]))
        #expect(m.issues.isEmpty, "모르는 형의 값은 재지 않는다")
        let w = SchemaValidation.warnings(m.schema)
        #expect(w.contains("A — 이 빌드가 모르는 상태 ‘archived’(읽기 전용)"))
        #expect(w.contains("A.site — 이 빌드가 모르는 형 ‘url’(읽기 전용)"))
        #expect(w.contains("A.up — 이 빌드가 모르는 형 ‘삭제 규칙 noAction’(읽기 전용)"))
        #expect(w.contains("A — 규칙 ‘r’ 의 낱말 ‘pattern’ 을 이 빌드가 모른다(재지 않는다)"))
        #expect(try IsoDataFile.read(try file.encoded()) == file, "글자 그대로 쓴다")
    }

    /// 읽기 전용 창 — 미래 판도 `allowingNewer` 면 읽는다(모르는 키는 보존 · 알림).
    @Test func 미래_판은_읽기_전용으로_열린다() throws {
        let json = #"{ "version" : 5, "schema" : { "name" : "j", "entities" : [ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" } ] } ], "sync" : "cloud" } }"#
        #expect(throws: IsoDataError.tooNew(5)) { try IsoDataFile.read(Data(json.utf8)) }
        guard case .model(let m) = try IsoDataFile.read(Data(json.utf8), allowingNewer: true) else { Issue.record(); return }
        #expect(m.unknownKeys.count == 1 && m.schema.extra == ["sync": "cloud"])
    }

    /// 스키마의 이름공간 머리 · 판 — 선택 칸(적으면 쓰고 · 없으면 쓰지 않는다) · 판은 1 이상.
    @Test func 이름공간_머리와_스키마_판은_선택_칸() throws {
        let json = #"{ "version" : 4, "schema" : { "name" : "j", "idNamespace" : "com.example.rows", "revision" : 3 } }"#
        guard case .model(let m) = try IsoDataFile.read(Data(json.utf8)) else { Issue.record(); return }
        #expect(m.schema.idNamespace == "com.example.rows" && m.schema.revision == 3 && m.unknownKeys.isEmpty)
        let written = String(decoding: try IsoDataFile.model(m).encoded(), as: UTF8.self)
        #expect(written.contains(#""idNamespace" : "com.example.rows""#) && written.contains(#""revision" : 3"#))
        #expect(throws: IsoDataError.self) { try IsoDataFile.read(Data(#"{ "version" : 4, "schema" : { "name" : "j", "revision" : 0 } }"#.utf8)) }
    }

    @Test func 설명_오류_글은_한국어() {
        #expect(IsoDataError.tooNew(5).errorDescription?.contains("더 새 판") == true)
    }
}

@Suite("스키마 검증 — 경로를 대고 파일 전체를 거부")
struct SchemaValidationTests {

    func schema(_ entities: String, extra: String = "") -> Data {
        Data(#"{ "version" : 4, "schema" : { "name" : "j", "entities" : \#(entities)\#(extra) } }"#.utf8)
    }

    func path(of data: Data) -> String? {
        do { _ = try IsoDataFile.read(data); return nil } catch let IsoDataError.invalid(path, _) { return path } catch { return "?" }
    }

    @Test func 없는_엔티티를_가리키는_참조() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "bId", "type" : { "ref" : "B" } } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].fields[1].type.ref")
    }

    @Test func 형은_낱말_또는_객체() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "n", "type" : 3 } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].fields[1].type")
    }

    @Test func 엔티티_이름_겹침() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" } ] }, { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" } ] } ]"#)
        #expect(path(of: d) == "schema.entities[1].name")
    }

    @Test func 필드_이름_겹침() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "x", "type" : "text" }, { "name" : "x", "type" : "int" } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].fields[2].name")
    }

    @Test func 정체는_정확히_하나() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "x", "type" : "text" } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].fields")
    }

    @Test func 없는_공통_필드_묶음과_값_타입() {
        let uses = schema(#"[ { "name" : "A", "uses" : [ "Nope" ], "fields" : [ { "name" : "id", "type" : "id" } ] } ]"#)
        #expect(path(of: uses) == "schema.entities[0].uses[0]")
        let value = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "g", "type" : { "value" : "Unknown" } } ] } ]"#)
        #expect(path(of: value) == "schema.entities[0].fields[1].type.value")
    }

    @Test func 참조_목록은_조인_엔티티로() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "xs", "type" : { "list" : { "ref" : "A" } } } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].fields[1].type.list")
    }

    @Test func 규칙이_없는_필드를_가리킨다() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" } ], "rules" : [ { "id" : "r", "check" : { "required" : "nope" } } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].rules[0].check.required")
    }

    @Test func 상태는_글자() {
        let d = schema(#"[ { "name" : "A", "status" : 1, "fields" : [ { "name" : "id", "type" : "id" } ] } ]"#)
        #expect(path(of: d) == "schema.entities[0].status")
    }

    @Test func 경고는_막지_않는다() throws {
        let m = try IsoDataFixture.model()
        let warnings = SchemaValidation.warnings(m.schema)
        // Plant.kind 는 필수인데 기본값이 없다 — CloudKit 규약 노랑.
        #expect(warnings.contains("Plant.kind — 필수인데 기본값이 없다: CloudKit 전환에서 막힌다"))
    }
}

/// 시험 자원 — 판 4 표본 · 표본 삶(`Fixtures/`) · 이 시험만 읽는다(엔진의 시험은 제 자원을 든다).
enum IsoDataFixture {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }

    static func model() throws -> DataModelFile {
        guard case .model(let m) = try IsoDataFile.read(try data("sample-model.isodata")) else { throw CocoaError(.fileReadCorruptFile) }
        return m
    }

    /// 골든 비교 — `ISODATA_RECORD=1` 이면 기대 파일을 새로 쓴다(소스 자리에 — 다시 쓴 바이트가 표본을 짓는 스크립트의 바이트와 다르면 그 스크립트의 검사가 빨강이다).
    static func golden(_ name: String, _ actual: String) throws -> Bool {
        if ProcessInfo.processInfo.environment["ISODATA_RECORD"] == "1" {
            try actual.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            return true
        }
        return String(decoding: try data(name), as: UTF8.self) == actual
    }
}
