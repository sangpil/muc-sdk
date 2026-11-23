import Foundation
import Testing
@testable import SpokenTime

// 때가 아닌 것 · 말 고침 · 때가 둘 · 꾸미는 때 · 상한 · 방향만 — 규칙마다 맞는 쪽 · 거르는 쪽 문장(합성 — 기준 날 · 맥락 · 기대 글의 꼴은 `SpokenTimeTests` 와 같다).

/// 묻기의 후보(「첫 날..끝 날」 — 나온 차례).
func rivals(_ sentence: String, _ context: String = "none", now: String = "2040-10-10", direction: SpokenReading.Direction = .past) -> [String] {
    guard case .ask(let a) = SpokenReading.read(sentence, now: day(now), zone: zone, context: contexts[context]!, direction: direction) else { return [] }
    return a.candidates.map { "\(text($0.from))..\(text($0.to))" }
}
func spoken(_ sentence: String, _ context: String = "none", now: String = "2040-10-10", direction: SpokenReading.Direction = .past) -> SpokenReading {
    SpokenReading.read(sentence, now: day(now), zone: zone, context: contexts[context]!, direction: direction)
}

/// 이 스레드가 쓴 CPU 시간(초) — 함께 도는 시험의 몫이 섞이지 않는다.
func spent() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
}

/// 문장 하나와 기대 — 맥락 · 기준 날 · 방향 · 묻기의 후보.
struct Said: Sendable, CustomTestStringConvertible {
    let s: String, expect: String, candidates: [String], context: String, now: String, direction: SpokenReading.Direction
    init(_ s: String, _ expect: String, _ candidates: [String] = [], in context: String = "none", now: String = "2040-10-10", direction: SpokenReading.Direction = .past) {
        self.s = s; self.expect = expect; self.candidates = candidates; self.context = context; self.now = now; self.direction = direction
    }
    var testDescription: String { s }
    func check() {
        #expect(said(s, context, now: now, direction: direction) == expect, "\(s)")
        #expect(rivals(s, context, now: now, direction: direction) == candidates, "\(s)")
    }
}

