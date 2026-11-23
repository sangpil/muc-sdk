import Foundation

// 규칙 낱말 한 벌 — 모듈 자원 `Resources/words.json`(이 모듈의 낱말 · 꼴의 **정본**)을 한 번 읽어 든다.
//   소스에는 낱말을 두지 않는다 — 꼴(정규식)도 낱말 목록도 이 파일에서 온다(게이트 `qa/qa-sdk-build.mjs` ⑩ 이 소스의 글자 리터럴에 ASCII 밖 글자 0 을 잰다).
//   꼴 안의 `{이름}`(영문 글자만)은 같은 `patterns` 의 다른 꼴로 바꿔 끼운다 — 정규식의 수량자 `{1,2}` 는 수라 겹치지 않는다.
//   읽기가 실패하면(자원이 빠진 조립 · 모르는 끼움 이름 · 빠진 칸) 그 자리에서 멈춘다 — 낱말 없이 읽은 답은 조용히 틀리므로.

struct Words: Decodable, Sendable {
    /// 이름 붙은 꼴 — 칸 이름이 곧 JSON 의 키다(빠진 키는 읽기 실패 · 남는 키는 시험 `wordsUseEveryPattern` 이 잡는다).
    struct Patterns: Codable, Sendable {
        let attachedTail, fuzzyAttached, fuzzyWhen, monthMid, monthLate, recurring, vagueCount: String
        let seasonWord, season, relativeSeason, repeatDay, yearEnd: String
        let fullDate, yearMonth, year, monthDay, month, shiftedMonth, dayAfterWord, partAfterWord: String
        let halfYear, count, unitsAgo: String
        let weekDay, thisWeekday, lastWeekday, weekAgo, agoAfterWord, daysAgo, dayWordGuard: String
        let fromUntil, nights, spanWords: String
        let native, nativeAge, nativeAgeEo, recent, vague, vagueFuture, vaguePast, futureWord, pastWord, frequency, frequencyModifies, pastAfter, recurringWhen, childhood, schoolDays, stage, others: String
        let sentenceEnd, clauseLink, dependentNoun, recurringModifies, recurringModifiesWeak, numberLead, dateLead, topicStem, verbStemEnd: String
        let range, endMonthDay, endDay, endMonth: String
        let decade, decadeAsTime, twoDigitYear, plainWeek, anyYear, longNumberBlock, anyMonth, yearWords, monthOrPart: String
        let monthEarlySpaced, monthMidSpaced, monthLateSpaced, yearEarlySpaced: String
        let gradePre, gradePost, gradeSpaced, universityGrade, seasonAfter: String
        let ageExact, firstBirthday, sixtieth, age, bandMark, bandTime, bandPart, counted, ageBand: String
        let bornYear, bornDay, school, examDay, gapYear: String
        let ageUnit, ageStill, ageStillAfter, ageSaid, ageApart, ageEach, ageEachAge, ageEachKin, ageWhen, yearBefore, olInside, yearPart, gradeMonth, bornInMonth, daysTogether, joinedWordGuard, afterWord, thenNext: String
        let comparedWith, comparedTail, comparedVague, decadeNoun, yearsAgoBefore, yearsAgoMonth, ownYearMonth: String
        let rangeEnd, rangeEndCorrected, calendarDay, lateDay, tilde, calendarTilde, choiceYear, yearHead, choiceCount, dayCount: String
        let ageRange, within, quotedWhole, quoted, timeWord, namedTime, agoTail, yearsCount: String
        let correctionFiller, correctionWord, correction, correctionBound, correctionNoun, correctionAfter, afterTime, inheritMonth, inheritDay: String
        let dayPart, choiceBetween, choiceAhead, rangeTilde, rangeBetween, rangeAfter, comparing, timeEnd, ageTime, nounLink: String
        let joinsTimes, joinedOnly, joinMark, openEnd, afterEvent, bareTime, notDescribed, withParticle, toward, plainAdverb, vagueHead, markedTime, adnominal, doer, reported, eventTime, commaTime, correctionClause, notModifying, plainTime, modifiesObject: String
    }
    struct Grade: Decodable, Sendable { let pattern: String; let offset: Int; let last: Int }
    struct Anchored: Decodable, Sendable {
        let pattern: String
        let key: String
        /// 있으면 기간 꼴 — 「그 시절」이면 시작 … 끝(끝이 없으면 이 키의 시작)
        let endKey: String?
        /// 있으면 시작부터 이 햇수의 구간
        let years: Int?
    }
    struct Modifier: Decodable, Sendable { let pattern: String; let kind: SpanReader.Mod }
    struct Stage: Decodable, Sendable { let heads: [String]; let band: String?; let from: Int; let to: Int }
    struct StageRest: Decodable, Sendable { let from: Int; let to: Int }
    struct School: Decodable, Sendable {
        let entry: [String: Int]
        let graduation: [String: Int]
        let graduationWord: String
        let universityLevel: String
        let universityKey: String
    }
    struct Valued: Decodable, Sendable { let word: String; let value: Int }
    struct Shift: Decodable, Sendable { let past: [String]; let future: [String]; let twoBack: String }
    struct Season: Decodable, Sendable { let word: String; let first: Int; let months: Int }
    struct FixedDay: Decodable, Sendable { let word: String; let month: Int; let day: Int }

