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

    /// 날 하나 = 같은 글 · 같은 방향 · 빈 맥락의 구간 읽기가 저장할 앵커 · 정밀도 — 구간이 아니면(묻기 · 되풀이) nil.
    /// 「A부터 B까지」만 다르다 — 날 하나는 A 의 제 꼴(끝은 `end`). 기준 날 2040-10-10(수).
    @Test(arguments: [
        ("어제 만났다", "2040-10-09 exact"),
        ("3월 말에 옮겼다", "2040-03-21 circa"),
        ("작년 여름에 갔다", "2039-06-01 circa"),
        ("2030년에 시작했다", "2030-01-01 year"),
        ("다음 달부터 매달 5일 모은다", "2040-11-05 exact"),
        ("지난주에 바빴다", "2040-10-01 month"),
        ("이번 주 내내 연못을 손봤다", "2040-10-08 month"),
        ("최근에 연못을 팠다", "2039-10-10 period"),
        ("요새 연못에 물이 마른다", "2039-10-10 period"),
        ("몇 달 전에 시작했다", "2039-10-10 period"),
        ("열 해 전쯤 연못을 팠다", "2030-01-01 circa"),
        ("5달 전쯤 연못을 팠다", "2040-05-01 circa"),
        ("2031년 고2 때 연못을 팠다", "2031-01-01 year"),
        ("매달 5일에 모은다", "nil"),
        ("고3 때 공부했다", "nil"),
        ("예전에 연못을 팠다", "nil"),
    ])
    func oneDay(_ s: String, _ expect: String) {
        let d = SpokenReading.day(s, now: day("2040-10-10"), zone: zone)
        #expect((d.map { "\($0.text) \($0.precision.rawValue)" } ?? "nil") == expect, "\(s)")
        #expect(d.map { "\($0.text) \($0.precision.rawValue)" } == stored(s, now: day("2040-10-10"), .past), "\(s) · 구간 읽기와 같은 답")
        if let d { #expect(calendar().component(.hour, from: d.date) == 12 && text(d.date) == d.text) }
    }

    /// 구간 읽기(빈 맥락)의 저장 꼴 「YYYY-MM-DD 정밀도」 · 구간이 아니면 nil.
    func stored(_ s: String, now: Date, _ direction: SpokenReading.Direction) -> String? {
        guard case .span(let r) = SpokenReading.read(s, now: now, zone: zone, direction: direction) else { return nil }
        return "\(text(r.anchor)) \(r.precision.rawValue)"
    }

    /// 두 자리 해 · 연대가 해를 정하는 날 하나 — 해 = year · 쯤 · 계절 = circa · 달 = month · 날 = exact · 달의 때 = circa · 연대 = period(구간 첫 날).
    /// 함께 말한 달 · 계절은 그 해 안이다(기준 해로 채우지 않는다). 앞일도 구간 읽기와 같은 셈.
    @Test(arguments: [
        ("87년에 도자기를 배웠다", SpokenReading.Direction.past, "1987-01-01 year"),
        ("93년쯤 텃밭을 일궜다", .past, "1993-01-01 circa"),
        ("88년 가을에 감나무를 심었다", .past, "1988-09-01 circa"),
        ("91년 겨울에 연못이 얼었다", .past, "1991-12-01 circa"),
        ("73년 6월에 울타리를 세웠다", .past, "1973-06-01 month"),
        ("73년 6월 9일에 울타리를 세웠다", .past, "1973-06-09 exact"),
        ("73년 6월 말에 울타리를 세웠다", .past, "1973-06-21 circa"),
        ("45년에 정원을 넓혔다", .past, "1945-01-01 year"),                 // 기준 해보다 뒤면 앞 세기
        ("80년대에 온실을 지었다", .past, "1980-01-01 period"),
        ("80년대 말에 온실을 지었다", .past, "1987-01-01 period"),
        ("2050년대 초반에 온실을 지었다", .past, "2050-01-01 period"),      // 네 자리 연대도 연대
        ("45년에 정원을 넓히고 싶다", .future, "2045-01-01 year"),
        ("45년 봄에 정원을 넓히고 싶다", .future, "2045-03-01 circa"),
        ("52년 4월에 정원을 넓히고 싶다", .future, "2052-04-01 month"),
        ("40년대에 정원을 넓히고 싶다", .future, "2040-01-01 period"),       // 끝나지 않은 가장 가까운 연대
        ("30년대에 정원을 넓히고 싶다", .future, "2130-01-01 period"),
    ])
    func dayFromShortYear(_ s: String, _ direction: SpokenReading.Direction, _ expect: String) {
        let now = day("2040-10-10")
        let d = SpokenReading.day(s, now: now, zone: zone, direction: direction)
        #expect((d.map { "\($0.text) \($0.precision.rawValue)" } ?? "nil") == expect, "\(s) · \(direction)")
        #expect(d.map { "\($0.text) \($0.precision.rawValue)" } == stored(s, now: now, direction), "\(s) · 구간 읽기와 같은 답")
    }

    /// 두 자리 해의 달 · 날 · 계절을 기준 해로 채우지 않는다(지난 일 · 앞일) · 해와 달 사이의 「의 · 쉼표 · 도」는 그 해의 달 · 「인가」는 해를 흐리게 말한 것(circa).
    @Test func shortYearIsNotThisYear() {
        let now = day("2040-10-10")
        for (s, dir) in [("73년 3월에 우물을 팠다", SpokenReading.Direction.past), ("73년 3월 2일에 우물을 팠다", .past), ("73년 여름에 우물을 팠다", .past),
                         ("52년 여름에 우물을 파고 싶다", .future), ("52년 3월에 우물을 파고 싶다", .future)] {
            let d = SpokenReading.day(s, now: now, zone: zone, direction: dir)
            #expect(d != nil, "\(s)")
            #expect(d.map { $0.year != 2040 && $0.year != 2041 } == true, "\(s) · \(dir) — 기준 해 · 다음 해로 채우지 않는다")
        }
        for s in ["73년의 3월에 우물을 팠다", "73년, 3월에 우물을 팠다", "73년도 3월에 우물을 팠다", "1973년도 3월에 우물을 팠다", "1973년의 3월에 우물을 팠다"] {
            #expect(SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "1973-03-01 month", "\(s)")
            #expect(said(s) == "1973-03-01..1973-03-31 month absolute none", "\(s)")
        }
        #expect(said("1973년, 3월 2일에 우물을 팠다") == "1973-03-02..1973-03-02 exact absolute none")
        #expect(said("73년인가 3월에 우물을 팠다") == "1973-03-01..1973-03-31 circa absolute soft")
        #expect(SpokenReading.day("73년인가 3월에 우물을 팠다", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "1973-03-01 circa")
        #expect(said("73년도에 우물을 팠다") == "1973-01-01..1973-12-31 year absolute none")   // 「도」 뒤가 때 표지면 그 해
        // 네 자리 해 · 해 없는 달은 그대로
        #expect(SpokenReading.day("1973년 3월에 우물을 팠다", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "1973-03-01 month")
        #expect(SpokenReading.day("3월에 우물을 팠다", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2040-03-01 month")
        // 날 단위 상대 표현은 그대로 때다
        #expect(SpokenReading.day("어제 73년 사진을 정리했다", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2040-10-09 exact")
        // 되풀이는 말한 시작
        #expect(SpokenReading.day("73년 3월부터 매달 5일에 우물을 살폈다", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "1973-03-05 exact")
    }

    /// 「A부터 B까지」 — 날 하나는 A 의 제 꼴 · 끝은 B 의 제 꼴(두 자리 · 네 자리 해가 같은 답 · 구간 전체 꼴로 끌어오지 않는다) · 연대 끝은 그 연대 첫 날.
    @Test func rangeOwnEnds() {
        let now = day("2040-10-10")
        let f = { (d: SpokenReading.Day?) in d.map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        for s in ["1973년 3월부터 6월까지 울타리를 고쳤다", "73년 3월부터 6월까지 울타리를 고쳤다"] {
            let a = SpokenReading.day(s, now: now, zone: zone)
            #expect(f(a) == "1973-03-01 month", "\(s)")
            #expect(f(SpokenReading.end(s, start: a, now: now, zone: zone)) == "1973-06-01 month", "\(s)")
            #expect(said(s) == "1973-03-01..1973-06-30 year absolute none", "\(s) · 구간은 구간 꼴")
        }
        let y = "73년부터 75년까지 울타리를 고쳤다"
        let ys = SpokenReading.day(y, now: now, zone: zone)
        #expect(f(ys) == "1973-01-01 year")
        #expect(f(SpokenReading.end(y, start: ys, now: now, zone: zone)) == "1975-01-01 year")
        let d = "80년대부터 2050년대까지 온실을 가꿨다"
        let ds = SpokenReading.day(d, now: now, zone: zone)
        #expect(f(ds) == "1980-01-01 period")
        #expect(f(SpokenReading.end(d, start: ds, now: now, zone: zone)) == "2050-01-01 period")
    }

    /// 연대는 문장의 다른 때 표현(날 단위 상대 · 해 · 달)에 진다 — 「80년대 노래」는 노래를 꾸민다 · 홀로 선 연대는 그대로.
    /// 「N년에 한 번 · 두 번」은 빈도(되풀이)지 해가 아니다. 두 손이 같은 답.
    @Test func decadeYieldsAndFrequency() {
        let now = day("2040-10-10")
        let f = { (s: String) in SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        #expect(said("어제 80년대 노래를 틀었다") == "2040-10-09..2040-10-09 exact relative none")
        #expect(f("어제 80년대 노래를 틀었다") == "2040-10-09 exact")
        #expect(said("2031년에 80년대 영화를 봤다") == "2031-01-01..2031-12-31 year absolute none")
        #expect(f("2031년에 80년대 영화를 봤다") == "2031-01-01 year")
        #expect(said("지난 5월에 80년대 음반을 샀다") == "2040-05-01..2040-05-31 month absolute none")
        #expect(said("80년대에 온실을 지었다") == "1980-01-01..1989-12-31 period absolute soft")
        #expect(said("80년대 노래를 좋아한다") == "1980-01-01..1989-12-31 period absolute soft")
        for s in ["10년에 한 번 대나무 꽃이 핀다", "4년에 두 번 연못을 비운다", "100년에 한 번 오는 혜성", "76년에 한 번 오는 혜성을 봤다", "10년마다 연못을 비웠다"] {
            #expect(said(s) == "recurring", "\(s)")
            #expect(f(s) == "nil", "\(s)")
        }
        // 뒤의 풀이말이 지난 꼴이면 그 해에 한 번 — 빈도가 아니다(두 자리 · 네 자리 같은 셈)
        for (s, y) in [("73년에 한 번 가 봤다", "1973"), ("40년에 한 번 온실에 갔었다", "2040"), ("73년에 두 번 연못을 비웠다", "1973")] {
            #expect(said(s) == "\(y)-01-01..\(y)-12-31 year absolute none", "\(s)")
            #expect(f(s) == "\(y)-01-01 year", "\(s)")
        }
        #expect(said("2031년에 10년에 한 번 피는 꽃을 봤다") == "2031-01-01..2031-12-31 year absolute none")   // 빈도 밖의 때는 그대로
        // 네 자리 해는 빈도가 아니다 · 「번째」는 차례지 빈도가 아니다 — 그 해
        for (s, y) in [("2031년에 한 번 온실에 갔다", "2031"), ("2031년에 두 번 연못을 비웠다", "2031"), ("2031년에 두 번째 온실을 지었다", "2031"),
                       ("73년에 두 번째 온실을 지었다", "1973")] {
            #expect(said(s) == "\(y)-01-01..\(y)-12-31 year absolute none", "\(s)")
            #expect(f(s) == "\(y)-01-01 year", "\(s)")
        }
        // 지난 꼴이 아니어도 네 자리 해 · 「번째」는 해다(앞일)
        for (s, y) in [("2045년에 한 번 온실에 가 보고 싶다", "2045"), ("45년에 두 번째 온실을 지을 거다", "2045")] {
            #expect(said(s, direction: .future) == "\(y)-01-01..\(y)-12-31 year absolute none", "\(s)")
        }
        // 연대는 최근에 진다 · 해 없는 달 · 계절에는 지지 않는다(기준 해로 채우지 않는다)
        #expect(said("요즘 80년대 노래를 자주 튼다") == "2039-10-10..2040-10-10 period relative soft")
        #expect(f("요즘 80년대 노래를 자주 튼다") == "2039-10-10 period")
        #expect(said("80년대 초반에 살던 골목이 요즘 자꾸 떠오른다") == "1980-01-01..1983-12-31 period absolute soft")   // 때 토씨가 붙은 연대는 사건의 때
        #expect(said("80년대 어느 5월에 이사했다") == "1980-01-01..1989-12-31 period absolute soft")
        #expect(f("80년대 어느 5월에 이사했다") == "1980-01-01 period")
        #expect(SpokenReading.day("30년대 여름에 떠나고 싶다", now: now, zone: zone, direction: .future).map { "\($0.text) \($0.precision.rawValue)" } == "2130-01-01 period")
    }

    /// 햇수는 해 · 연대가 아니다 — 「N년 대장정」 · 「N년도 넘 · 더」 · 「N년에 걸쳐」 · 「N년 동안」 · 띄우지 않은 「N년대장정」. 연대 꼴은 빈칸 있는 원문에서 때 표지와 함께만.
    @Test func yearCountsAreNotYears() {
        let now = day("2040-10-10")
        let none = "ask:noExpression"
        for s in ["30년 대장정으로 온실을 지었다", "30년대장정으로 온실을 지었다", "온실을 지은 지 20년도 넘었다", "온실을 지은 지 20년도 더 됐다",
                  "빚을 15년에 걸쳐 갚았다", "20년 동안 텃밭을 가꿨다", "온실을 지은 지 20년도 됐다", "온실을 지은 지 10년도 안 됐다",
                  "온실을 지은 지 20년도 훨씬 넘었다", "30년에 가까운 세월을 보냈다", "20년에 이르는 세월을 보냈다"] {
            #expect(said(s) == none, "\(s)")
            #expect(SpokenReading.day(s, now: now, zone: zone) == nil, "\(s)")
        }
        #expect(said("작년에 30년 대장정을 시작했다") == "2039-01-01..2039-12-31 year relative none")
    }

    /// 흐림 「인가」는 해 수에 붙은 「…년인가」만(두 자리 · 네 자리 · 빈칸 없이) — 띄어 쓴 「인가」는 이름씨(허가)라 흐림이 아니다 · 해 낱말 · 달에 붙어도 흐림이 아니다.
    /// 띄어 써도 해 수와 달 · 계절 사이의 「인가」는 흐림 — 그 해의 달 · 계절(두 자리 · 네 자리 같은 답).
    @Test func spacedIngaIsNotVague() {
        let now = day("2040-10-10")
        let f = { (s: String) in SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        for (s, y) in [("지난해 인가 서류가 나왔다", "2039"), ("재작년 인가 심사를 마쳤다", "2038"), ("작년인가 온실을 지었다", "2039")] {
            #expect(said(s) == "\(y)-01-01..\(y)-12-31 year relative none", "\(s)")
            #expect(f(s) == "\(y)-01-01 year", "\(s)")
        }
        #expect(said("5월인가 온실을 지었다") == "2040-05-01..2040-05-31 month absolute none")
        for s in ["61년인가 5월에 온실을 지었다", "1961년인가 5월에 온실을 지었다", "61년 인가 5월에 온실을 지었다", "1961년 인가 5월에 온실을 지었다"] {
            #expect(said(s) == "1961-05-01..1961-05-31 circa absolute soft", "\(s)")
            #expect(f(s) == "1961-05-01 circa", "\(s)")
        }
        #expect(said("61년 인가 가을에 온실을 지었다") == "1961-09-01..1961-11-30 circa absolute+season soft")
    }

    /// 「N년에 한 번」 뒤의 지난 꼴은 낱말 목록이 아니라 꼴 — 과거 선어말(받침 ㅆ — 있 · 겠 밖)이나 「-ㄴ 적」이면 그 해에 한 번.
    /// 앞에 꾸밈 · 이음(는 · 는데 · 지만 · 면서) · 지난 버릇(어간에 붙은 「곤 하다」 · 「번씩」)이 서면 거기서 끊는다 — 빈도(되풀이). 지금 · 앞일 꼴도 빈도.
    /// 빈도 바로 뒤가 「-던」 + 이름씨면 빈도는 이름씨를 꾸민 것 — 둘레에 때가 없으면 때 없음. 받침 ㄴ · ㄹ 관형 · 「는」은 이름씨 · 토씨와 꼴로 갈리지 않아 꾸밈으로 보지 않는다.
    @Test func pastTenseByForm() {
        let now = day("2040-10-10")
        let f = { (s: String) in SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        for (s, y) in [("61년에 한 번 탈춤을 췄다", "1961"), ("67년에 한 번 등불을 껐다", "1967"), ("61년에 한 번 소원을 이뤘다", "1961"),
                       ("67년에 한 번 은반지를 꼈다", "1967"), ("61년에 한 번 담요를 갰다", "1961"), ("67년에 한 번 헛간을 없앴다", "1967"),
                       ("61년에 두 번 돛을 맸다", "1961"), ("67년에 한 번 그 섬에 가 본 적 있다", "1967"), ("61년에 한 번 등대에 들른 적이 있다", "1961"),
                       // 거르는 쪽 이웃 — 문장 가운데 「씩」 · 「피곤」 · 런던의 「던」은 끊지 않는다
                       ("67년에 한 번 다 같이 천 원씩 냈다", "1967"), ("67년에 한 번 조금씩 걸어 올라갔다", "1967"),
                       ("67년에 한 번 너무 피곤해서 쓰러졌다", "1967"), ("67년에 한 번 런던 갔다", "1967"),
                       // 받침 ㄴ · ㄹ 로 끝난 이름씨 · 대이름씨 토씨 「는」은 꾸밈도 끊음도 아니다
                       ("67년에 한 번 큰 산 너머로 이사했다", "1967"), ("67년에 한 번 저녁 반찬 일로 다퉜다", "1967"),
                       ("67년에 한 번 우리는 등대까지 걸었다", "1967"), ("67년에 한 번 런던 거리를 걸었다", "1967"), ("67년에 한 번 들른 찻집에 또 들렀다", "1967")] {
            #expect(said(s) == "\(y)-01-01..\(y)-12-31 year absolute none", "\(s)")
            #expect(f(s) == "\(y)-01-01 year", "\(s)")
        }
        for s in ["67년에 한 번 바닷가에 들르곤 했다", "67년에 한 번 바닷가에 들르곤했다", "67년에 한 번씩 바닷가에 들렀다", "67년에 한 번 바닷가를 걷는 편이다",
                  "6년에 한 번 우물을 판다", "6년에 한 번 바닷가에 들르곤 한다", "6년에 한 번 바닷가를 걷겠다", "6년에 한 번 섬에 갈 수 있다",
                  "60년에 한 번 인적이 드문 섬에 간다", "67년에 한 번 정말 재밌어"] {
            #expect(said(s) == "recurring", "\(s)")
            #expect(f(s) == "nil", "\(s)")
        }
        for s in ["67년에 한 번 서던 오일장에 들렀다", "50년에 한 번 피던 꽃을 봤다", "67년에 한 번 들렀던 찻집에 또 들렀다"] {
            #expect(said(s) == "ask:noExpression", "\(s)")
            #expect(f(s) == "nil", "\(s)")
        }
        #expect(said("2031년에 67년에 한 번 서던 오일장에 들렀다") == "2031-01-01..2031-12-31 year absolute none")   // 둘레의 때는 그대로
    }

    /// 되풀이 낱말은 문장의 끝 풀이말 마디에 걸릴 때만 문장 때를 되풀이로 바꾼다.
    /// 꾸미는 마디(「-던」 · 「-는」 + 이름씨)의 되풀이는 이름씨를 꾸밀 뿐 — 문장 때는 나머지에서(그 마디 안의 때 낱말도 가린다 · 「-는」은 날이 선 때가 따로 있을 때만).
    /// 여러 문장이면 되풀이는 제 문장의 일 — 다른 문장에 구간이 서면 그 구간 · 없으면 되풀이. 끝 풀이말 마디의 되풀이는 그대로.
    @Test func recurringBindsOnlyTheMainClause() {
        let now = day("2040-10-10")
        let f = { (s: String) in SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        // 꾸미는 마디 — 나머지의 때
        for (s, w) in [("그저께 매주 들르던 꽃집에 들렀다", "2040-10-08..2040-10-08 exact relative none"),
                       ("그저께 매주 들르는 꽃집에 들렀다", "2040-10-08..2040-10-08 exact relative none"),
                       ("1987년에 날마다 오르던 언덕을 깎았다", "1987-01-01..1987-12-31 year absolute none"),
                       ("매주 목요일에 가던 서점이 지난달에 닫았다", "2040-09-01..2040-09-30 month relative none"),
                       ("석 달째 매주 가던 모임에 그저께 빠졌다", "2040-10-08..2040-10-08 exact relative none"),
                       ("그저께 매일 아침 일찍 열던 빵집이 쉬었다", "2040-10-08..2040-10-08 exact relative none")] {
            #expect(said(s) == w, "\(s)")
            #expect(f(s) == String(w.prefix(10)) + " " + w.split(separator: " ")[1], "\(s)")
        }
        #expect(said("비 올 때마다 걷던 둑길이 사라졌다") == "ask:noExpression")   // 다른 때가 없으면 때 없음
        #expect(said("매년 4월에 열던 장터가 사라졌다") == "ask:noExpression")   // 꾸미는 마디 안의 달도 문장 때가 아니다
        // 여러 문장 — 다른 문장의 구간
        #expect(said("그저께 삼촌을 만났다. 삼촌은 매일 낚시를 한다") == "2040-10-08..2040-10-08 exact relative none")
        #expect(said("삼촌은 날마다 낚시를 한다! 1987년에 시작했다") == "1987-01-01..1987-12-31 year absolute none")
        #expect(f("그저께 삼촌을 만났다. 삼촌은 매일 낚시를 한다") == "2040-10-08 exact")
        // 끝 풀이말 마디 · 날이 선 때가 없는 무른 꾸밈 · 매인 이름씨 · 꼴이 겹치는 이웃(받침 ㄴ 이름씨 · 대이름씨 토씨 · 런던 · 소수점) — 되풀이 그대로
        for s in ["매일 저녁 줄넘기를 한다", "비 올 때마다 둑길을 걸었다", "삼촌은 매주 낚시를 간다", "삼촌을 만났다. 삼촌은 매일 낚시를 한다",
                  "매주 들르는 꽃집이 문을 닫았다", "매일 줄넘기를 했던 것 같다", "1987년에 매일 하는 중이었다", "1987년에 매일 걷는 편이었다", "1987년에 매일 돈을 모았다",
                  "1987년에 매일 나는 둑길을 걸었다", "1987년에 매일 런던 거리를 걸었다", "그저께 2.5 킬로를 매일 걸었다"] {
            #expect(said(s) == "recurring", "\(s)")
            #expect(f(s) == "nil", "\(s)")
        }
        #expect(said("그저께부터 매일 줄넘기를 한다") == "2040-10-08..2040-10-08 exact relative none")   // 말한 시작은 그대로
    }

    /// 되풀이 마디 가름의 둘레 — 마디는 앞에 붙은 수 · 해 없는 달 · 날 · 계절까지 · 사이 낱말이 마디 밖이면(임자말 · 토씨 은 · 는 · 도 · 이음 · 맺음 · 해가 선 때) 꾸밈이 아니다 ·
    /// 「-는」은 바로 뒤 낱말 · 풀이말 줄기만 · 매인 이름씨는 끝 풀이말 · 빈도와 함께 서도 · 되풀이 문장이 제 구간을 세우면 그 답 · 문장 끝은 수 뒤 마침표가 아니다.
    @Test func recurringClauseBoundaries() {
        let now = day("2040-10-10")
        let f = { (s: String) in SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } ?? "nil" }
        let ago2 = "2040-10-08..2040-10-08 exact relative none"
        // 마디의 왼쪽 — 수 · 단위 · 해 없는 달 · 날 · 계절은 되풀이의 낱말이라 함께 가린다(남은 글에 붙어 날이 되지 않는다)
        for s in ["4년마다 열리던 장터를 못 봤다", "3일마다 오던 문자가 끊겼다", "15일마다 가던 은행이 사라졌다", "6개월마다 가던 여행을 끊었다",
                  "5월 3일마다 가던 절이 없어졌다", "4월에 매년 열던 장터가 사라졌다", "1987년 4월에 매년 열던 장터가 사라졌다", "겨울에 주말마다 타던 썰매를 버렸다"] {
            #expect(said(s) == "ask:noExpression", "\(s)")
        }
        #expect(said("2주마다 보던 잡지를 그저께 끊었다") == ago2)
        #expect(said("겨울에 주말마다 타던 썰매를 고칠 거다", direction: .future) == "ask:noExpression")   // 앞일 — 계절이 남으면 오는 겨울로 읽힌다
        // 꾸밈 마디 안 — 목적어 · 마디 안 달이 끼어도 · 두 낱말까지
        for s in ["매일 신문을 보던 삼촌이 그저께 쓰러졌다", "그저께 매일 읽는 신문이 안 왔다", "그저께 매일 마시는 우유를 쏟았다",
                  "그저께 매일 걷던 거리를 걸었다", "그저께 매일 가는 게임방에 갔다", "매일 다니던 중학교에 그저께 갔다", "매일 가던 편의점이 그저께 닫았다",
                  "그저께 매일 먹는 수프를 쏟았다", "매일 보던 적군이 그저께 사라졌다", "그저께 매일 치는 줄넘기를 버렸다", "매일 듣던 건반 소리가 그저께 멎었다",
                  "그저께 매주 들르던 꽃집에서 10년에 한 번 피는 꽃을 샀다", "그저께 삼촌을 만났다. 삼촌은 매일 10년에 한 번 피는 꽃을 본다",
                  "그저께 갔어? 매일 가", "그저께 만났다... 삼촌은 매일 낚시를 한다", "그저께부터 매일 줄넘기를 한다. 1987년에도 그랬다",
                  "삼촌은 매일 10년에 한 번 피는 꽃을 본다. 그저께 만났다"] {
            #expect(said(s) == ago2, "\(s)")
        }
        #expect(said("매년 4월에 열던 장터가 사라졌다. 1987년에 처음 열렸다") == "1987-01-01..1987-12-31 year absolute none")
        // 되풀이 문장이 제 구간을 세우면 그 답(다른 문장의 때에 지지 않는다)
        #expect(said("1987년부터 매일 달렸다. 1990년까지 계속했다.") == "1987-01-01..1987-12-31 year absolute none")
        // 끝 풀이말 · 마디 밖 사이 낱말 · 이름씨 + 토씨 · 매인 이름씨 · 빈도 · 수 뒤 마침표 · 붙은 마침표 — 되풀이 그대로
        for s in ["날마다 아버지가 다니던 공장 앞을 지난다", "매일 내가 살던 집에 간다", "주말마다 삼촌도 살던 집에 갔다", "매주 예전에 머물던 마을에 간다",
                  "매일 걷다가 그저께 다니던 병원에 갔다", "매일 운동한다 다니던 헬스장이 닫았다", "매일 걸으며 지내던 삼촌이 쓰러졌다", "1987년에 매일 아침 먹는 약을 걸렀다", "매일 운동한다 그저께 다니던 헬스장에 갔다", "그저께 매일 같이 가던 친구를 만났다",
                  "그저께 하루도 빠짐없이 매일 열심히 아주 오래 다니던 학원에 갔다",
                  "1987년에 매일 누나는 시장에 갔다", "1987년에 매일 할머니는 시장에 갔다", "1987년에 매일 학교에서는 급식을 먹었다", "1987년에 매일 우리는 둑길을 걸었다",
                  "매일 누나는 그저께 산 신발을 신는다", "1987년에 매일 엄마가 일하는 가게에 들렀다",
                  "매일 운동하던 것이다", "매일 운동하던 거다", "매일 운동하던 거야", "매일 운동하던 겁니다", "매일 줄넘기를 하던 걸 기억한다", "작년에 매일 줄넘기를 하던 건 기억난다",
                  "매일 싸우던 모양이다", "매일 싸우던 듯하다", "매일 웃던 뿐이었다", "매일 싸우던 때가 있었다", "매일 가던 데가 있다", "매일 가던 수가 있다", "매일 가던 적이 있다",
                  "매일 가던 게 좋았다", "매일 가던 줄 알았다", "매일 가던 중이었다", "매일 가던 편이다", "그저께 매일 가는 줄 알았다", "그저께 매일 운동하는 수밖에 없다고 들었다",
                  "10년에 한 번 매일 가던 식당에 간다", "그저께 3. 5 킬로를 매일 걸었다", "매일 일기를 쓴다.그저께 시작했다"] {
            #expect(said(s) == "recurring", "\(s)")
            #expect(f(s) == "nil", "\(s)")
        }
        // 낸 토막에 가름 글자가 남지 않는다 · 가른 자리는 빈칸을 뺀 글에서도 둘레가 붙지 않는다
        if case .span(let s) = SpokenReading.read("그저께 매주 들르던 꽃집에 들렀다", now: now, zone: zone) { #expect(s.phrase == "그저께") } else { Issue.record("span") }
        #expect(!Rx.strip(SpanReader.gapped("12 매일 34", [3..<5])).contains("1234"))
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
        ("11월부터 1월까지 텃밭을 쉬었다", "2041-01-01 month"),     // 해 없는 달 끝 — 해는 시작에서 · 앞이면 한 해 올림
        ("3월부터 5월까지 텃밭을 갈았다", "2040-05-01 month"),
        ("8월 20일부터 9월 말까지 텃밭을 쉬었다", "2040-09-21 circa"),
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

    /// 해 없는 달 끝은 시작에서 해를 잇는다 — 앞일에서 시작이 다음 해로 가면 끝도 따라간다(끝만 따로 앞일로 풀지 않는다) · 구간 읽기도 같은 끝.
    @Test func endMonthFollowsStart() {
        let now = day("2040-11-20")
        let s = "9월부터 11월까지 도자기를 배우려 한다"
        let start = SpokenReading.day(s, now: now, zone: zone, direction: .future)
        #expect(start?.text == "2041-09-01")
        let e = SpokenReading.end(s, start: start, now: now, zone: zone, direction: .future)
        #expect(e.map { "\($0.text) \($0.precision.rawValue)" } == "2041-11-01 month")
        #expect(said(s, now: "2040-11-20", direction: .future) == "2041-09-01..2041-11-30 year absolute none")
        #expect(said("11월부터 1월까지 텃밭을 쉬었다") == "2040-11-01..2041-01-31 year absolute none")
    }

    /// 네 자리 해는 더 긴 수의 끝 네 자리가 아니다 — 앞이 숫자면 해로 읽지 않는다 · 네 자리 그 자체는 해.
    @Test func yearNotInsideLongerNumber() {
        let now = day("2040-10-10")
        for s in ["34567년 전에 묻힌 화석", "560000년 전 빙하 이야기"] {
            #expect(SpokenReading.day(s, now: now, zone: zone) == nil, "\(s)")
            #expect(said(s) == "ask:noExpression", "\(s)")
        }
        #expect(SpokenReading.day("2345년에 떠날 배", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2345-01-01 year")
        #expect(said("2345년에 떠날 배") == "2345-01-01..2345-12-31 year absolute none")
    }

    /// 해가 아닌 긴 수(다섯 자리 이상 · 쉼표 수)는 해 자리를 차지한다 — 수와 꼬리(년 · 년도 · 년의 · 년 전 + 달 · 날 · 계절 + 그것으로 여는 구간)를
    /// 덩이째 가리고 남은 문장을 평소대로 읽는다(가린 달 · 계절을 기준 해로 채우지 않는다 · 방향 상관없이) · 네 자리 그 자체는 그 해.
    @Test func longNumberBlockIsMasked() {
        let now = day("2040-10-10")
        let none = "ask:noExpression"
        // 덩이뿐인 문장 — 손 셋 모두 때 없음(지난 일 · 앞일)
        for s in ["45678년 7월에 별이 진다는 소설", "230000년 11월 9일 우주선 일지", "45678년 7월부터 9월까지 연재한 소설",
                  "56,789년 4월 별자리 기사", "45678년도 4월 별자리 기사", "45678년의 4월 별자리 기사", "45678년 전 4월 별자리 기사", "45678년 가을 별자리 기사"] {
            for dir in [SpokenReading.Direction.past, .future] {
                #expect(SpokenReading.day(s, now: now, zone: zone, direction: dir) == nil, "\(s) \(dir)")
                #expect(SpokenReading.end(s, start: SpokenReading.day(s, now: now, zone: zone, direction: dir), now: now, zone: zone, direction: dir) == nil, "\(s) · 끝")
                #expect(said(s, direction: dir) == none, "\(s) \(dir)")
            }
        }
        #expect(!SpokenReading.hasSpanSignal("45678년 7월부터 9월까지 연재한 소설"))   // 가린 구간은 기간 신호도 아니다
        // 네 자리 해는 그대로
        let y = "2345년 7월부터 9월까지 연재한 소설"
        let ys = SpokenReading.day(y, now: now, zone: zone)
        #expect(ys.map { "\($0.text) \($0.precision.rawValue)" } == "2345-07-01 month")
        #expect(SpokenReading.end(y, start: ys, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2345-09-01 month")
        #expect(SpokenReading.day("2345년 11월 9일 우주선 일지", now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2345-11-09 exact")
        #expect(said("2345년 7월에 별이 진다는 소설") == "2345-07-01..2345-07-31 month absolute none")
        // 덩이 밖 때 표현은 평소대로 — 날 단위 상대 · 절대 날짜 · 되풀이 · 나이 · 기준 사건 · 덩이가 끝인 구간의 시작
        for (s, d) in [("어제 45678년 7월 별자리 기사를 봤다", "2040-10-09"), ("5일 전에 230000년 11월 우주선 일지를 펼쳤다", "2040-10-05")] {
            #expect(SpokenReading.day(s, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "\(d) exact", "\(s)")
            #expect(said(s) == "\(d)..\(d) exact relative none", "\(s)")
        }
        let abs = "2035년 5월에 쓴 45678년 7월 별자리 기사"
        #expect(SpokenReading.day(abs, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2035-05-01 month")
        #expect(said(abs) == "2035-05-01..2035-05-31 month absolute none")
        #expect(said("주말마다 45678년 7월 별자리 기사를 읽는다") == "recurring")
        #expect(said("스무 살 때 45678년 7월 별자리 기사를 읽었다", "early") == said("스무 살 때 별자리 기사를 읽었다", "early"))
        #expect(said("결혼하고 나서 45678년 7월 별자리 기사를 읽었다", "full", now: "2090-01-01") == said("결혼하고 나서 별자리 기사를 읽었다", "full", now: "2090-01-01"))
        let tail = "1월부터 45678년 7월까지 연재한 소설"
        #expect(SpokenReading.day(tail, now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2040-01-01 month")
        #expect(SpokenReading.end(tail, start: SpokenReading.day(tail, now: now, zone: zone), now: now, zone: zone) == nil)
        // 「N박」은 남은 문장에서 — 날 단위 시작 뒤면 시작에서 세고 · 시작이 덩이뿐이면 시작 없음
        let nights = "어제 떠나 2박, 45678년 7월 별자리 기사를 읽었다"
        #expect(SpokenReading.end(nights, start: SpokenReading.day(nights, now: now, zone: zone), now: now, zone: zone).map { "\($0.text) \($0.precision.rawValue)" } == "2040-10-11 exact")
        let alone = "45678년 7월 9일에 떠나 2박 했다는 소설"
        #expect(SpokenReading.day(alone, now: now, zone: zone) == nil)
        #expect(SpokenReading.end(alone, start: SpokenReading.day(alone, now: now, zone: zone), now: now, zone: zone) == nil)
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
        #expect(SpokenReading.Ask.Reason.known.map(\.rawValue) == ["noExpression", "unbounded", "needsBirth", "needsAnchor", "conflict"])
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
        all += w.dayOffset.map { $0.word + w.patterns.dayWordGuard } + w.joinedDays.map { $0 + w.patterns.joinedWordGuard } + ["^\\s*" + w.patterns.choiceCount, "^\\s*" + w.patterns.seasonWord]
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
        let seasons: [Int] = [w.seasonShift.count, w.seasons.count, w.parts.count, w.fixedDays.count, w.monthUnits.count, w.weekUnits.count]
        let shifts: [Int] = [w.monthShift.past.count, w.monthShift.future.count, w.school.entry.count, w.school.graduation.count]
        #expect(patterns == 178)
        #expect(w.joinedDays.count == 1 && w.gates.count == 12)
        #expect(lists == [3, 10, 9, 6])
        #expect(numbers == [7, 10, 10, 10, 13])
        #expect(offsets == [11, 6, 6, 6, 8])
        #expect(seasons == [6, 6, 5, 1, 2, 2])
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
