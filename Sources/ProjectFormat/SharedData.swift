import Foundation

// 공유 데이터 모델 — 여러 앱 프로젝트가 **같은 데이터**(같은 모델 파일 · 같은 스키마 패키지 · 같은 저장 컨테이너)를 함께 읽고 고칠 때,
// 프로젝트의 매니페스트가 그 모델을 가리키는 칸의 꼴(`SharedDataModel`)과 프로젝트들이 맞물렸는지 재는 규칙(`SharedModelLockstep`).
// 진실원은 저장 컨테이너(CloudKit 프라이빗 컨테이너) 하나이고 앱마다 제 로컬 스토어를 둔다 — 그래서 스키마는 한 벌 · 판은 함께 오르고(lockstep) ·
// 변경은 칸 더하기만이다(`CloudKitRules.evolutionProblems`). 매니페스트의 어느 자리에 이 칸을 싣는가 · 경로를 어떻게 푸는가(폴더 밖 허용 · 링크)는
// 매니페스트를 읽는 엔진의 몫이다 — 이 꼴은 칸의 이름 · 값의 규칙과 맞물림의 판정만 든다(엔진 · 프로젝트의 도구가 같은 답을 내게).
//
//   칸           뜻
//   id           모델의 정체(역 DNS — `com.example.garden.data`). 같은 id = 같은 모델 — 체크아웃 배치와 무관하게 프로젝트끼리 맞춘다
//   model        모델 파일(`.isodata`) — 매니페스트가 선 폴더 기준 상대 경로 · 프로젝트 폴더 밖을 가리킬 수 있다(공유 모델은 어느 한 프로젝트의 것이 아니다)
//   package      스키마 패키지 폴더(앱들이 무는 SwiftPM 패키지) — 같은 규칙의 상대 경로 · 선택
//   revision     이 프로젝트가 채택한 스키마 판(모델 파일 `schema.revision` 과 같아야 맞물린다)
//   cloudKitContainer · appGroup   저장 컨테이너 식별자 — 한 자리(앱 엔타이틀먼트 · 스토어 설정이 이 값을 읽는다) · 같은 모델의 프로젝트는 같은 값

/// 매니페스트의 공유 데이터 모델 칸 하나.
public struct SharedDataModel: Codable, Equatable, Sendable {
    public var id: String
    public var model: String
    public var package: String?
    public var revision: Int
    public var cloudKitContainer: String?
    public var appGroup: String?
    /// 이 SDK 가 모르는 칸.
    public var extra: [String: JSONValue] = [:]

    public init(id: String, model: String, package: String? = nil, revision: Int, cloudKitContainer: String? = nil, appGroup: String? = nil) {
        self.id = id; self.model = model; self.package = package; self.revision = revision
        self.cloudKitContainer = cloudKitContainer; self.appGroup = appGroup
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, model, package, revision, cloudKitContainer, appGroup }
    static let known = Set(CodingKeys.allCases.map(\.rawValue))
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        model = try c.decode(String.self, forKey: .model)
        package = try c.decodeIfPresent(String.self, forKey: .package)
        revision = try c.decode(Int.self, forKey: .revision)
        cloudKitContainer = try c.decodeIfPresent(String.self, forKey: .cloudKitContainer)
        appGroup = try c.decodeIfPresent(String.self, forKey: .appGroup)
        extra = try ExtraKeys.decode(from: decoder, known: Self.known)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(model, forKey: .model); try c.encodeIfPresent(package, forKey: .package)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(cloudKitContainer, forKey: .cloudKitContainer); try c.encodeIfPresent(appGroup, forKey: .appGroup)
        try ExtraKeys.encode(extra, to: encoder, known: Self.known)
    }

    /// 칸 값의 문제 — id 는 역 DNS(점으로 나뉜 둘 이상의 마디 · 마디는 로마자 · 숫자 · `-`) · 경로는 상대(절대 · `~` 아님 · 모델은 `.isodata`) ·
    /// 판은 1 이상 · CloudKit 컨테이너는 `iCloud.` 머리 · 앱 그룹은 `group.` 머리(또는 macOS 의 팀 id 머리 `ABCDE12345.`).
    public var problems: [String] {
        var out: [String] = []
        let labels = id.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 || labels.contains(where: { $0.isEmpty || !$0.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") } }) {
            out.append("id ‘\(id)’ — 역 DNS 꼴(점으로 나뉜 둘 이상의 마디)이어야 한다")
        }
        func relative(_ key: String, _ p: String) {
            if p.isEmpty || p.hasPrefix("/") || p.hasPrefix("~") { out.append("\(key) ‘\(p)’ — 매니페스트 폴더 기준 상대 경로여야 한다") }
        }
        relative("model", model)
        if !model.hasSuffix(".isodata") { out.append("model ‘\(model)’ — 모델 파일(.isodata)이어야 한다") }
        if let package { relative("package", package) }
        if revision < 1 { out.append("revision \(revision) — 1 이상이어야 한다") }
        if let c = cloudKitContainer, !c.hasPrefix("iCloud.") { out.append("cloudKitContainer ‘\(c)’ — iCloud. 로 시작해야 한다") }
        if let g = appGroup {
            let team = g.split(separator: ".").first.map { $0.count == 10 && $0.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) } } ?? false
            if !g.hasPrefix("group.") && !team { out.append("appGroup ‘\(g)’ — group. 또는 팀 id 머리로 시작해야 한다") }
        }
        return out
    }
}

