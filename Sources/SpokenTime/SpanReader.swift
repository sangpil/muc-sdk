import Foundation

// 구간 읽기 — 절대 · 상대(날 하나 읽기 `DayReader` 위에 구간을 세운다) · 생년 · 기준 사건으로 읽는 때(나이 · 학년 · 학교급 · 시대 · 인생 사건).
//   생년에서: 학년도 = 3월 1일 ~ 이듬해 2월 말일 · 「N살」 = 두 해(세는나이 해 … 만 나이 해) · 「만 N세」 = 생일부터 한 해 ·
//   1~2월생이고 생년 ≤ 2002 이면 한 해 일찍 입학한 무리라 학교급 구간을 한 해 앞으로 넓히고 흐리게 둔다.
//   기준 사건에서: 사건 낱말 바로 뒤 수식(직후 · 직전 · 첫해 · 그해 · 전 · 뒤 · 때)이 구간을 정한다 · 그 사건이 없으면 지어내지 않고 묻는다 ·
//   사건 낱말 바로 앞이 다른 사람이면 내 사건이 아니다.
//   겹치면 좁은 것이 이긴다 — 절대 · 상대가 생년으로 읽은 때와 겹치면 겹치는 구간만 · 겹치지 않는 둘은 고르지 않고 묻는다(`SaidTimes`).
//   연대는 문장의 해가 선 다른 때 표현 · 최근에 진다(「어제 90년대 노래」 = 어제 · 해 없는 달 · 계절에는 지지 않는다) · 빈도(「N년에 한 번」)는 되풀이 · 되풀이 낱말은 문장의 끝 풀이말 마디에 걸릴 때만 되풀이(꾸미는 마디 · 다른 문장의 되풀이는 나머지를 읽는다 — `clauseRead`) · 날 하나(`storedDay`)는 이 읽음의 저장 꼴.

struct SpanReader: Sendable {
    let day: DayReader
    /// 두 자리 해의 방향(지난 일 ⟂ 앞일).
    let direction: SpokenReading.Direction
    var words: Words { day.words }
    var p: Words.Patterns { day.words.patterns }

    init(zone: TimeZone, words: Words, direction: SpokenReading.Direction) { day = DayReader(zone: zone, words: words); self.direction = direction }

    /// 사건 뒤 수식의 갈래.
    enum Mod: String, Decodable, Sendable { case after3m, before3m, firstYear, thatYear, before1y, after1y, at }

    /// 날(연 · 월 · 일) — 셈은 시간대 없는 그레고리력 날로 한다(정오 앵커라 시간대가 날을 바꾸지 않는다).
    struct D: Comparable, Hashable, Sendable {
        var y: Int, m: Int, d: Int
        init(_ y: Int, _ m: Int, _ d: Int) { self.y = y; self.m = m; self.d = d }
        static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()
        private var utcNoon: Date { D.utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        private init(utc date: Date) { let c = D.utc.dateComponents([.year, .month, .day], from: date); self.init(c.year!, c.month!, c.day!) }
        static func < (a: D, b: D) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }
        func adding(_ c: Calendar.Component, _ n: Int) -> D { D(utc: D.utc.date(byAdding: c, value: n, to: utcNoon)!) }
        static func last(_ y: Int, _ m: Int) -> D { D(y, m, utc.range(of: .day, in: .month, for: D(y, m, 1).utcNoon)!.count) }
    }
    /// 읽은 구간 — `parts` = 맞은 자리(읽은 글의 글자 자리 · 앞에서부터) · `bare` = 해를 기준 해로 채웠다(수식 없는 달 · 계절) · `decade` = 연대 · `bound` = 상한(「N년 안에」) ·
    /// `reach` = 겹침을 재는 폭(「결혼하고 나서 · 결혼 전」은 한 해만 말한 것이 아니다).
    struct S {
        var from: D, to: D
        var rule: String
        var soft: Bool
        var phrase: String
        var parts: [Range<Int>] = []
        var bare = false, decade = false, bound = false
        var reach: ClosedRange<D>?
    }
    enum Life { case span(S, Range<String.Index>); case ask(SpokenReading.Ask.Reason, String?, String, Range<String.Index>) }

    func d(_ date: Date) -> D { let c = day.ymd(date); return D(c.0, c.1, c.2) }
    func date(_ x: D) -> Date { day.noon(x.y, x.m, x.d) }

    static func year(_ y: Int) -> (D, D) { (D(y, 1, 1), D(y, 12, 31)) }
    static func month(_ y: Int, _ m: Int) -> (D, D) { (D(y, m, 1), D.last(y, m)) }
    static func schoolYear(_ y: Int) -> (D, D) { (D(y, 3, 1), D.last(y + 1, 2)) }
    /// 계절 구간 — 해(또는 학년도) y 안에서 · 겨울은 이듬해 2월까지.
    func season(_ word: String, in y: Int) -> (D, D) {
        guard let s = words.seasons.first(where: { $0.word == word }) else { return SpanReader.year(y) }
        let end = D(y, s.first, 1).adding(.month, s.months - 1)
        return (D(y, s.first, 1), D.last(end.y, end.m))
    }
    func nativeNumber(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        var v = 0, rest = Substring(s)
        if let t = words.nativeTens.keys.sorted(by: { $0.count > $1.count }).first(where: { rest.hasPrefix($0) }) { v += words.nativeTens[t]!; rest = rest.dropFirst(t.count) }
        if !rest.isEmpty { guard let o = words.nativeOnes[String(rest)] else { return nil }; v += o }
        return v == 0 ? nil : v
    }
    /// 구간 → 저장 값 — 앵커 = 구간 첫 날 · 정밀도 = 폭(하루 exact · 끝 < 첫 날 + 1달 month · 끝 < 첫 날 + 1해 year · 흐리면 둘 다 circa · 그 밖 period).
    static func store(_ f: D, _ t: D, soft: Bool) -> (D, SpokenReading.Precision) {
        if f == t { return (f, .exact) }
        if t < f.adding(.month, 1) { return (f, soft ? .circa : .month) }
        if t < f.adding(.year, 1) { return (f, soft ? .circa : .year) }
        return (f, .period)
    }
    func finish(_ s: S) -> SpokenReading.Span {
        let (a, precision) = SpanReader.store(s.from, s.to, soft: s.soft)
        return SpokenReading.Span(from: date(s.from), to: date(s.to), anchor: date(a), precision: precision, rule: s.rule, soft: s.soft,
                                  phrase: s.phrase.replacingOccurrences(of: SpanReader.gap, with: ""))
    }
    func ask(_ reason: SpokenReading.Ask.Reason, _ key: String?, _ rule: String, direction: SpokenReading.Direction? = nil) -> SpokenReading {
        .ask(SpokenReading.Ask(reason: reason, anchorKey: key, rule: rule, direction: direction))
    }