    let patterns: Patterns
    let grades: [Grade]
    let anchored: [Anchored]
    let modifiers: [Modifier]
    let stages: [Stage]
    let stageRest: StageRest
    let school: School
    let weekday, nativeCount, sinoCount, nativeTens, nativeOnes, weekOffset, seasonShift: [String: Int]
    let nativeDays, yearOffset, monthOffset, dayOffset: [Valued]
    let monthShift: Shift
    let seasons: [Season]
    let parts: [String: [Int]]
    let fixedDays: [FixedDay]
    let thisTime, from, until, before, dayUnit, monthUnit, weekend, when, yearSuffix: String
    let monthUnits, weekUnits: [String]
    /// 원문에 붙어 있을 때만 날인 낱말(「내 일」은 「내일」이 아니다).
    let joinedDays: [String]
    /// 꼴마다 반드시 드는 낱말 — 하나도 없는 글에는 그 꼴을 맞추지 않는다(답은 같다).
    let gates: [String: [String]]
    func may(_ name: String, _ s: String) -> Bool { gates[name].map { words in words.contains { Rx.holds(s, $0) } } ?? true }

    /// 이 모듈의 자원 자리(번들 `muc-sdk_SpokenTime` 안).
    static var resourceURL: URL? { Bundle.module.url(forResource: "words", withExtension: "json") }

    /// 이 모듈의 자원에서 한 번 읽은 한 벌.
    static let shared: Words = {
        guard let url = resourceURL else {
            fatalError("SpokenTime: resource words.json is missing from the module bundle")
        }
        do { return try Words.decode(Data(contentsOf: url)) } catch {
            fatalError("SpokenTime: resource words.json does not read: \(error)")
        }
    }()

    /// 바이트 → 한 벌 — 꼴의 끼움(`{이름}`)을 먼저 풀고 읽는다(목록 칸의 `pattern` 도 같은 끼움을 쓴다).
    static func decode(_ data: Data) throws -> Words {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["patterns"] as? [String: String] else { throw WordsError.shape("patterns") }
        let expanded = try expand(raw)
        object["patterns"] = expanded
        for key in ["grades", "anchored", "modifiers"] {
            guard let rows = object[key] as? [[String: Any]] else { throw WordsError.shape(key) }
            object[key] = try rows.map { row in
                var row = row
                guard let p = row["pattern"] as? String else { throw WordsError.shape(key) }
                row["pattern"] = try fill(p, from: expanded, seen: [])
                return row
            }
        }
        return try JSONDecoder().decode(Words.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// 꼴 이름 목록 — JSON 의 `patterns` 키(시험이 칸 이름과 맞댄다).
    static func patternNames(_ data: Data) throws -> Set<String> {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["patterns"] as? [String: String] else { throw WordsError.shape("patterns") }
        return Set(raw.keys)
    }

    static func expand(_ raw: [String: String]) throws -> [String: String] {
        try raw.mapValues { try fill($0, from: raw, seen: []) }
    }

    private static let slot = try! NSRegularExpression(pattern: #"\{([A-Za-z]+)\}"#)

    static func fill(_ pattern: String, from raw: [String: String], seen: Set<String>) throws -> String {
        var out = pattern
        while let m = slot.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
              let whole = Range(m.range, in: out), let name = Range(m.range(at: 1), in: out) {
            let key = String(out[name])
            guard !seen.contains(key) else { throw WordsError.cycle(key) }
            guard let inner = raw[key] else { throw WordsError.unknownSlot(key) }
            out.replaceSubrange(whole, with: try fill(inner, from: raw, seen: seen.union([key])))
        }
        return out
    }
}

enum WordsError: Error, Equatable {
    case shape(String)
    case unknownSlot(String)
    case cycle(String)
}
