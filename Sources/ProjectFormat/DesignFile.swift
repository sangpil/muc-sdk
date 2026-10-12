import Foundation

/// 안(案) 파일의 꼴 — `<안 폴더>/<화면>/<안>.design.json`. 앱의 읽는 손과 엔진의 손(저장 · 도달 목록)이
/// 같은 자리 · 같은 머리 · 같은 값 채우기를 이 한 벌로 쓴다. Style 값의 **꼴**(화면마다의 `…Style`)은 프로젝트의 것이라 여기 없다 —
/// 여기는 그 값을 JSON 사전으로만 다룬다.
///
/// 판 칸 `version`(맨 위 정수 · 선택 — 없으면 `DesignFormat.version` · `version(_:)`)으로 「이 SDK 보다 새 안」을 가른다. 칸: `screen` · `name` · `createdAt`(ISO 8601) · `confirmed` · `basedOn` · `style`(값 한 덩이) ·
/// `components`(`ScreenComponent` 배열 · 없으면 키가 안 선다) · 옛 칸 `notes` · `overall`(읽기만).
public enum DesignFile {
    /// 파일 이름 꼬리.
    public static let suffix = ".design.json"
    /// 의견 폴더 이름 — 안 폴더 밑 `reviews/`(한 기록 = `<id>.json`). 엔진의 의견 손과 도달 목록이 이 한 이름을 읽는다.
    public static let reviewsFolderName = "reviews"

    /// 화면 하나의 안 폴더.
    public static func folder(screen: String, in root: URL) -> URL { root.appendingPathComponent(screen) }

    /// 안 하나의 자리.
    public static func url(screen: String, name: String, in root: URL) -> URL {
        folder(screen: screen, in: root).appendingPathComponent(name + suffix)
    }

    /// 그 화면의 안 이름들(글자 순).
    public static func names(screen: String, in root: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder(screen: screen, in: root).path)) ?? []
        return items.filter { $0.hasSuffix(suffix) }.map { String($0.dropLast(suffix.count)) }.sorted()
    }

    /// 안 파일의 바이트 규칙 — 쓰는 손(엔진)이 이 인코더 하나로 쓴다: 들여쓰기 · 열쇠 글자 순 · `/` 그대로 · 날짜 ISO 8601.
    /// 같은 값이면 누가 써도(엔진의 서술로 잰 사전 ⟂ 프로젝트의 Style 타입) 같은 바이트가 나온다 — 그 동치는 프로젝트 쪽 시험이 잰다.
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// 안 파일 읽개 — 날짜 ISO 8601(`encoder` 의 짝).
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// 안 파일의 판 — 맨 위 정수 칸 `version`(`FormatStamp`) · 칸이 없으면 `DesignFormat.version`(판 칸을 들이기 전의 안 파일).
    public static func version(_ data: Data) -> Int { FormatStamp.version(data) ?? DesignFormat.version }

    /// 머리 — 배선 다음의 고르기(확정 → 가장 최근 · `IAWiring.rule`)가 읽는 두 칸과 판.
    public struct Head: Sendable, Equatable {
        public let confirmed: Bool
        public let createdAt: Date
        /// 안 파일의 판(`version(_:)` 과 같은 규칙).
        public let version: Int
        /// 판 칸 없는 머리 — 판은 `DesignFormat.version`.
        public init(confirmed: Bool, createdAt: Date) { self.init(confirmed: confirmed, createdAt: createdAt, version: DesignFormat.version) }
        public init(confirmed: Bool, createdAt: Date, version: Int) { self.confirmed = confirmed; self.createdAt = createdAt; self.version = version }
    }

    /// 머리만 읽는다 — 몸(Style)을 화면의 꼴로 풀지 않는다. 만든 때가 없거나 ISO 8601 이 아니면 nil(그 안은 고르기 후보에서 빠진다) ·
    /// `confirmed` 가 없으면 거짓 · 판 칸이 없으면 `DesignFormat.version`.
    public static func head(_ data: Data) -> Head? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stamp = obj["createdAt"] as? String,
              let date = iso8601.date(from: stamp) else { return nil }
        return Head(confirmed: (obj["confirmed"] as? Bool) ?? false, createdAt: date, version: version(data))
    }

    /// Style 값에 없는 칸을 기본값으로 채운다 — 칸이 늘어도 옛 안 파일이 읽힌다(칸 이름을 바꾸는 것만이 호환을 깬다). 채운 칸의 수를 돌려준다.
    /// - Parameter defaults: 화면의 기본값(프로젝트의 `…Style` · 프로젝트가 정한 값) — `JSONEncoder` 로 사전이 되는 값.
    public static func fillMissingStyleKeys(_ style: inout [String: Any], from defaults: some Encodable) throws -> Int {
        guard let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any] else { return 0 }
        var filled = 0
        for (k, v) in base where style[k] == nil { style[k] = v; filled += 1 }
        return filled
    }

    /// 만든 시각 읽개 — 한 번 짓는다(안마다 새로 지으면 비싸다). 설정을 바꾸지 않고 읽기만 한다 — `ISO8601DateFormatter` 의 읽기는 스레드 안전이다.
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()
}
