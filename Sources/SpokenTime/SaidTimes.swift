import Foundation

// 때가 둘 — 한 글에 선 때 표현을 하나씩 뽑아(맞은 자리를 가리며 같은 읽기 손을 다시 부른다) 무엇이 사건의 때인지 가른다.
//   말 고침   : 두 때 사이에 정정 표지(아니 · 아니다 · 아니라 · 정정할게 …)가 서면 앞 것을 가린다(`corrected` — 문장을 읽기 전에).
//   고름      : 「A였나 B였나 · A 아니면 B · A나 B」 — 맞닿거나 겹치면 합친 구간(흐림) · 떨어지면 묻기 `conflict`. 나잇대의 「A에서 B 사이 · A~B」는 A 의 처음 … B 의 끝(나이는 `age` 가 읽는다).
//     제 해를 저마다 말한 고름은 고름 말에서 갈라 읽는다(`chosen` — 말한 차례 · 방향과 상관없이) · 달력 물결은 「A부터 B까지」(`tilde`).
//   견줌      : 때에 붙은 「보다」 앞의 때는 가린다(`compared` — 문장을 읽기 전에).
//   꾸미는 때 : 이름씨를 꾸미는 때(「때 + 꼴이 또렷한 관형 + 이름씨」 바로 뒤에 다른 때 · 「때(의) + 이름씨 + 을/를」)는 또렷한 다른 때에 진다.
//   그 밖의 둘: 잇는 꼴 없이 한 마디에서 겹치지 않으면 고르지 않고 묻는다(`conflict` + 후보 · 문장에 나온 차례).
//     잇는 꼴(-아서 · -고 · -다가 · -는데 · -지만 …)로 이은 두 때 · 다른 문장의 두 때는 다투지 않는다 — 읽는 차례(`pick`)가 하나를 읽는다.
//     해 없는 달 · 계절은 해를 기준 해로 채운 것이라 해가 선 때와 다투지 않고 · 연대 · 최근 · 끝 없는 때도 다투지 않는다 ·
//     「결혼하고 나서 · 결혼 전」은 그 뒤 · 앞 전부와 겹치는 것으로 본다(`S.reach`). 이름씨를 꾸미는 때가 홀로면 문장의 때다.

extension SpanReader {
    /// 문장에 선 때 표현 하나 — `s` 가 없으면 생년 · 기준 사건이 있어야 정하는 때(자리만 안다).
    struct Mention {
        var s: S?
        var parts: [Range<Int>]
        /// 가릴 자리 — 맞은 자리(생년 · 기준 사건으로 읽은 때는 바로 뒤 「때」까지).
        var mask: [Range<Int>]
        let life: Bool
        /// 합친 것(고름 · 사이) — 다시 읽지 않고 이 구간을 쓴다.
        var merged = false
        var lo: Int { parts.first!.lowerBound }
        var hi: Int { parts.last!.upperBound }
    }

