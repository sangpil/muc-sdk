import CoreGraphics
import Foundation

// 스케일 토큰의 꼴 — 간격 · 반경 · 글자 크기 목록의 값 · 공급자 프로토콜 · 정본 읽개(엔진 SDK).
//
// 목록은 **공급자**가 낸다 — 같은 프로토콜이면 어느 공급자든 조절판 · 저장 형식이 그대로다.
//   · `SoTScaleProvider` — 토큰 정본 `tokens.json` 을 실행 시점에 읽는다. 엔진의 토큰 편집기가 토큰을 **낳는** 자리라 저장 즉시 재빌드 없이
//     목록에 서야 한다 · Swift 는 「타입이 있으면」을 컴파일 시점에 물을 수 없다는 사정도 같다.
//   · `EnumScaleProvider` — 생성기가 방출한 열거(`NamedScaleEnum` 꼴)를 그대로. 빌드 시점의 사본이라 정본과 어긋나면 「재빌드 필요」를 단다 —
//     어느 열거를 싣는지 · 실행 시점 등록부는 프로젝트의 것이다(값이 프로젝트의 생성물이다).

/// 스케일 한 단 — 이름(토큰 실명)과 pt(+ 쓰임 · Apple 대응). 미리보기 호스트의 빌드된 표 요약(`PreviewProtocol.BuiltTokens`)의 한 단도 이 꼴이다
/// (그 요약은 줄에 이름 · pt 만 싣는다).
public struct ScaleEntry: Hashable, Codable, Sendable {
    public let name: String
    public let pt: CGFloat
    public let doc: String
    /// Apple 텍스트 스타일 대응(글자 크기만 · `title(28)` 꼴 · `primitive.font.$apple`) — 표시용.
    public let apple: String?
    public init(name: String, pt: CGFloat, doc: String = "", apple: String? = nil) { self.name = name; self.pt = pt; self.doc = doc; self.apple = apple }
}

/// 토큰 목록의 종류 — Style 필드의 종류이자 저장 형식의 축. 열린 꼴: 아는 종류 셋(`known` — 간격 · 반경 · 글자 크기) · 모르는 종류(새 토큰 종류)도
/// 낱말 그대로 든다(공급자는 모르는 종류에 빈 목록을 낸다 · 새 종류를 싣는 공급자는 그 종류를 받는 손을 덧붙인다).
public struct ScaleKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let space = ScaleKind(rawValue: "space")
    public static let radius = ScaleKind(rawValue: "radius")
    public static let type = ScaleKind(rawValue: "type")
    /// 이 SDK 가 아는 종류 — 차례 그대로.
    public static let known: [ScaleKind] = [.space, .radius, .type]
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// 토큰 목록 공급자.
public protocol ScaleTokenProvider: Sendable {
    func entries(_ kind: ScaleKind) -> [ScaleEntry]
}

/// `CaseIterable & RawRepresentable<CGFloat>` + `name` + `doc` 꼴의 enum(생성기 방출 꼴)을 그대로 목록으로.
public protocol NamedScaleEnum: CaseIterable, RawRepresentable where RawValue == CGFloat {
    var name: String { get }
    var doc: String { get }
}
extension NamedScaleEnum {
    public static var scaleEntries: [ScaleEntry] { allCases.map { ScaleEntry(name: $0.name, pt: $0.rawValue, doc: $0.doc) } }
}

/// 정본 공급자 — 토큰 정본(tokens.json)을 실행 시점에 읽는다(수정 시각이 바뀌면 다시 읽는다 · 재빌드 없이 새 토큰이 목록에 뜬다).
/// 글자 크기는 `primitive.font.scale.m`(설정 글자 크기의 기본 단). `$doc` 지도가 있으면 쓰임을 함께 싣는다.
/// 간격 **역할**(`semantic.layout` — `margin-edge` · `gap-wide` …)은 따로 낸다(`layout()`) — 값은 `pt` 칸(숫자 ⟂ `{primitive.space.<단>}` 참조) ·
/// 안 파일의 간격 칸이 역할 이름을 토큰으로 들 수 있다(`{"token":"gap-wide"}`).
public final class SoTScaleProvider: ScaleTokenProvider, @unchecked Sendable {
    public let tokensJSONURL: URL
    private let lock = NSLock()
    private var cachedAt: Date?
    private var cache: [ScaleKind: [ScaleEntry]] = [:]
    private var layoutCache: [ScaleEntry] = []
    public init(tokensJSONURL: URL) { self.tokensJSONURL = tokensJSONURL }

