import Foundation

/// 판 읽개 — 문서 맨 위의 정수 칸 하나를 몸을 풀기 전에 읽는다. 판을 견주는 모든 손(엔진의 등록표 · 빌더의 쓰는 손 · 데이터 도구)이 이 하나를 쓴다.
///
/// 정수만 받는다 — JSON 이 아니거나 · 맨 위가 객체가 아니거나 · 칸이 없거나 · 참/거짓이거나(`true` 가 1 로 읽히지 않게) · 정수로 담기지 않는 수면 nil.
/// 몸 전체를 형식의 꼴로 풀지 않으므로 판 하나를 보는 값이 싸다(꼴 풀기는 문서 전체를 걷고 · 이 길은 맨 위 칸 하나만 본다).
public enum FormatStamp {
    /// 맨 위의 `version`.
    public static func version(_ data: Data) -> Int? { integer("version", in: data) }

    /// 맨 위의 정수 칸 `key`(매니페스트는 `schema`).
    public static func integer(_ key: String, in data: Data) -> Int? {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let n = top[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: n.doubleValue)
    }
}
