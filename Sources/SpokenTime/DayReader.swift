import Foundation

// 날 하나 셈 — 절대 · 상대 날짜 표현 → 앵커 날 + 정밀도(exact · month · year · circa). 구간 읽기(`SpanReader`)가 그 위에 구간을 세운다 ·
//   공개 손 `day` 는 이 셈이 아니라 구간 읽기의 저장 꼴이다(`SpanReader.storedDay`) — 이 셈은 구간 읽기 안과 끝 날 읽기의 몫.
//   상대 날짜는 말한 단위까지: 날 · 주 = exact · 달 · 반년 = month(그 달 1일) · 해 = year(그 해 1월 1일) · 흐림 표지(때 표현 바로 뒤에 붙은 것 · 따로 선 계절 · 이맘때) = circa.
//   앵커는 늘 그 구간의 첫 날 — 달 초 · 중순 · 말 = 1 · 11 · 21일 · 해 말 = 10월 1일(해 초 = 1월 1일) · 계절 = 그 계절 첫 달 1일 · 이맘때 = 그 해의 이번 달 1일.
//   날 단위 상대 표현(어제 · N일 전 · 지난주 + 요일 …)이 있으면 그것이 때다 — 같은 문장의 다른 달 표현은 대상이다(더 좁은 것이 이긴다).
//   해 없는 달은 달 바로 앞 수식이 정한다(지난 · 저번 = 오늘 앞의 가장 가까운 그 달 · 다음 · 오는 = 뒤 · 이번 · 올 · 수식 없음 = 올해).
//   되풀이 문장은 말한 시작(「A부터」의 A)만 · 흐린 수(「몇 달 전」)는 날을 정하지 않는다(구간 읽기가 「최근」으로 읽는다). 주는 월요일에 시작한다.
//   해와 달 사이의 「도 · 의 · 쉼표」는 그 해의 달 · 해 수 뒤 「인가」는 흐림 표지(「1977년인가 3월」 = 그 해의 달 circa) — 띄어 써도 뒤가 달 · 계절이면 흐림(「77년 인가 3월」) · 그 밖의 띄어 쓴 「인가」는 이름씨라 흐림이 아니다.
//   해가 아닌 긴 수(다섯 자리 이상 · 쉼표 수)는 해 자리를 차지한다 — 그 수와 꼬리(년 · 년도 · 년의 · 년 전 + 뒤의 달 · 날 · 계절 + 그것으로 여는 구간)를
//   덩이째 가린 글을 읽는다(`masked` — 세 손이 같은 글). 가린 달 · 계절을 기준 해로 채우면 해를 지어낸 것이다 · 덩이 밖 때 표현은 평소대로.
//   날은 기준 시간대의 정오(12:00)다.

/// 정규식 손 — 꼴이 서지 않으면 맞지 않은 것으로 친다(꼴은 자원 시험이 미리 짓는다). 지은 꼴은 한 번만 짓고 든다(꼴 글자가 열쇠 · 자물쇠 하나).
enum Rx {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var built: [String: NSRegularExpression] = [:]
    /// `key` = 든 꼴의 열쇠 — 푼 꼴(NFD)은 머리표를 단 열쇠로 든다(Swift 글자의 같음은 정준 같음이라 NFC · NFD 꼴이 한 열쇠로 겹친다).
    static func regex(_ p: String, key: String? = nil) -> NSRegularExpression? {
        let k = key ?? p
        lock.lock(); defer { lock.unlock() }
        if let r = built[k] { return r }
        guard let r = try? NSRegularExpression(pattern: p) else { return nil }
        built[k] = r
        return r
    }
    static func first(_ s: String, _ p: String) -> (range: Range<String.Index>, g: [String])? {
        guard let r = regex(p), let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let whole = Range(m.range, in: s) else { return nil }
        return (whole, (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" })
    }
    static func groups(_ s: String, _ p: String) -> [String]? { first(s, p)?.g }
    static func ints(_ s: String, _ p: String) -> [Int]? {
        guard let r = regex(p), let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).flatMap { Int(s[$0]) } }
    }
    static func has(_ s: String, _ p: String) -> Bool { regex(p)?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    /// 맞은 자리 모두(앞에서부터 · 겹치지 않게).
    static func all(_ s: String, _ p: String) -> [Range<String.Index>] {
        guard let r = regex(p) else { return [] }
        return r.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s) }
    }
    /// 자모로 푼 글(NFD)에서 맞추기 — 꼴도 같이 푼다. 받침 하나를 꼴로 잡을 때 쓴다(꼴 안의 음절 묶음 `[…]` 은 풀리면 뜻이 바뀌니 쓰지 않는다).
    /// 푼 글에서 꼴의 음절은 앞머리로도 맞는다(받침이 뒤 자모라 「하」는 「한 · 할」의 앞에도 맞는다) — 음절 하나를 통째로 잡으려면 받침 있는 꼴을 직접 적거나 뒤에 받침 없음을 적는다.
    static func hasDecomposed(_ s: String, _ p: String) -> Bool {
        let s = s.decomposedStringWithCanonicalMapping, d = p.decomposedStringWithCanonicalMapping
        return regex(d, key: "nfd:" + d)?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    static func replacing(_ s: String, _ p: String, with template: String) -> String {
        regex(p)?.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template) ?? s
    }
    /// 빈칸을 뺀 글.
    static func strip(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "") }
}

