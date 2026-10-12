import CoreGraphics
import Foundation
import SwiftUI

// 모듈 `DesignTokens` — 계약 갈래(플랫폼 중립 · iOS · macOS). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : 디자인 토큰의 꼴 — 색(값 · 테마 · 역할 · 공급자 · 정본 읽개) · 스케일(간격 · 반경 · 글자 크기) · 정본 곁 칸(씬 칸 규칙 · 색 역할 묶음).
//   누가 부르나 : 엔진의 도구(토큰 창 · 조절판) · 프로젝트(토큰 생성물 · 미리보기 호스트) · SDK 의 `PreviewProtocol`(스케일 종류).
//   지키는 것   : 꼴만 든다 — 토큰의 값(생성물 · 실행 시점 등록부)과 플랫폼 색 손(UIKit ⟂ AppKit)은 프로젝트의 것이다 ·
//                Foundation · CoreGraphics · SwiftUI 만 문다.
//   시작점     : `HexColor` · `ColorTokenProvider` · `SoTColorProvider` · `SoTScaleProvider`
//
// 색 토큰의 꼴 — 「어느 테마에서 어느 역할이 무슨 색인가」를 담는 값 · 공급자 프로토콜 · 정본 읽개(엔진 SDK · 프로젝트와 엔진의 도구가 함께 문다).
//
// 정본 `tokens.json` 을 실행 시점에 읽는 `SoTColorProvider`(저장 즉시 목록에 선다) ⟂ 빌드 시점 사본(생성기가 방출한 표 — 그 공급자 · 실행 시점 등록부는
// 프로젝트의 것이다: 값이 프로젝트의 생성물이다). 테마 = `semantic.themes.<name>` 한 벌 — light·dark 는 필수, 그 밖은 커스텀(`$base` 가 외양 기준
// light ⟂ dark). 역할 이름은 정본 실명(kebab · `ink-soft`) 그대로 든다.
// 값 형식 = iOS 관례의 hex(`#RRGGBB` · 알파는 `#RRGGBBAA`) · 입력은 `rgb()`·`rgba()`·`0x` 도 받는다(`HexColor.parse`).
// SwiftUI 색으로 옮기는 손은 둘이다 — 엔진의 도구가 쓰는 `Color(_: HexColor)`(SwiftUI 만 · sRGB 성분 그대로) ⟂ 앱 제품의 플랫폼 색 경로(UIColor ⟂ NSColor —
// 생성 열거와 같은 경로라야 옛 스냅과 픽셀이 같다 · SDK 는 UIKit · AppKit 을 쓰지 않으므로 그 손은 프로젝트가 든다). 둘이 같은 값인지는 프로젝트의 시험이 잰다.

/// 색 하나 — sRGB 8비트 + 알파. 저장·표시는 hex 소문자.
public struct HexColor: Hashable, Codable, Sendable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8
    /// 0…1
    public var alpha: Double
    public init(r: UInt8, g: UInt8, b: UInt8, alpha: Double = 1) { self.r = r; self.g = g; self.b = b; self.alpha = alpha }
    public init(rgb: UInt32, alpha: Double = 1) {
        self.init(r: UInt8((rgb >> 16) & 0xFF), g: UInt8((rgb >> 8) & 0xFF), b: UInt8(rgb & 0xFF), alpha: alpha)
    }
    public var rgb: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

    /// `#rrggbb` ⟂ 알파가 1 이 아니면 `#rrggbbaa`.
    public var hex: String {
        let base = String(format: "#%02x%02x%02x", r, g, b)
        return alpha >= 0.9995 ? base : base + String(format: "%02x", Int((alpha * 255).rounded()))
    }
    public var description: String { hex }
    /// 사람용 — `#a05010` · 알파가 있으면 `#a05010 · 8%`.
    public var display: String { alpha >= 0.9995 ? hex : "\(String(hex.prefix(7))) · \(Int((alpha * 100).rounded()))%" }

    /// 받는 꼴: `#rgb` · `#rrggbb` · `#rrggbbaa` · `rrggbb` · `0xrrggbb` · `rgb(r, g, b)` · `rgba(r, g, b, a)`(a = 0…1 ⟂ 0…100%). 못 읽으면 nil.
    public static func parse(_ raw: String) -> HexColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("rgb") {
            guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
            let parts = s[s.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3 || parts.count == 4 else { return nil }
            func chan(_ p: String) -> UInt8? { guard let v = Double(p), v >= 0, v <= 255 else { return nil }; return UInt8(v.rounded()) }
            guard let r = chan(parts[0]), let g = chan(parts[1]), let b = chan(parts[2]) else { return nil }
            var a = 1.0
            if parts.count == 4 {
                let p = parts[3]
                if p.hasSuffix("%"), let v = Double(p.dropLast()) { a = v / 100 } else if let v = Double(p) { a = v }
                guard a >= 0, a <= 1 else { return nil }
            }
            return HexColor(r: r, g: g, b: b, alpha: a)
        }
        var h = s
        if h.hasPrefix("#") { h.removeFirst() } else if h.hasPrefix("0x") { h.removeFirst(2) }
        guard h.allSatisfy({ $0.isHexDigit }) else { return nil }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 8 { return HexColor(rgb: UInt32(v >> 8), alpha: Double(v & 0xFF) / 255) }
        return HexColor(rgb: UInt32(v))
    }

    public var cgColor: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(alpha)) }
    /// 상대 휘도(WCAG · sRGB) — 대비 계산용.
    public var luminance: Double {
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    public func contrast(against other: HexColor) -> Double {
        let a = luminance + 0.05, b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }
}

