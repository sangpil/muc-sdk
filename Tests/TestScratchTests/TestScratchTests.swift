import Foundation
import Testing
import TestScratch

/// 시험의 임시 자리 — 만든 것이 끝에 하나도 남지 않는가(폴더 · 파일 자리 · 설정 도메인 · `~/Library/Preferences`).
@Suite struct TestScratchTests {
    private let fm = FileManager.default

    private var preferences: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences")
    }

    private func scratchPlists() -> Set<String> {
        Set(((try? fm.contentsOfDirectory(atPath: preferences.path)) ?? []).filter { $0.hasPrefix(TestScratch.prefix) })
    }

    @Test func aFolderIsMadeUnderTheRootWithTheNameAndRemoved() throws {
        let url = try TestScratch.folder("scratch-self")
        #expect(url.lastPathComponent.hasPrefix("test-scratch-" + (TestScratch.run.map { $0 + "-" } ?? "") + "scratch-self-"))
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == TestScratch.root.standardizedFileURL.path)
        var dir: ObjCBool = false
        #expect(fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue)
        try Data("x".utf8).write(to: url.appendingPathComponent("a.txt"))
        TestScratch.remove(url)
        #expect(!fm.fileExists(atPath: url.path))
    }

    /// 실행 표지 — 있으면 이름 머리에(남은 자리의 출처 진단) · 없으면 지금 꼴 그대로.
    @Test func theRunMarkerLeadsTheNameWhenGiven() {
        #expect(TestScratch.name("x", run: "r42-ab").hasPrefix("test-scratch-r42-ab-x-"))
        #expect(TestScratch.name("x", ext: "json", run: nil).hasPrefix("test-scratch-x-"))
        #expect(TestScratch.name("x", ext: "json", run: nil).hasSuffix(".json"))
    }

    @Test func aLocationIsNotMadeAndCarriesTheExtension() {
        let url = TestScratch.location("scratch-self", ext: "json")
        #expect(url.pathExtension == "json")
        #expect(!fm.fileExists(atPath: url.path))
        TestScratch.remove(url, nil)   // 없는 자리 · nil 은 조용히 지난다
    }

    @Test func aBorrowedFolderIsGoneEvenWhenTheBodyThrows() {
        struct Boom: Error {}
        var seen: URL?
        #expect(throws: Boom.self) {
            try TestScratch.withFolder("scratch-self") { url in seen = url; throw Boom() }
        }
        #expect(seen.map { !fm.fileExists(atPath: $0.path) } == true)
    }

    /// 재발 시험 — 설정 도메인은 임시 폴더 안의 plist 다: `~/Library/Preferences` 에 아무것도 서지 않고, 지우면 폴더째 간다.
    /// (`removePersistentDomain` 만 부르면 빈 plist 가 남는다 — 도메인을 비우기만 하고 파일은 두기 때문이다.)
    @Test func defaultsLiveInTheScratchFolderAndLeaveNoPlistBehind() throws {
        let before = scratchPlists()
        let d = try TestScratch.defaults("scratch-self")
        d.defaults.set("value", forKey: "key")
        d.defaults.synchronize()
        #expect(d.defaults.string(forKey: "key") == "value")
        #expect(UserDefaults(suiteName: d.name)?.string(forKey: "key") == "value", "같은 이름의 둘째 인스턴스도 같은 도메인")
        #expect(d.defaults.persistentDomain(forName: d.name)?["key"] as? String == "value")
        let plist = d.folder.appendingPathComponent("defaults.plist")
        #expect(fm.fileExists(atPath: plist.path), "plist 는 임시 폴더 안")
        #expect(scratchPlists() == before, "~/Library/Preferences 에 서지 않는다")
        d.remove()
        #expect(!fm.fileExists(atPath: d.folder.path))
        #expect(scratchPlists() == before)
    }
}