    public func entries(_ kind: ScaleKind) -> [ScaleEntry] {
        lock.lock(); defer { lock.unlock() }
        refreshLocked()
        return cache[kind] ?? []
    }

    /// 간격 역할 — 정본 차례가 아니라 이름 차례(JSONSerialization 은 키 순서를 잃는다) · 참조는 간격 스케일 값으로 푼다.
    public func layout() -> [ScaleEntry] {
        lock.lock(); defer { lock.unlock() }
        refreshLocked()
        return layoutCache
    }

    /// 간격 이름 → pt — 간격 스케일의 단이 먼저 · 없으면 간격 역할.
    public func spacePt(_ name: String) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        refreshLocked()
        return cache[.space]?.first { $0.name == name }?.pt ?? layoutCache.first { $0.name == name }?.pt
    }

    private func refreshLocked() {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: tokensJSONURL.path)[.modificationDate] as? Date) ?? nil
        if cachedAt != mtime || cache.isEmpty {
            (cache, layoutCache) = Self.readAll(tokensJSONURL); cachedAt = mtime
        }
    }

    static func readAll(_ url: URL) -> ([ScaleKind: [ScaleEntry]], [ScaleEntry]) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prim = root["primitive"] as? [String: Any] else { return ([:], []) }
        var out: [ScaleKind: [ScaleEntry]] = [:]
        out[.space] = scale(prim["space"] as? [String: Any], ascending: true)
        out[.radius] = scale(prim["radius"] as? [String: Any], ascending: true)
        if let font = prim["font"] as? [String: Any], let sc = font["scale"] as? [String: Any], let m = sc["m"] as? [String: Any] {
            var node = m; node["$doc"] = sc["$doc"]; node["$apple"] = font["$apple"]
            out[.type] = scale(node, ascending: false)
        }
        let space = Dictionary((out[.space] ?? []).map { ($0.name, $0.pt) }, uniquingKeysWith: { a, _ in a })
        let layout = ((root["semantic"] as? [String: Any])?["layout"] as? [String: Any]) ?? [:]
        let doc = layout["$doc"] as? [String: String] ?? [:]
        let roles = layout.compactMap { k, v -> ScaleEntry? in
            guard !k.hasPrefix("$"), let pt = (v as? [String: Any])?["pt"] else { return nil }
            if let n = pt as? NSNumber { return ScaleEntry(name: k, pt: CGFloat(n.doubleValue), doc: doc[k] ?? "") }
            // 참조 `{primitive.space.<단>}` — 간격 스케일의 그 단
            if let ref = pt as? String, ref.hasPrefix("{primitive.space."), ref.hasSuffix("}"),
               let v = space[String(ref.dropFirst("{primitive.space.".count).dropLast())] { return ScaleEntry(name: k, pt: v, doc: doc[k] ?? "") }
            return nil
        }
        return (out, roles.sorted { $0.name < $1.name })
    }

    /// `$` 아닌 키 → 숫자 값(생성기 `scaleEntries` 와 같은 규칙). JSONSerialization 은 키 순서를 잃으므로 값으로 세운다 —
    /// 스케일은 단조라 정본 키 순서와 같다(간격·반경 오름차순 · 글자 크기 내림차순).
    static func scale(_ dict: [String: Any]?, ascending: Bool) -> [ScaleEntry] {
        guard let dict else { return [] }
        let doc = dict["$doc"] as? [String: String] ?? [:]
        let apple = dict["$apple"] as? [String: String] ?? [:]
        let list = dict.compactMap { k, v -> ScaleEntry? in
            guard !k.hasPrefix("$"), let n = v as? NSNumber else { return nil }
            return ScaleEntry(name: k, pt: CGFloat(n.doubleValue), doc: doc[k] ?? "", apple: apple[k])
        }
        return list.sorted { ascending ? $0.pt < $1.pt : $0.pt > $1.pt }
    }
}

/// 열거 공급자 — 생성기가 방출한 열거 셋을 그대로.
public struct EnumScaleProvider: ScaleTokenProvider {
    public let space: [ScaleEntry], radius: [ScaleEntry], type: [ScaleEntry]
    public init<S: NamedScaleEnum, R: NamedScaleEnum, T: NamedScaleEnum>(space: S.Type, radius: R.Type, type: T.Type) {
        self.space = S.scaleEntries; self.radius = R.scaleEntries; self.type = T.scaleEntries
    }
    /// 아는 종류 셋 · 모르는 종류는 빈 목록.
    public func entries(_ kind: ScaleKind) -> [ScaleEntry] {
        switch kind { case .space: space; case .radius: radius; case .type: type; default: [] }
    }
}

