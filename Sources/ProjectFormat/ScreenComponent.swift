import CoreGraphics
import Foundation

// 화면 구성요소 — 안 파일(`<화면>/<안>.design.json`)의 `components` 칸 한 줄. **값만 산다**(파일 읽기 · 그리기는 쓰는 쪽):
//   · 엔진의 도구(상세 틀)가 미리보기에 그리고 편집한다 · 엔진의 도달 목록이 원천 파일을 따라간다(`hasFile` · `source`).
//   · 앱(프로젝트의 셸)이 같은 칸을 읽어 그 영역에 그린다(모르는 종류 · 깨진 줄은 건너뛴다 · `decodeLenient`).
// 종류가 셋이다:
//   · general  = 화면 코드가 그리는 요소(`StyleElement`). 값은 안 파일의 Style — 앱은 이 종류를 따로 그리지 않는다(화면 본체가 그린다).
//   · isoscene = 씬 파일(`.isoscene`) 한 장을 화면의 한 영역(또는 전체)에.
//   · isomodel = 모델 파일(`.isomodel`) 한 개를 한 영역에.
// 영역(`region`)은 **기기 화면(뷰포트) 비율** 0–1 — 위·왼쪽 원점 · 스크롤하지 않는다(크롬 층과 같은 자리 규칙). 없으면 전체.
// `interactive` — 일부 영역 씬을 손으로 만지게 하나(없으면 정적 — 스크롤을 가로채지 않는다). 전체 영역 씬은 늘 조작 · 모델은 늘 정적.

/// 화면 구성요소 하나 — 종류 · 원천 파일 · 영역 · 조작.
public struct ScreenComponent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case general, isoscene, isomodel

        /// 이 종류가 파일을 원천으로 갖나(전용 편집기가 여는 것 · 앱이 그리는 것).
        public var hasFile: Bool { self != .general }
        /// 파일 확장자.
        public var fileExtension: String? {
            switch self {
            case .general: nil
            case .isoscene: "isoscene"
            case .isomodel: "isomodel"
            }
        }
        /// 파일 확장자로 고른 종류 — `.isoscene` · `.isomodel` 밖이면 nil.
        public static func of(file url: URL) -> Kind? {
            switch url.pathExtension.lowercased() {
            case "isoscene": .isoscene
            case "isomodel": .isomodel
            default: nil
            }
        }
    }

    /// 뷰포트 비율 사각형 — 0–1(위·왼쪽 원점). 범위 밖은 읽을 때 잘린다(`clamped`).
    public struct Region: Codable, Equatable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        /// 이 SDK 가 모르는 칸(읽은 그대로 되쓴다).
        public var extra: [String: JSONValue] = [:]
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public static let full = Region(x: 0, y: 0, width: 1, height: 1)
        /// 0–1 안으로 · 최소 5% — 손편집 실수가 0 폭 영역으로 사라지지 않게.
        public var clamped: Region {
            let w = min(max(width, 0.05), 1), h = min(max(height, 0.05), 1)
            return Region(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
        }
        public var isFull: Bool { clamped == .full }

        enum CodingKeys: String, CodingKey { case x, y, width, height }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decode(Double.self, forKey: .x); y = try c.decode(Double.self, forKey: .y)
            width = try c.decode(Double.self, forKey: .width); height = try c.decode(Double.self, forKey: .height)
            extra = try ExtraKeys.decode(from: decoder, known: ScreenComponent.knownRegionKeys)
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(width, forKey: .width); try c.encode(height, forKey: .height)
            try ExtraKeys.encode(extra, to: encoder, known: ScreenComponent.knownRegionKeys)
        }
        /// 이 크기(pt)의 뷰포트에서 차지하는 사각형.
        public func rect(in size: CGSize) -> CGRect {
            let r = clamped
            return CGRect(x: r.x * size.width, y: r.y * size.height, width: r.width * size.width, height: r.height * size.height)
        }
    }

    /// 요소 id — 미리보기의 snapID 와 같은 낱말(`main.title` · `detail.chart`). 의견도 이 이름에 붙는다.
    public var id: String
    public var kind: Kind
    /// 사람이 읽는 이름 — 없으면 파일 이름.
    public var label: String?
    /// 원천 파일 — **프로젝트 폴더 기준** 상대경로(`muc.json` 이 선 폴더). `general` 은 nil.
    public var source: String?
    /// 영역 — nil = 전체 화면.
    public var region: Region?
    /// 일부 영역 씬을 손으로 만지나 — nil · false = 정적(스크롤을 가로채지 않는다). 전체 영역 씬 · 모델에는 뜻이 없다(`isInteractive`).
    public var interactive: Bool?
    /// 이 SDK 가 모르는 칸(읽은 그대로 되쓴다 — 앱 · 엔진이 열어 저장해도 새 판의 칸이 사라지지 않는다).
    public var extra: [String: JSONValue] = [:]

    public init(id: String, kind: Kind, label: String? = nil, source: String? = nil, region: Region? = nil, interactive: Bool? = nil) {
        self.id = id; self.kind = kind; self.label = label; self.source = source; self.region = region; self.interactive = interactive
    }

    /// 보이는 영역 — nil 은 전체.
    public var area: Region { (region ?? .full).clamped }

    /// 손을 받나 — 전체 영역 씬은 늘(화면 전체의 씬처럼) · 일부 영역 씬은 `interactive: true` 일 때만 · 모델 · 일반은 받지 않는다.
    public var isInteractive: Bool {
        guard kind == .isoscene else { return false }
        return area.isFull || interactive == true
    }

    /// 보이는 이름 — 이름 칸 ⟂ 파일 이름 ⟂ id.
    public var title: String {
        if let label, !label.isEmpty { return label }
        if let source { return URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent }
        return id
    }

    /// 칸 이름 — 이 꼴이 읽는 키(검사기가 모르는 키를 가를 때 · `CodingKeys` 와 한 벌).
    public static let knownKeys: Set<String> = ["id", "kind", "label", "source", "region", "interactive"]
    public static let knownRegionKeys: Set<String> = ["x", "y", "width", "height"]

    enum CodingKeys: String, CodingKey { case id, kind, label, source, region, interactive }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(Kind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label); source = try c.decodeIfPresent(String.self, forKey: .source)
        region = try c.decodeIfPresent(Region.self, forKey: .region); interactive = try c.decodeIfPresent(Bool.self, forKey: .interactive)
        extra = try ExtraKeys.decode(from: decoder, known: Self.knownKeys)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(label, forKey: .label); try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(region, forKey: .region); try c.encodeIfPresent(interactive, forKey: .interactive)
        try ExtraKeys.encode(extra, to: encoder, known: Self.knownKeys)
    }
}

