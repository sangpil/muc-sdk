import Foundation
import Testing
@testable import SpokenTime

// 말한 때 읽기 — 규칙마다 맞는 쪽 · 거르는 쪽 문장. 날은 합성 값이다: 기준 날 2040-10-10(수) · 겨울 규칙은 2040-01-15 · 시간대는 UTC+9 고정 오프셋.
// 맥락(생년 · 기준 사건으로 읽는 시험은 기준 날 2090-10-10): none = 없음 · born = 생년 2050-05-10 · early = 생년 1950-01-10(1~2월생 — 한 해 일찍 입학한 무리) ·
//       full = born + 기준 사건 다섯(wedding 2081-10-10 · military-enlist 2070-03-10 · military-discharge 2071-09-10 · first-job 2075-01-10 · university 2069-03-02) ·
//       enlisted = born + military-enlist 만.
// 기대 글 — 구간 「첫 날..끝 날 정밀도 규칙 soft|none」 · 묻기 「ask:까닭[:키]」 · 「recurring」.

let zone = TimeZone(secondsFromGMT: 9 * 3600)!
func calendar(_ z: TimeZone = zone) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = z; return c }
func day(_ s: String, hour: Int = 12, in z: TimeZone = zone) -> Date {
    let p = s.split(separator: "-").map { Int($0)! }
    return calendar(z).date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
}
func text(_ d: Date, in z: TimeZone = zone) -> String {
    let c = calendar(z).dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
let contexts: [String: SpokenReading.Context] = [
    "none": .empty,
    "born": .init(birth: day("2050-05-10")),
    "early": .init(birth: day("1950-01-10")),
    "full": .init(birth: day("2050-05-10"), anchors: [
        .init(key: "wedding", start: day("2081-10-10")), .init(key: "military-enlist", start: day("2070-03-10")),
        .init(key: "military-discharge", start: day("2071-09-10")), .init(key: "first-job", start: day("2075-01-10")),
        .init(key: "university", start: day("2069-03-02")),
    ]),
    "enlisted": .init(birth: day("2050-05-10"), anchors: [.init(key: "military-enlist", start: day("2070-03-10"))]),
]
let later = "2090-10-10"
func said(_ sentence: String, _ context: String = "none", now: String = "2040-10-10", direction: SpokenReading.Direction = .past) -> String {
    switch SpokenReading.read(sentence, now: day(now), zone: zone, context: contexts[context]!, direction: direction) {
    case .span(let s):
        #expect(s.anchor == s.from, "앵커는 늘 구간 첫 날 — \(sentence)")
        return "\(text(s.from))..\(text(s.to)) \(s.precision.rawValue) \(s.rule) \(s.soft ? "soft" : "none")"
    case .ask(let a): return "ask:\(a.reason.rawValue)" + (a.anchorKey.map { ":" + $0 } ?? "")
    case .recurring: return "recurring"
    }
}

@Suite struct SpokenReadingTests {
    /// 날 단위 상대 표현이 먼저 — 같은 문장의 다른 달 표현은 대상이다 · 「그제야 · 오늘날」은 날이 아니다.
    @Test(arguments: [
        ("어제 3월 일정을 정했다", "2040-10-09..2040-10-09 exact relative none"),
        ("3일 전에 12월 표를 샀다", "2040-10-07..2040-10-07 exact relative none"),
        ("내일 5월 계획을 짠다", "2040-10-11..2040-10-11 exact relative none"),
        ("지난주 금요일에 2월 일을 정리했다", "2040-10-05..2040-10-05 exact relative none"),
        ("5월 계획을 짰다", "2040-05-01..2040-05-31 month absolute none"),
        ("4월에 그제야 문을 열었다", "2040-04-01..2040-04-30 month absolute none"),
        ("12월 25일 전에 끝낸다", "2040-12-25..2040-12-25 exact absolute none"),
        ("오늘날 사람들은 바쁘다", "ask:noExpression"),
    ])
    func dayFirst(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 해 없는 달 — 달 바로 앞 수식이 해를 정한다(지난 · 저번 = 앞 · 다음 · 오는 = 뒤 · 이번 · 수식 없음 = 올해) · 날까지 말하면 exact.
    @Test(arguments: [
        ("지난 12월에 벽난로를 고쳤다", "2039-12-01..2039-12-31 month absolute none"),
        ("오는 3월에 시작한다", "2041-03-01..2041-03-31 month absolute none"),
        ("이번 12월에 쉰다", "2040-12-01..2040-12-31 month absolute none"),
        ("3월에 시작했다", "2040-03-01..2040-03-31 month absolute none"),
        ("지난 8월에 쉬었다", "2040-08-01..2040-08-31 month absolute none"),
        ("지난 10월에 쉬었다", "2039-10-01..2039-10-31 month absolute none"),
        ("지지난 11월에 모였다", "2038-11-01..2038-11-30 month absolute none"),
        ("지난 12월 25일에 모였다", "2039-12-25..2039-12-25 exact absolute none"),
        ("오는 2월 14일에 모인다", "2041-02-14..2041-02-14 exact absolute none"),
        ("6개월 동안 배웠다", "ask:noExpression"),
        ("3번 넘게 봤다", "ask:noExpression"),
        ("13월에 보자", "ask:noExpression"),
    ])
    func monthWithoutYear(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 해 말 = 10월 1일부터 · 「말」 뒤가 낱말 경계일 때만(「말했어」는 동사) · 달의 「말했어」도 흐림이 아니다.
    @Test(arguments: [
        ("올해 말했던 계획을 지켰다", "2040-01-01..2040-12-31 year relative none"),
        ("작년 말하던 버릇을 고쳤다", "2039-01-01..2039-12-31 year relative none"),
        ("8월 말했잖아", "2040-08-01..2040-08-31 month absolute none"),
        ("올해 말에 옮긴다", "2040-10-01..2040-12-31 circa relative soft"),
        ("작년 말쯤 옮겼다", "2039-10-01..2039-12-31 circa relative soft"),
        ("2030년 말에 옮겼다", "2030-10-01..2030-12-31 circa absolute soft"),
    ])
    func yearEnd(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 계절 = 그 계절 첫 달부터(봄 3 · 여름 6 · 가을 9 · 겨울 12~이듬해 2 · 여름방학 7~8) · 따로 선 낱말만(뒤가 「에게 · 에겐」이면 이름이다).
    @Test(arguments: [
        ("2030년 봄에 시작했다", "2030-03-01..2030-05-31 circa absolute+season soft"),
        ("작년 겨울엔 눈을 치웠다", "2039-12-01..2040-02-29 circa relative+season soft"),
        ("작년 가을에 산에 갔다", "2039-09-01..2039-11-30 circa relative+season soft"),
        ("2030년 겨울에 눈을 봤다", "2030-12-01..2031-02-28 circa absolute+season soft"),
        ("2030년 여름방학에 여행했다", "2030-07-01..2030-08-31 circa absolute+season soft"),
        ("올봄에 꽃을 심었다", "2040-03-01..2040-05-31 circa relative+season soft"),
        ("지난 가을에 산에 갔다", "2039-09-01..2039-11-30 circa relative+season soft"),
        ("다음 여름에 바다에 간다", "2041-06-01..2041-08-31 circa relative+season soft"),
        ("작년 이맘때 시작했다", "2039-10-01..2039-10-31 circa relative soft"),
        ("2030년에 봄에게 편지를 썼다", "2030-01-01..2030-12-31 year absolute none"),
        ("작년에 가을에게 책을 건넸다", "2039-01-01..2039-12-31 year relative none"),
    ])
    func seasons(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 1~2월의 「이번 겨울」 = 오늘이 든 겨울 · 「지난 겨울」 = 오늘 앞에 끝난 겨울.
    @Test(arguments: [
        ("이번 겨울에 눈을 봤다", "2039-12-01..2040-02-29 circa relative+season soft"),
        ("지난 겨울에 눈을 봤다", "2038-12-01..2039-02-28 circa relative+season soft"),
    ])
    func winterInJanuary(_ s: String, _ expect: String) { #expect(said(s, now: "2040-01-15") == expect, "\(s)") }

    /// 달 초 · 중순 · 말 = 1 · 11 · 21일부터 · 흐림 표지는 때 표현에 붙은 것만(「초록」은 아니다).
    @Test(arguments: [
        ("2030년 3월 초에 옮겼다", "2030-03-01..2030-03-10 circa absolute soft"),
        ("2030년 3월 중순에 옮겼다", "2030-03-11..2030-03-20 circa absolute soft"),
        ("2030년 3월 말에 옮겼다", "2030-03-21..2030-03-31 circa absolute soft"),
        ("이번 달 말까지 끝낸다", "2040-10-21..2040-10-31 circa relative soft"),
        ("지난달 중순에 옮겼다", "2040-09-11..2040-09-20 circa relative soft"),
        ("2030년 8월에 초록 우산을 샀다", "2030-08-01..2030-08-31 month absolute none"),
        ("2030년쯤 처음 나갔다", "2030-01-01..2030-12-31 circa absolute soft"),
    ])
    func monthParts(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 절대 날짜 · 상대 날 · 주 · 달 · 해.
    @Test(arguments: [
        ("2030년 3월 3일에 시작했다", "2030-03-03..2030-03-03 exact absolute none"),
        ("2030년 3월에 시작했다", "2030-03-01..2030-03-31 month absolute none"),
        ("2030년에 시작했다", "2030-01-01..2030-12-31 year absolute none"),
        ("작년 크리스마스에 모였다", "2039-12-25..2039-12-25 exact relative none"),
        ("지난주에 바빴다", "2040-10-01..2040-10-07 month relative none"),
        ("이번 주에 옮긴다", "2040-10-08..2040-10-14 month relative none"),
        ("다음 주 금요일에 만난다", "2040-10-19..2040-10-19 exact relative none"),
        ("지난 주말에 쉬었다", "2040-10-06..2040-10-06 exact relative none"),
        ("이번 수요일에 만난다", "2040-10-10..2040-10-10 exact relative none"),
        ("지난 월요일에 만났다", "2040-10-08..2040-10-08 exact relative none"),
        ("보름 전에 시작했다", "2040-09-25..2040-09-25 exact relative none"),
        ("이틀 뒤에 떠난다", "2040-10-12..2040-10-12 exact relative none"),
        ("일주일 전에 시작했다", "2040-10-03..2040-10-03 exact relative none"),
        ("2주 전에 시작했다", "2040-09-26..2040-09-26 exact relative none"),
        ("세 달 전에 시작했다", "2040-07-01..2040-07-31 month relative none"),
        ("반년 전에 시작했다", "2040-04-01..2040-04-30 month relative none"),
        ("3년 전에 시작했다", "2037-01-01..2037-12-31 year relative none"),
        ("그저께 만났다", "2040-10-08..2040-10-08 exact relative none"),
        ("모레 떠난다", "2040-10-12..2040-10-12 exact relative none"),
        ("다다음달 3일에 만난다", "2040-11-03..2040-11-03 exact relative none"),
    ])
    func absoluteAndRelative(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 범위 · 연대 · 두 자리 해 · 최근 · 끝 없는 때 · 되풀이.
    @Test(arguments: [
        ("2030년 3월 3일부터 5일까지 걸었다", "2030-03-03..2030-03-05 month absolute none"),
        ("2030년 12월 28일부터 1월 3일까지 쉬었다", "2030-12-28..2031-01-03 month absolute none"),
        ("작년 여름부터 올해 봄까지 배웠다", "2039-06-01..2040-05-31 circa relative+season soft"),
        ("2050년대 초반에 시작했다", "2050-01-01..2053-12-31 period absolute soft"),
        ("90년대 말에 시작했다", "1997-01-01..1999-12-31 period absolute soft"),
        ("97년에 시작했다", "1997-01-01..1997-12-31 year absolute none"),
        ("10년 넘게 다녔다", "ask:noExpression"),
        ("최근에 시작했다", "2039-10-10..2040-10-10 period relative soft"),
        ("몇 달 전에 시작했다", "2039-10-10..2040-10-10 period relative soft"),
        ("예전에 살던 곳", "ask:unbounded"),
        ("고양이를 길렀다", "ask:noExpression"),
        ("매주 토요일마다 걷는다", "recurring"),
        ("주말마다 걷는다", "recurring"),
        ("매달 5일에 모은다", "recurring"),
        ("사람마다 다르다", "ask:noExpression"),
        ("다음 달부터 매달 5일 모은다", "2040-11-05..2040-11-05 exact relative none"),
    ])
    func rangesAndOthers(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 생년에서 — 학년(학년도 3월 ~ 이듬해 2월) · 1~2월생은 한 해 넓혀 흐림 · 줄임 학년은 따로 선 낱말만 · 나이 · 나잇대 · 학교급 · 시대.
    @Test(arguments: [
        ("고3 때 공부했다", "none", "ask:needsBirth"),
        ("고3 때 공부했다", "born", "2068-03-01..2069-02-28 year grade none"),
        ("고3 때 공부했다", "early", "1967-03-01..1969-02-28 period grade soft"),
        ("고 3 때 공부했다", "born", "2068-03-01..2069-02-28 year grade none"),
        ("중2 겨울방학에 배웠다", "born", "2064-12-01..2065-02-28 circa grade+season soft"),
        ("신고 3번 했다", "born", "ask:noExpression"),
        ("회의 중 2 시간 동안 졸았다", "born", "ask:noExpression"),
        ("대학교 2학년 때 배웠다", "born", "2070-03-01..2074-02-28 period grade soft"),
        ("대학교 2학년 때 배웠다", "full", "2070-03-01..2073-02-28 period grade soft"),
        ("2068년 고3 때 공부했다", "born", "2068-03-01..2068-12-31 year absolute+grade none"),
        ("열여덟에 시작했다", "born", "2067-01-01..2068-12-31 period age soft"),
        ("열에 아홉은 그렇다", "born", "ask:noExpression"),
        ("만 20세 때 시작했다", "born", "2070-05-10..2071-05-09 year age none"),
        ("스무 살 때 시작했다", "born", "2069-01-01..2070-12-31 period age soft"),
        ("둘이었을 때 좋았다", "born", "ask:noExpression"),
        ("20대 초반에 시작했다", "born", "2069-01-01..2073-12-31 period ageBand soft"),
        ("초등학교 때 배웠다", "born", "2057-03-01..2063-02-28 period schoolStage soft"),
        ("초등학교 고학년 때 배웠다", "early", "1959-03-01..1963-02-28 period schoolStage soft"),
        ("중학생 때 배웠다", "born", "2063-03-01..2066-02-28 period schoolStage soft"),
        ("어릴 때 배웠다", "born", "2050-05-10..2063-02-28 period era soft"),
        ("어릴 때 배웠다", "none", "ask:needsBirth"),
        ("학창 시절에 배웠다", "born", "2057-03-01..2069-02-28 period era soft"),
        ("첫돌 때 사진을 찍었다", "born", "2051-05-10..2051-05-10 exact age none"),
        ("환갑 때 모였다", "born", "2110-01-01..2110-12-31 circa age soft"),
        ("어릴 때 여름마다 바다에 갔다", "born", "2050-05-10..2063-02-28 period era soft"),
        ("어릴 때 여름마다 바다에 갔다", "none", "ask:needsBirth"),
    ])
    func fromBirth(_ s: String, _ c: String, _ expect: String) { #expect(said(s, c, now: later) == expect, "\(s) · \(c)") }

    /// 인생 사건 — 기준 사건 + 바로 뒤 수식(직후 · 직전 · 그해 · 전 · 뒤 · 때) · 없으면 묻는다 · 남의 사건은 아니다 · 생년에서 셈하는 사건.
    @Test(arguments: [
        ("결혼하고 나서 옮겼다", "full", "2081-10-10..2082-10-09 circa lifeEvent soft"),
        ("결혼하고 나서 옮겼다", "born", "ask:needsAnchor:wedding"),
        ("결혼하기 전에 옮겼다", "full", "2080-10-10..2081-10-09 circa lifeEvent soft"),
        ("결혼한 해에 옮겼다", "full", "2081-01-01..2081-12-31 circa lifeEvent soft"),
        ("결혼식 때 비가 왔다", "full", "2081-10-10..2081-10-10 exact lifeEvent soft"),
        ("친구 결혼식 때 비가 왔다", "full", "ask:noExpression"),
        ("신혼 때 옮겼다", "full", "2081-10-10..2083-10-09 period lifeEvent soft"),
        ("군대 있을 때 일기를 썼다", "full", "2070-03-10..2071-09-10 period lifeEvent soft"),
        ("군대에 있던 시절 사진을 정리했다", "enlisted", "ask:needsAnchor:military-discharge"),
        ("입대 직전에 머리를 잘랐다", "full", "2069-12-10..2070-03-09 circa lifeEvent soft"),
        ("전역 직후에 여행했다", "full", "2071-09-10..2071-12-09 circa lifeEvent soft"),
        ("첫 직장에 들어간 후로 바빴다", "full", "2075-01-10..2076-01-09 circa lifeEvent soft"),
        ("이사하고 나서 바빴다", "full", "ask:needsAnchor:move"),
        ("퇴직하고 나서 쉬었다", "full", "ask:needsAnchor:retirement"),
        ("아이를 낳고 나서 바빴다", "full", "ask:needsAnchor:childbirth"),
        ("이사님이 오셨을 때 회의했다", "full", "ask:noExpression"),
        ("태어난 날 바람이 불었다", "born", "2050-05-10..2050-05-10 exact lifeEvent none"),
        ("태어난 해에 옮겼다", "born", "2050-01-01..2050-12-31 circa lifeEvent soft"),
        ("대학교 졸업하고 옮겼다", "born", "2073-02-01..2074-01-31 circa lifeEvent soft"),
        ("대학교 졸업하고 옮겼다", "full", "2073-02-01..2074-01-31 circa lifeEvent soft"),
        ("중학교 입학할 때 옮겼다", "early", "1962-03-01..1963-03-31 period lifeEvent soft"),
        ("수능 끝나고 여행했다", "born", "2068-11-01..2069-02-28 circa lifeEvent soft"),
        ("재수할 때 공부했다", "born", "2069-03-01..2070-02-28 circa lifeEvent soft"),
    ])
    func lifeEvents(_ s: String, _ c: String, _ expect: String) { #expect(said(s, c, now: later) == expect, "\(s) · \(c)") }

    /// 날 하나 — 말한 단위까지 · 앵커는 단위의 첫 날 · 되풀이는 말한 시작만 · 생년으로 읽는 때 · 요일 없는 주 · 흐린 수는 nil.
    @Test(arguments: [
        ("어제 만났다", "2040-10-09 exact"),
        ("3월 말에 옮겼다", "2040-03-21 circa"),
        ("작년 여름에 갔다", "2039-06-01 circa"),
        ("2030년에 시작했다", "2030-01-01 year"),
        ("다음 달부터 매달 5일 모은다", "2040-11-05 exact"),
        ("지난주에 바빴다", "nil"),
        ("매달 5일에 모은다", "nil"),
        ("몇 달 전에 시작했다", "nil"),
        ("고3 때 공부했다", "nil"),
    ])
    func oneDay(_ s: String, _ expect: String) {
        let d = SpokenReading.day(s, now: day("2040-10-10"), zone: zone)
        #expect((d.map { "\($0.text) \($0.precision.rawValue)" } ?? "nil") == expect, "\(s)")
        if let d { #expect(calendar().component(.hour, from: d.date) == 12 && text(d.date) == d.text) }
    }

    /// 끝 날 — 「A부터 B까지」 = B(빠진 해 · 달은 시작에서 · 이은 끝이 시작보다 앞이면 윗 단위를 하나 올림) · 「N박」 = 시작 + N일(시작이 exact · 낱말 경계).
    @Test(arguments: [
        ("10월 25일부터 3일까지 쉬었다", "2040-11-03 exact"),
        ("12월 28일부터 1월 3일까지 쉬었다", "2041-01-03 exact"),
        ("3월 3일부터 5일까지 걸었다", "2040-03-05 exact"),
        ("오늘부터 다음 달까지 쉰다", "2040-11-01 month"),
        ("3월 3일에 2박 3일 다녀왔다", "2040-03-05 exact"),
        ("3월에 2박 다녀왔다", "nil"),
        ("3월 3일에 귤 2 박스 샀다", "nil"),
        ("3월 3일부터 한동안 쉬었다", "nil"),
    ])
    func endDay(_ s: String, _ expect: String) {
        let now = day("2040-10-10")
        let e = SpokenReading.end(s, start: SpokenReading.day(s, now: now, zone: zone), now: now, zone: zone)
        #expect((e.map { "\($0.text) \($0.precision.rawValue)" } ?? "nil") == expect, "\(s)")
    }

    /// 기간 신호 — 「N박」(낱말 경계) · 「동안」 · 「…부터 …까지」.
    @Test(arguments: [("2박 3일 여행", true), ("한 달 동안 배웠다", true), ("3일부터 5일까지 쉬었다", true), ("귤 2 박스 샀다", false), ("어제 만났다", false),
                      ("어제 운동 안 했다", false)])   // 낱말 사이 빈칸이 뜻을 가른다 — 「동안」이 아니다
    func spanSignal(_ s: String, _ expect: Bool) { #expect(SpokenReading.hasSpanSignal(s) == expect, "\(s)") }

    /// 두 자리 해 · 두 자리 연대 — 기준 해의 세기에 붙인다. 지난 일(기본): 기준 해보다 뒤면 한 세기 앞 · 앞일: 기준 해 이상 가장 가까운 해.
    /// 기준 날은 기준 해의 끝 두 자리가 26 인 해 — 날 글자를 적지 않고 해만 견준다.
    @Test(arguments: [
        ("97년에 시작했다", SpokenReading.Direction.past, 1997, 1997),
        ("26년에 시작했다", .past, 2026, 2026),       // 끝 두 자리가 기준 해와 같으면 이번 세기
        ("27년에 시작했다", .past, 1927, 1927),       // 기준 해보다 뒤면 앞 세기 — 앞일은 방향 힌트로
        ("27년에 시작했다", .future, 2027, 2027),
        ("97년에 시작했다", .future, 2097, 2097),
        ("90년대에 시작했다", .past, 1990, 1999),
        ("30년대에 시작했다", .past, 1930, 1939),
        ("30년대에 시작했다", .future, 2030, 2039),
    ])
    func twoDigitYears(_ s: String, _ direction: SpokenReading.Direction, _ from: Int, _ to: Int) throws {
        let now = calendar().date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        guard case .span(let x) = SpokenReading.read(s, now: now, zone: zone, direction: direction) else { Issue.record("구간이 아니다 — \(s)"); return }
        #expect(calendar().component(.year, from: x.from) == from && calendar().component(.year, from: x.to) == to, "\(s) · \(direction)")
    }

    /// 앞일 힌트 — 수식 없는 달 · 달과 날은 오늘 이후(오늘 · 이번 달 포함 · 어제는 다음 해) 가장 가까운 것 · 수식 없는 계절은 아직 끝나지 않은 가장 가까운 것
    /// (오늘이 든 계절 포함) · 수식어(지난 · 작년 …)가 힌트를 이긴다 · 지난 일(기본)이면 그대로. 기준 날 2040-05-14.
    @Test(arguments: [
        ("3월에 옮기고 싶다", "2040-03-01..2040-03-31 month absolute none", "2041-03-01..2041-03-31 month absolute none"),
        ("5월에 텃밭을 갈 거다", "2040-05-01..2040-05-31 month absolute none", "2040-05-01..2040-05-31 month absolute none"),
        ("5월 13일에 화분을 사러 간다", "2040-05-13..2040-05-13 exact absolute none", "2041-05-13..2041-05-13 exact absolute none"),
        ("5월 14일에 전시를 보러 간다", "2040-05-14..2040-05-14 exact absolute none", "2040-05-14..2040-05-14 exact absolute none"),
        ("봄에 꽃씨를 뿌릴 거다", "ask:noExpression", "2040-03-01..2040-05-31 circa relative+season soft"),
        ("여름에 그늘막을 칠 거다", "ask:noExpression", "2040-06-01..2040-08-31 circa relative+season soft"),
        ("가을에 마당을 정리할 거다", "ask:noExpression", "2040-09-01..2040-11-30 circa relative+season soft"),
        ("겨울에 난로를 들일 거다", "ask:noExpression", "2040-12-01..2041-02-28 circa relative+season soft"),
        ("지난 3월에 옮겼다", "2040-03-01..2040-03-31 month absolute none", "2040-03-01..2040-03-31 month absolute none"),
        ("작년 여름에 갔다", "2039-06-01..2039-08-31 circa relative+season soft", "2039-06-01..2039-08-31 circa relative+season soft"),
    ])
    func futureHint(_ s: String, _ past: String, _ future: String) {
        let now = "2040-05-14"
        #expect(said(s, now: now) == past, "\(s) · 지난 일")
        #expect(said(s, now: now, direction: .future) == future, "\(s) · 앞일")
        let d = SpokenReading.day(s, now: day(now), zone: zone, direction: .future)
        #expect(d.map { text($0.date) } == (future.hasPrefix("ask") ? nil : String(future.prefix(10))), "\(s) · 날 하나 앞일")
    }

    /// 수는 네 자리까지 — 넘치는 수는 때가 아니다(멈추지 않는다).
    @Test func hugeNumbersAreNotTimes() {
        let now = day("2040-10-10")
        #expect(SpokenReading.day("9000000000000000000주 전에 시작했다", now: now, zone: zone) == nil)
        #expect(said("9000000000000000000주 전에 시작했다") == "ask:noExpression")
        #expect(SpokenReading.day("12345일 전에 시작했다", now: now, zone: zone) == nil)
        #expect(SpokenReading.day("9999일 전에 시작했다", now: now, zone: zone) != nil)
        let start = SpokenReading.day("3월 3일에 떠났다", now: now, zone: zone)
        #expect(SpokenReading.end("3월 3일에 12345박 했다", start: start, now: now, zone: zone) == nil)
    }

    /// 날 하나를 짓는 손 · 다른 시간대에서 지은 시작도 그 연 · 월 · 일로 센다 · 안의 값 꼴은 JSON 으로 오간다(결과 열거는 Codable 이 아니다).
    @Test func dayValues() throws {
        let west = TimeZone(secondsFromGMT: -10 * 3600)!
        let s = try #require(SpokenReading.Day(year: 2040, month: 3, day: 3, precision: .exact, zone: west))
        #expect(s.text == "2040-03-03" && calendar(west).component(.hour, from: s.date) == 12)
        #expect(SpokenReading.Day(year: 2040, month: 2, day: 30, precision: .exact, zone: zone)?.text == "2040-03-01")
        let e = SpokenReading.end("3월 3일부터 5일까지 걸었다", start: s, now: day("2040-10-10"), zone: zone)
        #expect(e?.text == "2040-03-05")
        #expect(SpokenReading.end("2박 3일 다녀왔다", start: s, now: day("2040-10-10"), zone: zone)?.text == "2040-03-05")
        guard case .span(let r) = SpokenReading.read("2030년 봄에 시작했다", now: day("2040-10-10"), zone: zone) else { Issue.record("구간이 아니다"); return }
        #expect(try JSONDecoder().decode(SpokenReading.Span.self, from: JSONEncoder().encode(r)) == r)
        guard case .ask(let a) = SpokenReading.read("고3 때 공부했다", now: day("2040-10-10"), zone: zone) else { Issue.record("묻기가 아니다"); return }
        #expect(try JSONDecoder().decode(SpokenReading.Ask.self, from: JSONEncoder().encode(a)) == a)
        #expect(try JSONDecoder().decode(SpokenReading.Day.self, from: JSONEncoder().encode(s)) == s)
    }

    /// 방향의 기본은 지난 일 — 힌트 없이 부르면 지난 일과 같다.
    @Test func directionDefaultsToPast() {
        let now = calendar().date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        #expect(SpokenReading.read("27년에 시작했다", now: now, zone: zone) == SpokenReading.read("27년에 시작했다", now: now, zone: zone, direction: .past))
        #expect(SpokenReading.read("27년에 시작했다", now: now, zone: zone) != SpokenReading.read("27년에 시작했다", now: now, zone: zone, direction: .future))
        #expect(SpokenReading.Direction.allCases.map(\.rawValue) == ["past", "future"])
    }

    /// 시간대가 날을 정한다 — 같은 순간이라도 시간대의 날에서 센다 · 낸 날은 그 시간대의 정오.
    @Test func zoneDecidesTheDay() throws {
        let instant = day("2040-10-10", hour: 0)   // UTC+9 의 10일 0시 = UTC 의 9일 15시
        let utc = TimeZone(secondsFromGMT: 0)!
        guard case .span(let a) = SpokenReading.read("어제 만났다", now: instant, zone: zone),
              case .span(let b) = SpokenReading.read("어제 만났다", now: instant, zone: utc) else { Issue.record("구간이 아니다"); return }
        #expect(text(a.from) == "2040-10-09")
        #expect(text(b.from, in: utc) == "2040-10-08")
        #expect(calendar().component(.hour, from: a.anchor) == 12)
        #expect(calendar(utc).component(.hour, from: b.anchor) == 12)
    }

    /// 저장 정밀도의 낱말 — 다섯이고 차례가 그대로다.
    @Test func precisionWords() {
        #expect(SpokenReading.Precision.allCases.map(\.rawValue) == ["exact", "month", "year", "circa", "period"])
        #expect(SpokenReading.Ask.Reason.known.map(\.rawValue) == ["noExpression", "unbounded", "needsBirth", "needsAnchor"])
        #expect(SpokenReading.Ask.Reason(rawValue: "laterWord").rawValue == "laterWord")   // 열린 꼴 — 모르는 낱말도 그대로 든다
    }

    /// 같은 키의 기준 사건이 여럿이면 가장 이른 것.
    @Test func earliestEventOfAKey() {
        let c = SpokenReading.Context(birth: nil, anchors: [.init(key: "move", start: day("2035-01-01")), .init(key: "move", start: day("2031-01-01"))])
        #expect(c.anchor("move").map { text($0.start) } == "2031-01-01")
        guard case .span(let s) = SpokenReading.read("이사하고 나서 바빴다", now: day("2040-10-10"), zone: zone, context: c) else { Issue.record("구간이 아니다"); return }
        #expect(text(s.from) == "2031-01-01")
    }
}

@Suite struct WordsTests {
    static var resource: Data { get throws { try Data(contentsOf: #require(Words.resourceURL)) } }

    /// 자원이 번들에 실려 읽힌다.
    @Test func resourceReads() throws {
        _ = Words.shared
        _ = try Words.decode(Self.resource)
    }

    /// 꼴은 모두 정규식으로 선다(끼움을 푼 뒤) — 목록 칸의 꼴과 바로 뒤에 낱말을 이어 붙여 쓰는 꼴 포함.
    @Test func everyPatternCompiles() throws {
        let w = Words.shared
        var all = Mirror(reflecting: w.patterns).children.compactMap { $0.value as? String }
        all += w.grades.map(\.pattern) + w.anchored.map(\.pattern) + w.modifiers.map(\.pattern)
        all += w.monthOffset.map { $0.word + w.patterns.dayAfterWord } + w.nativeDays.map { $0.word + w.patterns.agoAfterWord }
        all += w.dayOffset.map { $0.word + w.patterns.dayWordGuard }
        for p in all { #expect((try? NSRegularExpression(pattern: p)) != nil, "\(p)") }
        #expect(!all.contains { $0.contains("{") && $0.range(of: #"\{[A-Za-z]+\}"#, options: .regularExpression) != nil }, "풀리지 않은 끼움")
    }

    /// 자원의 꼴 이름 = 읽는 쪽의 칸 이름(남는 꼴 0 · 빠진 꼴은 읽기 실패).
    @Test func wordsUseEveryPattern() throws {
        let fields = Set(Mirror(reflecting: Words.shared.patterns).children.compactMap(\.label))
        #expect(try Words.patternNames(Self.resource) == fields)
    }

    /// 낱말 표의 크기 — 줄 하나가 빠지면 빨강(자원이 이 모듈의 정본이다).
    @Test func vocabularyIsWhole() {
        let w = Words.shared
        let patterns: Int = Mirror(reflecting: w.patterns).children.count
        let lists: [Int] = [w.grades.count, w.anchored.count, w.modifiers.count, w.stages.count]
        let numbers: [Int] = [w.weekday.count, w.nativeCount.count, w.sinoCount.count, w.nativeTens.count, w.nativeOnes.count]
        let offsets: [Int] = [w.nativeDays.count, w.weekOffset.count, w.yearOffset.count, w.monthOffset.count, w.dayOffset.count]
        let seasons: [Int] = [w.seasonShift.count, w.seasons.count, w.parts.count, w.fixedDays.count, w.monthUnits.count]
        let shifts: [Int] = [w.monthShift.past.count, w.monthShift.future.count, w.school.entry.count, w.school.graduation.count]
        #expect(patterns == 73)
        #expect(lists == [3, 10, 8, 6])
        #expect(numbers == [7, 10, 10, 10, 13])
        #expect(offsets == [11, 6, 6, 6, 8])
        #expect(seasons == [6, 6, 5, 1, 2])
        #expect(shifts == [3, 3, 4, 4])
    }

    /// 계절 표 — 첫 달 · 달 수(봄 3 · 여름 6 · 가을 9 · 겨울 12 · 방학은 여름 7~8 · 겨울 12~2).
    @Test func seasonTable() {
        #expect(Words.shared.seasons.map { "\($0.first)/\($0.months)" } == ["7/2", "12/3", "3/3", "6/3", "9/3", "12/3"])
    }

    /// 끼움 — 모르는 이름 · 제 자신을 부르는 이름은 읽기 실패.
    @Test func slotsFailLoudly() {
        #expect(throws: WordsError.unknownSlot("nope")) { try Words.fill("a{nope}", from: [:], seen: []) }
        #expect(throws: WordsError.cycle("a")) { try Words.fill("{a}", from: ["a": "x{a}"], seen: []) }
        #expect((try? Words.fill(#"\d{1,2}{b}"#, from: ["b": "z"], seen: [])) == #"\d{1,2}z"#)
    }
}
