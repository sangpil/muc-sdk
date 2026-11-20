import Foundation

// 모듈 `SpokenTime` — 계약 갈래(플랫폼 중립 · iOS · macOS · tvOS). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : 말한 때 읽기 — 한국어 문장 하나 + 기준 시각 + 시간대(+ 생년 · 기준 사건 · 방향)를 날의 구간 · 앵커 날 · 정밀도로(`read`) ·
//                 날 하나로(`day`) · 끝 날로(`end`) 푼다 · 기간 신호(`hasSpanSignal`). 모델 없이 · 결정적.
//   누가 부르나 : 엔진의 데이터 도구(문장에서 레코드 뽑기) · 프로젝트의 앱(기록 입력의 때 칸).
//   지키는 것   : 낱말 · 꼴은 모듈 자원 `Resources/words.json` 한 파일에만 산다(주석 밖 코드에 ASCII 밖 글자 0 — 게이트 `qa-sdk-build` ⑩) ·
//                 날은 기준 시간대의 정오다(시간대가 날 경계를 흔들어도 날이 바뀌지 않게) · 앵커는 늘 구간의 첫 날 · 정밀도는 구간의 폭에서 · 못 읽으면 지어내지 않고 까닭을 낸다.
//   시작점     : `SpokenReading`
//
// 읽는 차례(좁은 것이 이긴다): 되풀이(「매주 · 마다」 — 둘레 구간이 서지 않으면 시점이 아니다) → 「A부터 B까지」(A 의 처음 … B 의 끝) →
// 생년 · 기준 사건으로 읽는 때(인생 사건 > 학년 > 나이 > 나잇대 > 학교급 > 시대)와 절대 · 상대 날짜 — 둘이 서면 겹치는 구간 → 최근 → 끝 없는 때(묻기).
// 저장 꼴: 앵커 = 구간 첫 날 · 정밀도 = 하루 `exact` · 한 달 이하 `month` · 한 해 이하 `year`(흐리면 둘 다 `circa`) · 한 해 넘음 `period`(구간을 저장).
// 빈칸은 U+0020 만 빈칸으로 본다(문장의 다른 빈칸 글자는 부르는 쪽이 고른다). 수는 네 자리까지 읽는다(「N일 · N주 · N달 · N년 전 · 후」 · 「N박」).
// 자원 번들(`muc-sdk_SpokenTime`)은 이 모듈과 함께 실려야 한다 — 빠지면 첫 읽기에서 멈춘다(낱말 없이 읽은 답은 조용히 틀린다).

/// 문장 하나가 말한 때 — 구간 · 묻기 · 되풀이 셋 중 하나. 닫힌 열거다(갈래를 더하면 주 판).
/// 이 결과 열거는 `Codable` 이 아니다 — 연관값 열거의 합성 꼴이 저장 형식이 되지 않게. 담아 둘 것은 안의 값 꼴(`Span` · `Ask` · `Day`)로.
public enum SpokenReading: Sendable, Hashable {
    /// 말한 때의 구간.
    case span(Span)
    /// 때를 정하지 못했다 — 까닭과 무엇이 있으면 정하는지.
    case ask(Ask)
    /// 되풀이(「매주 · 주말마다」)는 시점이 아니다.
    case recurring

    /// 문장 하나를 구간으로 읽는다.
    /// - Parameters:
    ///   - sentence: 한국어 문장(빈칸 · 조사 그대로).
    ///   - now: 기준 시각 — 「어제 · 작년 · 지난 3월」이 이 시각의 날에서 센다.
    ///   - zone: 날을 세는 시간대 — 기준 시각의 날 · 낸 날의 정오 · 맥락의 생년 · 기준 사건의 날을 이 시간대로 읽는다.
    ///   - context: 생년 · 기준 사건(나이 · 학년 · 「결혼하고 나서」 같은 때) — 없으면 그런 때는 `.ask` 로 묻는다.
    ///   - direction: 문장이 지난 일인가 앞일인가(기본 지난 일 — `Direction`).
    public static func read(_ sentence: String, now: Date, zone: TimeZone, context: Context = .empty, direction: Direction = .past) -> SpokenReading {
        SpanReader(zone: zone, words: .shared, direction: direction).read(sentence, now: now, context: context)
    }