extension Color {
    /// SwiftUI 색 — sRGB 성분 그대로(`Color(.sRGB, …)` · 플랫폼 색 경로 없이). 엔진의 도구(조절판 색 띠 · 색 팝오버의 스와치)가 쓴다.
    /// 앱 제품의 손(프로젝트가 드는 플랫폼 색 경로 — UIColor ⟂ NSColor `red:green:blue:alpha:`)은 그대로 두고, 두 손이 같은 값인지는
    /// 프로젝트의 시험이 잰다(성분 0…1 안에서 플랫폼 경로의 확장 sRGB 는 sRGB 와 같다 · macOS · iOS).
    public init(_ hex: HexColor) {
        self.init(.sRGB, red: Double(hex.r) / 255, green: Double(hex.g) / 255, blue: Double(hex.b) / 255, opacity: hex.alpha)
    }
}

/// 테마 한 벌의 머리 — 이름 · 외양 기준 · 설명.
public struct ThemeInfo: Hashable, Sendable {
    public let name: String
    /// 시스템 컨트롤·다크 종이판 등이 따를 외양 — light ⟂ dark
    public let base: ColorScheme
    public let doc: String
    public init(name: String, base: ColorScheme, doc: String = "") { self.name = name; self.base = base; self.doc = doc }
    public static let lightName = "light", darkName = "dark"
}

/// 역할 하나 — 이름 · 쓰임 · Apple 대응 · 테마별 값.
public struct ColorEntry: Hashable, Sendable {
    public let name: String
    public let doc: String
    /// UIKit/SwiftUI 의미색 이름(있으면 · `label` · `secondarySystemBackground` …) — 표시용. 앱 고유 색은 nil.
    public let apple: String?
    public let values: [String: HexColor]
    public init(name: String, doc: String = "", apple: String? = nil, values: [String: HexColor]) {
        self.name = name; self.doc = doc; self.apple = apple; self.values = values
    }
}

public protocol ColorTokenProvider: Sendable {
    /// 테마들 — light · dark 가 앞, 커스텀은 정본 순서.
    func themes() -> [ThemeInfo]
    /// 역할들 — 정본 순서(light 테마의 키 순서).
    func entries() -> [ColorEntry]
    /// 이름 → 역할 하나. **프로토콜 요구**다 — 확장 기본 구현만 두면 `any ColorTokenProvider` 가 늘 선형 탐색으로 떨어진다(그리기마다 수백 번).
    func entry(_ name: String) -> ColorEntry?
    /// 저장 이름(camel · 안 파일) → 정본 실명(kebab). 숫자가 든 손편집 이름(`gray-2`)도 돌아오게 한다.
    func roleName(forCamel camel: String) -> String?
}

extension ColorTokenProvider {
    public func entry(_ name: String) -> ColorEntry? { entries().first { $0.name == name } }
    public func roleName(forCamel camel: String) -> String? { entries().first { ColorRoleNaming.camel($0.name) == camel }?.name }
    /// 이름 → 항목 사전(그리기마다 선형 탐색을 피한다 — 공급자가 캐시하면 덮어쓴다)
    public func index() -> [String: ColorEntry] { Dictionary(uniqueKeysWithValues: entries().map { ($0.name, $0) }) }
    public func color(_ role: String, theme: String) -> HexColor? { entry(role)?.values[theme] }
    public func theme(_ name: String) -> ThemeInfo? { themes().first { $0.name == name } }
}

