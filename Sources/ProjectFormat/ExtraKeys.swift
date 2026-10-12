import Foundation

// 모르는 칸 보존 — 이 SDK 가 모르는 칸(더 새 판 · 같은 판의 덧붙임)을 읽은 그대로 들고 되쓴다. 같은 판에 칸이 더해져도 옛 읽개가 열어 저장하면 그 칸이 사라지지 않게.
// SDK 안 모듈끼리 쓰는 손(`package`) — 꼴마다 `extra: [String: JSONValue]` 칸 하나가 그 객체의 모르는 칸이다. 아는 칸과 이름이 겹치면 아는 칸이 이긴다.

/// 아무 이름이나 받는 열쇠.
package struct AnyCodingKey: CodingKey, Hashable {
    package let stringValue: String
    package var intValue: Int? { nil }
    package init(_ s: String) { stringValue = s }
    package init?(stringValue: String) { self.stringValue = stringValue }
    package init?(intValue: Int) { nil }
}

package enum ExtraKeys {
    /// 디코더가 선 객체에서 `known` 밖 칸 전부(JSON 값 그대로).
    package static func decode(from decoder: Decoder, known: Set<String>) throws -> [String: JSONValue] {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var out: [String: JSONValue] = [:]
        for key in c.allKeys where !known.contains(key.stringValue) {
            out[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        return out
    }

    /// 모르는 칸을 같은 객체에 되쓴다 — `known` 의 이름은 건너뛴다(아는 칸이 이긴다).
    package static func encode(_ extra: [String: JSONValue], to encoder: Encoder, known: Set<String>) throws {
        guard !extra.isEmpty else { return }
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, v) in extra where !known.contains(k) { try c.encode(v, forKey: AnyCodingKey(k)) }
    }

    /// 아는 칸으로 지은 객체에 모르는 칸을 얹는다 — 아는 칸이 이긴다 · 둘 다 객체인 칸은 안으로 내려가 같은 규칙(아는 하위 객체 안의 모르는 칸).
    package static func merge(_ typed: [String: JSONValue], _ extra: [String: JSONValue]) -> [String: JSONValue] {
        var out = typed
        for (k, v) in extra {
            switch (out[k], v) {
            case (nil, _): out[k] = v
            case (.object(let a)?, .object(let b)): out[k] = .object(merge(a, b))
            default: break
            }
        }
        return out
    }
}
