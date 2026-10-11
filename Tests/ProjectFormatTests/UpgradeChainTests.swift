import Foundation
import ProjectFormat
import Testing

// 업그레이드 사슬의 꼴 — 불변식(간격마다 스텝 하나 · 쓰는 바닥) · 길 찾기 · 판 찍기 · 순수 · 잃는 칸 · 올릴 것 · 쓸 판 · 잃음 스텝의 가드.
// 스텝의 몸은 엔진 쪽 타깃이 갖고, 여기는 꼴만 잰다.

/// 시험의 스텝 — 칸 하나를 덧붙이거나(값 바꿈) · 잃는 칸을 걷거나(잃음 — `sweeps` 가 거짓이면 걷지 않는 몸) · 그대로 넘긴다.
private struct Probe: UpgradeStep {
    let from: Int
    var effect: UpgradeEffect = .identity
    var summary: String { "판 \(to)" }
    var mark: String?
    var sweeps = true

    func apply(_ document: JSONValue) throws -> JSONValue {
        guard case .object(var o) = document else { return document }
        if let mark { o[mark] = true }
        if sweeps { for f in effect.lostFields { o[f] = nil } }
        return .object(o)
    }
}

@Suite struct UpgradeChainTests {
    static func chain(_ steps: [any UpgradeStep], oldest: Int = 2, newest: Int = 5, floor: Int? = nil, key: String = "version") -> UpgradeChain {
        UpgradeChain(stampKey: key, oldest: oldest, newest: newest, writeFloor: floor ?? oldest, steps: steps)
    }

    @Test func aChainWithOneStepPerGapStands() {
        #expect(Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 4)]).violations.isEmpty)
        #expect(Self.chain([], oldest: 1, newest: 1).violations.isEmpty, "판이 하나뿐인 형식 — 간격이 없다")
        #expect(Self.chain([Probe(from: 4), Probe(from: 2), Probe(from: 3)]).violations.isEmpty, "차례는 상관없다")
    }