/// 정본 공급자 — `tokens.json` 의 `semantic.themes` 를 실행 시점에 읽고 `{primitive…}` 참조를 푼다(수정 시각이 바뀌면 다시 읽는다).
public final class SoTColorProvider: ColorTokenProvider, @unchecked Sendable {
    public let tokensJSONURL: URL
    private let lock = NSLock()
    private var cachedAt: Date?
    private var cachedThemes: [ThemeInfo] = []
    private var cachedEntries: [ColorEntry] = []
    private var cachedIndex: [String: ColorEntry] = [:]
    private var cachedCamel: [String: String] = [:]
    public init(tokensJSONURL: URL) { self.tokensJSONURL = tokensJSONURL }

    public func themes() -> [ThemeInfo] { refreshIfNeeded(); return cachedThemes }
    public func entries() -> [ColorEntry] { refreshIfNeeded(); return cachedEntries }
    public func index() -> [String: ColorEntry] { refreshIfNeeded(); return cachedIndex }
    public func entry(_ name: String) -> ColorEntry? { refreshIfNeeded(); return cachedIndex[name] }
    public func roleName(forCamel camel: String) -> String? { refreshIfNeeded(); return cachedCamel[camel] }
    /// 씬 칸의 별칭(`semantic.$sceneSlots` — `SceneSlotNaming`) · 칸이 없으면 빈 표.
    public func sceneSlotAliases() -> [String: String] { refreshIfNeeded(); return lock.withLock { cachedAliases } }
    /// 색 역할의 묶음(`semantic.$group` — `ColorRoleGroups`) · 칸이 없으면 `.none`.
    public func roleGroups() -> ColorRoleGroups { refreshIfNeeded(); return lock.withLock { cachedGroups } }
    private var cachedAliases: [String: String] = [:]
    private var cachedGroups = ColorRoleGroups.none

    private var lastStat: Date = .distantPast
    /// 저장 직후 강제로 다시 읽게 한다(mtime 확인 주기를 기다리지 않고).
    public func invalidate() { lock.lock(); lastStat = .distantPast; cachedAt = nil; lock.unlock() }