    // ── 글자 자리
    static func offsets(_ s: String, _ r: Range<String.Index>) -> Range<Int> { DayReader.at(r, in: s) }
    /// 자리 범위들을 빈칸으로(자리 수는 그대로 — 빈칸을 뺀 글에서는 둘레가 붙는다).
    static func blank(_ raw: String, _ rs: [Range<Int>]) -> String {
        var c = Array(raw)
        for r in rs { for i in r { c[i] = " " } }
        return String(c)
    }
    /// 겹치거나 닿은 범위를 이은 것(앞에서부터).
    static func joined(_ rs: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in rs.sorted(by: { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }) {
            if let last = out.last, r.lowerBound <= last.upperBound { out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound) } else { out.append(r) }
        }
        return out
    }
    /// 자리 범위들의 글(빈칸을 뺀다) — 맞은 토막.
    static func text(_ raw: String, _ rs: [Range<Int>]) -> String {
        let c = Array(raw)
        return Rx.strip(joined(rs).map { String(c[$0]) }.joined())
    }
    static func slice(_ raw: String, _ r: Range<Int>) -> String { let c = Array(raw); return String(c[r.clamped(to: 0..<c.count)]) }

    /// 글의 문장들 — 끝 표지로 가른다(수 뒤 마침표는 아니다).
    func sentences(_ raw: String) -> [Range<Int>] {
        var out: [Range<Int>] = [], lo = 0
        for end in Rx.all(raw, p.sentenceEnd).map({ SpanReader.offsets(raw, $0).upperBound }) + [raw.count] where end > lo { out.append(lo..<end); lo = end }
        return out
    }

    // ── 때 표현 뽑기
    /// 글에 선 때 표현들 — 읽는 차례로 뽑고(앞 것을 가리며 다시 읽는다) 나온 차례로 낸다. 첫 뽑음이 읽는 손(`pick`)이 고르는 때다(`first`).
    func mentions(_ raw: String, now: Date, context: SpokenReading.Context) -> [Mention] { draw(raw, now: now, context: context).list }
    /// 뽑은 것 — 첫 생년 · 기준 사건의 때 · 그것을 지운 나머지의 첫 절대 · 상대(`pick` 이 다시 읽지 않게).
    struct Drawn {
        var list: [Mention]
        var life: Life?
        var rest: S?
    }
    func draw(_ raw: String, now: Date, context: SpokenReading.Context) -> Drawn {
        var out: [Mention] = []
        var body = raw
        var hit: Life?, seen = false
        let take = { (x: Life, t: String, first: Bool) in
            let reach = self.lifeReach(x, raw: body, t: t)
            switch x {
            case .span(let s, let r): out.append(Mention(s: s, parts: [SpanReader.offsets(body, SpanReader.unstripped(body, r, in: t))], mask: [reach], life: true))
            case .ask: out.append(Mention(s: nil, parts: [reach], mask: [reach], life: true))
            }
            body = first ? SpanReader.blank(body, [reach]) : SpanReader.gapped(body, [reach])
        }
        let life = { (first: Bool) -> Bool in
            let t = Rx.strip(body)
            let found = self.lifeRead(t, raw: body, context)
            if !seen { seen = true; hit = found }
            guard let x = found else { return false }
            take(x, t, first)
            return true
        }
        _ = life(true)
        // 달이 붙은 학년이 이어 서면(「고3 때 5월이었나 고2 때 5월이었나」) 그 달을 먼저 묶는다
        while !out.isEmpty, out.count < SpanReader.most, case let t = Rx.strip(body), let x = lifeRead(t, raw: body, context), gradeMonthOf(x, in: t) { take(x, t, true) }
        var rest: S?
        for k in 0..<SpanReader.most {
            let found = absRel(body, now: now)
            if k == 0 { rest = found }
            guard let s = found, !s.parts.isEmpty else { break }
            out.append(Mention(s: s, parts: s.parts, mask: s.parts, life: false))
            body = SpanReader.gapped(body, s.parts)
        }
        for _ in 0..<SpanReader.most where out.contains(where: \.life) { if !life(false) { break } }
        return Drawn(list: out, life: hit, rest: rest)
    }
    /// 한 글에서 뽑는 때의 상한.
    static let most = 6

    /// 흩어진 토막 사이에 다른 때가 끼면(「작년 … 올해 3월」) 그 자리에서 갈라 따로 뽑는다.
    func separated(_ ms: [Mention], _ raw: String, now: Date, context: SpokenReading.Context, depth: Int = 0) -> [Mention] {
        let spread = ms.lazy.filter { !$0.life && $0.parts.count > 1 }
        let within = spread.compactMap { a in ms.first { b in b.lo >= a.parts[0].upperBound && b.hi <= a.parts.last!.lowerBound }?.lo }.first
        // 앞 때 뒤에 선 작은 단위를 더 뒤의 해가 끌어간 것(「올해 3월 … 작년에」)은 뒤의 해에서 가른다
        let stolen = spread.compactMap { a in
            ms.contains { $0.hi <= a.lo } && Rx.has(SpanReader.text(raw, [a.parts.last!]), "^(?:" + p.yearWords + "|" + p.anyYear + ")") ? a.parts.last!.lowerBound : nil
        }.first
        guard let cut = within ?? stolen, depth < 2 else { return ms.sorted { $0.lo < $1.lo } }
        return [SpanReader.gapped(raw, [cut..<raw.count]), SpanReader.gapped(raw, [0..<cut])].flatMap { half in
            separated(mentions(half, now: now, context: context).filter { $0.s != nil }, half, now: now, context: context, depth: depth + 1)
        }
    }

    // ── 때가 둘
    /// 때가 둘일 때의 답 — nil 이면 지금 손(`pick`)이 하나를 읽는다.
    func twoTimes(_ raw: String, _ drawn: Drawn, now: Date, context: SpokenReading.Context) -> SpokenReading? {
        let drawn = drawn.list.filter { $0.s != nil }
        guard let first = drawn.first(where: { !$0.life }) ?? drawn.first else { return nil }
        if drawn.count >= SpanReader.most { return nil }   // 때가 여섯 넘게 선 글은 가르지 않는다(길이에 비례하는 만큼만 일한다)
        // 흩어진 토막이 있거나 계절이 선 글만 고름 말에서 갈라 본다
        let pair = drawn.contains { $0.parts.count > 1 } || Rx.has(raw, p.seasonWord) ? chosen(raw, now: now, context: context) : nil
        if drawn.count == 1, pair == nil {
            if let x = ahead(first, raw, now: now) { return x.s.map { .span(finish($0)) } }
            return choiceApart(first, raw, now: now)
        }
        if let pair, pair.count > 2, !zip(pair, pair.dropFirst()).contains(where: { a, b in SpanReader.touch(a.s!, b.s!) }) { return conflict(pair, pair, raw, now: now) }
        let ms = merged(pair ?? separated(drawn, raw, now: now, context: context), raw, now: now, context: context)
        if let split = ms.split { return split }
        let all = ms.list
        let head = pair == nil ? first : all[0]
        let parts = sentences(raw)
        let section = { (m: Mention) -> Int in parts.firstIndex { $0.contains(m.lo) } ?? 0 }
        let apart = { (a: Mention, b: Mention) in a.s.map { x in b.s.map { !SpanReader.meet(x, $0) } ?? true } ?? true }
        let exact = { (m: Mention) in m.s.map { !m.life && $0.from == $0.to } ?? false }
        let beside = { (a: Mention, b: Mention) in section(a) == section(b) && self.level(a, b, raw) }
        // 옮긴 말(「-다고 · -대 · -다는」)이 든 문장은 어느 때가 누구의 것인지 꼴로 갈리지 않는다 — 읽는 차례 그대로
        let told = { (m: Mention) -> Bool in
            let own = parts.first { $0.contains(m.lo) } ?? 0..<raw.count
            return Rx.has(SpanReader.slice(raw, own), self.p.reported)
        }
        // 꾸미는 때 · 목적어 덩이의 때는 또렷한 사건의 때에 진다
        let weak = { (i: Int) -> Bool in
            let m = all[i]
            return all.indices.contains { j in
                let other = all[j]
                guard j != i, self.marked(m, raw), apart(m, other), other.s?.decade == false, self.solid(other, raw), beside(m, other), !told(m) else { return false }
                // 이기는 때 — 날 하나이거나 때 토씨(에 · 은 · 는 · 안에 · 쉼표 …)가 붙었거나 바로 뒤가 그 꾸미는 때 · 다른 이름씨를 꾸미거나 목적어 덩이거나 옮긴 끝이 아닌 것
                let clear = exact(other) || other.s?.bound == true || Rx.has(SpanReader.slice(raw, other.hi..<raw.count), self.p.plainTime)
                    || (other.mask.last!.upperBound <= m.lo && SpanReader.text(raw, [other.mask.last!.upperBound..<m.lo]).isEmpty)
                guard clear, !self.leads(other, among: all, raw), !self.inObject(other, among: all, raw) else { return false }
                if self.described(m, by: other, raw) { return true }
                // 「어제 책을」의 날은 사건의 때로도 흔하다 — 앞에 선 날 하나에만 진다
                //   쉼표 · 「그리고」로 이은 때에 때 표지가 선 것(「20대, 40대 때 온실을」)은 이름씨를 꾸미는 것이 아니다
                if self.sideBySide(m, other, raw), Rx.has(SpanReader.slice(raw, max(m.lo, m.hi - 2)..<raw.count), self.p.markedTime) { return false }
                return self.inObject(m, among: all, raw) && (!exact(m) || (exact(other) && other.lo < m.lo))
            }
        }
        let gone = all.indices.filter { weak($0) }
        if !gone.isEmpty, gone.count < all.count { return readOne(SpanReader.gapped(raw, gone.flatMap { all[$0].mask }), now: now, context: context) }
        // 한 마디에 겹치지 않는 둘 — 읽는 차례가 고를 때와 다투는 때가 있으면 묻는다
        guard let main = all.first(where: { $0.lo == head.lo }) ?? all.first(where: { $0.lo <= head.lo && head.lo < $0.hi }), let a = main.s,
              main.merged || solid(main, raw) else { return nil }
        let rivals = all.filter { m in
            guard let b = m.s, m.lo != main.lo, !told(m) else { return false }
            // 해 없는 달 · 계절은 해가 선 때와 · 연대와 상한(「N년 안에」)은 무엇과도 다투지 않는다
            if a.bare != b.bare || a.decade || b.decade || a.bound || b.bound { return false }
            return apart(main, m) && solid(m, raw) && sideBySide(main, m, raw)
        }
        if !rivals.isEmpty { return conflict([main] + rivals, all, raw, now: now) }
        return main.merged ? .span(finish(a)) : nil
    }

    /// 맞닿거나 겹치는가.
    static func touch(_ a: S, _ b: S) -> Bool {
        let (early, late) = a.from <= b.from ? (a, b) : (b, a)
        return late.from <= early.to.adding(.day, 1)
    }
    /// 겹치는가 — 「뒤 · 앞」은 말이 닿는 폭으로.
    static func meet(_ a: S, _ b: S) -> Bool {
        let x = a.reach ?? a.from...a.to, y = b.reach ?? b.from...b.to
        return x.overlaps(y)
    }

    /// 다툴 만한 때인가 — 낱말의 처음에서 시작해 토씨 · 낱말 끝에서 끝난 것만(빈칸을 뺀 글에서 이웃 낱말에 걸친 「월세 살았다」 · 「내 일」 · 「3년 후배」는 때가 아니다) ·
    /// 견주는 때(「작년보다」)도 아니다 · 나이 · 학년 · 나잇대는 때 표지와 함께일 때만(「두 살 어린 사촌」 · 「고3 사촌」은 사건의 때가 아니다).
    func solid(_ m: Mention, _ raw: String) -> Bool {
        let c = Array(raw)
        if m.lo > 0, c[m.lo - 1].isLetter { return false }
        let after = SpanReader.slice(raw, m.hi..<raw.count)
        guard Rx.has(after, p.timeEnd), !Rx.has(after, p.comparing) else { return false }
        if m.life, let s = m.s, ["age", "grade"].contains(s.rule), !Rx.has(after, p.ageTime) { return false }
        if !marked(m, raw) { return false }
        return !m.parts.contains { r in
            let said = SpanReader.text(raw, [r])
            return !said.contains(where: \.isNumber) && words.dayOffset.contains { r.count > $0.word.count && said.first == $0.word.first && said.last == $0.word.last }
        }
    }
    /// 때 표지가 선 때인가 — 나잇대는 표지가 없으면(「20대는 힘들었다」) 읽는 차례의 것이고 다른 때와 겨루지 않는다.
    func marked(_ m: Mention, _ raw: String) -> Bool {
        guard let s = m.s, s.rule == "ageBand", !m.merged else { return true }
        return Rx.has(s.phrase, p.bandPart) || Rx.has(SpanReader.slice(raw, m.hi..<raw.count), p.bandTime)
    }
    /// 나란한 사건의 때 둘인가 — 사이가 「그리고 · 쉼표 · 고름 말」뿐이거나 앞 때 뒤에 쉼표가 서고 뒤 때에 「에」가 붙고 사이에 풀이말이 없다(「30년 전, 내가 30대에」).
    ///   「고등학교 때 친구가 작년에」 · 「내년 달력이 오늘」 · 「작년엔 … 올해는」은 꾸밈인지 견줌인지 두 사건인지 모른다 — 읽는 차례 그대로.
    func sideBySide(_ a: Mention, _ b: Mention, _ raw: String) -> Bool {
        let (x, y) = a.lo < b.lo ? (a, b) : (b, a)
        guard x.hi <= y.lo else { return false }
        let between = SpanReader.slice(raw, x.hi..<y.lo)
        if Rx.has(between, p.joinedOnly), Rx.has(between, p.joinMark) { return true }
        if let g = Rx.groups(between, p.choiceBetween), g.contains(where: { !$0.isEmpty }) { return true }   // 떨어진 고름
        return Rx.has(between, p.commaTime) && Rx.has(SpanReader.slice(raw, y.hi..<raw.count), p.eventTime) && level(x, y, raw)
    }
    /// 두 때 사이에 풀이말이 없는가 — 토씨 붙은 낱말 · 풀이말이 아닌 꼴 · 「그리고」뿐(「비가 와 어제 쉬었다」 · 「본 뒤 어제」 · 「부산, 올해에」는 두 사건이다).
    func level(_ a: Mention, _ b: Mention, _ raw: String) -> Bool {
        let (x, y) = a.lo < b.lo ? (a, b) : (b, a)
        guard x.hi <= y.lo else { return false }
        return SpanReader.afterParticle(SpanReader.slice(raw, x.hi..<y.lo)).allSatisfy { w in
            let s = String(w)
            return Rx.has(s, p.joinsTimes) || (!Rx.has(s, p.afterEvent) && !Rx.has(s, p.openEnd) && (Rx.has(s, p.withParticle) || plain(w)))
        }
    }
    /// 풀이말이 아닌 꼴의 낱말(토씨 없는 이름씨 · 꾸밈말).
    func plain(_ w: Substring) -> Bool { Rx.has(" " + String(w), "^" + p.nounLink + "$") }
    /// 묻기 — 후보는 문장에 나온 차례 · 저마다 다른 때를 가리고 다시 읽은 것.
    func conflict(_ ms: [Mention], _ all: [Mention], _ raw: String, now: Date) -> SpokenReading {
        let spans = ms.sorted { $0.lo < $1.lo }.compactMap { m -> SpokenReading.Span? in
            if m.merged || m.life { return m.s.map(finish) }
            let others = all.filter { $0.lo != m.lo }.flatMap(\.mask)
            return (absRel(SpanReader.gapped(raw, others), now: now) ?? m.s).map(finish)
        }
        let once = spans.enumerated().filter { i, s in !spans[..<i].contains { $0.from == s.from && $0.to == s.to } }.map(\.element)
        return .ask(SpokenReading.Ask(reason: .conflict, anchorKey: nil, rule: "conflict", candidates: once))
    }

    /// 고름 · 사이 — 이어진 둘 사이가 고름 말뿐이면 합친다(맞닿지 않으면 묻기) · 나잇대의 「A에서 B 사이 · A~B」면 A 의 처음 … B 의 끝.
    func merged(_ ms: [Mention], _ raw: String, now: Date, context: SpokenReading.Context) -> (list: [Mention], split: SpokenReading?) {
        var out: [Mention] = []
        for (i, m) in ms.enumerated() {
            guard let last = out.last, let a = last.s, var b = m.s, last.hi <= m.lo else { out.append(m); continue }
            let between = SpanReader.slice(raw, last.hi..<m.lo), after = SpanReader.slice(raw, m.hi..<raw.count)
            if m.life, !solid(m, raw) { out.append(m); continue }   // 「두 살이나 다섯 살 어린 …」은 때가 아니다
            if let g = Rx.groups(between, p.choiceBetween), g.contains(where: { !$0.isEmpty }) {
                if b.bare, !a.bare, let whole = inherited(last, at: m.lo, raw), let x = reread(whole, like: last, now: now, context: context) { b = S(from: x.from, to: x.to, rule: x.rule, soft: x.soft, phrase: b.phrase) }
                if a.bare != b.bare { out.append(m); continue }   // 해를 채운 달은 해가 선 때와 고르는 것이 아니다
                let lo = min(a.from, b.from), hi = max(a.to, b.to)
                let (early, late) = a.from <= b.from ? (a, b) : (b, a)
                var c = last
                c.parts = last.parts + m.parts
                c.mask = last.mask + m.mask
                c.s = S(from: lo, to: hi, rule: SpanReader.named(a.rule, b.rule), soft: true, phrase: a.phrase + b.phrase, parts: c.parts)
                c.merged = true
                guard late.from <= early.to.adding(.day, 1) else {
                    // 고름뿐이면 그 둘을 묻는다 · 다른 때가 더 있으면 아래에서 함께 가른다
                    if out.count == 1, i == ms.count - 1 {
                        var late = m
                        late.s = b
                        late.merged = m.s != nil && m.s!.bare && !a.bare   // 앞의 해를 이은 것은 다시 읽지 않는다
                        return (ms, conflict([last, late], ms, raw, now: now))
                    }
                    var late = m
                    if m.s?.bare == true, !a.bare { late.s = b; late.merged = true }
                    out.append(late)
                    continue
                }
                out[out.count - 1] = c
            } else if last.life, m.life, Rx.has(between, p.rangeTilde) || (Rx.has(between, p.rangeBetween) && Rx.has(after, p.rangeAfter)) {
                guard a.from <= b.to else { out.append(m); continue }
                var c = last
                c.parts = last.parts + m.parts
                c.mask = last.mask + m.mask
                c.s = S(from: a.from, to: b.to, rule: a.rule, soft: a.soft || b.soft, phrase: a.phrase + b.phrase, parts: c.parts)
                c.merged = true
                out[out.count - 1] = c
            } else { out.append(m) }
        }
        return (out.map { ahead($0, raw, now: now) ?? $0 }, nil)
    }
    /// 고름 말 뒤가 작은 단위만이라 때로 서지 않는 것(「작년 여름이나 가을에」 · 「3월 2일이나 3일에」) — 앞 때의 큰 단위를 이어 합친다.
    func ahead(_ m: Mention, _ raw: String, now: Date) -> Mention? {
        guard let (a, b, at, end) = choiceAfter(m, raw, now: now) else { return nil }
        let (early, late) = a.from <= b.from ? (a, b) : (b, a)
        guard SpanReader.touch(early, late) else { return nil }
        var c = m
        c.parts = m.parts + [at..<end]
        c.mask = c.parts
        c.s = S(from: early.from, to: max(a.to, b.to), rule: SpanReader.named(a.rule, b.rule), soft: true, phrase: SpanReader.text(raw, c.parts), parts: c.parts)
        c.merged = true
        return c
    }
    /// 고름 말 뒤의 작은 단위 — 앞 때 · 앞 때의 큰 단위를 이은 뒤 때 · 뒤 때의 자리.
    func choiceAfter(_ m: Mention, _ raw: String, now: Date) -> (S, S, Int, Int)? {
        guard !m.life, let a = m.s, let x = Rx.first(SpanReader.slice(raw, m.hi..<raw.count), p.choiceAhead) else { return nil }
        let at = m.hi + SpanReader.offsets(SpanReader.slice(raw, m.hi..<raw.count), x.range).upperBound
        guard let whole = inherited(m, at: at, raw), let b = absRel(whole, now: now), let end = b.parts.last?.upperBound, end > at else { return nil }
        return (a, b, at, end)
    }
    /// 떨어진 고름(「3월 2일이나 9일에」) — 문장의 때가 그 둘뿐이면 고르지 않고 묻는다. 뒤가 수를 세는 말(「5일 동안 · 5일 걸렸다」)이면 고름이 아니다.
    func choiceApart(_ m: Mention, _ raw: String, now: Date) -> SpokenReading? {
        guard !m.merged, let (_, b, at, end) = choiceAfter(m, raw, now: now),
              !Rx.has(SpanReader.slice(raw, end..<raw.count), "^\\s*" + p.choiceCount) else { return nil }
        var late = m
        late.parts = [at..<end]
        late.mask = late.parts
        late.s = S(from: b.from, to: b.to, rule: b.rule, soft: b.soft, phrase: SpanReader.text(raw, late.parts), parts: late.parts)
        late.merged = true
        return conflict([m, late], [m, late], raw, now: now)
    }
    /// 저마다 제 해를 말한 고름(「작년 봄이었나 재작년 봄이었나」)의 때들 — 고름 말에서 가른 토막마다 하나씩(말한 차례 · 방향과 상관없이) · 다른 때가 더 있거나 꼴이 아니면 nil.
    func chosen(_ raw: String, now: Date, context: SpokenReading.Context) -> [Mention]? {
        let cuts = Rx.all(raw, p.choiceYear).map { SpanReader.offsets(raw, $0) }
        guard (1..<SpanReader.most).contains(cuts.count) else { return nil }
        var out: [Mention] = []
        for i in 0...cuts.count {
            let own = (i == 0 ? 0 : cuts[i - 1].upperBound)..<(i == cuts.count ? raw.count : cuts[i].lowerBound)
            let said = mentions(SpanReader.slice(raw, own), now: now, context: context)
            guard said.count == 1, var m = said.first, var s = m.s, !m.life, !s.bare, !s.decade, !s.bound else { return nil }
            m.parts = m.parts.map { ($0.lowerBound + own.lowerBound)..<($0.upperBound + own.lowerBound) }
            m.mask = m.parts
            s.parts = m.parts
            m.s = s
            // 해에 붙지 않은 계절(「3년 전 봄이었나」)은 그 때의 자리다
            if let w = Rx.first(SpanReader.slice(raw, m.hi..<own.upperBound), "^\\s*" + p.seasonWord) {
                m.parts.append(m.hi..<(m.hi + SpanReader.offsets(SpanReader.slice(raw, m.hi..<own.upperBound), w.range).upperBound))
                m.mask = m.parts
            }
            if let last = out.last {
                guard let g = Rx.groups(SpanReader.slice(raw, last.hi..<m.lo), p.choiceBetween), g.contains(where: { !$0.isEmpty }) else { return nil }
            }
            out.append(m)
        }
        return out
    }
    /// 이은 글의 다시 읽음 — 앞 때가 생년으로 읽은 것이면 그 손으로.
    func reread(_ whole: String, like m: Mention, now: Date, context: SpokenReading.Context) -> S? {
        guard m.life else { return absRel(whole, now: now) }
        if case .span(let s, _)? = lifeRead(Rx.strip(whole), raw: whole, context) { return s }
        return nil
    }
    /// 합친 구간의 규칙 이름 — 같으면 그 이름 · 다르면 절대 > 상대 > 생년.
    static func named(_ a: String, _ b: String) -> String {
        if a == b { return a }
        for head in ["absolute", "relative"] { if let x = [a, b].first(where: { $0.hasPrefix(head) }) { return x.hasPrefix(head + "+") ? head : x } }
        return a
    }
    /// 뒤 때가 앞 때의 해(달)를 잇는 글 — 「작년 3월이나 4월」 = 「작년 4월」 · 잇는 자리가 없으면 nil(자리 수는 그대로).
    func inherited(_ a: Mention, at lo: Int, _ raw: String) -> String? {
        let tail = SpanReader.slice(raw, lo..<raw.count)
        for unit in [p.inheritMonth, p.inheritDay, p.seasonWord] where Rx.has(tail, "^(?:" + unit + ")") {
            guard let at = Rx.all(SpanReader.slice(raw, a.lo..<a.hi), unit).last else { return nil }
            let start = a.lo + SpanReader.offsets(SpanReader.slice(raw, a.lo..<a.hi), at).lowerBound
            return start > a.lo ? SpanReader.blank(raw, [start..<lo]) : nil
        }
        return nil
    }

    // ── 꾸미는 때
    /// 때 뒤의 글 — 다음 때 앞까지.
    func room(_ m: Mention, among all: [Mention], _ raw: String) -> String {
        SpanReader.slice(raw, m.hi..<(all.map(\.lo).filter { $0 >= m.hi }.min() ?? raw.count))
    }
    /// 목적어 덩이 안의 때인가 — 「때(의) + 이름씨 + 을/를」.
    func inObject(_ m: Mention, among all: [Mention], _ raw: String) -> Bool { Rx.has(room(m, among: all, raw), p.modifiesObject) }
    /// 낱말 끝 글자의 받침 자리(ㄴ = 4 · ㄹ = 8 · 없음 = 0) — 한글 음절이 아니면 nil.
    static func coda(_ w: Substring) -> Int? {
        guard let last = w.unicodeScalars.last, (0xAC00..<0xD7A4).contains(Int(last.value)) else { return nil }
        return (Int(last.value) - 0xAC00) % 28
    }
    /// 때 `m` 이 관형 풀이말로 이름씨를 꾸미고 그 이름씨 덩이 바로 뒤에 `other` 가 서는가 — 「그저께 (임자말) 산 (이름씨) 책을 어제 …」.
    ///   관형 풀이말은 꼴이 또렷한 것만(`adnominal` — 「-은 · -는」은 토씨와 · 「-한 · -운」과 그 밖의 받침 ㄴ 은 그림씨 · 이름씨와 겹쳐 보지 않는다) ·
    ///   이름씨 덩이 = 낱말 둘까지 · 끝에 토씨가 붙은 것 · 첫 낱말이 매인 이름씨 · 「뒤 · 다음」 · 하루 중 낱말이면 아니다.
    func described(_ m: Mention, by other: Mention, _ raw: String) -> Bool {
        guard m.hi <= other.lo else { return false }
        let between = SpanReader.slice(raw, m.hi..<other.lo)
        guard Rx.has(between, p.bareTime) else { return false }
        let said = SpanReader.afterParticle(between)
        return said.indices.prefix(2).contains { k in
            let chunk = said[(k + 1)...]
            guard Rx.has(String(said[k]), p.adnominal), said[..<k].allSatisfy({ Rx.has(String($0), p.doer) }), (1...2).contains(chunk.count), let last = chunk.last,
                  !Rx.has(String(chunk.first!), p.notDescribed) else { return false }
            return Rx.has(String(last), p.withParticle)   // 덩이 안의 풀이말은 `level` 이 거른다
        }
    }
    /// 낱말들 — 앞의 때에 붙은 토씨는 낱말이 아니다.
    static func afterParticle(_ s: String) -> [Substring] { Array(s.split(separator: " ").dropFirst(s.hasPrefix(" ") || s.isEmpty ? 0 : 1)) }
    /// 사건의 때로 또렷하지 않은 쪽 — 뒤가 「로 · 까지 · 부터」(옮긴 끝)이거나 받침 ㄴ · ㄹ 관형으로 다른 이름씨를 꾸민다(「모레 볼 영화가 …」).
    func leads(_ m: Mention, among all: [Mention], _ raw: String) -> Bool {
        let tail = room(m, among: all, raw)
        if Rx.has(tail, p.toward) { return true }
        let said = SpanReader.afterParticle(tail)
        return said.indices.dropLast().prefix(3).contains { k in
            [4, 8].contains(SpanReader.coda(said[k]) ?? 0) && !Rx.has(String(said[k]), p.notModifying) && !Rx.has(String(said[k]), p.plainAdverb)
                && !Rx.has(String(said[k + 1]), "^" + p.dependentNoun)
        }
    }
    // ── 말 고침
    /// 말 고침을 걷은 글(앞에서부터 · 한 글에 여섯 번까지 — 구간 읽기와 끝 날 읽기가 같은 글을 읽는다).
    func settled(_ text: String, now: Date, context: SpokenReading.Context = .empty) -> String {
        guard words.may("correction", text), Rx.all(text, p.correction).count <= SpanReader.most else { return text }   // 표지가 여섯 넘으면 고치지 않는다
        var s = endCorrected(text)
        for _ in 0..<SpanReader.most { guard let x = corrected(s, now: now, context: context) else { break }; s = x }
        return s
    }
    /// 「A부터 B까지」의 끝만 고친 말(「3월 2일부터 5일 아니 7일까지」) — 시작은 그대로 · 나중 것이 날만이면 앞의 달을 잇는다(「4월 5일 아니 7일까지」 = 4월 7일).
    func endCorrected(_ raw: String) -> String {
        guard let m = Rx.first(raw, p.rangeEndCorrected), m.g.count == 2, let former = raw.range(of: m.g[0], range: m.range),
              let later = raw.range(of: m.g[1], options: .backwards, range: m.range), former.upperBound <= later.lowerBound else { return raw }
        var lo = former.lowerBound
        if !m.g[1].contains(words.monthUnit), let month = raw.range(of: words.monthUnit, range: former) { lo = month.upperBound }
        return SpanReader.gapped(raw, [SpanReader.offsets(raw, lo..<later.lowerBound)])
    }
    // ── 견줌
    /// 견주는 때(「작년보다 · 어릴 때보다는」)를 가린 글 — 때에 붙은 「보다 · 보다는 · 보다도 · 보단」만 · 때 · 최근 · 끝 없는 낱말 다.
    func compared(_ raw: String, now: Date, context: SpokenReading.Context = .empty) -> String {
        let marks = words.may("comparedWith", raw) ? Rx.all(raw, p.comparedWith) : []
        guard (1...SpanReader.most).contains(marks.count) else { return raw }   // 여섯 넘으면 가리지 않는다
        var body = Array(raw)
        var last = 0
        for at in marks.map({ SpanReader.offsets(raw, $0) }) {
            // 표지 바로 앞의 짧은 토막만 읽는다(낱말 처음에서)
            var lo = max(last, at.lowerBound - SpanReader.near)
            if lo > last, body[lo - 1] != " " { lo = body[lo..<at.lowerBound].firstIndex(of: " ") ?? lo }
            last = at.upperBound
            let before = String(body[lo..<at.lowerBound])
            guard let cut = Rx.first(before, p.comparedVague).map({ SpanReader.offsets(before, $0.range).lowerBound }) ?? touching(before, now: now, context: context) else { continue }
            let own = Mention(s: nil, parts: [(lo + cut)..<at.lowerBound], mask: [], life: false)
            // 바로 뒤가 작은 단위만이면 큰 단위를 잇는다(「2068년 3월보다 4월이」 = 2068년 4월 · 「3월 2일보다 3일 더」의 3일은 날수다)
            if let next = body[at.upperBound...].firstIndex(where: { $0 != " " }), !Rx.has(String(body[next...].prefix(16)), p.dayCount), let whole = inherited(own, at: next, String(body)) { body = Array(whole); continue }
            for i in (lo + cut)..<at.lowerBound { body[i] = " " }
            body[lo + cut] = Character(SpanReader.gap)
        }
        return String(body)
    }
    /// 글 끝에 닿은 때의 첫 자리 — 흩어진 토막이면 끝에 닿은 쪽만 · 없으면 nil.
    func touching(_ s: String, now: Date, context: SpokenReading.Context) -> Int? {
        let ends = { (hi: Int) in Rx.has(SpanReader.slice(s, hi..<s.count), self.p.comparedTail) }
        let t = Rx.strip(s)
        var body = s
        if let x = lifeRead(t, raw: s, context) {
            let reach = lifeReach(x, raw: s, t: t)
            if ends(reach.upperBound) { return reach.lowerBound }
            body = SpanReader.blank(body, [reach])
        }
        for _ in 0..<SpanReader.most {
            guard let x = absRel(body, now: now), let tail = x.parts.last else { return nil }
            if ends(tail.upperBound) {
                var head = tail.lowerBound
                for r in x.parts.dropLast().reversed() where SpanReader.text(s, [r.upperBound..<max(r.upperBound, head)]).isEmpty { head = r.lowerBound }
                return head
            }
            body = SpanReader.gapped(body, x.parts)
        }
        return nil
    }
    /// 견줌 표지 앞에서 읽는 글자 수.
    static let near = 24
    // ── 달력 물결
    /// 「3월 2일~9일 · 3월~5월 · 2081~2084년」 = 「A부터 B까지」 — 양쪽이 달력 꼴(년 · 월 · 일)이고 뒤가 「전 · 후 · 뒤 · 동안 · 걸리-」가 아닐 때 ·
    ///   문장의 때가 바로 그 시작일 때만(다른 때가 이기면 그 읽음 그대로). `until` = 끝의 글.
    func tilde(_ raw: String, now: Date, context: SpokenReading.Context = .empty) -> (from: SpokenReading.Span, to: SpokenReading.Span, until: String)? {
        guard Rx.has(raw, p.tilde), (1...SpanReader.most).contains(Rx.all(raw, p.calendarTilde).count), let m = Rx.first(raw, p.calendarTilde), m.g.count == 9 else { return nil }
        let bare = m.g[0].isEmpty && m.g[2].isEmpty   // 단위를 끝과 함께 쓴 시작(「2081~2084년 · 3월 2~9일」)
        let (number, unit) = !m.g[0].isEmpty ? (m.g[0], m.g[1]) : !m.g[2].isEmpty ? (m.g[2], m.g[3])
            : !m.g[4].isEmpty ? (m.g[4], words.yearSuffix) : !m.g[5].isEmpty ? (m.g[5], words.dayUnit) : (m.g[6], words.monthUnit)
        guard let n = Int(number) else { return nil }
        // 시작 — 물결부터 끝까지를 가른 글의 읽음이 그 시작 그대로일 때
        let whole = String(raw[..<m.range.lowerBound]) + (bare ? " " : "") + number + unit + " " + SpanReader.gap + " " + String(raw[m.range.upperBound...])
        guard case .span(let a) = readOne(whole, now: now, context: context) else { return nil }
        let f = d(a.from), e = d(a.to), end = m.g[7]
        switch unit {
        case words.dayUnit: guard f == e, f.d == n else { return nil }
        case words.monthUnit: guard f.m == n, (f, e) == SpanReader.month(f.y, f.m), !Rx.has(end, p.endDay) else { return nil }
        default: guard (f, e) == SpanReader.year(n), Rx.has(Rx.strip(end), "^" + p.anyYear) else { return nil }
        }
        guard case .span(let b) = inheritEnd(end, from: f).map({ SpokenReading.span(finish($0)) }) ?? readOne(end, now: now, context: context), a.from <= b.to else { return nil }
        let from = finish(S(from: f, to: e, rule: a.rule, soft: a.soft || !m.g[8].isEmpty, phrase: bare && a.phrase.hasSuffix(unit) ? String(a.phrase.dropLast(unit.count)) : a.phrase))
        return (from, b, Rx.strip(end))
    }
    // ── 학년에 붙은 달 · 연대
    /// 학년에 붙은 달이 다른 이름씨를 꾸미거나 목적어 덩이 안에 있는가(「고3 때 5월 사진을 6월에」).
    func describes(_ r: Range<Int>, _ a: S, _ raw: String) -> Bool {
        let x = Mention(s: nil, parts: [r], mask: [r], life: true), y = Mention(s: a, parts: a.parts, mask: a.parts, life: false)
        return described(x, by: y, raw) || (x.hi <= y.lo && inObject(x, among: [x, y], raw))
    }
    /// 연대가 토씨 없이 이름씨를 꾸미고 · 학년에 때 표지가 서고 · 둘 사이에 풀이말이 없는가(「80년대 노래를 고3 때 들었다」).
    func decadeYields(_ a: S, to r: Range<Int>, _ raw: String) -> Bool {
        guard let own = a.parts.last else { return false }
        let after = SpanReader.slice(raw, own.upperBound..<(r.lowerBound >= own.upperBound ? r.lowerBound : raw.count))
        let x = Mention(s: nil, parts: [own], mask: [own], life: false), y = Mention(s: nil, parts: [r], mask: [r], life: true)
        let said = SpanReader.slice(raw, r).hasSuffix(words.when) || SpanReader.slice(raw, r).contains(words.monthUnit) || Rx.has(SpanReader.slice(raw, r.upperBound..<raw.count), p.ageTime)
        return said && Rx.has(after, p.decadeNoun) && level(x, y, raw)
    }

    /// 정정 표지 앞의 때를 가린 글 — 표지 앞뒤에 다 때가 있을 때만(표지 뒤에 때가 없으면 정정이 아니다 · 뒤가 끝 없는 때여도 때다). 고칠 것이 없으면 nil.
    ///   「아니고 · 아니라」와 앞이 토씨 「이 · 가 · 은 · 는」인 표지는 때에 붙은 것만(「서울이 아니라 부산」은 때의 정정이 아니다) ·
    ///   뒤가 작은 단위만이면 앞의 큰 단위를 잇는다(「작년 3월 아니 4월」 = 작년 4월).
    func corrected(_ raw: String, now: Date, context: SpokenReading.Context) -> String? {
        let all = sentences(raw)
        for mark in Rx.all(raw, p.correction) {
            let at = SpanReader.offsets(raw, mark)
            guard let i = all.firstIndex(where: { $0.contains(at.lowerBound) }) else { continue }
            let own = all[i], silent = { (r: Range<Int>) in SpanReader.text(raw, [r]).allSatisfy { !$0.isLetter && !$0.isNumber } }
            let open = silent(own.lowerBound..<at.lowerBound), shut = silent(at.upperBound..<own.upperBound)
            let from = open && i > 0 ? all[i - 1].lowerBound : own.lowerBound
            let to = shut && open && i + 1 < all.count ? all[i + 1].upperBound : own.upperBound
            let left = SpanReader.gapped(raw, [0..<from, at.lowerBound..<raw.count]), right = SpanReader.gapped(raw, [0..<at.upperBound, to..<raw.count])
            guard let former = mentions(left, now: now, context: context).max(by: { $0.hi < $1.hi }) else { continue }
            // 앞 때는 표지에 붙었거나(「4년 전은 아니고」) 풀이말로 맺은 말(「4년 전에 팠어, 아니 …」)의 때다 — 「어제 밥 아니 빵을」의 어제는 아니다
            let between = SpanReader.slice(raw, former.hi..<at.lowerBound), word = SpanReader.text(raw, [at])
            let bound = Rx.has(between, p.correctionNoun) || Rx.has(word, p.correctionBound)
            guard Rx.has(between, p.correctionAfter) || (!bound && Rx.has(between, p.correctionClause)) else { continue }
            // 나중 때는 표지 바로 뒤에 선다
            let body = Array(raw)
            guard let head = (at.upperBound..<max(at.upperBound, to)).first(where: { body[$0].isLetter || body[$0].isNumber }) else { continue }
            let later = mentions(right, now: now, context: context).min { $0.lo < $1.lo }
            // 뒤가 작은 단위만이면 앞의 큰 단위를 잇는다
            if later == nil || later?.s?.bare == true, let joined = inherited(former, at: head, raw) { return joined }
            if later?.s?.bare == true, former.s?.bare != true { continue }   // 「작년, 아니 4월에」 — 어느 해의 4월인지 지어내지 않는다
            let words = SpanReader.slice(raw, head..<to).split(separator: " ").prefix(2).map(String.init)
            let heads = words.count == 2 && Rx.has(words[0], p.vagueHead) ? words.joined(separator: " ") : words.first ?? ""
            guard later?.lo == head || (later == nil && (vague(heads) != nil || recent(Rx.strip(heads), now: now) != nil)) else { continue }
            return SpanReader.gapped(raw, [former.lo..<at.upperBound])
        }
        return nil
    }
}
