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
        #expect(m.migrated.swiftSchemaVersion == 1)
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

    /// 모델 파일 안의 모르는 키는 거부 — 저장하면 사라질 것이라서(읽기 규율 ③). 삶 파일은 지금처럼 나른다.
    @Test func 모델_파일의_모르는_키는_경로를_대고_거부() throws {
        let top = #"{ "version" : 4, "schema" : { "name" : "j" }, "extra" : 1 }"#
        #expect(throws: IsoDataError.invalid(path: "extra", reason: "모르는 키 — 더 새 판의 흔적이거나 오타다(모델 파일은 모르는 키를 받지 않는다)")) {
            try IsoDataFile.read(Data(top.utf8))
        }
        let nested = #"{ "version" : 4, "schema" : { "name" : "j", "entities" : [ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id", "color" : "red" } ] } ] } }"#
        do {
            _ = try IsoDataFile.read(Data(nested.utf8))
            Issue.record("거부해야 한다")
        } catch let IsoDataError.invalid(path, _) {
            #expect(path == "schema.entities[0].fields[0].color")
        }
        let life = #"{ "version" : 3, "domain" : { "birth" : "2040-01-01", "lifeExpectancy" : 90 }, "future" : true }"#
        let file = try IsoDataFile.read(Data(life.utf8))
        guard case .life(let l) = file else { Issue.record(); return }
        #expect(l.body["future"] == .bool(true))
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

    @Test func 모르는_형_낱말() {
        let d = schema(#"[ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "n", "type" : "float" } ] } ]"#)
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

    @Test func 모르는_상태_낱말() {
        let d = schema(#"[ { "name" : "A", "status" : "gone", "fields" : [ { "name" : "id", "type" : "id" } ] } ]"#)
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
