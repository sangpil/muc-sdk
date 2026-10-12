import CryptoKit
import Foundation

/// `.isodata` 레코드의 스토어 UUID 규약 — 데이터 도구가 쓰는 id 와 앱이 앉히는 행의 UUID 가 **바이트째 같아야** 씬의 plot 결합이 선다.
/// 그래서 규약은 한 벌이고 엔진(데이터 도구)과 프로젝트(레코드를 스토어에 앉히는 코어)가 함께 이것을 부른다.
///
///   이름공간 = uuid5(RFC 4122 URL 이름공간 6ba7b811-9dad-11d1-80b4-00c04fd430c8, "<머리>/<스키마 이름>")
///   머리    = 스키마의 `idNamespace`(선택 칸) · 없으면 `defaultNamespace`(`com.makeusclever.isodata`)
///   UUID    = uuid5(이름공간, "<엔티티 이름>/<id>")      — 글자는 UTF-8 · 쓸 때는 소문자
///   id 가 이미 UUID 꼴(8-4-4-4-12 · 대소문자 무관)이면 해시하지 않고 그 UUID 그대로(스토어 → 행 → 스토어 왕복이 UUID 를 바꾸지 않는다)
///   검산값: 기본 머리 · 스키마 "sample" · "Watering/watering-1" → 28241eae-2497-50f0-b848-aa5eab203910 (Python `uuid.uuid5` 로 잰 값 · 시험이 붙든다)
///
/// 머리를 바꾸면 이미 앉은 행의 UUID 가 모두 바뀐다 — 앉은 행을 지키려는 스키마는 그 행을 앉힌 머리를 `idNamespace` 로 적는다.
public enum IsoDataIDs {
    /// RFC 4122 URL 이름공간.
    public static let urlNamespace = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!
    /// 기본 머리 — 스키마가 `idNamespace` 를 적지 않으면 이 글자.
    public static let defaultNamespace = "com.makeusclever.isodata"

    /// 스키마 이름의 이름공간 — 기본 머리.
    public static func namespace(schema: String) -> UUID { namespace(prefix: defaultNamespace, schema: schema) }

    /// 스키마 이름의 이름공간 — 주어진 머리.
    public static func namespace(prefix: String, schema: String) -> UUID {
        uuid5(namespace: urlNamespace, name: "\(prefix)/\(schema)")
    }

    /// 레코드 id → 스토어 UUID(기본 머리). id 가 이미 UUID 꼴이면 그대로.
    public static func uuid(schema: String, entity: String, id: String) -> UUID {
        uuid(namespace: nil, schema: schema, entity: entity, id: id)
    }

    /// 레코드 id → 스토어 UUID — 머리 `namespace`(nil = 기본 · 스키마의 `idNamespace` 를 넘긴다). id 가 이미 UUID 꼴이면 그대로.
    public static func uuid(namespace: String?, schema: String, entity: String, id: String) -> UUID {
        UUID(uuidString: id) ?? uuid5(namespace: self.namespace(prefix: namespace ?? defaultNamespace, schema: schema), name: "\(entity)/\(id)")
    }

    /// 레코드 id → 스토어 UUID — 스키마의 이름 · 머리(`idNamespace`)와 엔티티의 이름 칸(`uuidKey`)으로.
    public static func uuid(in schema: DataSchema, entity: DataEntity, id: String) -> UUID {
        uuid(namespace: schema.idNamespace, schema: schema.name, entity: entity.uuidKey, id: id)
    }

    /// RFC 4122 v5(SHA-1 · §4.3).
    public static func uuid5(namespace: UUID, name: String) -> UUID {
        let ns = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        var b = Array(Insecure.SHA1.hash(data: Data(ns + Array(name.utf8))).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