extension ScreenComponent {
    /// 칸 크기(pt) → 그릴 픽셀 — 배율 2 · 긴 변 2400 상한. 도구의 미리보기와 앱의 모델 칸이 **한 셈**을 쓴다(같은 그림).
    public static func renderPixels(for size: CGSize) -> CGSize {
        let scale = min(2, 2400 / max(size.width, size.height, 1))
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
    /// 모델 한 장의 정사각 한 변(px) — 픽셀의 긴 변 · 최소 64(빌더 코어의 미리보기 문이 받는 수).
    public static func modelSide(for size: CGSize) -> Int {
        let p = renderPixels(for: size)
        return max(64, Int(max(p.width, p.height).rounded()))
    }

    /// `components` 칸을 **관대하게** 읽는다 — 앱의 읽기 · 엔진의 도달 목록. 모르는 종류 · 깨진 줄은 건너뛰고(`skipped` 에 까닭) 나머지를 돌려준다.
    /// 모르는 칸은 `extra` 로 든다(되쓰면 남는다). 앞으로 종류가 늘어도 앱이 깨지지 않게 — 엔진의 안 파일 검사기는 같은 줄을 경고로 알린다.
    /// - Parameter value: `JSONSerialization` 으로 읽은 `components` 값(배열이 아니면 빈 목록).
    public static func decodeLenient(_ value: Any?) -> (components: [ScreenComponent], skipped: [String]) {
        guard let value else { return ([], []) }
        guard let items = value as? [Any] else { return ([], ["components 가 배열이 아니다"]) }
        var out: [ScreenComponent] = [], skipped: [String] = []
        for (i, item) in items.enumerated() {
            guard let obj = item as? [String: Any] else { skipped.append("#\(i) — 객체가 아니다"); continue }
            if let k = obj["kind"] as? String, Kind(rawValue: k) == nil {
                skipped.append("#\(i) \(obj["id"] as? String ?? "?") — 모르는 종류 \(k)"); continue
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: obj)
                out.append(try JSONDecoder().decode(ScreenComponent.self, from: data))
            } catch {
                skipped.append("#\(i) \(obj["id"] as? String ?? "?") — 읽지 못함")
            }
        }
        return (out, skipped)
    }
}