    private func refreshIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        // 그리기마다(역할 수백 번) 파일 stat 을 하지 않는다 — 0.5 s 에 한 번만 mtime 을 본다
        let now = Date()
        guard now.timeIntervalSince(lastStat) > 0.5 || cachedEntries.isEmpty else { return }
        lastStat = now
        let mtime = (try? FileManager.default.attributesOfItem(atPath: tokensJSONURL.path)[.modificationDate] as? Date) ?? nil
        guard cachedAt != mtime || cachedEntries.isEmpty else { return }
        let semantic: [String: Any]
        (cachedThemes, cachedEntries, semantic) = Self.read(tokensJSONURL)
        cachedIndex = Dictionary(uniqueKeysWithValues: cachedEntries.map { ($0.name, $0) })
        cachedCamel = Dictionary(cachedEntries.map { (ColorRoleNaming.camel($0.name), $0.name) }, uniquingKeysWith: { a, _ in a })
        cachedAliases = SceneSlotNaming.aliases(semantic: semantic)
        cachedGroups = ColorRoleGroups(semantic: semantic)
        cachedAt = mtime
    }

    /// JSONSerialization 은 키 순서를 잃는다 — 순서는 **파일의 줄 차례**로 세운다(테마 = `themes` 블록 안의 `"<이름>": {` 위치 · 역할 = 그 첫 테마 블록 안의 키 위치).
    /// 자리는 이름마다 **한 번만** 잰다(정렬 비교자 안에서 재면 비교마다 문자열을 처음부터 훑는다 — 역할 수십 개에서 백 ms 대).
    /// 파일은 한 번 읽고 한 번 푼다 — `semantic` 은 곁 칸(씬 칸 별칭 · 색 역할 묶음)을 위해 함께 낸다.
    static func read(_ url: URL) -> ([ThemeInfo], [ColorEntry], [String: Any]) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let semantic = root["semantic"] as? [String: Any] else { return ([], [], [:]) }
        guard let themesAny = semantic["themes"] as? [String: Any] else { return ([], [], semantic) }
        // `themes` 아래 `$note` 같은 문자열이 섞여도 테마만 든다(전체 캐스트는 하나만 어긋나도 다 잃는다)
        var themes: [String: [String: Any]] = [:]
        for (k, v) in themesAny where !k.hasPrefix("$") { if let d = v as? [String: Any] { themes[k] = d } }
        guard !themes.isEmpty else { return ([], [], semantic) }
        let text = String(decoding: data, as: UTF8.self)
        let apple = semantic["$apple"] as? [String: String] ?? [:]
        let docs = semantic["$doc"] as? [String: String] ?? [:]
        // 테마 순서: light · dark 가 앞 · 나머지는 themes 블록 안의 등장 순(파일 산문에 든 같은 낱말에 끌리지 않게 블록 안에서만 찾는다)
        let themesAt = text.range(of: "\"themes\": {")?.upperBound ?? text.startIndex
        let themePos = Dictionary(uniqueKeysWithValues: themes.keys.map { ($0, orderIndex("\"\($0)\": {", in: text, from: themesAt)) })
        let rest = themes.keys.filter { $0 != ThemeInfo.lightName && $0 != ThemeInfo.darkName }
            .sorted { (themePos[$0] ?? .max, $0) < (themePos[$1] ?? .max, $1) }
        let ordered = [ThemeInfo.lightName, ThemeInfo.darkName].filter { themes[$0] != nil } + rest
        let infos = ordered.map { n -> ThemeInfo in
            let d = themes[n] ?? [:]
            let base: ColorScheme = (d["$base"] as? String) == "dark" || (d["$base"] == nil && n.contains("dark")) ? .dark : .light
            return ThemeInfo(name: n, base: base, doc: d["$doc"] as? String ?? "")
        }
        // 역할 순서: 머리 테마(light · 없으면 첫 테마) 블록 **안**의 키 차례 — 블록 끝을 넘지 않는다($apple·$doc 지도의 같은 키에 끌리지 않게)
        let headName = themes[ThemeInfo.lightName] != nil ? ThemeInfo.lightName : (ordered.first ?? "")
        let head = themes[headName] ?? [:]
        let blockFrom = text.range(of: "\"\(headName)\": {", range: themesAt..<text.endIndex)?.upperBound ?? themesAt
        let blockTo = text.range(of: "\n      }", range: blockFrom..<text.endIndex)?.lowerBound ?? text.endIndex
        let rolePos = Dictionary(uniqueKeysWithValues: head.keys.filter { !$0.hasPrefix("$") }
            .map { ($0, orderIndex("\"\($0)\":", in: text, from: blockFrom, to: blockTo)) })
        let roleNames = rolePos.keys.sorted { (rolePos[$0] ?? .max, $0) < (rolePos[$1] ?? .max, $1) }
        let entries = roleNames.map { role -> ColorEntry in
            var values: [String: HexColor] = [:]
            for n in ordered {
                if let raw = themes[n]?[role] as? String, let hex = HexColor.parse(resolve(raw, root: root)) { values[n] = hex }
            }
            return ColorEntry(name: role, doc: docs[role] ?? "", apple: apple[role], values: values)
        }
        return (infos, entries, semantic)
    }

    /// `{primitive.color.neutral.950}` → 값(사슬도 푼다 · 못 풀면 원문).
    static func resolve(_ raw: String, root: [String: Any], depth: Int = 0) -> String {
        guard depth < 8, raw.hasPrefix("{"), raw.hasSuffix("}") else { return raw }
        let path = raw.dropFirst().dropLast().split(separator: ".").map(String.init)
        var node: Any = root
        for p in path { guard let d = node as? [String: Any], let next = d[p] else { return raw }; node = next }
        guard let s = node as? String else { return raw }
        return resolve(s, root: root, depth: depth + 1)
    }
    private static func orderIndex(_ needle: String, in text: String, from: String.Index? = nil, to: String.Index? = nil) -> Int {
        let lo = from ?? text.startIndex, hi = to ?? text.endIndex
        guard lo <= hi, let r = text.range(of: needle, range: lo..<hi) else { return Int.max }
        return text.distance(from: text.startIndex, to: r.lowerBound)
    }
}

/// 역할 이름 표기 — 정본은 kebab(`ink-soft`) · 안 파일 저장은 camel(`inkSoft`). 한자리에 둔다(프로젝트의 색 역할 값 꼴도 이것을 쓴다).
public enum ColorRoleNaming {
    public static func kebab(_ camel: String) -> String {
        var out = ""
        for ch in camel { if ch.isUppercase { out.append("-"); out.append(Character(ch.lowercased())) } else { out.append(ch) } }
        return out
    }
    public static func camel(_ kebab: String) -> String {
        var out = ""; var up = false
        for ch in kebab { if ch == "-" { up = true } else { out.append(up ? Character(ch.uppercased()) : ch); up = false } }
        return out
    }
}