    /// 빈 간격 · 겹친 간격 · 범위 밖 · 판 차례 · 쓰는 바닥이 범위 밖 — 다 이름 대고 선다.
    @Test func gapsOverlapsAndStrayStepsAreNamed() {
        let gap = Self.chain([Probe(from: 2), Probe(from: 4)]).violations
        #expect(gap == ["3 → 4 간격에 스텝이 없다"])
        let twice = Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 3), Probe(from: 4)]).violations
        #expect(twice == ["3 → 4 간격에 스텝이 둘 이상이다"])
        let stray = Self.chain([Probe(from: 1), Probe(from: 2), Probe(from: 3), Probe(from: 4), Probe(from: 5)]).violations
        #expect(stray.count == 2 && stray.allSatisfy { $0.contains("범위") })
        #expect(Self.chain([], oldest: 3, newest: 2, floor: 3).violations.first?.contains("최신 판") == true)
        #expect(Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 4)], floor: 6).violations == ["쓰는 바닥 판 6 이 사슬 범위(2…5) 밖이다"])
        #expect(Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 4)], floor: 1).violations.count == 1)
    }

    @Test func pathWalksFromTheVersionToTheNewest() throws {
        let c = Self.chain([Probe(from: 4), Probe(from: 2), Probe(from: 3)])
        #expect(try c.path(from: 2).map(\.from) == [2, 3, 4])
        #expect(try c.path(from: 4).map(\.to) == [5])
        #expect(try c.path(from: 5).isEmpty)
        #expect(throws: UpgradeError.belowOldest(version: 1, oldest: 2)) { try c.path(from: 1) }
        #expect(throws: UpgradeError.aboveNewest(version: 6, newest: 5)) { try c.path(from: 6) }
        #expect(throws: UpgradeError.missingStep(from: 3)) { try Self.chain([Probe(from: 2), Probe(from: 4)]).path(from: 2) }
    }

    /// 사슬이 스텝마다 판 칸을 찍는다 — 스텝은 판을 모른다 · 매니페스트는 `schema`. 값 바꿈이 맨 위 간격이면 쓸 판 = 최신.
    @Test func theChainStampsEachStep() throws {
        let c = Self.chain([Probe(from: 2, mark: "two"), Probe(from: 3), Probe(from: 4, effect: .valueChange, mark: "four")])
        let out = try c.upgrade(["version": 2, "body": "x"])
        #expect(out.document == ["version": 5, "body": "x", "two": true, "four": true])
        #expect(out.from == 2 && out.to == 5 && out.newest == 5 && out.steps.map(\.from) == [2, 3, 4] && out.needsUpgrade)
        let newest = try c.upgrade(["version": 5])
        #expect(newest.steps.isEmpty && newest.document == ["version": 5] && !newest.needsUpgrade && newest.to == 5)
        let manifest = try Self.chain([Probe(from: 1, effect: .valueChange)], oldest: 1, newest: 2, key: "schema").upgrade(["schema": 1])
        #expect(manifest.document == ["schema": 2])
    }

    @Test func refusesWhatItCannotRead() {
        let c = Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 4)])
        #expect(throws: UpgradeError.notObject) { try c.upgrade([1, 2]) }
        #expect(throws: UpgradeError.unstamped(key: "version")) { try c.upgrade(["version": "3"]) }
        #expect(throws: UpgradeError.unstamped(key: "version")) { try c.upgrade(["version": .number(2.5)]) }
        #expect(throws: UpgradeError.belowOldest(version: 1, oldest: 2)) { try c.upgrade(["version": 1]) }
        #expect(throws: UpgradeError.aboveNewest(version: 9, newest: 5)) { try c.upgrade(["version": 9]) }
    }

    /// 순수 — 같은 입력은 같은 출력(시계 · 파일 · 환경을 보지 않는다).
    @Test func sameInputSameOutput() throws {
        let c = Self.chain([Probe(from: 2, effect: .valueChange, mark: "a"), Probe(from: 3, mark: "b"), Probe(from: 4)])
        let doc: JSONValue = ["version": 2, "list": [1, 2, 3]]
        #expect(try c.upgrade(doc).document == (try c.upgrade(doc).document))
    }

    /// 갈래 — 잃음만 잃는 칸을 갖는다 · 기본 셈은 맨 위의 칸 가운데 내용이 든 것만(빈 배열 · 빈 글자 · 널은 든 것이 아니다).
    @Test func effectsAndLostFields() {
        #expect(UpgradeEffect.identity.lostFields.isEmpty && UpgradeEffect.valueChange.lostFields.isEmpty)
        #expect(UpgradeEffect.lossy(fields: ["a", "b"]).lostFields == ["a", "b"])
        #expect([UpgradeEffect.identity, .valueChange, .lossy(fields: [])].map(\.word) == ["항등", "값 바꿈", "잃음"])
        #expect([UpgradeEffect.identity, .valueChange, .lossy(fields: [])].map(\.key) == ["identity", "valueChange", "lossy"])
        let step = Probe(from: 1, effect: .lossy(fields: ["bands", "series", "gone", "note"]))
        #expect(step.lostFields(in: ["bands": [1], "series": [], "note": ""]) == ["bands"])
        #expect(step.lostFields(in: [1]).isEmpty)
        #expect(JSONValue.number(0).holdsSomething && JSONValue.bool(false).holdsSomething && !JSONValue.object([:]).holdsSomething)
    }

    /// 한 번 돈 결과 — 실제로 잃은 칸(스텝 차례 · 겹침 없이 · 몸이 걷었다) · 올릴 것인가.
    @Test func theOutcomeNamesWhatTheDocumentLost() throws {
        let c = Self.chain([Probe(from: 2, effect: .lossy(fields: ["a", "b"])), Probe(from: 3), Probe(from: 4, effect: .lossy(fields: ["b", "c"]))])
        let out = try c.upgrade(["version": 2, "a": [1], "b": "x", "c": []])
        #expect(out.lost == ["a", "b"])
        #expect(out.needsUpgrade && out.document == ["version": 5], "잃음 스텝의 몸이 칸을 걷었다(빈 칸 c 도)")
        #expect(!(try c.upgrade(["version": 3, "b": "x"]).lost.contains("a")))
        #expect(try c.upgrade(["version": 3, "b": "x"]).lost == ["b"])
        let identityOnly = try Self.chain([Probe(from: 2), Probe(from: 3), Probe(from: 4)]).upgrade(["version": 2])
        #expect(!identityOnly.needsUpgrade && identityOnly.lost.isEmpty)
    }

    /// 올릴 것 = 실제로 잃는 칸 ∨ 길에 값 바꿈 — 내용 없는 잃음 · 항등만 밟는 문서는 판 번호만 뒤진다(쓸 판 = 지금 판 · 문서 그대로).
    @Test func onlyRealLossOrAValueChangeIsAnUpgrade() throws {
        let c = Self.chain([Probe(from: 2), Probe(from: 3, effect: .lossy(fields: ["old"])), Probe(from: 4)])
        let nothing = try c.upgrade(["version": 2, "old": [], "body": 1])
        #expect(!nothing.needsUpgrade && nothing.to == 2 && nothing.steps.isEmpty && nothing.lost.isEmpty)
        #expect(nothing.document == ["version": 2, "old": [], "body": 1], "올릴 것이 아니면 받은 문서 그대로")
        let real = try c.upgrade(["version": 2, "old": ["x"], "body": 1])
        #expect(real.needsUpgrade && real.lost == ["old"])
    }

    /// 쓸 판 = max(마지막 값 바꿈 · 잃음 스텝이 내는 판, 쓰는 바닥) — 최신까지 쓰지 않는다 · 그 위 항등 간격은 넘지 않는다.
    @Test func theWrittenVersionIsTheLowestThatCarriesTheChange() throws {
        let steps: [any UpgradeStep] = [Probe(from: 2, effect: .valueChange, mark: "stamped"), Probe(from: 3), Probe(from: 4, mark: "late"),
                                        Probe(from: 5), Probe(from: 6)]
        let low = try Self.chain(steps, newest: 7, floor: 2).upgrade(["version": 2])
        #expect(low.to == 3 && low.newest == 7 && low.steps.map(\.from) == [2])
        #expect(low.document == ["version": 3, "stamped": true], "쓸 판의 꼴 — 그 위 스텝의 몸은 싣지 않는다")
        let floored = try Self.chain(steps, newest: 7, floor: 5).upgrade(["version": 2])
        #expect(floored.to == 5 && floored.steps.map(\.from) == [2, 3, 4])
        #expect(floored.document == ["version": 5, "stamped": true, "late": true])
        let above = try Self.chain(steps, newest: 7, floor: 5).upgrade(["version": 4])
        #expect(!above.needsUpgrade && above.to == 4, "바닥 아래라도 바꿀 것이 없으면 쓰지 않는다")
    }

    /// 잃음 스텝의 몸이 칸을 걷지 않으면 사슬이 결과를 내지 않는다 — 판 칸만 올라 잃는 칸이 남는 꼴.
    @Test func aLossyStepThatKeepsItsFieldsIsRefused() throws {
        let c = Self.chain([Probe(from: 2, effect: .lossy(fields: ["a", "b"]), sweeps: false), Probe(from: 3), Probe(from: 4)])
        #expect(throws: UpgradeError.lossyStepKept(from: 2, fields: ["a"])) { try c.upgrade(["version": 2, "a": [1], "b": []]) }
        #expect(try c.upgrade(["version": 2, "b": []]).lost.isEmpty, "든 것이 없으면 남아도 잃는 것이 없다")
        #expect(UpgradeError.lossyStepKept(from: 10, fields: ["bands"]).description.contains("10 → 11"))
    }
}