struct DayReader: Sendable {
    let words: Words
    let zone: TimeZone
    let cal: Calendar

    init(zone: TimeZone, words: Words) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2
        self.words = words
        self.zone = zone
        self.cal = c
    }

    private var p: Words.Patterns { words.patterns }

    func noon(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(timeZone: zone, year: y, month: m, day: d, hour: 12))!
    }
    func ymd(_ d: Date) -> (Int, Int, Int) {
        let c = cal.dateComponents([.year, .month, .day], from: d); return (c.year!, c.month!, c.day!)
    }
    /// 날 하나 — 넘친 값(2월 30일)은 달력이 굴린 날로(정오를 세워 다시 읽는다).
    func make(_ d: Date, _ precision: SpokenReading.Precision) -> SpokenReading.Day {
        let (y, m, dd) = ymd(d)
        return SpokenReading.Day(date: noon(y, m, dd), year: y, month: m, day: dd, precision: precision)
    }

    /// 흐림 표지 — 때 표현 바로 뒤에 붙은 것만(빈칸 있는 원문에서) · 따로 선 「때」 · 이맘때 · 따로 선 계절 낱말.
    func isFuzzy(_ raw: String) -> Bool {
        let s = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return Rx.has(s, p.fuzzyAttached) || Rx.has(s, p.fuzzyWhen) || s.contains(words.thisTime) || season(Rx.strip(s)) != nil
    }
    /// 달 안의 앵커 날 — 달 초 = 1 · 중순 = 11 · 말 = 21일(흐림 표지로 붙은 때만).
    func part(_ t: String, _ fuzzy: Bool) -> Int {
        guard fuzzy else { return 1 }
        if Rx.has(t, p.monthMid) { return 11 }
        if Rx.has(t, p.monthLate) { return 21 }
        return 1
    }
    /// 따로 선 계절 낱말(앞이 해 · 상대 표지이거나 뒤가 조사 · 흐림 표지) → 그 계절.
    func season(_ t: String) -> Words.Season? {
        guard let g = Rx.groups(t, p.season) else { return nil }
        let w = g.first { !$0.isEmpty } ?? ""
        return words.seasons.first { $0.word == w }
    }
    /// 「이번 · 올 + 계절」 = 올해의 그 계절(1~2월의 겨울은 오늘이 든 겨울) · 「지난 + 계절」 = 오늘 앞에 끝난 가장 가까운 그 계절 ·
    /// 「다음 + 계절」 = 오늘 뒤에 시작하는 가장 가까운 그 계절. 그 계절 첫 달 1일.
    func relativeSeason(_ t: String, now: Date) -> Date? {
        guard let g = Rx.groups(t, p.relativeSeason), g.count == 2, let s = words.seasons.first(where: { $0.word == g[1] }) else { return nil }
        let (ny, nm, nd) = ymd(now)
        let today = noon(ny, nm, nd)
        let start = { (y: Int) in noon(y, s.first, 1) }
        let end = { (y: Int) in cal.date(byAdding: DateComponents(month: s.months, day: -1), to: start(y))! }
        let shift = words.seasonShift[g[0]] ?? 1
        if shift == 0 { return (s.first == 12 && nm <= 2) ? start(ny - 1) : start(ny) }
        if shift < 0 { var y = ny; while end(y) >= today { y -= 1 }; return start(y) }
        var y = ny; while start(y) <= today { y += 1 }; return start(y)
    }

    func count(_ s: String) -> Int? { Int(s) ?? words.nativeCount[s] ?? words.sinoCount[s] }

    /// 날 하나 셈의 답 — 날 + 맞은 자리(빈칸 뺀 글의 글자 자리) + 흐림(「N년 안에」) + 해를 기준 해로 채웠는가(수식 없는 달 · 계절).
    struct Hit {
        var day: SpokenReading.Day
        var parts: [Range<Int>]
        var soft = false
        var bare = false
    }
    static func at(_ r: Range<String.Index>, in t: String) -> Range<Int> {
        let lo = t.distance(from: t.startIndex, to: r.lowerBound)
        return lo..<(lo + t.distance(from: r.lowerBound, to: r.upperBound))
    }

    /// 표현 하나(문장 전체)를 기준 시각에서 푼다. 못 풀면 nil. `future` = 앞일 — 수식 없는 달 · 달과 날 · 계절만 오늘 이후로(수식어가 이긴다).
    func resolve(_ text: String, now: Date, future: Bool = false) -> SpokenReading.Day? { hit(text, now: now, future: future)?.day }

    /// `resolve` 의 셈 — 맞은 자리와 함께.
    func hit(_ text: String, now: Date, future: Bool = false) -> Hit? {
        let t = Rx.strip(text)
        var parts: [Range<Int>] = []
        // 맞은 꼴 · 낱말의 자리를 적으며 읽는다
        let ints = { (pattern: String) -> [Int]? in
            guard let m = Rx.first(t, pattern) else { return nil }
            parts.append(DayReader.at(m.range, in: t))
            return m.g.compactMap { Int($0) }
        }
        let groups = { (pattern: String) -> [String]? in
            guard let m = Rx.first(t, pattern) else { return nil }
            parts.append(DayReader.at(m.range, in: t))
            return m.g
        }
        let word = { (w: String) -> Bool in
            guard let r = t.range(of: w) else { return false }
            parts.append(DayReader.at(r, in: t))
            return true
        }
        let seasonHit = { () -> Words.Season? in
            guard let s = season(t) else { return nil }
            _ = groups(p.season)
            return s
        }
        let done = { (date: Date, precision: SpokenReading.Precision) -> Hit in Hit(day: make(date, precision), parts: parts) }
        if Rx.has(t, p.vagueCount) { return nil }
        // 되풀이 문장 — 말한 시작(「A부터」의 A)만 푼다 · 시작이 달이고 되풀이 날을 말했으면 그 달의 그 날
        if Rx.has(t, p.recurring) {
            guard let r = t.range(of: words.from) else { return nil }
            let head = String(t[..<r.lowerBound])
            guard !Rx.has(head, p.recurring), var s = hit(head, now: now, future: future) else { return nil }
            if s.day.precision == .month, let m = Rx.first(String(t[r.upperBound...]), p.repeatDay), let d = Int(m.g[0]) {
                let (y, mm, _) = ymd(s.day.date); s.day = make(noon(y, mm, d), .exact)
            }
            return s
        }
        let fuzzy = isFuzzy(text)
        // 해 말 = 10월 — 「말」 뒤가 낱말 경계일 때만(빈칸 있는 원문에서 · 「말하다」는 아니다)
        let yearEnd = Rx.has(text, p.yearEnd)
        let (ny, nm, _) = ymd(now)
        let add: (Calendar.Component, Int) -> Date? = { cal.date(byAdding: $0, value: $1, to: now) }
        if let d = dayRelative(t, now: now) { return d }

        // 완전한 날짜 · 해 · 달
        if let v = ints(p.fullDate), v.count == 3 { return done(noon(v[0], v[1], v[2]), .exact) }
        if let v = ints(p.yearMonth), v.count == 2 { return done(noon(v[0], v[1], part(t, fuzzy)), fuzzy ? .circa : .month) }
        if let v = ints(p.year), v.count == 1 {
            if let s = seasonHit() { return done(noon(v[0], s.first, 1), .circa) }
            if yearEnd { return done(noon(v[0], 10, 1), .circa) }
            return done(noon(v[0], 1, 1), fuzzy ? .circa : .year)
        }
        // 상대 — 해(달 · 날보다 먼저 — 해는 접두가 정한다)
        for o in words.yearOffset where word(o.word) {
            if let f = words.fixedDays.first(where: { word($0.word) }) { return done(noon(ny + o.value, f.month, f.day), .exact) }
            if let v = ints(p.monthDay), v.count == 2 { return done(noon(ny + o.value, v[0], v[1]), .exact) }
            if let v = ints(p.month), v.count == 1 { return done(noon(ny + o.value, v[0], part(t, fuzzy)), fuzzy ? .circa : .month) }
            if word(words.thisTime) { return done(noon(ny + o.value, nm, 1), .circa) }
            if let s = seasonHit() { return done(noon(ny + o.value, s.first, 1), .circa) }
            if yearEnd { return done(noon(ny + o.value, 10, 1), .circa) }
            return done(noon(ny + o.value, 1, 1), fuzzy ? .circa : .year)
        }
        // 해 없는 달 · 날 — 달 바로 앞 수식이 정한다 · 날까지 말하면 같은 셈으로 exact
        if let g = groups(p.shiftedMonth), g.count == 3, let m = Int(g[1]), (1...12).contains(m) {
            let past = words.monthShift.past.contains(g[0]), next = words.monthShift.future.contains(g[0])
            let twoBack = g[0] == words.monthShift.twoBack
            // 앞일 + 수식 없음 = 오늘 이후(오늘 · 이번 달 포함) 가장 가까운 그 날 · 그 달
            let ahead = future && g[0].isEmpty
            let today = noon(ny, nm, ymd(now).2)
            var y = ny
            var h: Hit
            if let d = Int(g[2]) {
                if past, noon(y, m, d) >= today { y -= 1 }
                if next, noon(y, m, d) <= today { y += 1 }
                if ahead, noon(y, m, d) < today { y += 1 }
                if twoBack { y -= 1 }
                h = done(noon(y, m, d), .exact)
            } else {
                if past, m >= nm { y -= 1 }
                if next, m <= nm { y += 1 }
                if ahead, m < nm { y += 1 }
                if twoBack { y -= 1 }
                h = done(noon(y, m, part(t, fuzzy)), fuzzy ? .circa : .month)
            }
            h.bare = g[0].isEmpty
            return h
        }
        parts = []   // 열두 달 밖의 수(「13월」)는 맞은 자리가 아니다
        // 상대 — 달(그 달의 날을 말하면 그 날 · exact)
        for o in words.monthOffset where word(o.word) {
            guard let at = add(.month, o.value) else { return nil }
            let (y, m, _) = ymd(at)
            if let v = ints(o.word + p.dayAfterWord), v.count == 1 { return done(noon(y, m, v[0]), .exact) }
            return done(noon(y, m, part(t, fuzzy)), fuzzy && Rx.has(t, o.word + p.partAfterWord) ? .circa : .month)
        }
        if let d = relativeSeason(t, now: now) { _ = groups(p.relativeSeason); return done(d, .circa) }
        // 앞일 + 수식 없는 계절 = 아직 끝나지 않은 가장 가까운 그 계절(오늘이 든 계절 포함 · 첫 달 1일)
        if future, let s = seasonHit() {
            let today = noon(ny, nm, ymd(now).2)
            var y = ny - 1
            while let end = cal.date(byAdding: DateComponents(month: s.months, day: -1), to: noon(y, s.first, 1)), end < today { y += 1 }
            var h = done(noon(y, s.first, 1), .circa)
            h.bare = true
            return h
        }
        // 상대 — 달 수 · 해 수
        let sign: (String) -> Int = { $0 == words.before ? -1 : 1 }
        if let g = groups(p.halfYear), g.count == 1, let at = add(.month, 6 * sign(g[0])) { let (y, m, _) = ymd(at); return done(noon(y, m, 1), .month) }
        if let g = groups(p.unitsAgo), g.count == 3, let n = count(g[0]) {
            let k = sign(g[2])
            if words.monthUnits.contains(g[1]) { guard let at = add(.month, n * k) else { return nil }; let (y, m, _) = ymd(at); return done(noon(y, m, 1), .month) }
            guard let at = add(.year, n * k) else { return nil }
            return done(noon(ymd(at).0, 1, 1), .year)
        }
        return future ? within(text, now: now) : nil
    }

    /// 「N년 안에 · 이내에」(앞일만) — 「N년 뒤」와 같은 자리 · 흐림(상한을 점으로 놓는다). 달 · 주 · 일도 같은 셈. 지난 일의 「안에」는 햇수다(때가 아니다).
    func within(_ text: String, now: Date) -> Hit? {
        guard let m = Rx.first(text, p.within) else { return nil }
        let g = m.g, t = Rx.strip(text)
        let date: Date?, precision: SpokenReading.Precision
        if !g[0].isEmpty {
            date = cal.date(byAdding: .month, value: 6, to: now); precision = .month
        } else if let d = words.nativeDays.first(where: { $0.word == g[1] }) {
            date = cal.date(byAdding: .day, value: d.value, to: now); precision = .exact
        } else if let n = count(g[2]) {
            if words.monthUnits.contains(g[3]) { date = cal.date(byAdding: .month, value: n, to: now); precision = .month }
            else if g[3] == words.dayUnit { date = cal.date(byAdding: .day, value: n, to: now); precision = .exact }
            else if words.weekUnits.contains(g[3]) { date = cal.date(byAdding: .day, value: 7 * n, to: now); precision = .exact }
            else { date = cal.date(byAdding: .year, value: n, to: now); precision = .year }
        } else { return nil }
        guard let date else { return nil }
        let (y, mm, d) = ymd(date)
        let first = precision == .year ? noon(y, 1, 1) : precision == .month ? noon(y, mm, 1) : noon(y, mm, d)
        return Hit(day: make(first, precision), parts: [DayReader.at(SpanReader.stripped(text, m.range, in: t), in: t)], soft: true)
    }

    /// 날 단위 상대 표현 — 있으면 이것이 때다(같은 문장의 다른 달 표현은 대상).
    func dayRelative(_ text: String, now: Date) -> Hit? {
        let t = Rx.strip(text)
        let add: (Calendar.Component, Int) -> Date? = { cal.date(byAdding: $0, value: $1, to: now) }
        guard let mon = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return nil }   // 이번 주 월요일
        var part = 0..<0
        let groups = { (pattern: String) -> [String]? in
            guard let m = Rx.first(t, pattern) else { return nil }
            part = DayReader.at(m.range, in: t)
            return m.g
        }
        let exact = { (d: Date) -> Hit in Hit(day: make(d, .exact), parts: [part]) }
        if let g = groups(p.weekDay), g.count == 2, let o = words.weekOffset[g[0]] {
            let idx: Int
            if g[1] == words.weekend { idx = 5 }                                                   // 주말 = 토
            else if let wd = words.weekday[String(g[1].prefix(1))] { idx = (wd + 5) % 7 }        // 월 0 … 일 6
            else { return nil }
            return cal.date(byAdding: .day, value: o * 7 + idx, to: mon).map(exact)
        }
        if let g = groups(p.thisWeekday), g.count == 1, let wd = words.weekday[g[0]] {
            return cal.date(byAdding: .day, value: (wd + 5) % 7, to: mon).map(exact)
        }
        if let g = groups(p.lastWeekday), g.count == 1, let wd = words.weekday[g[0]] {
            let cur = cal.component(.weekday, from: now)
            var back = (cur - wd + 7) % 7; if back == 0 { back = 7 }
            return add(.day, -back).map(exact)
        }
        let sign: (String) -> Int = { $0 == words.before ? -1 : 1 }
        if let g = groups(p.weekAgo), g.count == 1 { return add(.day, 7 * sign(g[0])).map(exact) }
        for d in words.nativeDays {
            if let g = groups(d.word + p.agoAfterWord), g.count == 1 { return add(.day, d.value * sign(g[0])).map(exact) }
        }
        if let g = groups(p.daysAgo), g.count == 3, let n = count(g[0]) {
            let (days, over) = ((g[1] == words.dayUnit ? 1 : 7) * sign(g[2])).multipliedReportingOverflow(by: n)
            return over ? nil : add(.day, days).map(exact)
        }
        for o in words.dayOffset where groups(o.word + p.dayWordGuard) != nil { return add(.day, o.value).map(exact) }
        return nil
    }

    /// 끝 날 — 말한 끝만: 「A부터 B까지」 = B(빠진 해 · 달은 시작에서 잇고 이은 끝이 시작보다 앞이면 빠진 쪽의 윗 단위를 하나 올린다 — 「D일」 · 「M월 D일」 · 「M월」) ·
    /// 「N박」 = 시작 + N일(시작이 exact 일 때만) · 그 밖은 nil.
    /// 시작은 그 연 · 월 · 일로 센다(다른 시간대에서 지은 날이어도 날이 어긋나지 않게).
    func resolveEnd(_ text: String, start: SpokenReading.Day?, now: Date, future: Bool = false) -> SpokenReading.Day? {
        let reader = SpanReader(zone: zone, words: words, direction: future ? .future : .past)
        let t = Rx.strip(reader.settled(text, now: now))
        let before = { (e: SpokenReading.Day, s: SpokenReading.Day) in (e.year, e.month, e.day) < (s.year, s.month, s.day) }
        if let g = Rx.groups(t, p.fromUntil), g.count == 1 {
            let b = g[0].replacingOccurrences(of: SpanReader.gap, with: "")
            if let s = start, let v = Rx.ints(b, p.endDay), v.count == 1 {
                var e = make(noon(s.year, s.month, v[0]), .exact)
                if before(e, s) { e = make(noon(s.year, s.month + 1, v[0]), .exact) }
                return e
            }
            if let s = start, let v = Rx.ints(b, p.endMonthDay), v.count == 2 {
                var e = make(noon(s.year, v[0], v[1]), .exact)
                if before(e, s) { e = make(noon(s.year + 1, v[0], v[1]), .exact) }
                return e
            }
            // 해 없는 달만(「M월」 · 달 안의 때 표지는 붙어도 된다) — 해는 시작에서 잇고, 이은 끝의 달이 시작의 달보다 앞이면 한 해 올린다(방향과 상관없이)
            if let s = start, let v = Rx.ints(b, p.endMonth), v.count == 1, (1...12).contains(v[0]),
               let r = resolve(b, now: now, future: future), r.month == v[0] {
                let y = v[0] < s.month ? s.year + 1 : s.year
                return make(noon(y, r.month, r.day), r.precision)
            }
            // 그 밖의 끝은 끝 쪽 제 꼴 — 날 하나 읽기와 같은 읽음(두 자리 해 · 연대 포함 · 연대 끝은 그 연대 첫 날)
            return reader.storedDay(b, now: now)
        }
        if let s = start, s.precision == .exact, let v = Rx.ints(t, p.nights), v.count == 1 {
            return cal.date(byAdding: .day, value: v[0], to: noon(s.year, s.month, s.day)).map { make($0, .exact) }
        }
        return nil
    }

    /// 때가 아닌 것을 가린 글 — 공개 손 넷이 읽기 전에 한 번(가린 토막 밖 글은 그대로).
    ///   해가 아닌 긴 수의 덩이는 빈칸으로 · 이름 · 인용(낫표 · 따옴표 안 · 「X(이)라는 · (이)란 · (이)라고」 앞의 때 낱말)과
    ///   뒤에 낱말이 이은 「전」 앞의 햇수(「20년 전통」)는 가름 글자로. 문장 전체가 따옴표로 싸였으면 벗기고 읽는다.
    static func masked(_ text: String, words: Words) -> String {
        let p = words.patterns
        var s = text
        if let m = Rx.first(s, p.quotedWhole), let inner = m.g.first(where: { !$0.isEmpty }) { s = inner }
        for pattern in [p.quoted, p.namedTime, p.yearsCount] { s = Rx.replacing(s, pattern, with: " " + SpanReader.gap + " ") }
        return Rx.replacing(s, p.longNumberBlock, with: " ")
    }

    /// 기간 신호 — 「N박」(낱말 경계 · 빈칸을 뺀 글에서) · 기간 낱말(빈칸을 하나로 줄인 원문에서 — 낱말 사이 빈칸이 뜻을 가른다).
    static func spanSignal(_ text: String, words: Words) -> Bool {
        let spaced = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return Rx.has(Rx.strip(text), words.patterns.nights) || Rx.has(spaced, words.patterns.spanWords)
    }
}