/// 같은 모델을 무는 프로젝트들의 맞물림 — 판(lockstep) · 저장 컨테이너가 같은가 · 모델의 판과 같은가.
public enum SharedModelLockstep {
    /// 프로젝트 하나의 칸.
    public struct Member: Equatable, Sendable {
        public var project: String
        public var reference: SharedDataModel
        public init(project: String, reference: SharedDataModel) { self.project = project; self.reference = reference }
    }

    /// 문제 — `model` = 모델 파일의 스키마(nil = 읽지 못했다) · `members` = 그 모델을 가리킨다는 프로젝트들. 경로는 `<프로젝트>.<칸>`.
    /// ① 모두 같은 id ② 모델이 판(`revision`)을 적었다 ③ 프로젝트마다 채택한 판 = 모델의 판 ④ 저장 컨테이너(CloudKit · 앱 그룹)가 모두 같다.
    public static func problems(model: DataSchema?, members: [Member]) -> [SchemaIssue] {
        var out: [SchemaIssue] = []
        guard let first = members.first else { return out }
        for m in members where m.reference.id != first.reference.id {
            out.append(SchemaIssue(path: "\(m.project).id", reason: "다른 모델 ‘\(m.reference.id)’ 을 가리킨다 — ‘\(first.reference.id)’ 과 맞대지 않는다"))
        }
        if let model {
            if let revision = model.revision {
                for m in members where m.reference.revision != revision {
                    out.append(SchemaIssue(path: "\(m.project).revision",
                                           reason: "채택한 판 \(m.reference.revision) ≠ 모델의 판 \(revision) — 판은 함께 오른다(lockstep)"))
                }
            } else {
                out.append(SchemaIssue(path: "schema.revision", reason: "공유 모델인데 스키마 판(revision)이 없다 — 프로젝트들이 맞물릴 기준이 없다"))
            }
        } else {
            out.append(SchemaIssue(path: "model", reason: "모델 파일을 읽지 못했다 — 판을 맞댈 수 없다"))
        }
        for m in members.dropFirst() {
            if m.reference.cloudKitContainer != first.reference.cloudKitContainer {
                out.append(SchemaIssue(path: "\(m.project).cloudKitContainer", reason: "CloudKit 컨테이너가 \(first.project) 와 다르다 — 같은 데이터가 아니게 된다"))
            }
            if m.reference.appGroup != first.reference.appGroup {
                out.append(SchemaIssue(path: "\(m.project).appGroup", reason: "앱 그룹이 \(first.project) 와 다르다 — 같은 데이터가 아니게 된다"))
            }
        }
        return out
    }
}
