import Foundation

// 시험의 임시 자리 한 벌 — 임시 폴더 · 임시 파일 자리 · 설정 도메인(UserDefaults suite). **만든 것은 그 시험이 끝날 때 지운다.**
//
// 시험마다 제 손으로 `temporaryDirectory` 밑에 폴더를 만들고 suite 도메인을 열던 것이 부산물을 쌓았다(`$TMPDIR` 의 시험 폴더 ·
// `~/Library/Preferences` 의 빈 plist). 까닭 둘: ⓐ 지우는 줄이 없거나 다른 이름을 지웠다 ⓑ `removePersistentDomain(forName:)` 은 도메인을 비우기만 하고
// plist 파일(빈 사전 42바이트)을 남긴다. 그래서 만드는 손과 지우는 손을 이 한 자리에 모은다:
//   · 이름은 늘 `test-scratch-[<실행 표지>-]<이름>-<UUID>` — 남으면 무엇이 남겼는지 이름으로 보인다. 실행 표지는 환경 `TEST_SCRATCH_RUN`(게이트가 준다) —
//     **진단 정보**다: 게이트 범위 안에 표지 없는 자리가 남으면 env 를 받지 못한 프로세스가 쓴 것이다(셈을 거르는 데 쓰지 않는다). 표지가 없으면 지금 꼴 그대로.
//   · 자리의 뿌리 = 환경 `TEST_SCRATCH_ROOT` ⟂ 없으면 `temporaryDirectory`. 게이트가 범위 폴더를 주고 시험 묶음 뒤에 그 안을 센다
//     (빌더의 시험 찌꺼기 게이트 — Foundation 의 `temporaryDirectory` 는 macOS 에서 `TMPDIR` 을 읽지 않아 칸을 따로 둔다).
//   · 설정 도메인은 **임시 폴더 안의 plist**다(suite 이름 = 절대 경로 — `~/Library/Preferences` 를 건드리지 않는다) — 폴더를 지우면 함께 간다.
// **시험 타깃만 문다** — 제품 타깃은 물지 않는다(SDK.md §1 「시험」 갈래). 시험 소스는 임시 자리를 이 손으로만 만든다.

/// 시험의 임시 자리 — 폴더 · 파일 자리 · 설정 도메인. 부른 쪽이 `defer` · `addTeardownBlock` 에서 지우거나 `withFolder` · `withDefaults` 로 빌려 쓴다.
public enum TestScratch {
    /// 이 손이 만드는 모든 이름의 머리.
    public static let prefix = "test-scratch-"
    /// 자리의 뿌리를 바꾸는 환경 칸(게이트의 범위 폴더).
    public static let rootEnvironment = "TEST_SCRATCH_ROOT"
    /// 실행 표지 환경 칸 — 게이트가 주고 이름 머리에 넣는다(남은 자리의 출처 진단 — 빌더의 시험 찌꺼기 게이트).
    public static let runEnvironment = "TEST_SCRATCH_RUN"

    /// 이 실행의 표지 — 환경 `TEST_SCRATCH_RUN`(영숫자 · `-` 만 남긴다) ⟂ 없으면 nil.
    public static var run: String? {
        guard let r = ProcessInfo.processInfo.environment[runEnvironment] else { return nil }
        let safe = String(r.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        return safe.isEmpty ? nil : safe
    }

    /// 자리 이름 — `test-scratch-[<표지>-]<이름>-<UUID>[.<확장자>]`.
    public static func name(_ label: String, ext: String? = nil, run: String? = TestScratch.run) -> String {
        prefix + (run.map { $0 + "-" } ?? "") + label + "-" + UUID().uuidString + (ext.map { "." + $0 } ?? "")
    }

    /// 자리의 뿌리 — `TEST_SCRATCH_ROOT` ⟂ `temporaryDirectory`.
    public static var root: URL {
        if let r = ProcessInfo.processInfo.environment[rootEnvironment], !r.isEmpty { return URL(fileURLWithPath: r, isDirectory: true) }
        return FileManager.default.temporaryDirectory
    }

    /// 새 임시 폴더(만들어 둔다) — `<뿌리>/test-scratch-<이름>-<UUID>/`(폴더 URL — 상대 경로를 이 밑으로 푼다). 지우기는 `remove(_:)`.
    public static func folder(_ label: String) throws -> URL {
        let url = location(label, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 새 임시 자리(만들지 않는다) — `<뿌리>/test-scratch-[<표지>-]<이름>-<UUID>[.<확장자>]`. 아직 없는 폴더 · 파일을 시험이 세울 때. 지우기는 `remove(_:)`.
    /// `isDirectory` — 폴더로 쓸 자리면 참(끝 `/` — `URL(fileURLWithPath:relativeTo:)` 가 그 밑으로 푼다 · 거짓이면 그 옆으로 푼다).
    public static func location(_ label: String, ext: String? = nil, isDirectory: Bool = false) -> URL {
        root.appendingPathComponent(name(label, ext: ext), isDirectory: isDirectory).standardizedFileURL
    }

    /// 지운다 — 없으면 그만(아무것도 쓰지 않은 자리가 보통이다).
    public static func remove(_ urls: URL?...) {
        for url in urls.compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
    }

    /// 폴더 하나를 빌려 쓰고 지운다.
    public static func withFolder<T>(_ label: String, _ body: (URL) throws -> T) throws -> T {
        let url = try folder(label)
        defer { remove(url) }
        return try body(url)
    }

    /// 폴더 하나를 빌려 쓰고 지운다(비동기).
    public static func withFolder<T>(_ label: String, _ body: (URL) async throws -> T) async throws -> T {
        let url = try folder(label)
        defer { remove(url) }
        return try await body(url)
    }

    // MARK: 설정 도메인

    /// 설정 도메인 하나 — 임시 폴더 안의 plist(`name` = 그 절대 경로 · `persistentDomain(forName:)` 에도 그대로). 지우기는 `remove()`.
    public struct Defaults: @unchecked Sendable {
        public let name: String
        public let defaults: UserDefaults
        /// 도메인 plist 가 사는 폴더
        public let folder: URL

        /// 도메인을 비우고 폴더째 지운다.
        public func remove() {
            defaults.removePersistentDomain(forName: name)
            TestScratch.remove(folder)
        }
    }

    /// 새 설정 도메인.
    public static func defaults(_ label: String) throws -> Defaults {
        let dir = try folder(label)
        let name = dir.appendingPathComponent("defaults").path
        guard let d = UserDefaults(suiteName: name) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name]) }
        return Defaults(name: name, defaults: d, folder: dir)
    }

    /// 설정 도메인 하나를 빌려 쓰고 지운다.
    public static func withDefaults<T>(_ label: String, _ body: (UserDefaults) throws -> T) throws -> T {
        let d = try defaults(label)
        defer { d.remove() }
        return try body(d.defaults)
    }
}