    // ── 문장 하나 → 읽음 하나
    /// `rangeStart` = 날 하나 읽기(`day`) — 「A부터 B까지」가 서면 구간 전체가 아니라 A 의 읽음(시작 쪽 제 꼴 · 끝은 `end` 가 B 를 읽는다). 그 밖은 같은 읽음.
    func read(_ text: String, now: Date, context: SpokenReading.Context, rangeStart: Bool = false) -> SpokenReading {
        // 말 고침을 걷고(정정 표지 앞의 때를 가린다 — `settled`) 빈칸은 대부분 지우고 읽는다 · 낱말 경계가 뜻을 가르는 토막만 빈칸 있는 원문(raw)에서 본다
        let raw = settled(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces), now: now, context: context)
        let t = Rx.strip(raw)
        // 되풀이는 시점이 아니다 — 둘레 구간이 서면 그 구간 · 생년 · 기준 사건이 없어 묻는 때도 되풀이보다 먼저.
        // 빈도(「N년에 한 번」 · 세 자리까지 — 네 자리는 늘 해)도 되풀이다 — 그 토막은 해가 아니니 가리고 둘레를 읽는다.
        // 단 뒤의 풀이말이 지난 꼴이면(「98년에 한 번 가 봤어」) 그 해에 한 번이다 — 빈도가 아니다(「마다」는 늘 빈도).
        // 지난 꼴 = 한 번 일어난 일 — 과거 선어말(받침 ㅆ — 있 · 겠 밖) · 「-ㄴ 적」. 낱말 목록이 아니라 꼴로 잡으니 자모로 푼 글에서 본다 ·
        // 앞에 꾸밈 · 이음(는 — 대이름씨에 붙은 토씨 「나는」 밖 · 는데 · 지만 · 면서) · 지난 버릇(어간에 붙은 곤 하다 · 번씩)이 서면 거기서 끊는다(빈도).
        // 빈도 토막 바로 뒤가 「-던」 + 이름씨(「런던」 밖 · 받침 ㄴ · ㄹ 관형과 「는」은 이름씨 · 토씨와 꼴로 갈리지 않아 보지 않는다 · 「61년에 한 번 열리던 축제에 갔다」)면 빈도는 이름씨를 꾸민 것 — 사건의 때도 되풀이도 아니니 가리고 둘레를 읽는다
        if let m = Rx.first(raw, p.frequency), Rx.hasDecomposed(String(raw[m.range.upperBound...]), p.frequencyModifies) {
            var body = raw
            body.replaceSubrange(m.range, with: " ")
            return read(body, now: now, context: context, rangeStart: rangeStart)
        }
        let frequency = Rx.first(raw, p.frequency).flatMap { m in Rx.hasDecomposed(String(raw[m.range.upperBound...]), p.pastAfter) ? nil : m.range }
        // 되풀이 낱말은 문장의 끝 풀이말 마디에 걸릴 때만 문장 때를 되풀이로 바꾼다(`clauseRead`) — 꾸미는 마디 · 다른 문장의 되풀이는 둘레를 읽는다 ·
        // 빈도가 함께 서도 같다(가른 글을 다시 읽는 손이 빈도를 빈도로 읽는다)
        if Rx.has(t, p.recurringWhen), let r = clauseRead(raw, now: now, context: context, rangeStart: rangeStart) { return r }
        if frequency != nil || Rx.has(t, p.recurringWhen) {
            var body = raw
            if let r = frequency { body.replaceSubrange(r, with: " ") }
            switch readOne(body, now: now, context: context) {
            case .span(let s): return .span(s)
            case .ask(let a) where a.reason == .needsBirth || a.reason == .needsAnchor || a.reason == .conflict: return .ask(a)
            default: return .recurring
            }
        }
        // 「A부터 B까지」 = A 의 처음 … B 의 끝(끝에 해 · 달이 없으면 시작의 것을 물려받는다)
        if let m = Rx.first(raw, p.range), case .span(let a) = readOne(m.g[0], now: now, context: context),
           case .span(let b) = (inheritEnd(m.g[1], from: d(a.from)).map { SpokenReading.span(finish($0)) } ?? readOne(m.g[1], now: now, context: context)),
           a.from <= b.to {
            if rangeStart { return .span(a) }
            return .span(finish(S(from: d(a.from), to: d(b.to), rule: a.rule, soft: a.soft || b.soft, phrase: a.phrase + words.from + b.phrase + words.until)))
        }
        return readOne(raw, now: now, context: context)
    }

    /// 되풀이 낱말의 마디 — 되풀이가 문장 때를 바꾸는 것은 그 낱말이 사건을 말하는 마디(문장의 끝 풀이말)에 걸릴 때뿐이다.
    ///   낱말마다 제 문장(끝 표지 `sentenceEnd` 로 가른다 — 수 뒤 마침표는 아니다) 안에서 뒤를 본다 — 꾸밈 풀이말 + 이름씨가 서면 꾸미는 마디(관형절):
    ///   「-던」(「런던」 밖 · 사이 낱말 둘까지 — 사이 낱말이 임자말 · 토씨 「은 · 는 · 도」 · 이음 · 맺음 꼴(`clauseLink`)이거나 때 표현이면 그 낱말은 마디 밖이라 꾸밈이 아니다) = 굳은 꾸밈 ·
    ///   「-는」(되풀이 낱말 바로 뒤 낱말만 · 줄기가 풀이말 꼴일 때만 — 받침 있는 줄기 · 풀이말 줄기 끝 `verbStemEnd` · 이름씨 + 토씨 `topicStem` 밖) = 무른 꾸밈 ·
    ///   뒤가 매인 이름씨(것 · 거 · 중 · 편 · 적 · 때 · 데 · 모양 …)면 끝 풀이말의 한 꼴이라 꾸밈이 아니다.
    ///   받침 ㄴ · ㄹ 관형은 받침 ㄴ · ㄹ 이름씨(돈 · 서울)와 꼴로 갈리지 않아 보지 않는다(끝 풀이말 마디로 남는다).
    ///   꾸미는 마디는 그 낱말(앞에 붙은 수 · 단위의 수 · 해 없는 달 · 날 · 계절 — 「4년마다」 · 「5월 3일마다」 · 「4월에 매년」 — 포함)부터 꾸밈 풀이말까지 가른다(가름 글자 —
    ///   빈칸을 뺀 글에서도 둘레가 붙지 않는다) · 문장 때는 나머지에서 — 굳은 꾸밈뿐이면 그 읽음 그대로(때가 없으면 묻기) · 무른 꾸밈이 끼면 구간이 설 때만.
    ///   끝 풀이말 마디의 되풀이가 있는 문장은 되풀이 문장 — 지금 손이 그 글에서 구간을 세우면(「1987년부터 매일 달렸다」) 그 답을 지키고, 아니면 다른 문장(여러 문장일 때)을 읽어 구간이 서면 그 구간.
    ///   nil = 되풀이 갈래(둘레 구간 · 생년 · 기준 사건 묻기 · 되풀이 — 부르는 쪽의 지금 손).
    func clauseRead(_ raw: String, now: Date, context: SpokenReading.Context, rangeStart: Bool) -> SpokenReading? {
        let t = Rx.strip(raw)
        let chars = Array(raw)
        let solid = chars.indices.filter { chars[$0] != " " }   // 빈칸 뺀 글의 자리 → 원문 자리
        let ends = Rx.all(raw, p.sentenceEnd).map { raw.distance(from: raw.startIndex, to: $0.upperBound) }
        let sentence = { (i: Int) -> Range<Int> in (ends.last { $0 <= i } ?? 0)..<(ends.first { $0 > i } ?? chars.count) }
        var hidden: [Range<Int>] = [], spoken: [Range<Int>] = [], loose = false
        for r in Rx.all(t, p.recurringWhen) {
            let lo = solid[t.distance(from: t.startIndex, to: r.lowerBound)], hi = solid[t.distance(from: t.startIndex, to: r.upperBound) - 1] + 1
            let s = sentence(lo)
            guard hi <= s.upperBound else { continue }   // 빈칸을 빼며 자모가 앞 글자에 붙으면 자리가 어긋난다 — 그 낱말은 건넌다
            let after = String(chars[hi..<s.upperBound])
            var end: Int?
            if let m = Rx.first(after, p.recurringModifies), !isTime(m.g[0], now: now) {
                end = hi + after.distance(from: after.startIndex, to: m.range.upperBound)
            } else if let m = Rx.first(after, p.recurringModifiesWeak), verbStem(m.g[0]) {
                end = hi + after.distance(from: after.startIndex, to: m.range.upperBound)
                loose = true
            }
            guard let e = end else { spoken.append(s); continue }
            hidden.append(lead(chars, lo, in: s)..<e)
        }
        if spoken.isEmpty {
            guard !hidden.isEmpty else { return nil }
            return ungap(read(SpanReader.gapped(raw, hidden), now: now, context: context, rangeStart: rangeStart), loose: loose)
        }
        // 되풀이 문장의 제 구간(「…부터」 · 최근 · 생년으로 읽는 때)은 지금 손 그대로
        switch readOne(raw, now: now, context: context) {
        case .span: return nil
        case .ask(let a) where a.reason == .conflict: return nil
        default: break
        }
        // 되풀이 문장을 뺀 다른 문장 — 구간이 설 때만(남은 글이 없으면 묻기라 nil)
        return ungap(read(SpanReader.gapped(raw, spoken), now: now, context: context, rangeStart: rangeStart), loose: true)   // 남은 문장의 꾸미는 마디는 다시 읽는 손이 가른다
    }

    /// 가름 글자 — 가린 토막의 자리(빈칸을 뺀 글에서도 둘레의 수 · 낱말이 붙지 않게 · 낸 `phrase` 에서는 뺀다).
    static let gap = "|"
    /// 자리 범위들을 가른 글 — 범위마다 첫 자리는 가름 글자 · 나머지는 빈칸(자리 수는 그대로).
    static func gapped(_ raw: String, _ rs: [Range<Int>]) -> String {
        var c = Array(raw)
        for r in rs where !r.isEmpty {
            for i in r { c[i] = " " }
            c[r.lowerBound] = Character(gap)
        }
        return String(c)
    }
    /// 가른 글의 읽음 — 구간이 아니면 `loose` 일 때 nil(지금 손으로).
    func ungap(_ x: SpokenReading, loose: Bool) -> SpokenReading? {
        switch x {
        case .span: return x
        case .ask(let a) where a.reason == .conflict: return x
        default: return loose ? nil : x
        }
    }
    /// 꾸미는 마디의 왼쪽 끝 — 되풀이 낱말 앞에 붙은 수(「4년마다」의 4) · 그 앞의 해 없는 달 · 날 · 계절(「5월 3일마다」 · 「4월에 매년」)도 마디다.
    func lead(_ chars: [Character], _ lo: Int, in s: Range<Int>) -> Int {
        var lo = lo
        for pattern in [p.numberLead, p.dateLead] {
            let before = String(chars[s.lowerBound..<lo])
            if let m = Rx.first(before, pattern) { lo = s.lowerBound + before.distance(from: before.startIndex, to: m.range.lowerBound) }
        }
        return lo
    }
    /// 사이 낱말에 해가 선 때 · 최근 · 끝 없는 때가 있는가(「매주 예전에 살던 동네에 간다」 — 그 되풀이는 마디 밖이다 · 해 없는 달 · 요일은 되풀이의 마디 안 낱말 「매년 4월에 열던」).
    func isTime(_ s: String, now: Date) -> Bool {
        let t = Rx.strip(s)
        return !t.isEmpty && (yearIsSet(s, now: now) || recent(t, now: now) != nil || vague(s) != nil)
    }
    /// 「-는」 앞 줄기가 풀이말 꼴인가 — 받침 있는 줄기(이름씨 뒤 토씨는 「은」) · 풀이말 줄기 끝 · 이름씨 + 토씨 꼴 밖.
    func verbStem(_ stem: String) -> Bool {
        guard let last = stem.unicodeScalars.last, !Rx.has(stem, p.topicStem) else { return false }
        let v = Int(last.value) - 0xAC00
        return (0..<11172).contains(v) && (v % 28 != 0 || Rx.has(stem, p.verbStemEnd))
    }

    /// 날 하나 — 같은 글 · 같은 방향 · 빈 맥락의 읽음이 낸 저장 꼴(앵커 · 정밀도) · 구간이 아니면(묻기 · 되풀이) nil · 「A부터 B까지」는 A 의 저장 꼴.
    func storedDay(_ text: String, now: Date) -> SpokenReading.Day? {
        guard case .span(let s) = read(text, now: now, context: .empty, rangeStart: true) else { return nil }
        return day.make(s.anchor, s.precision)
    }

    /// 끝 「M월 D일」 · 「D일」 · 「M월」(해 · 상대 낱말 없음) — 시작의 해 · 달을 잇고, 이은 끝이 시작보다 앞이면 한 칸 올린다.
    func inheritEnd(_ bRaw: String, from a: D) -> S? {
        let b = Rx.strip(bRaw).replacingOccurrences(of: SpanReader.gap, with: "")
        let matched = { (pattern: String) -> String in Rx.first(b, pattern).map { String(b[$0.range]) } ?? b }
        if let v = Rx.ints(b, p.endMonthDay), v.count == 2 {
            var e = D(a.y, v[0], v[1]); if e < a { e = D(a.y + 1, v[0], v[1]) }
            return S(from: e, to: e, rule: "absolute", soft: false, phrase: matched(p.endMonthDay))
        }
        if let v = Rx.ints(b, p.endDay), v.count == 1 {
            var e = D(a.y, a.m, v[0]); if e < a { e = D(a.y, a.m, 1).adding(.month, 1); e = D(e.y, e.m, v[0]) }
            return S(from: e, to: e, rule: "absolute", soft: false, phrase: matched(p.endDay))
        }
        if let v = Rx.ints(b, p.endMonth), v.count == 1, (1...12).contains(v[0]) {
            let y = v[0] < a.m ? a.y + 1 : a.y
            return S(from: D(y, v[0], 1), to: D.last(y, v[0]), rule: "absolute", soft: day.isFuzzy(bRaw), phrase: matched(p.endMonth))
        }
        return nil
    }
    /// 빈칸 뺀 글(t)의 범위 → 원문(raw)의 범위.
    static func unstripped(_ raw: String, _ r: Range<String.Index>, in t: String) -> Range<String.Index> {
        let lo = t.distance(from: t.startIndex, to: r.lowerBound), n = t.distance(from: r.lowerBound, to: r.upperBound)
        var seen = 0, a = raw.endIndex, b = raw.endIndex, i = raw.startIndex
        while i < raw.endIndex {
            if raw[i] != " " {
                if seen == lo { a = i }
                seen += 1
                if seen == lo + n { b = raw.index(after: i); break }
            }
            i = raw.index(after: i)
        }
        if n == 0 { b = a }
        return a..<b
    }
    /// 원문(raw)의 범위 → 빈칸 뺀 글(t)의 범위.
    static func stripped(_ raw: String, _ r: Range<String.Index>, in t: String) -> Range<String.Index> {
        let lo = raw[..<r.lowerBound].filter { $0 != " " }.count, n = raw[r].filter { $0 != " " }.count
        let a = t.index(t.startIndex, offsetBy: lo, limitedBy: t.endIndex) ?? t.endIndex
        return a..<(t.index(a, offsetBy: n, limitedBy: t.endIndex) ?? t.endIndex)
    }

    /// 마디 하나의 읽음 — 때가 둘이면 먼저 가르고(`SaidTimes` — 고름 · 꾸미는 때 · 겹치지 않는 둘) 남은 하나를 읽는다.
    func readOne(_ raw: String, now: Date, context: SpokenReading.Context) -> SpokenReading {
        let raw = raw.trimmingCharacters(in: .whitespaces)
        return twoTimes(raw, now: now, context: context) ?? pick(raw, now: now, context: context)
    }

    func pick(_ raw: String, now: Date, context: SpokenReading.Context) -> SpokenReading {
        let t = Rx.strip(raw)
        let lifeHit = lifeRead(t, raw: raw, context)
        // 맞은 토막 + 바로 뒤 「때」를 지운 나머지에서 절대 · 상대를 본다(빈칸 있는 나머지 — 흐림 표지는 붙은 자리로 가린다 · 자리 수는 그대로)
        let rest = lifeHit.map { SpanReader.blank(raw, [lifeReach($0, raw: raw, t: t)]) } ?? raw
        // 겹칠 때: 절대 > 상대 > 생년 · 기준 사건으로 읽은 때 — 겹치면 겹치는 구간만(겹치지 않는 둘은 `twoTimes` 가 먼저 묻는다)
        if var a = absRel(rest, now: now) {
            // 상한 안에 생년 · 기준 사건으로 읽은 때가 있으면 그 때다(「10년 안에 서른두 살 때」) — 상한은 다른 때가 없을 때의 점이다
            // 앞에 선 때도 그대로(「결혼하고 5년 안에」는 그 사건부터 센 것이다)
            if a.bound, let x = lifeHit {
                let first = lifeReach(x, raw: raw, t: t).lowerBound < (a.parts.first?.lowerBound ?? 0)
                switch x {
                case .span(let l, _): if first || (l.from <= a.to && d(now) <= l.to) { return .span(finish(l)) }
                case .ask(let w, let k, let b, _): if first { return ask(w, k, b) }
                }
            }
            if case .span(let l, let r)? = lifeHit, a.from <= l.to, l.from <= a.to {
                let f = max(a.from, l.from), e = min(a.to, l.to)
                if (f, e) != (a.from, a.to) {
                    a = S(from: f, to: e, rule: a.rule + "+" + (l.rule.split(separator: "+").first.map(String.init) ?? l.rule), soft: a.soft || l.soft,
                          phrase: SpanReader.text(raw, a.parts + [SpanReader.offsets(raw, SpanReader.unstripped(raw, r, in: t))]))
                }
            }
            return .span(finish(a))
        }
        switch lifeHit {
        case .span(let s, _)?: return .span(finish(s))
        case .ask(let w, let k, let b, _)?: return ask(w, k, b)
        case nil: break
        }
        if let r = recent(t, now: now) { return .span(finish(r)) }
        if let v = vague(raw) { return ask(.unbounded, nil, "vague", direction: v.direction) }
        return ask(.noExpression, nil, "none")
    }

    /// 생년 · 기준 사건으로 읽은 토막 + 바로 뒤 「때」의 자리(원문의 글자 자리).
    func lifeReach(_ x: Life, raw: String, t: String) -> Range<Int> {
        let r: Range<String.Index>
        switch x { case .span(_, let x): r = x; case .ask(_, _, _, let x): r = x }
        var e = r.upperBound
        if t[e...].hasPrefix(words.when) { e = t.index(e, offsetBy: words.when.count) }
        return SpanReader.offsets(raw, SpanReader.unstripped(raw, r.lowerBound..<e, in: t))
    }

    /// 끝 없는 때 · 방향만 있는 말 — 있으면 낱말이 품은 방향(앞 · 뒤 낱말이 함께 서거나 「언젠가 · 그때」면 없음 — 부르는 쪽의 몫).
    struct Vague { let direction: SpokenReading.Direction? }
    func vague(_ raw: String) -> Vague? {
        let t = Rx.strip(raw)
        let ahead = Rx.has(t, p.vagueFuture) || Rx.has(raw, p.futureWord), back = Rx.has(t, p.vaguePast) || Rx.has(raw, p.pastWord)
        guard ahead || back || Rx.has(t, p.vague) else { return nil }
        return Vague(direction: ahead == back ? nil : ahead ? .future : .past)
    }

    /// 최근(「최근 · 요즘 · 얼마 전 · 몇 달 전」) = 기준 날 한 해 전 … 기준 날(흐림).
    func recent(_ t: String, now: Date) -> S? {
        guard let m = Rx.first(t, p.recent) else { return nil }
        let n = d(now)
        return S(from: n.adding(.year, -1), to: n, rule: "relative", soft: true, phrase: String(t[m.range]))
    }

    /// 해가 선 때 표현이 있는가 — 날 단위 상대 · 요일 없는 주 · 네 자리 · 두 자리 해 · 해 낱말 · 수식 붙은 달 · 상대 달 · 상대 계절 · 「N달 · N년 전 · 후」 · 반년.
    /// 해 없는 달 · 계절은 기준 해로 채운 해라 서지 않는다(연대가 그것에 지면 해를 지어낸다).
    func yearIsSet(_ raw: String, now: Date) -> Bool {
        let t = Rx.strip(raw)
        if day.dayRelative(raw, now: now) != nil || Rx.has(t, p.plainWeek) { return true }
        if Rx.has(t, p.anyYear) || Rx.has(raw, p.twoDigitYear) { return true }
        if words.yearOffset.contains(where: { t.contains($0.word) }) || words.monthOffset.contains(where: { t.contains($0.word) }) { return true }
        if let g = Rx.groups(t, p.shiftedMonth), g.count == 3, !g[0].isEmpty { return true }
        return Rx.has(t, p.relativeSeason) || Rx.has(t, p.unitsAgo) || Rx.has(t, p.halfYear)
    }

    // ── 절대 · 상대(날 하나 읽기 위에 구간)
    /// `decades` = 연대 꼴을 볼까 — 연대는 문장의 다른 때 표현에 지므로, 연대를 가린 나머지를 연대 없이 먼저 읽는다.
    func absRel(_ raw0: String, now: Date, decades: Bool = true) -> S? {
        let n = d(now)
        let century = n.y - n.y % 100
        // 두 자리 해 · 두 자리 연대(「98년」 · 「90년대」) = 기준 해의 세기에 붙인다 — 지난 일(기본): 기준 해보다 뒤면 한 세기 앞 ·
        // 앞일: 기준 해보다 앞이면 한 세기 뒤(기준 해 이상 가장 가까운 해)
        let yy = { (v: Int) -> Int in
            let y = century + v
            switch direction {
            case .past: return y > n.y ? y - 100 : y
            case .future: return y < n.y ? y + 100 : y
            }
        }
        // 연대 — 초반 0~3 · 중반 4~6 · 후반 · 말 7~9. 문장의 해가 선 다른 때 표현 · 최근에 진다 — 「90년대 노래」는 노래를 꾸민다
        // 연대 꼴은 빈칸 있는 원문에서 · 뒤가 때 표지 · 조사 · 낱말 경계일 때만(「30년 대장정」 · 「30년대장정」은 연대가 아니다)
        if decades, let m = Rx.first(raw0, p.decade), let v = Int(m.g[0]) {
            let own = SpanReader.offsets(raw0, m.range)
            let rest = SpanReader.blank(raw0, [own])
            // 해가 선 다른 때 표현에 진다 — 해 없는 달 · 계절에는 지지 않는다(「90년대 어느 5월」은 기준 해의 5월이 아니다).
            // 최근에는 연대가 이름씨를 꾸밀 때만 진다(「요즘 90년대 노래」 = 요즘 ⟂ 「80년대에 살던 골목이 요즘 생각나」 = 연대 — 때 토씨가 붙은 연대는 사건의 때)
            if yearIsSet(rest, now: now), let other = absRel(rest, now: now, decades: false) { return other }
            if !Rx.has(String(raw0[m.range.upperBound...]), p.decadeAsTime), let r = recent(Rx.strip(rest), now: now) { return r }
            let base = m.g[0].count == 2 ? yy(v) : v
            let (lo, hi) = range(words.parts[m.g[1]]) ?? (0, 9)
            return S(from: D(base + lo, 1, 1), to: D(base + hi, 12, 31), rule: "absolute", soft: true, phrase: SpanReader.text(raw0, [own]), parts: [own], decade: true)
        }
        // 두 자리 해 — 뒤에 때 표지가 올 때만 해로 읽는다(햇수와 가른다 — 「N년도 넘 · 더」 · 「N년에 걸쳐」 · 「N년 동안」은 햇수) ·
        // 해 뒤 「도 · 의 · 쉼표」를 건너 달을 잇는다(「98년도 3월」 · 「98년의 3월」) · 세기는 방향을 따른다(위)
        var raw = raw0
        var short: (Range<Int>, Int)?   // 세기를 붙인 두 자리 해의 자리 · 늘어난 글자 수
        if let m = Rx.first(raw, p.twoDigitYear), let v = Int(m.g[0]) {
            let long = "\(yy(v))" + words.yearSuffix, own = SpanReader.offsets(raw0, m.range)
            short = (own, long.count - own.count)
            raw.replaceSubrange(m.range, with: long)
        }
        let t = Rx.strip(raw)
        // 맞은 자리(빈칸 뺀 글)를 읽은 글의 자리로 — 흐림 표지는 맞은 자리에 닿은 것만
        let located = { (found: [Range<Int>]) -> [Range<Int>] in
            let chars = Array(raw)
            let solid = chars.indices.filter { chars[$0] != " " }
            var touched = found.filter { !$0.isEmpty && $0.upperBound <= solid.count }.map { solid[$0.lowerBound]..<(solid[$0.upperBound - 1] + 1) }
            for r in touched {
                let near = r.lowerBound..<min(r.upperBound + 16, chars.count)
                let window = String(chars[near])
                for m in (Rx.all(window, p.fuzzyAttached) + Rx.all(window, p.fuzzyWhen)).map({ DayReader.at($0, in: window) }) {
                    let gapOnly = chars[r.upperBound..<max(r.upperBound, min(near.upperBound, near.lowerBound + m.lowerBound))].allSatisfy { $0 == " " }
                    if gapOnly { touched.append((near.lowerBound + m.lowerBound)..<(near.lowerBound + m.upperBound)) }
                }
            }
            return SpanReader.joined(touched.map { r in
                var lo = r.lowerBound, hi = r.upperBound
                if let (own, grown) = short {
                    if lo > own.lowerBound { lo = max(own.lowerBound, lo - grown) }
                    if hi > own.lowerBound { hi = max(own.lowerBound + 1, hi - grown) }
                }
                return lo..<hi
            })
        }
        guard let h = day.hit(raw, now: now, future: direction == .future) else {
            // 요일 없는 주 = 그 주 월 … 일
            guard let g = Rx.first(t, p.plainWeek), let o = words.weekOffset[g.g[0]] else { return nil }
            let mon = d(day.cal.date(from: day.cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!).adding(.day, 7 * o)
            let parts = located([DayReader.at(g.range, in: t)])
            return S(from: mon, to: mon.adding(.day, 6), rule: "relative", soft: day.isFuzzy(raw), phrase: SpanReader.text(raw0, parts), parts: parts)
        }
        let r = h.day
        let x = d(r.date)
        // 날 단위 상대가 때를 정했으면 relative — 같은 문장의 달 표현은 대상
        let absolute = !h.soft && day.dayRelative(raw, now: now) == nil
            && (Rx.has(t, p.anyYear) || (Rx.has(t, p.anyMonth) && !Rx.has(t, p.yearWords)))
        var rule = absolute ? "absolute" : "relative"
        var soft = h.soft || day.isFuzzy(raw)
        var span: (D, D)
        switch r.precision {
        case .exact, .period: span = (x, x)
        case .month: span = SpanReader.month(x.y, x.m)
        case .year: span = SpanReader.year(x.y)
        case .circa:
            soft = true
            if let s = day.season(t), x.m == s.first {
                span = season(s.word, in: x.y); rule += "+season"
            } else if t.contains(words.thisTime) {
                span = SpanReader.month(x.y, x.m)
            } else if Rx.has(t, p.monthOrPart) {
                // 달의 초 · 중순 · 말 — 붙은 자리만
                let (f, e) = SpanReader.month(x.y, x.m)
                if Rx.has(raw, p.monthEarlySpaced) { span = (f, D(x.y, x.m, 10)) }
                else if Rx.has(raw, p.monthMidSpaced) { span = (D(x.y, x.m, 11), D(x.y, x.m, 20)) }
                else if Rx.has(raw, p.monthLateSpaced) { span = (D(x.y, x.m, 21), e) }
                else { span = (f, e) }
            } else if Rx.has(raw, p.yearEarlySpaced) { span = (D(x.y, 1, 1), D.last(x.y, 3)) }
            else if Rx.has(raw, p.yearEnd) { span = (D(x.y, 10, 1), D(x.y, 12, 31)) }
            else { span = SpanReader.year(x.y) }
        }
        let parts = located(h.parts)
        // 「N년 안에」는 상한이다 — 겹침은 기준 날부터 상한까지로 잰다
        return S(from: span.0, to: span.1, rule: rule, soft: soft, phrase: SpanReader.text(raw0, parts), parts: parts, bare: h.bare, bound: h.soft,
                 reach: h.soft && n <= span.1 ? n...span.1 : nil)
    }

    private func range(_ v: [Int]?) -> (Int, Int)? { v.flatMap { $0.count == 2 ? ($0[0], $0[1]) : nil } }

    // ── 생년 · 기준 사건에서(인생 사건 > 학년 > 나이 > 나잇대 > 학교급 > 시대)
    func lifeRead(_ t: String, raw: String, _ c: SpokenReading.Context) -> Life? {
        if let x = lifeEvent(t, c) { return x }
        if let x = grade(t, raw: raw, c) { return x }
        if let x = age(t, c) { return x }
        if let x = ageBand(t, raw: raw, c) { return x }
        if let x = stage(t, c) { return x }
        return era(t, c)
    }

    struct Birth {
        let day: D
        var y: Int { day.y }
        /// 1~2월생이고 생년 ≤ 2002 — 한 해 일찍 입학한 마지막 무리까지
        var early: Bool { day.m <= 2 && day.y <= 2002 }
        /// 학교급 구간을 일찍 든 해까지 넓힌다
        func widen(_ s: (D, D)) -> (D, D) { early ? (s.0.adding(.year, -1), s.1) : s }
    }
    func birth(_ c: SpokenReading.Context) -> Birth? { c.birth.map { Birth(day: d($0)) } }

    /// 학년 — 학년도 Y = 생년 + 6 + 학년(초) · + 12(중) · + 15(고) · 대학 n학년은 늦은 입학 · 쉼까지 넓힌다.
    ///   줄임 학년은 빈칸 있는 원문에서 따로 선 낱말일 때만 · 띄운 줄임은 뒤에 학년 · 계절 같은 때 낱말이 올 때만.
    func grade(_ t: String, raw: String, _ c: SpokenReading.Context) -> Life? {
        for g in words.grades {
            guard let m = Rx.first(raw, g.pattern), let n = m.g.lazy.compactMap({ Int($0) }).first, (1...g.last).contains(n) else { continue }
            let r = SpanReader.stripped(raw, m.range, in: t)
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "grade", r) }
            let y = b.y + g.offset + n
            return withSeason(t, r, year: y, base: b.widen(SpanReader.schoolYear(y)), rule: "grade", soft: b.early, b: b)
        }
        if let m = Rx.first(t, p.universityGrade) {
            let n = Int(m.g[0]) ?? 1
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "grade", m.range) }
            let s: (D, D)
            if let u = c.anchor(words.school.universityKey).map({ d($0.start) }) {
                // 입학 사건이 있으면 그 해에서 센다 — 늦은 입학 없음 · 쉼 2 는 2학년부터
                let y = u.y + n - 1
                s = (D(y, 3, 1), D.last(y + 1 + (n == 1 ? 0 : 2), 2))
            } else {
                // 한 해 늦은 입학 · 두 해 쉼까지 — 1학년 1 · 2학년 이상 3
                let w = n == 1 ? 1 : 3
                s = b.widen((D(b.y + 18 + n, 3, 1), D.last(b.y + 18 + n + 1 + w, 2)))
            }
            return .span(S(from: s.0, to: s.1, rule: "grade", soft: true, phrase: String(t[m.range])), m.range)
        }
        return nil
    }

    /// 학년 · 나이 뒤의 계절 — 그 해(학년도) 안으로 좁힌다.
    func withSeason(_ t: String, _ r: Range<String.Index>, year y: Int, base: (D, D), rule: String, soft: Bool, b: Birth) -> Life {
        let tail = String(t[r.upperBound...])
        if let m = Rx.first(tail, p.seasonAfter) {
            let end = t.index(r.upperBound, offsetBy: tail.distance(from: tail.startIndex, to: m.range.upperBound))
            var s = season(m.g[0], in: y)
            if rule == "grade" { s = b.widen(s) }
            return .span(S(from: s.0, to: s.1, rule: rule + "+season", soft: true, phrase: String(t[r.lowerBound..<end])), r.lowerBound..<end)
        }
        return .span(S(from: base.0, to: base.1, rule: rule, soft: soft, phrase: String(t[r])), r)
    }

    /// 나이 — 「만 N세」 = 생일부터 한 해 · 「N살」 = 두 해(세는나이 해 … 만 나이 해) · 첫돌 · 환갑.
    ///   「A살에서 · 부터 B살 사이 · 까지」 = A 의 처음 … B 의 끝(「만」이 붙으면 생일에서 센다).
    func age(_ t: String, _ c: SpokenReading.Context) -> Life? {
        if let m = Rx.first(t, p.ageRange), case let ends = m.g.dropFirst().filter({ !$0.isEmpty }), ends.count == 2,
           let n = nativeNumber(ends[0]), let z = nativeNumber(ends[1]), n <= z {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "age", m.range) }
            let exact = !m.g[0].isEmpty
            let f = exact ? b.day.adding(.year, n) : D(b.y + n - 1, 1, 1)
            let e = exact ? b.day.adding(.year, z + 1).adding(.day, -1) : D(b.y + z, 12, 31)
            return .span(S(from: f, to: e, rule: "age", soft: !exact, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.ageExact), let n = nativeNumber(m.g.first { !$0.isEmpty } ?? "") {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "age", m.range) }
            let f = b.day.adding(.year, n)
            return .span(S(from: f, to: f.adding(.year, 1).adding(.day, -1), rule: "age", soft: false, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.firstBirthday) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "age", m.range) }
            let x = b.day.adding(.year, 1)
            return .span(S(from: x, to: x, rule: "age", soft: false, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.sixtieth) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "age", m.range) }
            let (f, e) = SpanReader.year(b.y + 60)
            return .span(S(from: f, to: e, rule: "age", soft: true, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.age), let n = nativeNumber(m.g.first { !$0.isEmpty } ?? "") {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "age", m.range) }
            return withSeason(t, m.range, year: b.y + n - 1, base: (D(b.y + n - 1, 1, 1), D(b.y + n, 12, 31)), rule: "age", soft: true, b: b)
        }
        return nil
    }

    /// 나잇대 — 각 끝 나이에 「N살」 규칙. 빈칸 있는 원문에서 · 대로 세는 이름씨가 토씨 없이 맞닿고 때 표지가 없으면 셈이다(「차 20대」).
    func ageBand(_ t: String, raw: String, _ c: SpokenReading.Context) -> Life? {
        let sums = Rx.all(raw, p.counted)
        guard let at = Rx.all(raw, p.ageBand).first(where: { x in !sums.contains { $0.overlaps(x) } }),
              let g = Rx.groups(String(raw[at]), p.ageBand), let k = Int(g[0]) else { return nil }
        let r = SpanReader.stripped(raw, at, in: t)
        guard let b = birth(c) else { return .ask(.needsBirth, nil, "ageBand", r) }
        let (lo, hi) = range(words.parts[g[1]]) ?? (0, 9)
        let a = k * 10 + lo, z = k * 10 + hi
        return .span(S(from: D(b.y + a - 1, 1, 1), to: D(b.y + z, 12, 31), rule: "ageBand", soft: true, phrase: String(t[r])), r)
    }

    /// 학교급 — 단계마다 생년에서 센 학년도 구간(자원의 표 · 표에 없는 단계는 대학).
    func stage(_ t: String, _ c: SpokenReading.Context) -> Life? {
        guard let m = Rx.first(t, p.stage) else { return nil }
        guard let b = birth(c) else { return .ask(.needsBirth, nil, "schoolStage", m.range) }
        let head = String(m.g[0].prefix(2))
        let row = words.stages.first { $0.heads.contains(head) && ($0.band == nil || $0.band == m.g[1]) }
        let (from, to) = row.map { ($0.from, $0.to) } ?? (words.stageRest.from, words.stageRest.to)
        let s = b.widen((D(b.y + from, 3, 1), D.last(b.y + to, 2)))
        return .span(S(from: s.0, to: s.1, rule: "schoolStage", soft: true, phrase: String(t[m.range])), m.range)
    }

    /// 시대 — 어릴 때 = 태어남 … 초등 마지막 학년도 끝 · 학창 시절 = 초1 … 고3.
    func era(_ t: String, _ c: SpokenReading.Context) -> Life? {
        if let m = Rx.first(t, p.childhood) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "era", m.range) }
            return .span(S(from: b.day, to: D.last(b.y + 13, 2), rule: "era", soft: true, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.schoolDays) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "era", m.range) }
            let s = b.widen((D(b.y + 7, 3, 1), D.last(b.y + 19, 2)))
            return .span(S(from: s.0, to: s.1, rule: "era", soft: true, phrase: String(t[m.range])), m.range)
        }
        return nil
    }

    /// 사건 뒤 수식 — 사건 낱말 바로 뒤(빈칸 뺀 글 8자 안).
    func modifier(_ t: String, after r: Range<String.Index>) -> (Mod, Range<String.Index>)? {
        let tail = String(t[r.upperBound...].prefix(8))
        for x in words.modifiers {
            if let m = Rx.first(tail, x.pattern) {
                let end = t.index(r.upperBound, offsetBy: tail.distance(from: tail.startIndex, to: m.range.upperBound))
                return (x.kind, r.lowerBound..<end)
            }
        }
        return nil
    }
    static func apply(_ k: Mod, _ e: (D, D)) -> (D, D, Bool) {
        let f = e.0
        switch k {
        case .after3m: return (f, f.adding(.month, 3).adding(.day, -1), true)
        case .before3m: return (f.adding(.month, -3), f.adding(.day, -1), true)
        case .firstYear, .after1y: return (f, f.adding(.year, 1).adding(.day, -1), true)
        case .before1y: return (f.adding(.year, -1), f.adding(.day, -1), true)
        case .thatYear: return (D(f.y, 1, 1), D(f.y, 12, 31), true)
        case .at: return (e.0, e.1, true)
        }
    }

    /// 「뒤 · 전」이 실제로 닿는 폭 — 한 해는 셈의 폭이지 말의 폭이 아니다(겹침은 이 폭으로 잰다).
    static func reach(_ k: Mod, _ e: (D, D)) -> ClosedRange<D>? {
        switch k {
        case .after1y: e.0...D(9999, 12, 31)
        case .before1y: D(1, 1, 1)...e.1
        default: nil
        }
    }

    /// 남의 사건 — 사건 낱말 바로 앞이 다른 사람이면 내 기준 사건이 아니다.
    func othersEvent(_ t: String, _ r: Range<String.Index>) -> Bool { Rx.has(String(t[..<r.lowerBound]), p.others) }

    /// 인생 사건 — 기준 사건(맥락의 사건) · 생년에서 셈하는 사건(태어남 · 학교의 처음과 끝 · 대입 시험 · 한 해 더 준비).
    func lifeEvent(_ t: String, _ c: SpokenReading.Context) -> Life? {
        // 기준 사건 — 없으면 지어내지 않고 묻는다
        for x in words.anchored {
            guard let m = Rx.first(t, x.pattern), case let (k, r)? = modifier(t, after: m.range), !othersEvent(t, m.range) else { continue }
            guard let a = c.anchor(x.key) else { return .ask(.needsAnchor, x.key, "lifeEvent", r) }
            let e = d(a.start)
            if let years = x.years {
                return .span(S(from: e, to: e.adding(.year, years).adding(.day, -1), rule: "lifeEvent", soft: true, phrase: String(t[r])), r)
            }
            if let endKey = x.endKey, k == .at {   // 기간 사건의 「그때」 = 시작 … 끝
                guard let end = a.end.map({ d($0) }) ?? c.anchor(endKey).map({ d($0.start) }) else {
                    return .ask(.needsAnchor, endKey, "lifeEvent", r)
                }
                return .span(S(from: e, to: end, rule: "lifeEvent", soft: true, phrase: String(t[r])), r)
            }
            let s = SpanReader.apply(k, (e, e))
            return .span(S(from: s.0, to: s.1, rule: "lifeEvent", soft: s.2, phrase: String(t[r]), reach: SpanReader.reach(k, (e, e))), r)
        }
        // 생년에서 — 태어난 해(흐림) · 태어난 날(생년월일로 아는 날)
        if let m = Rx.first(t, p.bornYear) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "lifeEvent", m.range) }
            return .span(S(from: D(b.y, 1, 1), to: D(b.y, 12, 31), rule: "lifeEvent", soft: true, phrase: String(t[m.range])), m.range)
        }
        if let m = Rx.first(t, p.bornDay) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "lifeEvent", m.range) }
            return .span(S(from: b.day, to: b.day, rule: "lifeEvent", soft: false, phrase: String(t[m.range])), m.range)
        }
        // 학교의 처음 = 3월 · 끝 = 2월 — 대학의 처음 해 = 맥락의 대학 사건의 해 · 없으면 생년 + 19 · 대학의 끝 = 처음 해 + 4 의 2월
        let school = words.school
        if let m = Rx.first(t, p.school), case let (k, r)? = modifier(t, after: m.range) {
            let lv = String(m.g[0].prefix(1)), isEntry = m.g[1] != school.graduationWord
            guard let off = isEntry ? school.entry[lv] : school.graduation[lv] else { return nil }
            let uni = lv == school.universityLevel ? c.anchor(school.universityKey).map { d($0.start).y } : nil
            guard uni != nil || c.birth != nil, let b = birth(c) ?? uni.map({ Birth(day: D($0 - 19, 6, 1)) }) else {
                return .ask(.needsBirth, nil, "lifeEvent", r)
            }
            let y = uni.map { $0 + (isEntry ? 0 : 4) } ?? (b.y + off)
            var e = SpanReader.month(y, isEntry ? 3 : 2)
            let early = uni == nil && b.early
            if early { e = (e.0.adding(.year, -1), e.1) }
            let s = SpanReader.apply(k, e)
            return .span(S(from: s.0, to: s.1, rule: "lifeEvent", soft: s.2 || early, phrase: String(t[r]), reach: SpanReader.reach(k, e)), r)
        }
        // 대입 시험 = 고3 학년도의 11월(「끝나고」 = 시험 … 고3 학년도 끝)
        if let m = Rx.first(t, p.examDay), case let (k, r)? = modifier(t, after: m.range) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "lifeEvent", r) }
            let y = b.y + 18
            var s: (D, D)
            switch k {
            case .after1y: s = (D(y, 11, 1), D.last(y + 1, 2))
            case .at: s = SpanReader.month(y, 11)
            default: let a = SpanReader.apply(k, SpanReader.month(y, 11)); s = (a.0, a.1)
            }
            s = b.widen(s)
            return .span(S(from: s.0, to: s.1, rule: "lifeEvent", soft: true, phrase: String(t[r]), reach: SpanReader.reach(k, b.widen(SpanReader.month(y, 11)))), r)
        }
        // 고3 다음 학년도
        if let m = Rx.first(t, p.gapYear) {
            guard let b = birth(c) else { return .ask(.needsBirth, nil, "lifeEvent", m.range) }
            let s = b.widen(SpanReader.schoolYear(b.y + 19))
            return .span(S(from: s.0, to: s.1, rule: "lifeEvent", soft: true, phrase: String(t[m.range])), m.range)
        }
        return nil
    }
}
