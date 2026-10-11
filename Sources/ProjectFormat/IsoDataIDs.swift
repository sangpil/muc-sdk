import CryptoKit
import Foundation

/// `.isodata` 레코드의 스토어 UUID 규약 — 데이터 도구가 쓰는 id 와 앱이 앉히는 행의 UUID 가 **바이트째 같아야** 씬의 plot 결합이 선다.
/// 그래서 규약은 한 벌이고 엔진(데이터 도구)과 프로젝트(레코드를 스토어에 앉히는 코어)가 함께 이것을 부른다.
///
///   이름공간 = uuid5(RFC 4122 URL 이름공간 6ba7b811-9dad-11d1-80b4-00c04fd430c8, "com.sangpil.isodata/<스키마 이름>")
///   UUID    = uuid5(이름공간, "<엔티티 이름>/<id>")      — 글자는 UTF-8 · 쓸 때는 소문자
///   id 가 이미 UUID 꼴(8-4-4-4-12 · 대소문자 무관)이면 해시하지 않고 그 UUID 그대로(스토어 → 행 → 스토어 왕복이 UUID 를 바꾸지 않는다)
///   검산값: 스키마 "sample" · "Watering/watering-1" → ee5c8311-4efc-5c4e-9c14-313d666b319d (Python `uuid.uuid5` 로 잰 값 · 시험이 붙든다)
///
/// 이름공간의 글자 `com.sangpil.isodata` 는 확정된 형식 식별자다 — 바꾸면 이미 앉은 행의 UUID 가 모두 바뀐다.
public enum IsoDataIDs {
    /// RFC 4122 URL 이름공간.
    public static let urlNamespace = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!

    /// 스키마 이름의 이름공간.
    public static func namespace(schema: String) -> UUID {
        uuid5(namespace: urlNamespace, name: "com.sangpil.isodata/\(schema)")
    }

    /// 레코드 id → 스토어 UUID. id 가 이미 UUID 꼴이면 그대로.
    public static func uuid(schema: String, entity: String, id: String) -> UUID {
        UUID(uuidString: id) ?? uuid5(namespace: namespace(schema: schema), name: "\(entity)/\(id)")
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