    /// 문장 하나를 날 하나로 읽는다 — 말한 단위까지(날 · 주 = `exact` · 달 · 반년 = `month` · 해 = `year` · 흐리면 `circa` · `period` 는 내지 않는다).
    /// 앵커는 그 단위의 첫 날(달 초 · 중순 · 말 = 1 · 11 · 21일 · 해 말 = 10월 1일 · 계절 = 첫 달 1일). 날 단위 상대 표현이 있으면 그것이 때다 ·
    /// 되풀이 문장은 말한 시작(「A부터」의 A)만 · 못 읽으면 nil(나이 · 학년 · 기준 사건 같은 때는 이 손이 읽지 않는다 — `read`).
    /// - Parameter direction: 방향(`Direction` — 앞일이면 수식 없는 달 · 날 · 계절을 오늘 이후로).
    public static func day(_ sentence: String, now: Date, zone: TimeZone, direction: Direction = .past) -> Day? {
        DayReader(zone: zone, words: .shared).resolve(sentence, now: now, future: direction == .future)
    }

    /// 문장이 말한 끝 날 — 말한 끝만(지어내지 않는다): 「A부터 B까지」 = B(빠진 해 · 달은 시작에서 잇고, 이은 끝이 시작보다 앞이면 빠진 쪽의 윗 단위를
    /// 하나 올린다 — 「10월 25일부터 3일까지」 = 다음 달 3일 · 「12월 28일부터 1월 3일까지」 = 다음 해) · 「N박」 = 시작 + N일(시작이 `exact` 일 때만 ·
    /// 「박」 뒤가 낱말 경계일 때만) · 그 밖(「동안」만 · 「부터」만)은 nil.
    /// - Parameters:
    ///   - start: 시작 날(보통 같은 문장의 `day`) — 그 연 · 월 · 일로 센다(다른 시간대에서 지은 날이어도 날이 어긋나지 않는다).
    ///   - direction: 방향 — 끝을 문장 그대로 읽을 때(시작이 없거나 끝에 해 · 달이 있을 때) `day` 와 같은 뜻.
    public static func end(_ sentence: String, start: Day?, now: Date, zone: TimeZone, direction: Direction = .past) -> Day? {
        DayReader(zone: zone, words: .shared).resolveEnd(sentence, start: start, now: now, future: direction == .future)
    }

    /// 문장에 기간 신호가 있는가 — 「N박」(낱말 경계 · 빈칸을 뺀 글에서) · 「동안」 · 「…부터 …까지」(빈칸이 있는 글에서 — 「운동 안 했다」는 아니다).
    public static func hasSpanSignal(_ sentence: String) -> Bool {
        DayReader.spanSignal(sentence, words: .shared)
    }

    /// Whether the sentence speaks of something past or something ahead. The caller passes it from its own classification of the sentence;
    /// the reader does not guess it. A modifier the sentence states (last · next · this year …) always wins over the hint.
    /// `future` changes three readings: a two-digit year or decade becomes the closest such year at or after the reference year
    /// (`past`, the default, puts it in the reference year's century and moves it back a century when that lands after the reference year);
    /// a month or a month and day with no modifier becomes the closest one from today on (today and this month included);
    /// a season with no modifier becomes the closest one that has not ended yet (the current season included).
    /// 방향은 부르는 쪽이 문장 분류로 넘긴다 — 문장의 수식어가 늘 힌트를 이긴다. 앞일이 바꾸는 것은 셋: 두 자리 해 · 연대(기준 해 이상 가장 가까운 해) ·
    /// 수식 없는 달 · 달과 날(오늘 · 이번 달을 넣어 오늘 이후 가장 가까운 것) · 수식 없는 계절(아직 끝나지 않은 가장 가까운 것). 닫힌 열거다(갈래를 더하면 주 판).
    public enum Direction: String, Sendable, Hashable, Codable, CaseIterable {
        /// 지난 일(기본).
        case past
        /// 앞일.
        case future
    }

    /// 날 하나 — 기준 시간대의 정오와 그 날의 연 · 월 · 일 · 정밀도(`exact` · `month` · `year` · `circa`).
    public struct Day: Sendable, Hashable, Codable {
        /// 그 날 기준 시간대의 정오.
        public let date: Date
        public let year: Int
        public let month: Int
        public let day: Int
        public let precision: Precision
        /// 「YYYY-MM-DD」.
        public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

        /// 날 하나를 짓는다 — 그 시간대의 정오 · 넘친 값(2월 30일)은 달력이 굴린 날로 · 달력이 짓지 못하면 nil.
        public init?(year: Int, month: Int, day: Int, precision: Precision, zone: TimeZone) {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zone
            guard let d = c.date(from: DateComponents(timeZone: zone, year: year, month: month, day: day, hour: 12)) else { return nil }
            let k = c.dateComponents([.year, .month, .day], from: d)
            guard let y = k.year, let m = k.month, let dd = k.day else { return nil }
            self.init(date: d, year: y, month: m, day: dd, precision: precision)
        }
        init(date: Date, year: Int, month: Int, day: Int, precision: Precision) {
            self.date = date; self.year = year; self.month = month; self.day = day; self.precision = precision
        }
    }