@Suite struct SaidTimesTests {
    /// 「N0대」는 나잇대다 — 대로 세는 이름씨가 토씨 없이 맞닿고 때 표지가 없을 때만 셈이다.
    @Test(arguments: [
        ("30대는 힘들었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("섬에서 30대를 보냈다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대가 그립다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대로 돌아가고 싶다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("그때 나는 30대였다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("내가 30대였어요", "2079-01-01..2089-12-31 period ageBand soft"),
        ("이제 30대네", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대라서 좋았다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 동무랑 걸었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 내내 놀았다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("수레 30대를 고쳤다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차를 30대 샀다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("카메라는 30대 취미였다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("입사 3년 차 30대였다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("일한 지 오 년 차 30대다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("6개월 차 30대다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("버스 기사 30대였다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차는 30대에 샀다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차 안에서 30대를 보냈다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("헌차 30대를 고쳤다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차, 30대를 보냈다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차 30대에 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차 30대 때 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("버스 30대 후반에 탔다", "2086-01-01..2089-12-31 period ageBand soft"),
        ("차 30대쯤 샀다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차 30대까지 탔다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대에 차 20대를 고쳤다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("차 20대를 30대에 고쳤다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대에 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 때 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대였을 때 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 무렵 온실을 지었다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대에 수레 30대를 고쳤다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 안에 온실을 짓는다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대.", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대요", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대야!", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대예요.", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대였어요", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대입니다", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 때요", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30 대", "2079-01-01..2089-12-31 period ageBand soft"),
        ("30대 후반에 온실을 지었다", "2086-01-01..2089-12-31 period ageBand soft"),
        ("30대 초반이요", "2079-01-01..2083-12-31 period ageBand soft"),
        ("차 30대를 고쳤다", "ask:noExpression"),
        ("자동차30대를 고쳤다", "ask:noExpression"),
        ("버스 30대를 고쳤다", "ask:noExpression"),
        ("트럭 30대를 고쳤다", "ask:noExpression"),
        ("택시 30대를 고쳤다", "ask:noExpression"),
        ("자전거 30대를 고쳤다", "ask:noExpression"),
        ("오토바이 30대를 고쳤다", "ask:noExpression"),
        ("컴퓨터 30대를 고쳤다", "ask:noExpression"),
        ("노트북 30대를 고쳤다", "ask:noExpression"),
        ("카메라 30대를 고쳤다", "ask:noExpression"),
        ("에어컨 30대를 고쳤다", "ask:noExpression"),
        ("냉장고 30대를 고쳤다", "ask:noExpression"),
        ("세탁기 30대를 고쳤다", "ask:noExpression"),
        ("텔레비전 30대를 고쳤다", "ask:noExpression"),
        ("TV 30대를 고쳤다", "ask:noExpression"),
        ("휴대폰 30대를 고쳤다", "ask:noExpression"),
        ("핸드폰 30대를 고쳤다", "ask:noExpression"),
        ("전화기 30대를 고쳤다", "ask:noExpression"),
        ("비행기 30대를 고쳤다", "ask:noExpression"),
        ("드론 30대를 고쳤다", "ask:noExpression"),
        ("로봇 30대를 고쳤다", "ask:noExpression"),
        ("기계 30대를 고쳤다", "ask:noExpression"),
        ("차 30대", "ask:noExpression"),
        ("차 30대요", "ask:noExpression"),
        ("차 30대에요", "ask:noExpression"),
        ("버스 10대가 지나갔다", "ask:noExpression"),
        ("차30대를 고쳤다", "ask:noExpression"),
        ("차 20대~30대를 고쳤다", "ask:noExpression"),
        ("차 20대나 30대를 고쳤다", "ask:noExpression"),
        ("차 30대였다", "ask:noExpression"),
        ("차 30대 때문에 막혔다", "ask:noExpression"),
        ("19~20세기 책을 읽었다", "ask:noExpression"),
        ("1~2세대 책을 읽었다", "ask:noExpression"),
        ("아마 20대였나 30대였나 온실을 지었다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("20대나 30대였나 온실을 지었다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("20대 또는 30대인지 온실을 지었다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("20대~30대에 온실을 지었다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("20대 아니면 30대에 온실을 지었다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("차 20대나 30대에 샀다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("차 20대였나 30대에 샀다", "2069-01-01..2089-12-31 period ageBand soft"),
        ("20대 아니면 40대 말에 온실을 지었다", "ask:conflict"),
        ("20대, 40대 때 온실을 지었다", "ask:conflict"),
        ("20대 초반 그리고 30대 후반 섬에서 지냈다", "ask:conflict"),
        ("대학교 때 40대 그림을 그렸다", "2089-01-01..2099-12-31 period ageBand soft"),
        ("20대 40대쯤 온실을 지었다", "2069-01-01..2079-12-31 period ageBand soft"),
        ("20대 그리고 온실을 30대에 지었다", "2069-01-01..2079-12-31 period ageBand soft"),
        ("20대 30대 40대에 온실을 지었다", "2069-01-01..2079-12-31 period ageBand soft"),
        ("작년에 20대 이야기를 적었다", "2089-01-01..2089-12-31 year relative none"),
        ("20대를 작년에 적었다", "2089-01-01..2089-12-31 year relative none"),
        ("20대, 작년에 온실을 지었다", "2089-01-01..2089-12-31 year relative none"),
    ])
    func ageBandIsDefault(_ s: String, _ expect: String) { #expect(said(s, "born", now: later) == expect, "\(s)") }

    /// 「N년 전」의 「전」 뒤에 낱말이 이으면 햇수다 — 토씨 · 빈칸 · 쉼표 · 끝이면 때다.
    @Test(arguments: [
        ("40년 전통 찻집에 들렀다", "ask:noExpression"),
        ("6년전갔다", "2034-01-01..2034-12-31 year relative none"),
        ("6년 전여름에 갔다", "2034-01-01..2034-12-31 circa relative soft"),
        ("그저께 40년 전통 찻집에 들렀다", "2040-10-08..2040-10-08 exact relative none"),
        ("6년 전부 맡겼다", "ask:noExpression"),
        ("3일 전시를 열었다", "2040-10-07..2040-10-07 exact relative none"),
        ("이틀 전화가 끊겼다", "2040-10-08..2040-10-08 exact relative none"),
        ("40년 전 통나무를 옮겼다", "2000-01-01..2000-12-31 year relative none"),
        ("6년 전, 통나무를 옮겼다", "2034-01-01..2034-12-31 year relative none"),
        ("6년 전부터 가꿨다", "2034-01-01..2034-12-31 year relative none"),
        ("6년 전입니다", "2034-01-01..2034-12-31 year relative none"),
        ("6년 전이에요", "2034-01-01..2034-12-31 year relative none"),
        ("6년 전만 해도 몰랐다", "2034-01-01..2034-12-31 year relative none"),
        ("5월 3일 전시를 열었다", "2040-05-03..2040-05-03 exact absolute none"),
        ("2033년 전쟁이 끝났다", "2033-01-01..2033-12-31 year absolute none"),
    ])
    func agoNeedsBoundary(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 낫표 · 따옴표 안과 「X(이)라는 · (이)란 + 이름씨」의 때 낱말은 이름이다(따옴표 없는 「(이)라고」는 때) — 글 전체가 따옴표면 벗기고 읽는다.
    @Test(arguments: [
        ("『그저께』라는 연극을 봤다", "ask:noExpression"),
        ("지난달에 「모레」라는 노래를 불렀다", "2040-09-01..2040-09-30 month relative none"),
        ("삼촌이 \"글피 들른다\"라고 했다", "ask:noExpression"),
        ("《매주》를 작년에 읽었다", "2039-01-01..2039-12-31 year relative none"),
        ("그저께 ‘작년’을 불렀다", "2040-10-08..2040-10-08 exact relative none"),
        ("모레라는 배를 탔다", "ask:noExpression"),
        ("모레란 배를 탔다", "ask:noExpression"),
        ("6년 전이라고 들었다", "2034-01-01..2034-12-31 year relative none"),
        ("“그저께 연못을 팠다.”", "2040-10-08..2040-10-08 exact relative none"),
        ("\"그저께 연못을 팠다\"", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 모레라는 노래를 불렀다", "2040-10-08..2040-10-08 exact relative none"),
        ("모레라고요", "2040-10-12..2040-10-12 exact relative none"),
        ("모임이 모레라고 들었다", "2040-10-12..2040-10-12 exact relative none"),
        ("모레라고 했다", "2040-10-12..2040-10-12 exact relative none"),
        ("만난 게 2033년이라고 하더라", "2033-01-01..2033-12-31 year absolute none"),
        ("\"모레\"라고 했다", "ask:noExpression"),
        ("모레라는 연락을 받았다", "2040-10-12..2040-10-12 exact relative none"),
        ("모레란, 멀다", "2040-10-12..2040-10-12 exact relative none"),
        ("잔치는 다음 주라고 했다", "2040-10-15..2040-10-21 month relative none"),
        ("모임이 모레라는 소식을 들었다", "2040-10-12..2040-10-12 exact relative none"),
        ("2033년이라는 해에 심었다", "2033-01-01..2033-12-31 year absolute none"),
        ("작년이라는 게 멀다", "2039-01-01..2039-12-31 year relative none"),
        ("삼촌이 모레라는 배를 탔다", "ask:noExpression"),
        ("작년 여름이라는 노래를 불렀다", "ask:noExpression"),
        ("'87년에 우물을 팠다", "1987-01-01..1987-12-31 year absolute none"),
        ("모임이 모레라는데 바쁘다", "2040-10-12..2040-10-12 exact relative none"),
    ])
    func namesAndQuotes(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 이름 · 인용은 손 넷이 같이 가린다.
    @Test func quotesForEveryHand() {
        let now = day("2040-10-10")
        #expect(SpokenReading.day("『그저께』라는 연극을 봤다", now: now, zone: zone) == nil)
        #expect(SpokenReading.day("지난달에 「모레」라는 노래를 불렀다", now: now, zone: zone)?.text == "2040-09-01")
        #expect(SpokenReading.end("「3월부터 5월까지」라는 노래를 불렀다", start: nil, now: now, zone: zone) == nil)
        #expect(!SpokenReading.hasSpanSignal("『3월부터 5월까지』를 읽었다"))
        #expect(SpokenReading.hasSpanSignal("\"3월부터 5월까지 쉬었다\""))
    }

    /// 말 고침 — 정정 표지 앞의 때를 가리고 나중 것을 읽는다 · 표지 뒤에 때가 없으면 걸리지 않는다 · 때가 아닌 것의 정정은 아니다.
    @Test(arguments: [
        ("4년 전 아니 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전이 아니라 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전은 아니고 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전, 아니다, 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전, 정정할게, 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전, 다시 말하면 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전에 우물을 팠다. 아니, 6년 전에.", "2034-01-01..2034-12-31 year relative none"),
        ("4년 전. 아니다. 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        ("그저께 심은 게 아니라 어제 심었다", "2040-10-09..2040-10-09 exact relative none"),
        ("4년 전은 아니고 옛날에 팠다", "ask:unbounded"),
        ("그저께 아니 어릴 때 심었다", "ask:needsBirth"),
        ("작년 3월 아니 4월에 심었다", "2039-04-01..2039-04-30 month relative none"),
        ("2033년 3월이 아니라 5월에 심었다", "2033-05-01..2033-05-31 month absolute none"),
        ("3월 2일 아니 3일에 심었다", "2040-03-03..2040-03-03 exact absolute none"),
        ("작년 여름 아니 가을에 심었다", "2039-09-01..2039-11-30 circa relative+season soft"),
        ("지난달에 아니 그럴 리가 없다", "2040-09-01..2040-09-30 month relative none"),
        ("그저께 이게 아니고 모레 먹는다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 그게 아니라 모레 먹는다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 밥 아니 떡을 모레 먹는다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께, 아니 떡을 모레 먹는다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 바다 아니고 모레 산에 간다", "2040-10-08..2040-10-08 exact relative none"),
        ("2041년 아니 2042년 아니 2043년 아니 2044년 아니 2045년 아니 2046년 아니 2047년 아니 2048년에 심었다", "2041-01-01..2041-12-31 year absolute none"),
        ("작년, 아니 4월에 심었다", "2039-04-01..2039-04-30 month relative none"),
        ("작년에 아니 글쎄 예전에 심었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년에 아니나 다를까 시들었다", "2039-01-01..2039-12-31 year relative none"),
        ("그저께 감나무가 아니라 밤나무를 심었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 감나무가 아니라 밤나무를 심고 어제 물을 줬다", "2040-10-08..2040-10-08 exact relative none"),
        ("2033년 3월 2일부터 5일 아니 7일 까지 쉬었다", "2033-03-02..2033-03-07 month absolute none"),
        ("작년 일은 내 잘못이 아니다. 그저께 들었다.", "2040-10-08..2040-10-08 exact relative none"),
    ])
    func correctionTakesLater(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 끝 날도 고친 글에서 읽는다 — 끝만 고치면 시작의 해를 잇는다.
    @Test func correctedEnd() {
        let now = day("2040-10-10"), s = "2033년 3월부터 5월 아니 6월까지 쉬었다"
        #expect(said(s) == "2033-03-01..2033-06-30 year absolute none")
        let a = SpokenReading.day(s, now: now, zone: zone)
        #expect(a?.text == "2033-03-01")
        #expect(SpokenReading.end(s, start: a, now: now, zone: zone)?.text == "2033-06-01")
    }

    /// 고름 · 망설임 — 맞닿거나 겹치면 합친 구간(흐림) · 떨어지면 묻는다.
    @Test(arguments: [
        ("작년이었나 올해였나 우물을 팠다", "2039-01-01..2040-12-31 period relative soft"),
        ("작년인지 재작년인지 우물을 팠다", "2038-01-01..2039-12-31 period relative soft"),
        ("작년이나 재작년에 우물을 팠다", "2038-01-01..2039-12-31 period relative soft"),
        ("그저께 아니면 어제 심었다", "2040-10-08..2040-10-09 circa relative soft"),
        ("어제 아니면 그저께 아니면 3일 전에 심었다", "2040-10-07..2040-10-09 circa relative soft"),
        ("그저께 저녁이나 어제 아침에 심었다", "2040-10-08..2040-10-09 circa relative soft"),
        ("작년 3월이나 4월에 심었다", "2039-03-01..2039-04-30 circa relative soft"),
        ("작년 여름이나 가을에 심었다", "2039-06-01..2039-11-30 circa relative+season soft"),
        ("3월 2일이나 3일에 심었다", "2040-03-02..2040-03-03 circa absolute soft"),
        ("3월 2일이나 9일에 심었다", "ask:conflict"),
        ("올해 아니면 7년 전에 심었다", "ask:conflict"),
        ("그저께 아니면 모레 심는다", "ask:conflict"),
        ("4년 전 아니면 6년 전에 심었다", "ask:conflict"),
    ])
    func choiceMergesOrAsks(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    @Test func ageChoice() {
        #expect(said("서른 살이나 서른한 살 때 옮겼다", "born", now: later) == "2079-01-01..2081-12-31 period age soft")
        #expect(said("고2 때인지 고3 때인지 옮겼다", "born", now: later) == "2067-03-01..2069-02-28 period grade soft")
    }

    /// 겹치지 않는 사건의 때 둘 = 묻기 + 후보(나온 차례) · 겹치면 지금처럼 좁힌다.
    @Test func twoTimesAsk() {
        let cases: [(String, String, [String])] = [
            ("30년 전, 내가 30대에 우물을 팠다", "born", ["2060-01-01..2060-12-31", "2079-01-01..2089-12-31"]),
            ("내가 30대에, 30년 전에 우물을 팠다", "born", ["2079-01-01..2089-12-31", "2060-01-01..2060-12-31"]),
            ("어제, 그저께, 어제에 심었다", "none", ["2090-10-09..2090-10-09", "2090-10-08..2090-10-08"]),
            ("매일 걷는다. 재작년 그리고 올해 거뒀다.", "none", ["2088-01-01..2088-12-31", "2090-01-01..2090-12-31"]),
            ("작년, 재작년 때 온실을 지었다", "none", ["2089-01-01..2089-12-31", "2088-01-01..2088-12-31"]),
            ("재작년 그리고 올해 거뒀다", "none", ["2088-01-01..2088-12-31", "2090-01-01..2090-12-31"]),
            ("스무 살 때 그리고 서른 살 때 걸었다", "born", ["2069-01-01..2070-12-31", "2079-01-01..2080-12-31"]),
            ("3월 그리고 8월에 거뒀다", "none", ["2090-03-01..2090-03-31", "2090-08-01..2090-08-31"]),
            ("올해 2월 3일 그리고 내년3월5일에 걸었다", "none", ["2090-02-03..2090-02-03", "2091-03-05..2091-03-05"]),
            ("재작년 그리고 올해 3월에 거뒀다", "none", ["2088-01-01..2088-12-31", "2090-03-01..2090-03-31"]),
            ("그저께 그리고 어제, 어제 또 줬다", "none", ["2090-10-08..2090-10-08", "2090-10-09..2090-10-09"]),
            ("스무 살 때 그리고 서른 살 때 매주 걸었다", "born", ["2069-01-01..2070-12-31", "2079-01-01..2080-12-31"]),
            ("올해 3월 그리고 작년에 심었다", "none", ["2090-03-01..2090-03-31", "2089-01-01..2089-12-31"]),
            ("작년 3월이나 7월에 심었다. 올해 거뒀다.", "none", ["2089-03-01..2089-03-31", "2089-07-01..2089-07-31"]),
            ("2085년 아니면 2088년 말에 심었다", "none", ["2085-01-01..2085-12-31", "2088-10-01..2088-12-31"]),
            ("올해 아니면 7년 전에 심었다", "none", ["2090-01-01..2090-12-31", "2083-01-01..2083-12-31"]),
        ]
        for (s, c, expect) in cases {
            #expect(said(s, c, now: later) == "ask:conflict", "\(s)")
            #expect(rivals(s, c, now: later) == expect, "\(s)")
        }
        #expect(said("2068년 고3 때 옮겼다", "born", now: later) == "2068-03-01..2068-12-31 year absolute+grade none")
        guard case .ask(let a) = spoken("30년 전, 내가 30대에 우물을 팠다", "born", now: later) else { Issue.record("묻기가 아니다"); return }
        #expect(a.rule == "conflict" && a.direction == nil && a.candidates.map(\.phrase) == ["30년전", "30대"])
        guard case .ask(let b) = spoken("작년 그리고 올해쯤 거뒀다", now: later) else { Issue.record("묻기가 아니다"); return }
        #expect(b.candidates.map(\.soft) == [false, true])   // 후보는 저마다 제 글만 읽는다
        #expect(SpokenReading.day("재작년 그리고 올해 거뒀다", now: day(later), zone: zone) == nil)   // 날 하나는 고르지 않는다
    }

    /// 다투지 않는 둘 — 날 단위 뒤의 해 없는 달 · 다른 문장 · 맞서는 마디 · 「뒤 · 전」의 폭 · 견줌 · 낱말 가운데의 글꼴 · 때 표지 없는 나이.
    @Test(arguments: [
        ("그저께 3월 모종을 골랐다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("2085년 3월에 심어서 8월에 거뒀다", "none", "2085-03-01..2085-03-31 month absolute none"),
        ("그저께 심었다. 작년에도 심었다.", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("작년 이맘때 모였는데 올해도 모인다", "none", "2089-10-01..2089-10-31 circa relative soft"),
        ("결혼하고 나서 2085년에 옮겼다", "full", "2085-01-01..2085-12-31 year absolute none"),
        ("결혼 전에 2077년에 옮겼다", "full", "2077-01-01..2077-12-31 year absolute none"),
        ("신혼 때는 곁방세 살았다", "full", "2081-10-10..2083-10-09 period lifeEvent soft"),
        ("작년에 살던 집에서 곁방세 살았다", "born", "2089-01-01..2089-12-31 year relative none"),
        ("그저께 팔을 재수술했다", "born", "2090-10-08..2090-10-08 exact relative none"),
        ("2071년 고3 때 옮겼다", "born", "2071-01-01..2071-12-31 year absolute none"),
        ("결혼하기 전에 2085년에 옮겼다", "full", "2085-01-01..2085-12-31 year absolute none"),
        ("내년 달력이 그저께 왔다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("4년 전 그저께 옮겼다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("두 살이나 다섯 살 어린 사촌이 왔다", "born", "2051-01-01..2052-12-31 period age soft"),
        ("5년 전 3월에 옮겼다", "none", "2085-03-01..2085-03-31 month relative none"),
        ("고3 때 5월 잔치에 갔다", "born", "2068-05-01..2068-05-31 month grade none"),
        ("80년대 노래를 고3 때 들었다", "born", "2068-03-01..2069-02-28 year grade none"),
        ("내 어릴 때 일이 떠오른다", "born", "2050-05-10..2063-02-28 period era soft"),
        ("그저께에. 작년에도 심었다.", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께에 푸른어제는 들렸다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("지난주 금요일에 산 책을 3일 후배에게 줬다", "none", "2090-10-06..2090-10-06 exact relative none"),
        ("지난주 금요일에 산 책은 어제보다 비싸다", "none", "2090-10-06..2090-10-06 exact relative none"),
        ("지난주 금요일에 산 책을 내 어릴 때 일로 여겼다", "born", "2090-10-06..2090-10-06 exact relative none"),
        ("5년 전에, 3월에 옮겼다", "none", "2090-03-01..2090-03-31 month absolute none"),
        ("80년대에, 고3 때는 놀았다", "born", "2080-01-01..2089-12-31 period absolute soft"),
        ("재작년에 심어 올해는 거뒀다", "none", "2088-01-01..2088-12-31 year relative none"),
        ("재작년에 앓다가 올해는 나았다", "none", "2088-01-01..2088-12-31 year relative none"),
        ("재작년에 만나 올해는 헤어졌다", "none", "2088-01-01..2088-12-31 year relative none"),
        ("그저께에 본 뒤 어제는 쉬었다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("비가 와 그저께 쉬었다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("수능 끝나고는 1967년 12월에 걸었다", "early", "1967-12-01..1967-12-31 month absolute none"),
        ("수능 끝나고 1967년 12월에 걸었다", "early", "1967-12-01..1967-12-31 month absolute none"),
        ("두 살 어린 사촌을 그저께 만났다", "born", "2090-10-08..2090-10-08 exact relative none"),
        ("고3 사촌이 그저께 다녀갔다", "born", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께 작년보다 더웠다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("3년 후배를 그저께 만났다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("모레 들른다고 그저께 말했다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께 80년대 노래가 들렸다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께 푸른어제가 들렸다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께 내 일이 끝났다", "none", "2090-10-08..2090-10-08 exact relative none"),
        ("그저께 80년대 노래를 틀었다", "none", "2090-10-08..2090-10-08 exact relative none"),
    ])
    func notRivals(_ s: String, _ c: String, _ expect: String) { #expect(said(s, c, now: later) == expect, "\(s)") }

    /// 잇는 꼴로 이은 겹치지 않는 두 때는 묻지 않는다 — 읽는 차례가 고른 하나 그대로(「그리고」는 잇는 꼴이 아니라 나란히 세운 것이라 묻는다).
    @Test(arguments: [
        ("재작년에 심어서 올해 거뒀다", "2038-01-01..2038-12-31 year relative none"),
        ("재작년에 사서 올해 거뒀다", "2038-01-01..2038-12-31 year relative none"),
        ("2033년에 만나고 2036년에 헤어졌다", "2033-01-01..2033-12-31 year absolute none"),
        ("2033년에 심고서 2036년에 거뒀다", "2033-01-01..2033-12-31 year absolute none"),
        ("2033년에 심고 나서 2036년에 거뒀다", "2033-01-01..2033-12-31 year absolute none"),
        ("그저께 앓다가 오늘 나았다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년에 심었는데 올해 시들었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년에 추운데 올해 따뜻하다", "2039-01-01..2039-12-31 year relative none"),
        ("2033년에 심었지만 2036년에 시들었다", "2033-01-01..2033-12-31 year absolute none"),
        ("작년에 이어 올해도 심었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년에 이어서 올해도 심었다", "2039-01-01..2039-12-31 year relative none"),
        ("2033년에 심고 1년 뒤에 거뒀다", "2033-01-01..2033-12-31 year absolute none"),
        ("지난달에 다쳐서 어제 나았다", "2040-10-09..2040-10-09 exact relative none"),
        ("4년 전에 옮기고 2039년에 또 옮겼다", "2039-01-01..2039-12-31 year absolute none"),
        ("3월에 심어서 8월에 거뒀다", "2040-03-01..2040-03-31 month absolute none"),
        ("그저께 그리고 어제 심었다", "ask:conflict"),
        ("작년, 재작년에 심었다", "ask:conflict"),
        ("작년 마을에서 그저께 들에서 걸었다", "2040-10-08..2040-10-08 exact relative none"),
    ])
    func joinedClausesKeepOneReading(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 나이 · 나잇대 범위 — A 의 처음 … B 의 끝(끝을 버리지 않는다) · 해 · 달의 「A에서 B 사이 · A~B」는 읽는 차례 그대로.
    @Test(arguments: [
        ("33살에서 36살 사이에 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("33살부터 36살 사이에 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("33살부터 36살까지 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("33에서 36살 사이에 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("33~36살 때 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("서른셋에서 서른여섯 사이에 공방을 열었다", "born", "2082-01-01..2086-12-31 period age soft"),
        ("만 33세에서 36세 사이에 공방을 열었다", "born", "2083-05-10..2087-05-09 period age none"),
        ("33살에서 36살 사이에 공방을 열었다", "none", "ask:needsBirth"),
        ("20대에서 30대 사이에 공방을 열었다", "born", "2069-01-01..2089-12-31 period ageBand soft"),
        ("2081년에서 2084년 사이에 공방을 열었다", "none", "2081-01-01..2081-12-31 year absolute none"),
        ("2081년~2084년에 공방을 열었다", "none", "2081-01-01..2084-12-31 period absolute none"),
        ("2081년 3월에서 5월 사이에 공방을 열었다", "none", "2081-03-01..2081-03-31 month absolute none"),
    ])
    func rangesKeepTheEnd(_ s: String, _ c: String, _ expect: String) { #expect(said(s, c, now: later) == expect, "\(s)") }

    /// 「전후」는 쯤 · 무렵과 같은 흐림 — 넓히지 않고 「N년 전」의 「전」으로 읽지 않는다.
    @Test(arguments: [
        ("2081년 전후에 옮겼다", "none", "2081-01-01..2081-12-31 circa absolute soft"),
        ("88년 전후에 옮겼다", "none", "ask:noExpression"),
        ("3일 전후로 닿는다", "none", "ask:noExpression"),
        ("10년 전 후배가 왔다", "none", "2080-01-01..2080-12-31 year relative none"),
        ("3일 전 후기를 적었다", "none", "2090-10-07..2090-10-07 exact relative none"),
        ("몇 년 전후로 닿는다", "none", "ask:noExpression"),
        ("서른 살 전후에 옮겼다", "born", "2079-01-01..2080-12-31 period age soft"),
        ("30대 전후에 옮겼다", "born", "2079-01-01..2089-12-31 period ageBand soft"),
        ("결혼 전후에 옮겼다", "full", "2081-10-10..2081-10-10 exact lifeEvent soft"),
    ])
    func beforeAndAfterIsVague(_ s: String, _ c: String, _ expect: String) { #expect(said(s, c, now: later) == expect, "\(s)") }

    /// 꾸미는 때 — 이름씨를 꾸미는 때 · 목적어 덩이의 때는 다른 때에 진다 · 홀로면 문장의 때다(흐림을 붙이지 않는다).
    @Test(arguments: [
        ("그저께 삼촌이 4일 전 이야기를 꺼냈다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 4일 전 이야기를 꺼냈다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께! 4일 전 이야기를 꺼냈다", "2040-10-06..2040-10-06 exact relative none"),
        ("그저께 그림을 4일 전 사진을 보고 그렸다", "2040-10-06..2040-10-06 exact relative none"),
        ("그저께 산 배 모레 판다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 배를 산 동무를 모레 또 만난다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 만난 동무랑 모레 볼 그림을 골랐다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 만난 동무랑 모레 볼 그림이 비싸다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 산 배를 모레로 미뤘다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년 동무를 만나 지난주에 떠났다", "2039-01-01..2039-12-31 year relative none"),
        ("5월이나 2031년에 심었다", "2031-01-01..2031-12-31 year absolute none"),
        ("재작년, 내가 어제 심었다", "2040-10-09..2040-10-09 exact relative none"),
        ("작년, 섬을 떠나 올해에 심었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 본 뒤 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 뒤지자마자 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("재작년 그리고 올해 거뒀다고 했다", "2038-01-01..2038-12-31 year relative none"),
        ("재작년, 서울에서 문어제에 갔다", "2040-10-09..2040-10-09 exact relative none"),
        ("삼촌이 4일 전에 산 배를 그저께 되팔았다", "2040-10-08..2040-10-08 exact relative none"),
        ("4일 전 옆집에서 받은 배를 그저께 팔았다", "2040-10-06..2040-10-06 exact relative none"),
        ("4년 전에 타던 배를 작년에 팔았다", "2039-01-01..2039-12-31 year relative none"),
        ("4년 전에 타던 배를 팔고 올해 새 배를 샀다", "2040-01-01..2040-12-31 year relative none"),
        ("2033년에 타던 배를 작년에 팔았다", "2039-01-01..2039-12-31 year relative none"),
        ("2033년에 심는 나무를 작년에 적었다", "2033-01-01..2033-12-31 year absolute none"),
        ("2033년의 장부를 지난주에 찾았다", "2040-10-01..2040-10-07 month relative none"),
        ("2033년산 배를 작년에 땄다", "2033-01-01..2033-12-31 year absolute none"),
        ("지난주에 2033년 장부를 찾았다", "2040-10-01..2040-10-07 month relative none"),
        ("그저께 작년을 돌아봤다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년 장부를 그저께 찾았다", "2040-10-08..2040-10-08 exact relative none"),
        ("4년 전에 타던 배를 그린다", "2036-01-01..2036-12-31 year relative none"),     // 홀로 선 꾸미는 때는 문장의 때(흐림을 붙이지 않는다)
        ("4년 전에 탔던 배를 그린다", "2036-01-01..2036-12-31 year relative none"),
        ("작년에 다니던 서당을 그만뒀다", "2039-01-01..2039-12-31 year relative none"),
        ("2033년에 옮기던 날을 그저께 떠올렸다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년에 있었던 일을 그저께 들었다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년에 다니던 서당을 그저께 그만뒀다", "2040-10-08..2040-10-08 exact relative none"),
        ("1930년대에 만든 시계를 샀다", "1930-01-01..1939-12-31 period absolute soft"),
        ("작년에 1930년대에 만든 시계를 샀다", "2039-01-01..2039-12-31 year relative none"),
        ("4년 전에 타던 배가 요즘 떠오른다", "2036-01-01..2036-12-31 year relative none"),
        ("4년 전에 타던 배를 언젠가 사겠다", "2036-01-01..2036-12-31 year relative none"),
        ("4년 전에 있었던 일을 적는다", "2036-01-01..2036-12-31 year relative none"),
        ("2033년에 옮기던 날 눈이 왔다", "2033-01-01..2033-12-31 year absolute none"),
        ("2033년에 탔던 것 같다", "2033-01-01..2033-12-31 year absolute none"),
        ("2030년대 초반에 살던 골목이 헐렸다", "2030-01-01..2033-12-31 period absolute soft"),
        ("작년에 큰 배를 샀다", "2039-01-01..2039-12-31 year relative none"),
        ("형이 4년 전에 배를 샀다", "2036-01-01..2036-12-31 year relative none"),
        ("작년에 동무랑 그저께 그림을 봤다", "2040-10-08..2040-10-08 exact relative none"),
        ("2033년 여름에 갔던 섬을 작년 가을에 또 갔다", "2039-09-01..2039-11-30 circa relative+season soft"),
        ("작년에 타던 배를 팔고 올해 새 배를 샀다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 책을 지난주에 산 의자에서 읽었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년에 동무가 그저께 산 옷을 입었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 누나는 떡을 어제 먹었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 난 산불 소식 어제 들었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 작은 사고 나 어제 쉬었다", "2040-10-08..2040-10-08 exact relative none"),
        ("재작년이나 작년에 살던 집을 올해에 지나갔다", "2040-01-01..2040-12-31 year relative none"),
        ("작년 장부를 찾고 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾고서 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾아서 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾았는데 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾았지만 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾다가 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 찾았다 지난주에 적었다", "2039-01-01..2039-12-31 year relative none"),
        ("작년 장부를 지난주에 적었다", "2040-10-01..2040-10-07 month relative none"),
        ("작년에 타던 배를 그저께 팔았다", "2040-10-08..2040-10-08 exact relative none"),
        ("3월에 병원 갔다 8월에 또 갔다", "2040-03-01..2040-03-31 month absolute none"),
        ("2033년에 부산 갔다 2036년에 또 갔다", "2033-01-01..2033-12-31 year absolute none"),
        ("작년에 일본 여행을 예약해 올해 갔다", "2039-01-01..2039-12-31 year relative none"),
        ("그저께 아내는 작년에 산 옷을 입었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 아내는 쉬었다. 작년에도 쉬었다.", "2040-10-08..2040-10-08 exact relative none"),
        ("작년이나 재작년에 타던 배를 그저께 팔았다", "2040-10-08..2040-10-08 exact relative none"),
        ("2033년~2035년에 살던 집을 그저께 지나갔다", "2040-10-08..2040-10-08 exact relative none"),
        ("올해 3월에 작년에 타던 배를 팔았다", "2039-03-01..2039-03-31 month relative none"),
        ("그저께 모레 들른다고 말했다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년에 산 배를 동생뻘 사촌이 그저께 망가뜨렸다", "2040-10-08..2040-10-08 exact relative none"),
        ("2033년에 심는 나무를 그린 책을 작년에 샀다", "2033-01-01..2033-12-31 year absolute none"),
        ("작년에 산 배를 팔고 그저께 새 배를 샀다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 장부를 읽고 어제 신문을 읽었다", "2040-10-08..2040-10-08 exact relative none"),
        ("작년에 런던 거리를 걸었다", "2039-01-01..2039-12-31 year relative none"),
    ])
    func describingTimeYields(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 토씨 없는 때 + 받침 ㄴ 관형 + 이름씨 — 그 이름씨 바로 뒤(또는 때 바로 앞)에 또렷한 사건의 때가 서면 이름씨의 때다 ·
    /// 사이에 풀이말이 끼면 두 사건이라 읽는 차례 그대로 · 뒤의 때가 또렷하지 않으면(옮긴 끝 · 다른 이름씨를 꾸밈) 읽는 차례 그대로.
    @Test(arguments: [
        ("그저께 만난 동무랑 모레 또 만나기로 했다", "2040-10-12..2040-10-12 exact relative none"),
        ("그저께 산 책을 어제 읽었다", "2040-10-09..2040-10-09 exact relative none"),
        ("그저께 들른 나그네가 모레 또 온다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 삼촌이 준 책을 어제 읽었다", "2040-10-09..2040-10-09 exact relative none"),
        ("그저께 쑨 팥죽 냄새가 어제 났다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 앓은 조카가 오늘은 나았다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 산 팽이 어제 돌렸다", "2040-10-09..2040-10-09 exact relative none"),
        ("모레 그저께 못 한 빨래를 한다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 만난 동무랑 다음 주에 또 만난다", "2040-10-15..2040-10-21 month relative none"),
        ("모레 어제 만난 동무를 안 만난다", "2040-10-12..2040-10-12 exact relative none"),
        ("그저께 산 책을 모레 안 읽는다", "2040-10-12..2040-10-12 exact relative none"),
        ("그저께 많은 비가 와 어제 쉬었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 작은 화분을 사서 어제 심었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 새 신발을 어제 빨았다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 사진 찍어 어제 걸었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 본 뒤 어제 또 봤다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 급한 모임이 모레로 밀렸다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 친한 동무랑 모레 볼 연극이 밀렸다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 늦은 밤 어제 못 한 빨래를 했다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 친한 동무랑 모레 볼 연극을 골랐다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 친한 동무가 4일 전 이야기를 꺼냈다", "2040-10-06..2040-10-06 exact relative none"),
        ("그저께 맛있는 떡을 먹고 어제는 굶었다", "2040-10-08..2040-10-08 exact relative none"),
        ("그저께 맛있는 떡을 어제 또 먹었다", "2040-10-08..2040-10-08 exact relative none"),
    ])
    func bareTimeDescribesNoun(_ s: String, _ expect: String) { #expect(said(s) == expect, "\(s)") }

    /// 임자말 「은 · 는」은 관형이 아니다 — 앞 사건의 때를 버리고 뒤의 때를 짓지 않는다(격자 900 줄).
    @Test func topicIsNotDescribing() {
        let who = ["형은", "남편은", "조카는", "아내는", "엄마는", "선생님은", "회사는", "강아지는", "삼촌은", "언니는", "동무는", "아들은", "팀장은", "할머니는", "고양이는"]
        let what = [("사촌이", "들른다고 말했다"), ("차를", "바꾼다고 말했다"), ("휴가를", "낸다고 했대"), ("동무가", "온다고 들었다"), ("학교에", "간다"), ("병원에", "갈 거다"),
                    ("편지를", "받았다"), ("돈을", "빌린대"), ("산에", "오른다"), ("일을", "마친다"), ("짐을", "보냈다고 한다"), ("책을", "읽자고 했다")]
        for w in who { for (o, v) in what { for t in ["모레", "내일", "내년에", "다음 주에", "오늘"] {
            let s = "그저께 \(w) \(o) \(t) \(v)"
            #expect(said(s) == "2040-10-08..2040-10-08 exact relative none", "\(s)")
        } } }
    }
    /// 이름씨 · 그림씨와 꼴이 겹치는 관형도 보지 않는다 · 옮긴 말이 든 문장은 읽는 차례 그대로.
    @Test func unclearDescribingIsLeft() {
        for x in ["병원 의사가", "부산 동무가", "사진 이야기를", "남편 동생뻘이", "중요한 모임을", "급한 일을", "친한 동무랑", "힘든 일을", "고마운 사람을", "화난 형이", "신난 아이가", "어린 조카를",
                  "느린 수레를", "맛있는 떡을", "큰 가방을", "받은 편지를", "먹은 밥이", "주문한 책을", "찍은 그림을", "가는 길을", "런던 거리를", "장난 전화를", "산 근처를", "산 위에서", "간 검사를", "본 건물을", "온 집안이", "판 위를", "쓴 커피를", "만난 지", "모던 찻집을", "바이올린 수업을", "기린 인형을", "치킨 냄새를", "지난 모임을", "피난 이야기를", "가든 모임을"] {
            for t in ["모레", "오늘", "내년에"] {
                let s = "그저께 \(x) \(t) 또 봤다"
                #expect(said(s) == "2040-10-08..2040-10-08 exact relative none", "\(s)")
            }
        }
        #expect(said("그저께 만난 형이 모레 온다고 말했다") == "2040-10-08..2040-10-08 exact relative none")
        #expect(said("그저께 온 나그네가 모레 또 온대") == "2040-10-08..2040-10-08 exact relative none")
    }
    /// 긴 글 — 되풀이 뒤에 다른 때가 와도 길이만큼만(400 번에 0.5 초 안 · 4,000 번에 멈추지 않는다).
    @Test func longTextIsBounded() {
        for (unit, end) in [("작년에 산 배를 ", "그저께 팔았다"), ("아니 6년 전 ", "팠다"), ("어제 아니면 ", "그저께 심었다"), ("20대 ", "에 팠다"), ("작년보다 ", "올해가 낫다"), ("4년 전 5월에 산 배를 ", "그저께 팔았다"), ("5월 3일~8일 ", "쉬었다"),
                            ("고3 때 6월 ", "팠다"), ("작년 봄이었나 재작년 봄이었나 ", "심었다"), ("내 일 ", "내일 마친다"), ("두 살 어린 ", "동무")] {
            let start = spent()
            _ = said(String(repeating: unit, count: 400) + end)
            #expect(spent() - start < 0.5, "\(unit)")
            _ = said(String(repeating: unit, count: 4000) + end)
        }
    }

    @Test func lifeTimeInObject() {
        #expect(said("고3 때 80년대 노래를 들었다", "born", now: later) == "2068-03-01..2069-02-28 year grade none")
        #expect(said("스무 살 때 그린 그림을 그저께 찾았다", "born", now: later) == "2090-10-08..2090-10-08 exact relative none")
        // 어느 쪽이 꾸미는지 또렷하지 않으면 읽는 차례 그대로 — 「그저께 …을」을 걷고 생년의 때를 고르지 않는다
        for s in ["고등학교 때 동무가 그저께 밥을 샀다", "고등학교 때 동무랑 그저께 그림을 봤다"] {
            #expect(said(s, "born", now: later) == "2090-10-08..2090-10-08 exact relative none", "\(s)")
        }
        #expect(said("작년에 산 배를 고등학교 때 동무에게 줬다", "born", now: later) == "2089-01-01..2089-12-31 year relative none")
        #expect(said("고등학교 때 동무를 그저께 만났다", "born", now: later) == "2090-10-08..2090-10-08 exact relative none")
        #expect(said("고등학교 때에 알던 동무가 있다", "born", now: later) == "2066-03-01..2069-02-28 period schoolStage soft")
        #expect(said("고등학교 때 알던 동무가 있다", "born", now: later) == "2066-03-01..2069-02-28 period schoolStage soft")
    }

    /// 「N년 안에 · 이내에」 = 앞일이면 「N년 뒤」와 같은 자리 · 흐림(상한을 점으로) · 지난 일이면 햇수.
    @Test(arguments: [
        ("6년 안에 배를 사고 싶다", "2046-01-01..2046-12-31 circa relative soft"),
        ("6년 이내에 배를 사고 싶다", "2046-01-01..2046-12-31 circa relative soft"),
        ("6년 안에는 배를 사고 싶다", "2046-01-01..2046-12-31 circa relative soft"),
        ("5달 안에 배를 사고 싶다", "2041-03-01..2041-03-31 circa relative soft"),
        ("반년 안에 배를 사고 싶다", "2041-04-01..2041-04-30 circa relative soft"),
        ("2주 안에 배를 사고 싶다", "2040-10-24..2040-10-24 exact relative soft"),
        ("사흘 안에 배를 사고 싶다", "2040-10-13..2040-10-13 exact relative soft"),
        ("12일 안에 배를 사고 싶다", "2040-10-22..2040-10-22 exact relative soft"),
        ("올해 안에 4년 전에 빌린 배를 돌려준다", "2040-01-01..2040-12-31 year relative none"),
        ("4년 전에, 6년 안에 떠난다", "2036-01-01..2036-12-31 year relative none"),
        ("4년 전에 빌린 배를 6년 안에 돌려준다", "2046-01-01..2046-12-31 circa relative soft"),
        ("5년 안에 결혼하고 싶다", "2045-01-01..2045-12-31 circa relative soft"),
        ("2년 안에 5월에 떠난다", "2041-05-01..2041-05-31 month absolute none"),
        ("집 안에 배를 두고 싶다", "ask:noExpression"),
        ("6년 안 됐다", "ask:noExpression"),
        ("12월 3일 안에 떠난다", "2040-12-03..2040-12-03 exact absolute none"),
    ])
    func withinIsThePointAhead(_ s: String, _ expect: String) { #expect(said(s, direction: .future) == expect, "\(s)") }

    /// 상한 안에 생년으로 읽은 때가 있으면 그 때다.
    @Test func withinYieldsToAge() {
        #expect(said("10년 안에 마흔다섯 살 때 배를 산다", "born", now: later, direction: .future) == "2094-01-01..2095-12-31 period age soft")
    }

    @Test func withinAfterAnEvent() {
        #expect(said("결혼하고 5년 안에 배를 산다", direction: .future) == "ask:needsAnchor:wedding")   // 그 사건부터 센 것 — 오늘부터 세지 않는다
        #expect(said("20대에 5년 안에 배를 산다", "born", now: "2075-10-10", direction: .future) == "2069-01-01..2079-12-31 period ageBand soft")
    }
    @Test func withinInThePast() {
        for s in ["6년 안에 배를 세 번 샀다", "사흘 안에 다 읽었다", "6년 이내에 갚았다"] { #expect(said(s) == "ask:noExpression", "\(s)") }
        let d = SpokenReading.day("6년 안에 배를 사고 싶다", now: day("2040-10-10"), zone: zone, direction: .future)
        #expect(d.map { "\($0.text) \($0.precision.rawValue)" } == "2046-01-01 circa")
    }

    /// 방향만 있는 말 — 끝 없는 때(묻기) + 낱말이 품은 방향 · 날은 짓지 않는다 · 주제 · 이름 · 토씨 없는 낱말은 때가 아니다.
    @Test func directionOnly() {
        let cases: [(String, SpokenReading.Direction?)] = [
            ("미래에 배를 사겠다", .future), ("먼 미래에는 배를 사겠다", .future), ("미래엔 배를 사겠다", .future), ("나중에 배를 사겠다", .future),
            ("훗날 배를 사겠다", .future), ("다음에 배를 사겠다", .future),
            ("과거에 배를 탔다", .past), ("과거엔 배를 탔다", .past), ("예전에 배를 탔다", .past), ("옛날에 배를 탔다", .past), ("오래전 배를 탔다", .past),
            ("한참 전에 배를 탔다", .past), ("몇 년 전에 배를 탔다", .past),
            ("언젠가 배를 사겠다", nil), ("그때 배를 탔다", nil), ("나중에 예전 배를 사겠다", nil),
        ]
        for (s, expect) in cases {
            for hint in SpokenReading.Direction.allCases {
                guard case .ask(let a) = spoken(s, direction: hint) else { Issue.record("묻기가 아니다 — \(s)"); continue }
                #expect(a.reason == .unbounded && a.direction == expect && a.candidates.isEmpty && a.rule == "vague", "\(s)")
            }
        }
        for s in ["미래에 대한 그림을 그렸다", "과거에 관해 물었다", "미래에셋을 지났다", "미래 그림을 그렸다", "과거에서 온 편지를 읽었다"] {
            guard case .ask(let a) = spoken(s) else { Issue.record("묻기가 아니다 — \(s)"); continue }
            #expect(a.reason == .noExpression && a.direction == nil, "\(s)")
        }
        #expect(said("과거에 배를 작년에 탔다") == "2039-01-01..2039-12-31 year relative none")
    }

    /// 맞은 토막 — 문장 전체가 아니라 때로 읽은 글자만(빈칸을 뺀다).
    @Test(arguments: [
        ("우리는 그저께 연못을 팠다", "그저께"),
        ("우리는 4년 전에 연못을 팠다", "4년전"),
        ("우리는 작년 여름에 연못을 팠다", "작년여름"),
        ("우리는 작년에 연못을 5월에 팠다", "작년5월"),
        ("우리는 2033년 3월 2일에 연못을 팠다", "2033년3월2일"),
        ("우리는 73년 6월에 연못을 팠다", "73년6월"),
        ("우리는 2033년쯤 연못을 팠다", "2033년쯤"),
        ("우리는 작년 말에 연못을 팠다", "작년말"),
        ("우리는 지난주에 연못을 팠다", "지난주"),
        ("우리는 80년대 말에 연못을 팠다", "80년대말"),
        ("우리는 최근에 연못을 팠다", "최근"),
        ("우리는 3월 3일부터 5일까지 연못을 팠다", "3월3일부터5일까지"),
        ("우리는 그저께 아니면 어제 연못을 팠다", "그저께어제"),
        ("우리는 4년 전 아니 6년 전에 연못을 팠다", "6년전"),
        ("그저께 매주 들르던 꽃집에 들렀다", "그저께"),
        ("2033년에 10년에 한 번 피는 꽃을 봤다", "2033년"),
    ])
    func phraseIsTheMatch(_ s: String, _ expect: String) {
        guard case .span(let r) = spoken(s) else { Issue.record("구간이 아니다 — \(s)"); return }
        #expect(r.phrase == expect, "\(s)")
    }
    @Test func phraseOfNarrowed() {
        guard case .span(let r) = spoken("우리는 2068년 고3 때 연못을 팠다", "born", now: later) else { Issue.record("구간이 아니다"); return }
        #expect(r.phrase == "2068년고3")
    }

    /// 토박이 수 뒤의 「세」는 바로 뒤가 「살」일 때만 나이다 — 세우다 · 세다 · 세트 · 세차 · 「세 명」은 아니다(「세」로 세는 나이는 아라비아 수만).
    @Test(arguments: [
        Said("등대 하나 세우자", "ask:noExpression", in: "born", now: later),
        Said("기둥 둘 세워 둬", "ask:noExpression", in: "born", now: later),
        Said("말뚝 셋 세어 보자", "ask:noExpression", in: "born", now: later),
        Said("울타리 여덟 세웠다", "ask:noExpression", in: "born", now: later),
        Said("그릇 열 세트를 샀다", "ask:noExpression", in: "born", now: later),
        Said("수레 하나 세차했다", "ask:noExpression", in: "born", now: later),
        Said("마흔세 개를 옮겼다", "ask:noExpression", in: "born", now: later),
        Said("열세에 몰렸다", "ask:noExpression", in: "born", now: later),
        Said("떡 하나 세 조각", "ask:noExpression", in: "born", now: later),
        Said("두세 번 갔다", "ask:noExpression", in: "born", now: later),
        Said("30대 길목에 등대 하나 세워 줘", "2079-01-01..2089-12-31 period ageBand soft", in: "born", now: later),
        Said("그저께 등대 하나 세웠다", "2090-10-08..2090-10-08 exact relative none", in: "born", now: later),
        Said("열세 살에 배를 탔다", "2062-01-01..2063-12-31 period age soft", in: "born", now: later),
        Said("열 세 살에 배를 탔다", "2062-01-01..2063-12-31 period age soft", in: "born", now: later),
        Said("서른세 살 때 배를 탔다", "2082-01-01..2083-12-31 period age soft", in: "born", now: later),
        Said("두세 살 때 배를 탔다", "2051-01-01..2052-12-31 period age soft", in: "born", now: later),
        Said("만 열세 살에 배를 탔다", "2063-05-10..2064-05-09 year age none", in: "born", now: later),
        Said("만두 세 개", "ask:noExpression", in: "born", now: later),
        Said("30세에 배를 탔다", "2079-01-01..2080-12-31 period age soft", in: "born", now: later),
        Said("3세에서 5세 사이에 섬에 살았다", "2052-01-01..2055-12-31 period age soft", in: "born", now: later),
        Said("열셋에 배를 탔다", "2062-01-01..2063-12-31 period age soft", in: "born", now: later),
        Said("만 서른세에 배를 탔다", "ask:noExpression", in: "born", now: later),
        Said("서른세쯤 모였다", "ask:noExpression", in: "born", now: later),
        Said("열세에서 스물 사이", "ask:noExpression", in: "born", now: later),
    ])
    func nativeSeIsAgeOnlyBeforeSal(_ r: Said) { r.check() }

    /// 정정 표지 앞에 군말(아 · 어 · 음 · 에)이 끼고 쉼표가 있어도 말 고침이다 — 표지 없는 군말은 아니다.
    @Test(arguments: [
        Said("4년 전, 아 아니다, 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        Said("4년 전, 음 아니, 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        Said("4년 전에, 에 아니라 6년 전에 우물을 팠다", "2034-01-01..2034-12-31 year relative none"),
        Said("모레, 어 아니 글피 간다", "2040-10-13..2040-10-13 exact relative none"),
        Said("3월 2일, 아 아니, 3월 5일에 심었다", "2040-03-05..2040-03-05 exact absolute none"),
        Said("30대, 아 아니다, 40대 때 우물을 팠다", "2089-01-01..2099-12-31 period ageBand soft", in: "born", now: later),
        Said("4년 전에 팠다. 아 아니다, 6년 전이다.", "2034-01-01..2034-12-31 year relative none"),
        Said("작년에 아 참 힘들었다", "2039-01-01..2039-12-31 year relative none"),
        Said("그저께 아 아니나 다를까 비가 왔다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께 동무가, 아 아니 형이 왔다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께 동무가 어, 아니라 형이 왔다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께 동무를 봤다, 어 아니라 모레 본다", "2040-10-08..2040-10-08 exact relative none"),
        Said("아 아니다 그저께 갔다", "2040-10-08..2040-10-08 exact relative none"),
    ])
    func correctionWithFiller(_ r: Said) { r.check() }

    /// 붙여 쓴 「어제오늘」은 요즘이라 때가 아니다(띄어 쓴 「어제 오늘」 · 「오늘내일」은 그대로).
    @Test(arguments: [
        Said("어제오늘 생긴 일이 아니다", "ask:noExpression"),
        Said("어제오늘 사이에 꽃이 졌다", "ask:noExpression"),
        Said("어제오늘이 아니라 작년부터 그랬다", "2039-01-01..2039-12-31 year relative none"),
        Said("어제 오늘 내내 바람이 불었다", "2040-10-09..2040-10-09 exact relative none"),
        Said("오늘내일 중으로 심는다", "2040-10-10..2040-10-10 exact relative none"),
        Said("어제오늘내일 바쁘다", "2040-10-09..2040-10-09 exact relative none"),
        Said("그어제오늘 바쁘다", "2040-10-09..2040-10-09 exact relative none"),
    ])
    func daysTogether(_ r: Said) { r.check() }

    /// 해 없는 달 · 날은 바로 앞에 맞닿은 「N년 전 · 뒤 · 후」의 것이다 — 토씨 · 쉼표 · 꾸미는 마디 너머는 아니다.
    @Test(arguments: [
        Said("4년 전 5월에 우물을 팠다", "2036-05-01..2036-05-31 month relative none"),
        Said("4년 전 5월 3일에 우물을 팠다", "2036-05-03..2036-05-03 exact relative none"),
        Said("4년 전 12월 24일에 우물을 팠다", "2036-12-24..2036-12-24 exact relative none"),
        Said("4년 전쯤 5월에 우물을 팠다", "2036-05-01..2036-05-31 circa relative soft"),
        Said("4년 전 5월쯤 우물을 팠다", "2036-05-01..2036-05-31 circa relative soft"),
        Said("4년 전 5월 말에 우물을 팠다", "2036-05-21..2036-05-31 circa relative soft"),
        Said("4년 뒤 5월에 우물을 판다", "2044-05-01..2044-05-31 month relative none", direction: .future),
        Said("4년 후 5월에 우물을 판다", "2044-05-01..2044-05-31 month relative none"),
        Said("사 년 전 5월에 우물을 팠다", "2036-05-01..2036-05-31 month relative none"),
        Said("4년 전 5월부터 7월까지 섬에 살았다", "2036-05-01..2036-07-31 year relative none"),
        Said("4년 전 5월이나 6월에 우물을 팠다", "2036-05-01..2036-06-30 circa relative soft"),
        Said("4년 전 5월에 산 배를 그저께 팔았다", "2040-10-08..2040-10-08 exact relative none"),
        Said("4년 전 5월에 산 배를 작년에 팔았다", "2039-01-01..2039-12-31 year relative none"),
        Said("작년에 4년 전 5월 그림을 봤다", "2039-01-01..2039-12-31 year relative none"),
        Said("5월에 4년 전 7월 그림을 봤다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전 5월에 만난 동무를 7월에 또 만났다", "2040-07-01..2040-07-31 month absolute none"),
        Said("4년 전에 만난 동무를 5월에 또 만났다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전에 팠고 5월에 또 팠다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전에 5월에 우물을 팠다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전, 5월에 우물을 팠다", "2040-05-01..2040-05-31 month absolute none"),
        Said("세 해 전 5월에 우물을 팠다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전 지난 5월에 우물을 팠다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전 13월에 우물을 팠다", "2036-01-01..2036-12-31 year absolute none"),
        Said("몇 년 전 5월에 우물을 팠다", "ask:unbounded"),
        Said("4년 전 5월에 파서 작년에 메웠다", "2039-01-01..2039-12-31 year relative none"),
    ])
    func monthBelongsToYearsAgo(_ r: Said) { r.check() }

    /// 해 없는 달 · 날은 바로 앞에 맞닿은 한 해짜리 학년의 것이다(1 · 2월은 이듬해) — 여러 해 구간 · 「고3 1월」은 그대로.
    @Test(arguments: [
        Said("고3 때 6월 잔치에 갔다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("고3 6월에", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("고3 때 6월 3일에 배를 탔다", "2068-06-03..2068-06-03 exact grade none", in: "born", now: later),
        Said("고3 때 6월 말에 배를 탔다", "2068-06-21..2068-06-30 circa grade soft", in: "born", now: later),
        Said("고3 때 6월쯤 배를 탔다", "2068-06-01..2068-06-30 circa grade soft", in: "born", now: later),
        Said("중1 때 11월에 배를 탔다", "2063-11-01..2063-11-30 month grade none", in: "born", now: later),
        Said("고3 때 2월에 배를 탔다", "2069-02-01..2069-02-28 month grade none", in: "born", now: later),
        Said("고3 때 1월에 배를 탔다", "2069-01-01..2069-01-31 month grade none", in: "born", now: later),
        Said("고등학교 2학년 때 6월에 배를 탔다", "2067-06-01..2067-06-30 month grade none", in: "born", now: later),
        Said("고3 시절 6월에 배를 탔다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("고3 때 6월부터 8월까지 섬에 살았다", "2068-06-01..2068-08-31 year grade none", in: "born", now: later),
        Said("고3 때 6월이나 7월에 배를 탔다", "2068-06-01..2068-07-31 circa grade soft", in: "born", now: later),
        Said("고3 때 6월이었나 고2 때 6월이었나", "ask:conflict", ["2068-06-01..2068-06-30", "2067-06-01..2067-06-30"], in: "born", now: later),
        Said("고3 때 6월에 탄 배를 그저께 봤다", "2090-10-08..2090-10-08 exact relative none", in: "born", now: later),
        Said("고3 때 6월 그림을 8월에 봤다", "2090-08-01..2090-08-31 month absolute none", in: "born", now: later),
        Said("고3 때 6월에 탔다. 8월에 또 탔다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("2068년 고3 때 6월에 배를 탔다", "2068-06-01..2068-06-30 month absolute none", in: "born", now: later),
        Said("고3 1월에 배를 탔다", "2090-01-01..2090-01-31 month absolute none", in: "born", now: later),
        Said("고3 때 동무를 6월에 만났다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("고3 때, 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("대학교 3학년 때 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("중학교 때 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("스무 살 때 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("30대 때 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "born", now: later),
        Said("고3 때 6월에 배를 탔다", "2090-06-01..2090-06-30 month absolute none", in: "early", now: later),
        Said("고3 때 6월에 배를 탔다", "ask:needsBirth", now: later),
        Said("고3 때 6월부터 8월까지 섬에 살았다", "ask:needsBirth", now: later),
        Said("고3 때 6월 그림을 8월에 봤다", "2090-08-01..2090-08-31 month absolute none", now: later),
    ])
    func monthBelongsToGrade(_ r: Said) { r.check() }

    /// 해 없는 「N월생」은 때가 아니다(생일 · 생활 · 해가 선 「2033년 3월생」은 그대로).
    @Test(arguments: [
        Said("5월생 아이를 만났다", "ask:noExpression"),
        Said("나는 5월생이라 빠르다", "ask:noExpression"),
        Said("12월생은 어리다", "ask:noExpression"),
        Said("4년 전에 5월생 아이를 만났다", "2036-01-01..2036-12-31 year relative none"),
        Said("5월생 동무를 작년에 만났다", "2039-01-01..2039-12-31 year relative none"),
        Said("5월 생일에 만났다", "2040-05-01..2040-05-31 month absolute none"),
        Said("5월생일에 만났다", "2040-05-01..2040-05-31 month absolute none"),
        Said("5월 생활비를 셌다", "2040-05-01..2040-05-31 month absolute none"),
        Said("2033년 5월생 아이를 만났다", "2033-05-01..2033-05-31 month absolute none"),
        Said("작년 5월생 아이를 만났다", "2039-05-01..2039-05-31 month relative none"),
        Said("5월 3일생 아이를 만났다", "2040-05-03..2040-05-03 exact absolute none"),
    ])
    func bornInMonth(_ r: Said) { r.check() }

    /// 「내일」은 원문에 붙어 있을 때만 날이다(다른 때 낱말은 띄어 써도 그대로).
    @Test(arguments: [
        Said("내 일을 마쳤다", "ask:noExpression"),
        Said("내 일이 쌓였다", "ask:noExpression"),
        Said("내 일요일은 길다", "ask:noExpression"),
        Said("내 일을 작년에 마쳤다", "2039-01-01..2039-12-31 year relative none"),
        Said("내 일은 내일 마친다", "2040-10-11..2040-10-11 exact relative none"),
        Said("내 어릴 때 일이 떠오른다", "2050-05-10..2063-02-28 period era soft", in: "born", now: later),
        Said("그저께 내 일을 도왔다", "2040-10-08..2040-10-08 exact relative none"),
        Said("내 일부터 매일 한다", "recurring", direction: .future),
        Said("오늘부터 내 일 마칠 때까지 쉰다", "2040-10-10..2040-10-10 exact relative soft"),
        Said("내일까지 마친다", "2040-10-11..2040-10-11 exact relative none"),
        Said("내일모레 간다", "2040-10-11..2040-10-11 exact relative none"),
        Said("올 해 심었다", "2040-01-01..2040-12-31 year relative none"),
        Said("지난 주에 심었다", "2040-10-01..2040-10-07 month relative none"),
    ])
    func tomorrowIsOneWord(_ r: Said) { r.check() }

    /// 「N일 · 주 · 달 · 년」 뒤가 「후」로 시작하는 낱말이면 때가 아니다(낱말은 자원의 닫힌 목록 — 토씨 · 빈칸은 때).
    @Test(arguments: [
        Said("4일 후배를 그저께 만났다", "2040-10-08..2040-10-08 exact relative none"),
        Said("4년 후배를 만났다", "ask:noExpression"),
        Said("두 달 후기를 적었다", "ask:noExpression"),
        Said("일주일 후회했다", "ask:noExpression"),
        Said("4년 후원금을 냈다", "ask:noExpression"),
        Said("지난달 4일 후배를 만났다", "2040-09-04..2040-09-04 exact relative none"),
        Said("5월 4일 후배를 만났다", "2040-05-04..2040-05-04 exact absolute none"),
        Said("4일 후에 만난다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4일 후면 끝난다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4일 후 배를 탄다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4일 후보다 길다", "ask:noExpression"),
        Said("4일 후배송된다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4일 후기차를 탄다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4일후출발한다", "2040-10-14..2040-10-14 exact relative none"),
        Said("4년 후부터 짓는다", "2044-01-01..2044-12-31 year relative none"),
        Said("4년 전 후배를 만났다", "2036-01-01..2036-12-31 year relative none"),
        Said("이틀 후배를 만났다", "2040-10-12..2040-10-12 exact relative none"),
    ])
    func afterIsNotAWord(_ r: Said) { r.check() }

    /// 나이 차는 나이가 아니다 — 「N살」 뒤의 온 낱말 「어린 · 많은 · 위 · 아래 · 차이 · 터울 · 더 · 연상 · 연하」와 붙은 「-짜리」만.
    @Test(arguments: [
        Said("세 살 어린 동무", "ask:noExpression", in: "born", now: later),
        Said("세 살 많은 동무를 만났다", "ask:noExpression", in: "born", now: later),
        Said("네 살 위 동무", "ask:noExpression", in: "born", now: later),
        Said("네 살 위인 동무다", "ask:noExpression", in: "born", now: later),
        Said("네 살 아래였다", "ask:noExpression", in: "born", now: later),
        Said("세 살 터울이다", "ask:noExpression", in: "born", now: later),
        Said("일곱 살 차이가 난다", "ask:noExpression", in: "born", now: later),
        Said("일곱 살 차이나는 동무", "ask:noExpression", in: "born", now: later),
        Said("한 살 더 먹었다", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 조카", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세살짜리때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 때는 섬에 살았다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 때부터 섬에 살았다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리였을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리였을때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리일 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리이던 시절에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("나 세 살짜리 적에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 적부터 섬에 살았다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 시절에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 무렵 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 나이에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 어린 적에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 많은 적에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 위였을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 아래 적에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 연상일 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 연하였던 시절 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 터울이었을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 차이였을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 더 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 아이였을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 꼬마였을 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 애 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 꼬맹이 시절에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 어린애였던 시절", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 작은 아이 적에 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 철부지 무렵", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 아가 즈음", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 내가 배를 타던 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 동생이었을 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 아이였을 때", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 조카가 왔을 때", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 딸아이를 업던 시절", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 남동생이 태어났을 무렵", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이를 봤다. 때마침 비가 왔다", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이를 봤다! 어느 시절 노래였다", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이를 업었다", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이의 감정적 말", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이를 봤다. 그때 비가 왔다", "ask:unbounded", in: "born", now: later),
        Said("세 살짜리 조카를 업었다. 세 살짜리 아이였을 때 배를 탔다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 아이였을 때 배를 탔다. 세 살짜리 조카를 업었다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 위 때문에 울었다", "ask:noExpression", in: "born", now: later),
        Said("세 살 위 때린 동무", "ask:noExpression", in: "born", now: later),
        Said("세 살 위 때 묻은 옷", "ask:noExpression", in: "born", now: later),
        Said("세 살 위 적군", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 아이를 때마침 봤다", "ask:noExpression", in: "born", now: later),
        Said("세 살 위 무렵", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 위 즈음", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("그때 세 살짜리 아이를 업었다", "ask:unbounded", in: "born", now: later),
        Said("세 살짜리 적을 떠올린다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 적만 떠오른다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 아이였던 적을 떠올린다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살 위 적을 떠올린다", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
        Said("세 살짜리 조카랑 놀던 때", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 때문에 울었다", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 때린 동무", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 때 묻은 옷", "ask:noExpression", in: "born", now: later),
        Said("세 살짜리 적군", "ask:noExpression", in: "born", now: later),
        Said("세 살 위 동무와 놀던 때", "ask:noExpression", in: "born", now: later),
        Said("한 살 더 먹었을 때", "ask:noExpression", in: "born", now: later),
        Said("네 살 연상의 동무", "ask:noExpression", in: "born", now: later),
        Said("네 살 연하다", "ask:noExpression", in: "born", now: later),
        Said("두세 살 어린 동무", "ask:noExpression", in: "born", now: later),
        Said("2~3살 어린 동무", "ask:noExpression", in: "born", now: later),
        Said("세 살 어린 동무를 작년에 만났다", "2089-01-01..2089-12-31 year relative none", in: "born", now: later),
        Said("세 살 어린 동무가 서른 살 때 왔다", "2079-01-01..2080-12-31 period age soft", in: "born", now: later),
        Said("여섯 살 어린이집에 다녔다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("여섯 살 더운 여름에 배를 탔다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("나 여섯 살 많이 아팠다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("열다섯 살 어린 나이에 배를 탔다", "2064-01-01..2065-12-31 period age soft", in: "born", now: later),
        Said("열 살 어린 눈에 비쳤다", "2059-01-01..2060-12-31 period age soft", in: "born", now: later),
        Said("스무 살 많은 것을 배웠다", "2069-01-01..2070-12-31 period age soft", in: "born", now: later),
        Said("여섯 살 위가 아팠다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("여섯 살 아래층에 살았다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("스무 살 차이나타운에 갔다", "2069-01-01..2070-12-31 period age soft", in: "born", now: later),
        Said("여섯 살 때 배를 탔다", "2055-01-01..2056-12-31 period age soft", in: "born", now: later),
        Said("네 살 차이다", "ask:noExpression", in: "born", now: later),
        Said("3세 연하 동무", "2052-01-01..2053-12-31 period age soft", in: "born", now: later),
    ])
    func ageApart(_ r: Said) { r.check() }

    /// 견주는 때(때에 붙은 「보다 · 보다는 · 보다도 · 보단」)는 사건의 때가 아니다 — 남은 때가 있으면 그 때.
    @Test(arguments: [
        Said("작년보다 올해가 시원했다", "2040-01-01..2040-12-31 year relative none"),
        Said("올해는 작년보다 시원했다", "2040-01-01..2040-12-31 year relative none"),
        Said("그저께보다 나아졌다", "ask:noExpression"),
        Said("작년보다는 낫다", "ask:noExpression"),
        Said("작년보다도 낫다", "ask:noExpression"),
        Said("작년보단 낫다", "ask:noExpression"),
        Said("4년 전보다 키가 컸다", "ask:noExpression"),
        Said("5월보다 7월에 바빴다", "2040-07-01..2040-07-31 month absolute none"),
        Said("2033년보다 2034년이 바빴다", "2034-01-01..2034-12-31 year absolute none"),
        Said("2033년 5월보다 7월이 바빴다", "2033-07-01..2033-07-31 month absolute none"),
        Said("작년 여름보다 가을이 좋았다", "2039-09-01..2039-11-30 circa relative+season soft"),
        Said("작년 여름보다 올여름이 덥다", "2040-06-01..2040-08-31 circa relative+season soft"),
        Said("5월 3일보다 8일에 바빴다", "2040-05-08..2040-05-08 exact absolute none"),
        Said("5월 3일보다 8일 더 걸렸다", "ask:noExpression"),
        Said("5월 3일보다 8일이나 늦었다", "ask:noExpression"),
        Said("5월 3일보다 8일쯤 일찍 끝났다", "ask:noExpression"),
        Said("작년은 5월보다 나았다", "2039-01-01..2039-12-31 year relative none"),
        Said("작년은 5월보다 7월이 더웠다", "2039-07-01..2039-07-31 month relative none"),
        Said("어릴 때보다 키가 컸다", "ask:noExpression", in: "born", now: later),
        Said("30대 때보다 힘이 빠졌다", "ask:noExpression", in: "born", now: later),
        Said("고등학교 때보다 대학교 때가 좋았다", "2069-03-01..2076-02-29 period schoolStage soft", in: "born", now: later),
        Said("어릴 때보다 키가 컸다", "ask:noExpression", now: later),
        Said("예전보다 좋아졌다", "ask:noExpression"),
        Said("그때보다 낫다", "ask:noExpression"),
        Said("요즘보다 예전이 좋았다", "ask:unbounded"),
        Said("몇 년 전보다 낫다", "ask:noExpression"),
        Said("매일 작년보다 더 걷는다", "recurring"),
        Said("5월보다 6월부터 8월까지 바빴다", "2040-06-01..2040-08-31 year absolute none"),
        Said("그저께 보다 만 그림을 오늘 봤다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께 그림을 보다가 잤다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께보다가 잤다", "2040-10-08..2040-10-08 exact relative none"),
        Said("작년에 산 배보다 그저께 산 배가 낫다", "2040-10-08..2040-10-08 exact relative none"),
        Said("작년보다야 낫다", "2039-01-01..2039-12-31 year relative none"),
    ])
    func comparedIsNotTheTime(_ r: Said) { r.check() }

    /// 토씨 없이 이름씨를 꾸미는 연대는 학년에도 진다(둘 사이에 풀이말이 없고 학년에 때 표지가 설 때).
    @Test(arguments: [
        Said("70년대 노래를 고3 때 들었다", "2068-03-01..2069-02-28 year grade none", in: "born", now: later),
        Said("70년대 말 노래를 동무랑 고3 때 들었다", "2068-03-01..2069-02-28 year grade none", in: "born", now: later),
        Said("2060년대 노래를 고3 때 들었다", "2068-03-01..2069-02-28 year grade none", in: "born", now: later),
        Said("70년대 노래를 고3 때 들었다", "ask:needsBirth", now: later),
        Said("70년대에 나온 노래를 고3 때 들었다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대 노래를 고3 때 6월에 들었다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("60년대 노래를 고3 때 6월에 들었다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("70년대 노래를 고3 때 6월 그대로 들었다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("고3 때 6월에 70년대 노래를 들었다", "2068-06-01..2068-06-30 month grade none", in: "born", now: later),
        Said("70년대 노래를 고3 때 6월에 들었다", "ask:needsBirth", now: later),
        Said("70년대에 나온 노래를 고3 때 6월에 들었다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대에 고3 때 6월에 들었다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대에 고3 때 놀았다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대 고3 때 놀았다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대 섬에 살았고 고3 때 옮겼다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대 노래를 고3 형이 불렀다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
        Said("70년대 노래를 고등학교 때 들었다", "2070-01-01..2079-12-31 period absolute soft", in: "born", now: later),
    ])
    func decadeYieldsToGrade(_ r: Said) { r.check() }

    /// 달력 물결은 「부터 … 까지」다 — 양쪽이 년 · 월 · 일 꼴이고 뒤가 「전 · 후 · 뒤 · 동안 · 걸리-」가 아니고 문장의 때가 그 시작일 때만.
    @Test(arguments: [
        Said("5월 3일~8일에 섬에 갔다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3~8일에 섬에 갔다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일 ~ 6월 8일에 섬에 갔다", "2040-05-03..2040-06-08 year absolute none"),
        Said("5월 3일～8일에 섬에 갔다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일〜8일에 섬에 갔다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일∼8일에 섬에 갔다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월~7월에 섬에 살았다", "2040-05-01..2040-07-31 year absolute none"),
        Said("3~5월에 섬에 살았다", "2040-03-01..2040-05-31 year absolute none"),
        Said("11월~2월에 섬에 살았다", "2040-11-01..2041-02-28 year absolute none"),
        Said("작년 5월~7월에 섬에 살았다", "2039-05-01..2039-07-31 year relative none"),
        Said("2081~2084년에 섬에 살았다", "2081-01-01..2084-12-31 period absolute none"),
        Said("2031년~2034년에 섬에 살았다", "2031-01-01..2034-12-31 period absolute none"),
        Said("2031년 5월~2034년 7월에 섬에 살았다", "2031-05-01..2034-07-31 period absolute none"),
        Said("지난달 3일~8일에 섬에 갔다", "2040-09-03..2040-09-08 month relative none"),
        Said("5월 3일~8일쯤 섬에 갔다", "2040-05-03..2040-05-08 circa absolute soft"),
        Said("3~5월에 섬에 간다", "2041-03-01..2041-05-31 year absolute none", direction: .future),
        Said("고3 때 5월~7월에 섬에 살았다", "2068-05-01..2068-07-31 year grade none", in: "born", now: later),
        Said("5월 3일~8일 전시를 봤다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일~8일 전에 봤다", "2040-10-02..2040-10-02 exact relative none"),
        Said("5월 3일~8일 동안 쉬었다", "2040-05-03..2040-05-03 exact absolute none"),
        Said("5월 2~3일 걸렸다", "2040-05-01..2040-05-31 month absolute none"),
        Said("5월 2~3일 정도 쉬었다", "2040-05-01..2040-05-31 month absolute none"),
        Said("2~3년 전에 심었다", "2037-01-01..2037-12-31 year relative none"),
        Said("3~4일 걸렸다", "ask:noExpression"),
        Said("5월 3일-8일에 섬에 갔다", "2040-05-03..2040-05-03 exact absolute none"),
        Said("그저께 5월~7월 뱃길을 잡았다", "2040-10-08..2040-10-08 exact relative none"),
        Said("5월~8일에 쉬었다", "2040-05-01..2040-05-31 month absolute none"),
        Said("2031년~5월에 쉬었다", "2031-01-01..2031-12-31 year absolute none"),
        Said("그저께 5월 3일~8일 뱃길을 잡았다", "2040-10-08..2040-10-08 exact relative none"),
        Said("그저께~ 쉬었다", "2040-10-08..2040-10-08 exact relative none"),
        Said("5월~그저께", "2040-10-08..2040-10-08 exact relative none"),
        Said("2034년~2031년에 섬에 살았다", "2034-01-01..2034-12-31 year absolute none"),
    ])
    func calendarTilde(_ r: Said) { r.check() }

    /// 맞닿지 않은 고름은 말한 차례 · 방향과 상관없이 묻는다 — 맞닿은 고름은 합친 구간 그대로.
    @Test(arguments: [
        Said("5월 3일이나 8일에 심었다", "ask:conflict", ["2040-05-03..2040-05-03", "2040-05-08..2040-05-08"]),
        Said("5월 3일 또는 8일에 심었다", "ask:conflict", ["2040-05-03..2040-05-03", "2040-05-08..2040-05-08"]),
        Said("작년 5월 3일이나 8일에 심었다", "ask:conflict", ["2039-05-03..2039-05-03", "2039-05-08..2039-05-08"]),
        Said("작년 봄이나 가을에 심었다", "ask:conflict", ["2039-03-01..2039-05-31", "2039-09-01..2039-11-30"]),
        Said("작년 봄이었나 재작년 봄이었나 심었다", "ask:conflict", ["2039-03-01..2039-05-31", "2038-03-01..2038-05-31"]),
        Said("작년 봄이었나 재작년 봄이었나 심었다", "ask:conflict", ["2039-03-01..2039-05-31", "2038-03-01..2038-05-31"], direction: .future),
        Said("재작년 봄이었나 작년 봄이었나 심었다", "ask:conflict", ["2038-03-01..2038-05-31", "2039-03-01..2039-05-31"]),
        Said("올봄이었나 재작년 봄이었나 심었다", "ask:conflict", ["2040-03-01..2040-05-31", "2038-03-01..2038-05-31"]),
        Said("작년 5월이었나 재작년 5월이었나 심었다", "ask:conflict", ["2039-05-01..2039-05-31", "2038-05-01..2038-05-31"]),
        Said("4년 전 봄이었나 6년 전 봄이었나 심었다", "ask:conflict", ["2036-01-01..2036-12-31", "2034-01-01..2034-12-31"]),
        Said("작년 봄이었나 재작년 봄이었나 4년 전이었나 심었다", "ask:conflict", ["2039-03-01..2039-05-31", "2038-03-01..2038-05-31", "2036-01-01..2036-12-31"]),
        Said("작년 1월이었나 재작년 12월이었나 심었다", "2038-12-01..2039-01-31 circa relative soft"),
        Said("작년 봄이었나 재작년 봄에 4년 전 그림을 봤다", "2038-03-01..2038-05-31 circa relative+season soft"),   // 다른 때가 더 있으면 읽는 차례 그대로
        Said("3월이었나 작년 5월이었나 4년 전 7월이었나 심었다", "2039-03-01..2039-03-31 month relative none"),
        Said("작년이었나 재작년이었나 심었다", "2038-01-01..2039-12-31 period relative soft"),
        Said("5월 3일이나 4일에 심었다", "2040-05-03..2040-05-04 circa absolute soft"),
        Said("5월 3일이나 8일 동안 쉬었다", "2040-05-03..2040-05-03 exact absolute none"),
        Said("5월 3일이나 8일 걸렸다", "2040-05-03..2040-05-03 exact absolute none"),
        Said("5월 3일이나 8일 먼저 마쳤다", "2040-05-03..2040-05-03 exact absolute none"),
        Said("5월 3일이나 8일에 심었고 그저께 또 심었다", "2040-10-08..2040-10-08 exact relative none"),
        Said("내년에 나올 5월 달력을 골랐다", "2041-05-01..2041-05-31 month relative none"),   // 「나올」의 나는 고름 말이 아니다
        Said("작년에 나올 5월에 심었다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년 봄 나 재작년 봄에 간 섬에 또 갔다", "2038-03-01..2038-05-31 circa relative+season soft"),   // 대이름씨 「나」
        Said("언제나 작년 봄이 그립다", "2039-03-01..2039-05-31 circa relative+season soft"),
        Said("작년 봄이었나 재작년 봄이었나 그저께 떠올렸다", "2040-10-08..2040-10-08 exact relative soft"),
        Said("3월이나 2031년에 심었다", "2031-01-01..2031-12-31 year absolute none"),
    ])
    func choiceApartAsks(_ r: Said) { r.check() }

    /// 「A부터 B까지」의 끝만 고치면 시작은 그대로다.
    @Test(arguments: [
        Said("2033년 5월 3일부터 6일 아니 8일까지 쉬었다", "2033-05-03..2033-05-08 month absolute none"),
        Said("5월 3일부터 6일, 아 아니다, 8일까지 쉬었다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일부터 6일이 아니라 8일까지 쉬었다", "2040-05-03..2040-05-08 month absolute none"),
        Said("5월 3일부터 6월 6일 아니 8일까지 쉬었다", "2040-05-03..2040-06-08 year absolute none"),
        Said("5월 3일부터 6일 아니 6월 8일까지 쉬었다", "2040-05-03..2040-06-08 year absolute none"),
        Said("5월 3일부터 6일 아니면 8일까지 쉬었다", "2040-05-03..2040-05-06 month absolute none"),
        Said("5월 3일부터 6일까지 쉬었다", "2040-05-03..2040-05-06 month absolute none"),
        Said("5월 3일 아니 6일까지 쉬었다", "2040-05-03..2040-05-03 exact absolute none"),
    ])
    func rangeEndCorrected(_ r: Said) { r.check() }

    /// 「그 다음에 · 그다음에」는 이음 낱말이다(「다음에 · 이 다음에」는 그대로).
    @Test(arguments: [
        Said("그 다음에 밥을 지었다", "ask:noExpression"),
        Said("그다음에 밥을 지었다", "ask:noExpression"),
        Said("그다음에 예전에 살던 섬에 갔다", "ask:unbounded"),
        Said("다음에 또 간다", "ask:unbounded"),
        Said("이 다음에 크면 간다", "ask:unbounded"),
        Said("블로그 다음에 적었다", "ask:unbounded"),
        Said("그 다음에 다음에 간다", "ask:unbounded"),
    ])
    func thenIsNotAhead(_ r: Said) { r.check() }

    /// 「지난 · 오는 · 이번 · 올 + 달」은 제 해를 가진다 — 앞에 떨어져 선 해 낱말과 잇지 않는다.
    @Test(arguments: [
        Said("작년에 타던 배를 지난 5월에 팔았다", "2040-05-01..2040-05-31 month absolute none"),
        Said("작년에 심어서 올 5월에 거뒀다", "2040-05-01..2040-05-31 month relative none"),
        Said("재작년에 심은 나무를 이번 4월에 옮겼다", "2040-04-01..2040-04-30 month relative none"),
        Said("작년에 만난 동무를 오는 12월에 만난다", "2040-12-01..2040-12-31 month absolute none"),
        Said("작년 3월에 산 배를 지난 5월 5일에 팔았다", "2040-05-05..2040-05-05 exact absolute none"),
        Said("작년 여름에 산 배를 지난 5월에 팔았다", "2040-05-01..2040-05-31 month absolute none"),
        Said("4년 전 3월에 산 배를 작년에 고쳐서 지난 5월에 팔았다", "2040-05-01..2040-05-31 month relative none"),
        Said("4년 전 3월에 팠고 작년에 메워서 지난 5월에 덮었다", "2040-05-01..2040-05-31 month relative none"),
        Said("작년 이맘때 지난 3월에 만났다", "2040-03-01..2040-03-31 month relative none"),
        Said("작년 겨울에 다쳐서 지난 3월에 나았다", "2040-03-01..2040-03-31 month relative none"),
        Said("작년 봄에 심어서 올 3월에 거뒀다", "2040-03-01..2040-03-31 month relative none"),
        Said("작년 말에 심어서 올 4월에 거뒀다", "2040-04-01..2040-04-30 month relative none"),
        Said("작년 말에 심어서 올 4월 말에 거뒀다", "2040-04-21..2040-04-30 circa relative soft"),
        Said("작년 겨울에 지난 5월 그림을 봤다", "2039-12-01..2040-02-29 circa relative+season soft"),
        Said("작년 여름 지난 7월에 심었다", "2039-07-01..2039-07-31 circa relative soft"),
        Said("작년 말 올 4월에 심었다", "2040-04-01..2040-04-30 month relative none"),
        Said("작년 겨울 올 1월에 심었다", "2040-01-01..2040-01-31 month relative none"),
        Said("작년 초 지난 3월에 심었다", "2039-03-01..2039-03-31 circa relative soft"),
        Said("올해 말에 오는 12월에 심는다", "2040-12-01..2040-12-31 month relative none"),
        Said("올해 말 오는 12월에 심는다", "2040-12-01..2040-12-31 circa relative soft"),
        Said("작년 이맘때 지난 10월에 심었다", "2039-10-01..2039-10-31 circa relative soft"),
        Said("작년에 심어 돌아올 5월에 거둔다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년에 쓴 글이 나올 5월을 기다린다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년에 만난 동무가 올 5월에 왔다", "2040-05-01..2040-05-31 month absolute none"),
        Said("지난 5월에 산 배를 작년에 고쳤다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년 봄에 심어서 올 3월쯤 거뒀다", "2040-03-01..2040-03-31 circa relative soft"),
        Said("작년 겨울 지난 2월에 심었다", "2039-02-01..2039-02-28 circa relative soft", now: "2040-01-15"),
        Said("작년 겨울 올 1월에 심었다", "2040-01-01..2040-01-31 month relative none", now: "2040-01-15"),
        Said("작년 겨울 지난 1월에 심었다", "2040-01-01..2040-01-31 month relative none", now: "2040-02-20"),
        Said("작년 겨울 지난 2월에 심었다", "2040-02-01..2040-02-29 month relative none", now: "2040-12-05"),
        Said("올해 겨울 지난 1월에 심었다", "2040-01-01..2040-01-31 circa relative soft", now: "2040-01-15"),
        Said("올해 겨울 지난 2월에 심었다", "2040-02-01..2040-02-29 circa relative soft", now: "2040-02-20"),
        Said("작년 겨울 오는 2월에 심는다", "2041-02-01..2041-02-28 month relative none", now: "2040-12-05"),
        Said("올해 겨울 오는 2월에 심는다", "2041-02-01..2041-02-28 month relative none", now: "2040-12-05"),
        Said("작년에 지난 5월 그림을 봤다", "2039-01-01..2039-12-31 year relative none"),
        Said("올해는 지난 5월에 심었다", "2040-05-01..2040-05-31 month relative none"),
        Said("올해 지난 5월에 심었다", "2040-05-01..2040-05-31 month relative none"),
        Said("내년에는 오는 3월에 심는다", "2041-03-01..2041-03-31 month relative none"),
        Said("작년 지난 5월에 심었다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년에 저번 5월에 심었다", "2039-05-01..2039-05-31 month relative none"),
        Said("작년에 우리는 5월에 심었다", "2039-05-01..2039-05-31 month relative none"),
    ])
    func shiftedMonthKeepsItsYear(_ r: Said) { r.check() }

    /// 달력 물결은 손 넷이 같다 — `day` = 시작 · `end` = 끝 · 기간 신호 · 구간을 열지 않는 물결은 아무 손도 아니다.
    @Test func calendarTildeForEveryHand() {
        let now = day("2040-10-10")
        for (s, a, b) in [("5월 3일~8일에 섬에 갔다", "2040-05-03", "2040-05-08"), ("5월 3~8일에 섬에 갔다", "2040-05-03", "2040-05-08"), ("11월~2월에 섬에 살았다", "2040-11-01", "2041-02-01"),
                          ("2081~2084년에 섬에 살았다", "2081-01-01", "2084-01-01"), ("지난달 29일~3일에 섬에 갔다", "2040-09-29", "2040-10-03"), ("2월 29일~3월 1일에 섬에 갔다", "2040-02-29", "2040-03-01"), ("다음 달 30일~2일에 섬에 간다", "2040-11-30", "2040-12-02")] {
            let x = SpokenReading.day(s, now: now, zone: zone)
            #expect(x?.text == a && (x?.precision == .exact) == s.contains("일"), "\(s)")
            #expect(SpokenReading.end(s, start: x, now: now, zone: zone)?.text == b, "\(s)")
            #expect(SpokenReading.hasSpanSignal(s), "\(s)")
        }
        for s in ["그저께 5월 3일~8일 뱃길을 잡았다", "3~4일 걸렸다", "5월 3일~8일 전에 봤다", "그저께~ 쉬었다", "3일~8일에 쉬었다", "10~20년 동안 살았다"] {
            let x = SpokenReading.day(s, now: now, zone: zone)
            #expect(SpokenReading.end(s, start: x, now: now, zone: zone) == nil, "\(s)")
            #expect(SpokenReading.hasSpanSignal(s) == s.contains("동안"), "\(s)")
        }
        // 기준 날에 없는 날(윤년 · 달의 길이)이어도 신호는 같다
        for s in ["작년 2월 29일~3월 1일에 갔다", "재작년 2월 29일~3월 1일에 갔다", "내년 2월 29일~3월 1일에 간다", "3년 전 2월 29일~3월 1일에 갔다", "20년 뒤 2월 29일~3월 1일에 간다", "180년 전 2월 29일~3월 1일에 갔다", "28년 뒤 2월 29일~3월 1일에 간다"] { #expect(SpokenReading.hasSpanSignal(s), "\(s)") }
        guard case .span(let q) = spoken("5월 3~8일에 섬에 갔다") else { Issue.record("구간이 아니다"); return }
        #expect(q.phrase == "5월3~8일")
    }
    /// 끝만 고친 말 · 원문에 붙은 「내일」은 끝 날도 같다.
    @Test func correctedRangeEnd() {
        let now = day("2040-10-10")
        for (s, e) in [("5월 3일부터 6일 아니 8일까지 쉬었다", "2040-05-08"), ("5월 3일부터 6월 6일 아니 8일까지 쉬었다", "2040-06-08")] {
            #expect(SpokenReading.end(s, start: SpokenReading.day(s, now: now, zone: zone), now: now, zone: zone)?.text == e, "\(s)")
        }
        let own = "오늘부터 내 일 마칠 때까지 쉰다", tomorrow = "오늘부터 내일까지 쉰다"
        #expect(SpokenReading.end(own, start: SpokenReading.day(own, now: now, zone: zone), now: now, zone: zone) == nil)
        #expect(SpokenReading.end(tomorrow, start: SpokenReading.day(tomorrow, now: now, zone: zone), now: now, zone: zone)?.text == "2040-10-11")
    }
    /// 「그다음에 예전에」의 방향은 남은 낱말의 것이다.
    @Test func thenLeavesDirection() {
        guard case .ask(let a) = spoken("그다음에 예전에 살던 섬에 갔다") else { Issue.record("묻기가 아니다"); return }
        #expect(a.reason == .unbounded && a.direction == .past)
    }
    /// 견줌 · 고름이 여섯 넘게 선 글은 가리지도 가르지도 않는다(길이만큼만 일한다).
    @Test func manyMarksAreLeft() {
        #expect(said(String(repeating: "작년보다 ", count: 7) + "낫다") == "2039-01-01..2039-12-31 year relative none")
        #expect(said(String(repeating: "작년보다 ", count: 6) + "낫다") == "ask:noExpression")
    }
    /// 거르는 낱말(`gates`)은 그 꼴에 반드시 든다 — 맞는 글은 모두 거름을 지난다.
    @Test func gatesNeverHideAMatch() {
        let w = Words.shared, p = w.patterns
        let samples: [(String, String, [String])] = [
            ("namedTime", p.namedTime, ["모레라는 배", "모레란 배", "작년이라는 배"]), ("yearsCount", p.yearsCount, ["40년 전통", "사 년 전부 맡겼다"]),
            ("daysTogether", p.daysTogether, ["어제오늘 일"]), ("bornInMonth", p.bornInMonth, ["5월생", "12 월생이다"]), ("ageApart", p.ageApart, ["두 살 어린", "세 살 위"]),
            ("ageEach", p.ageEach, ["세 살짜리", "3살짜리"]), ("afterWord", p.afterWord, ["4일 후배", "일주일 후기를"]), ("longNumberBlock", p.longNumberBlock, ["45678년", "12,345년도"]),
            ("correction", p.correction, ["4년 전 아니 6년 전", "작년 아냐 올해", "작년, 정정할게, 올해", "작년, 다시 말하면 올해", "작년, 아 아니다, 올해"]),
            ("comparedWith", p.comparedWith, ["작년보다", "작년보단", "작년보다도"]), ("thenNext", p.thenNext, ["그 다음에", "그다음에"]), ("frequency", p.frequency, ["4년에 한 번"]),
        ]
        #expect(Set(samples.map(\.0)) == Set(w.gates.keys))
        for (name, pattern, texts) in samples { for s in texts { #expect(Rx.has(s, pattern) && w.may(name, s), "\(name) — \(s)") } }
        // 거르는 낱말을 뺀 글은 그 꼴에 맞지 않는다
        for (name, pattern, texts) in samples {
            for s in texts {
                var bare = s
                for g in w.gates[name]! { bare = bare.replacingOccurrences(of: g, with: "") }
                #expect(!Rx.has(bare, pattern), "\(name) — \(bare)")
            }
        }
    }
    /// 빈칸을 줄이는 손 — 바이트로 거른 것과 꼴로 줄인 것이 같다.
    @Test func oneSpace() {
        // 기대는 글자로 적는다 — 꼴로 다시 지으면 바이트 거름이 틀려도 같은 답이 된다
        for (s, e) in [("가 나", "가 나"), ("가  나", "가 나"), ("가   나  다", "가 나 다"), ("가\t나", "가 나"), ("가\n 나", "가 나"), ("가\u{B}나", "가 나"), ("가\r\n나", "가 나"), ("가\u{00A0}나", "가 나"),
                       ("가\u{3000}나", "가 나"), ("가\u{2009}나", "가 나"), ("가\u{2028}나", "가 나"), ("가\u{1680}나", "가 나"), (" 가 ", " 가 "), ("  가", " 가"), ("가  ", "가 "), ("", ""),
                       ("…가", "…가"), ("\u{1100}\u{1161} 나", "\u{1100}\u{1161} 나"), ("가~나", "가~나"), ("é 가", "é 가")] {
            #expect(Array(Rx.oneSpace(s).unicodeScalars) == Array(e.unicodeScalars), "\(s.debugDescription)")
        }
        #expect(Rx.holds("가나다", "나") && !Rx.holds("가나다", "라") && Rx.holds("가", "가") && !Rx.holds("", "가"))
    }

    /// 되풀이 입력에 폭주하지 않는다 — 꼴마다 제 글자의 낱말을 되풀이한 글(× 8 · 16 · 32 · 64)을 맞추는 시간이 길이에 비례하는 만큼만 는다
    /// (길이 두 배에 시간 열 배까지 — 다항식의 여유 · 겹친 갈래의 되풀이는 256 배로 뛴다 · 절대 시간은 재지 않는다 · 짧은 것은 바닥 0.2 ms 로 본다).
    @Test func patternsDoNotBlowUp() throws {
        let floor = 0.0002
        var stuck: [String] = []
        for (name, pattern) in Mirror(reflecting: Words.shared.patterns).children.compactMap({ c in (c.value as? String).map { (c.label ?? "", $0) } }) {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            let own = Set(Rx.all(pattern, "[\\uAC00-\\uD7A3]+").map { String(pattern[$0]) })
            let words = own.union(["한 살", "지난주말", "이번 주말", "20대", "3월 2일", "어제", "작년에 ", "아니 ", "가나다라 ", "그리고 "])
            next: for w in words {
                for unit in [w, w + " "] {
                    var last = floor
                    for n in [8, 16, 32, 64] {
                        let body = String(repeating: unit, count: n) + "갔다"
                        let limit = max(last, floor) * 10
                        let start = spent()
                        var over = false
                        rx.enumerateMatches(in: body, options: [.reportProgress], range: NSRange(body.startIndex..., in: body)) { _, _, stop in
                            if spent() - start > limit * 4 { over = true; stop.pointee = true }
                        }
                        let took = spent() - start
                        if over || took > limit { stuck.append("\(name) · \(w) × \(n)"); break next }
                        last = took
                    }
                }
            }
        }
        #expect(stuck.isEmpty, "\(stuck)")
    }
    /// 빈칸을 빼며 앞 글자에 붙는 자모가 있어도 멈추지 않는다.
    @Test func strayJamoDoesNotStop() {
        for s in ["그저께 \u{11A8}갔어? 매일 가", "매일 \u{11A8}가던 \u{11A8}집", "작년\u{0301} 아니 \u{11A8}올해"] { _ = said(s) }
    }
    /// 공개 손도 되풀이 입력에 길이만큼만 는다.
    @Test func readingDoesNotBlowUp() {
        let now = day("2040-10-10")
        for w in ["한 살 ", "한살", "지난주말 ", "이번 주말 ", "20대 ", "3월 2일 ", "그저께 ", "4년 전 ", "작년에 산 배를 ", "아니 6년 전 ", "서른 살에서 ", "『가", "\"가 ", "사흘 안에 ", "4년 전 5월 ", "고3 때 6월 ", "5월생 ", "내 일 ", "내일 ", "4일 후배 ", "두 살 어린 ", "작년보다 ", "어릴 때보다 ",
                  "70년대 노래를 고3 때 ", "5월 3일~8일 ", "2081~2084년 ", "5월 3일이나 8일 ", "5월 3일부터 6일 아니 8일까지 ", "그 다음에 ", "작년에 타던 배를 지난 5월에 ", "작년 봄이었나 재작년 봄이었나 ", "어제오늘 ", "하나 세워 ", "아 아니다, ", "~", "아, "] {
            var last = 0.005
            for n in [5, 10, 20, 40, 80] {
                let s = String(repeating: w, count: n) + "갔다"
                let took = (0..<3).map { _ in let start = spent(); _ = SpokenReading.read(s, now: now, zone: zone); return spent() - start }.min()!
                #expect(took <= max(last, 0.005) * 10, "\(w) × \(n) — \(took)초")
                if took > max(last, 0.005) * 10 { return }   // 폭주하면 더 긴 글을 재지 않는다
                last = took
            }
        }
    }

    /// 묻기의 새 칸 — 옛 글(칸 없음)이 읽히고 · 비면 옛 글과 같은 바이트 · 차면 오간다.
    @Test func askCoding() throws {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        for (old, reason) in [(#"{"reason":"noExpression","rule":"none"}"#, SpokenReading.Ask.Reason.noExpression),
                              (#"{"anchorKey":"wedding","reason":"needsAnchor","rule":"lifeEvent"}"#, .needsAnchor)] {
            let a = try JSONDecoder().decode(SpokenReading.Ask.self, from: Data(old.utf8))
            #expect(a.reason == reason && a.candidates.isEmpty && a.direction == nil)
            #expect(String(decoding: try e.encode(a), as: UTF8.self) == old)
        }
        guard case .ask(let plain) = spoken("연못을 팠다") else { Issue.record("묻기가 아니다"); return }
        #expect(String(decoding: try e.encode(plain), as: UTF8.self) == #"{"reason":"noExpression","rule":"none"}"#)
        guard case .ask(let way) = spoken("나중에 배를 사겠다") else { Issue.record("묻기가 아니다"); return }
        #expect(String(decoding: try e.encode(way), as: UTF8.self) == #"{"direction":"future","reason":"unbounded","rule":"vague"}"#)
        guard case .ask(let two) = spoken("재작년 그리고 올해 거뒀다") else { Issue.record("묻기가 아니다"); return }
        #expect(two.reason == .conflict && two.candidates.count == 2)
        #expect(try JSONDecoder().decode(SpokenReading.Ask.self, from: e.encode(two)) == two)
        #expect(try JSONDecoder().decode(SpokenReading.Ask.self, from: e.encode(way)) == way)
    }
}
