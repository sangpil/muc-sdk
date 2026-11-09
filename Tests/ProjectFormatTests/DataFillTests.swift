import Foundation
@testable import ProjectFormat
import Testing

// 채우는 손(필드의 선택 키 `fill` — `DataFill`) — 열린 꼴 · 읽고 되쓴다 · 없으면 키를 쓰지 않는다 · 모르는 낱말은 경고 한 줄.

@Suite("isodata — 채우는 손")
struct DataFillTests {

    static let file = #"""
    {
      "schema" : {
        "entities" : [
          {
            "fields" : [
              {
                "name" : "id",
                "type" : "id"
              },
              {
                "fill" : "model",
                "name" : "title",
                "type" : "text"
              },
              {
                "fill" : "rule",
                "name" : "sown",
                "optional" : true,
                "type" : "date"
              },
              {
                "fill" : "lookup",
                "name" : "potId",
                "optional" : true,
                "type" : {
                  "onDelete" : "setNull",
                  "ref" : "Pot"
                }
              },
              {
                "fill" : "person",
                "name" : "note",
                "optional" : true,
                "type" : "longText"
              },
              {
                "fill" : "derived",
                "name" : "total",
                "optional" : true,
                "type" : "int"
              },
              {
                "fill" : "sensor",
                "name" : "moisture",
                "optional" : true,
                "type" : "decimal"
              },
              {
                "name" : "height",
                "optional" : true,
                "type" : "decimal"
              }
            ],
            "name" : "Plant"
          },
          {
            "fields" : [
              {
                "name" : "id",
                "type" : "id"
              }
            ],
            "name" : "Pot"
          }
        ],
        "name" : "g",
        "traits" : [
          {
            "fields" : [
              {
                "fill" : "derived",
                "name" : "createdAt",
                "optional" : true,
                "type" : "instant"
              }
            ],
            "name" : "Stamped"
          }
        ],
        "values" : [
          {
            "fields" : [
              {
                "fill" : "rule",
                "name" : "cm",
                "type" : "decimal"
              }
            ],
            "name" : "Length"
          }
        ]
      },
      "version" : \#(IsoDataFormat.version)
    }
    """#

    @Test func 아는_낱말은_다섯_차례대로() {
        #expect(DataFill.known.map(\.rawValue) == ["model", "rule", "lookup", "person", "derived"])
    }

    /// 엔티티 · 공통 필드 묶음 · 값 타입의 필드 모두 — 아는 낱말과 모르는 낱말을 글자 그대로 들고 · 모르는 키로 알리지 않고 · 바이트 그대로 되쓴다.
    @Test func 채우는_손은_읽고_바이트_그대로_되쓴다() throws {
        let bytes = Data(Self.file.utf8)
        guard case .model(let m) = try IsoDataFile.read(bytes) else { Issue.record("모델 파일로 읽혀야 한다"); return }
        let plant = try #require(m.schema.entity("Plant"))
        #expect(plant.fields.map(\.fill) == [nil, .model, .rule, .lookup, .person, .derived, DataFill(rawValue: "sensor"), nil])
        #expect(m.schema.trait("Stamped")?.fields.first?.fill == .derived)
        #expect(m.schema.valueType("Length")?.fields.first?.fill == .rule)
        #expect(m.unknownKeys.isEmpty && plant.fields.allSatisfy { $0.extra.isEmpty })
        #expect(try IsoDataFile.model(m).encoded() == bytes)
    }

    /// 선언이 없으면 키를 쓰지 않는다 — 이 키를 모르던 판이 쓴 파일은 읽고 쓰면 바이트가 같다(표본 모델의 골든은 `IsoDataFileTests` 가 잰다).
    @Test func 선언이_없으면_키를_쓰지_않는다() throws {
        var field = DataField(name: "height", type: .decimal, optional: true)
        #expect(field.fill == nil)
        let plain = DataModelCoding.encodeField(field)
        #expect(plain["fill"] == nil)
        field.fill = .rule
        #expect(DataModelCoding.encodeField(field)["fill"] == "rule")
    }

    /// 모르는 낱말은 경고 한 줄(막지 않는다) · 아는 낱말은 경고 0.
    @Test func 모르는_낱말은_경고_한_줄() throws {
        guard case .model(let m) = try IsoDataFile.read(Data(Self.file.utf8)) else { Issue.record(); return }
        let lines = SchemaValidation.warnings(m.schema).filter { $0.contains("채우는 손") }
        #expect(lines == ["Plant.moisture — 이 빌드가 모르는 채우는 손 ‘sensor’(그대로 둔다)"])
        #expect(SchemaValidation.errors(m.schema).isEmpty)
    }

    /// 낱말이 아니면 경로를 대고 파일 전체를 거부한다(스키마가 먼저 선다).
    @Test func 글자가_아니면_거부() {
        let json = #"{ "version" : \#(IsoDataFormat.version), "schema" : { "name" : "g", "entities" : [ { "name" : "A", "fields" : [ { "name" : "id", "type" : "id" }, { "name" : "n", "type" : "int", "fill" : 3 } ] } ] } }"#
        #expect(throws: IsoDataError.invalid(path: "schema.entities[0].fields[1].fill", reason: "글자여야 한다")) {
            try IsoDataFile.read(Data(json.utf8))
        }
    }

    /// 이 키를 모르던 읽개가 든 꼴(`extra["fill"]`)과 아는 칸이 함께 있으면 아는 칸이 이긴다.
    @Test func 아는_칸이_든_글자를_이긴다() {
        var field = DataField(name: "sown", type: .date, optional: true)
        field.extra["fill"] = "model"
        field.fill = .rule
        #expect(DataModelCoding.encodeField(field)["fill"] == "rule")
    }
}