    /// 구간 — 날은 모두 기준 시간대의 정오다(`from` · `to` 는 양 끝을 넣는다).
    public struct Span: Sendable, Hashable, Codable {
        /// 구간 첫 날.
        public let from: Date
        /// 구간 끝 날(포함).
        public let to: Date
        /// 저장할 날 — 늘 구간 첫 날(`from` 과 같다).
        public let anchor: Date
        /// 저장할 정밀도 — 구간의 폭에서.
        public let precision: Precision
        /// 읽은 규칙의 이름 — `absolute` · `relative` · `era` · `age` · `ageBand` · `grade` · `schoolStage` · `lifeEvent` ·
        /// 계절로 좁혔으면 `+season` 을 붙인다(`absolute+season`) · 생년으로 읽은 때와 겹쳐 좁혔으면 그 이름을 붙인다(`absolute+grade`).
        /// 열린 낱말이다 — 규칙이 자라면 부 판에서 낱말이 늘 수 있다(부르는 쪽은 모르는 낱말을 그대로 든다).
        public let rule: String
        /// 흐린 때인가(「쯤 · 무렵 · 초 · 말 · 계절 · 나이」 — 사람이 확인할 값).
        public let soft: Bool
        /// 맞은 토막(빈칸을 뺀 글).
        public let phrase: String
    }

    /// 저장 정밀도. 닫힌 열거다(갈래를 더하면 주 판).
    public enum Precision: String, Sendable, Hashable, Codable, CaseIterable {
        /// 하루.
        case exact
        /// 한 달 이하.
        case month
        /// 한 해 이하.
        case year
        /// 한 해 이하이고 흐리다.
        case circa
        /// 한 해 넘는 시기 — 구간을 저장한다.
        case period
    }

    /// 묻기 — 때를 정하지 못한 까닭.
    public struct Ask: Sendable, Hashable, Codable {
        /// 까닭 — 열린 꼴(아는 낱말 + 모르는 낱말도 그대로 든다 · 부르는 쪽은 `default` 를 둔다).
        public struct Reason: RawRepresentable, Sendable, Hashable, Codable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            /// 때 표현이 없다.
            public static let noExpression = Reason(rawValue: "noExpression")
            /// 끝 없는 때(「예전에 · 언젠가」).
            public static let unbounded = Reason(rawValue: "unbounded")
            /// 생년이 있어야 정한다(나이 · 학년 · 학교급 · 시대).
            public static let needsBirth = Reason(rawValue: "needsBirth")
            /// 기준 사건이 있어야 정한다(`anchorKey`).
            public static let needsAnchor = Reason(rawValue: "needsAnchor")
            /// 이 SDK 가 아는 낱말 — 차례 그대로.
            public static let known: [Reason] = [.noExpression, .unbounded, .needsBirth, .needsAnchor]
            public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
            public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
        }
        public let reason: Reason
        /// `needsAnchor` 면 그 기준 사건의 키(`Context.Anchor.key` 와 같은 낱말).
        public let anchorKey: String?
        /// 읽은 규칙의 이름(`Span.rule` 과 같은 낱말 · 때 표현이 없으면 `none` · 끝 없는 때는 `vague`).
        public let rule: String
    }

    /// 생년 · 기준 사건 — 나이 · 학년 · 「결혼하고 나서」 같은 때를 날로 바꾸는 재료. 날은 읽는 손의 `zone` 으로 읽는다(그 시간대의 날).
    public struct Context: Sendable, Hashable, Codable {
        /// 기준 사건 하나 — 키는 사건의 종류(`wedding` · `first-job` · `military-enlist` · `military-discharge` · `childbirth` · `retirement` · `move` · `university`).
        public struct Anchor: Sendable, Hashable, Codable {
            public let key: String
            public let start: Date
            /// 기간 사건의 끝(있으면).
            public let end: Date?
            public init(key: String, start: Date, end: Date? = nil) { self.key = key; self.start = start; self.end = end }
        }
        public let birth: Date?
        public let anchors: [Anchor]
        public init(birth: Date?, anchors: [Anchor] = []) { self.birth = birth; self.anchors = anchors }
        /// 생년도 기준 사건도 없다.
        public static let empty = Context(birth: nil)

        /// 같은 키가 여럿이면 가장 이른 것.
        func anchor(_ key: String) -> Anchor? { anchors.filter { $0.key == key }.min { $0.start < $1.start } }
    }
}
