import Foundation
@testable import ProjectFormat
import Testing
import TestScratch

// 모델의 말 이름 표 — 계약(`Docs/MODEL-WORDS.md`)의 벡터(`Fixtures/model-words-vectors.json`) 전부 · 문서의 예문 = 벡터의 표 ·
// 불변식 셋(벡터의 표 · 씨앗을 고정한 무작위 표) · 아무 바이트에도 죽지 않는다 · 서가 폴더에서 읽기.
// 답은 글자가 아니라 바이트로 견준다(Swift 의 글 견줌은 정준 동치라 NFC 를 빠뜨려도 같다고 한다).

@Suite("모델의 말 이름 표")
struct ModelWordsTests {
    typealias Rows = [[String?]]

    struct Vectors: Decodable {
        struct Case: Decodable, Sendable { let id, table, word, language: String, among: [String], expect: Rows }
        struct List: Decodable, Sendable { let id, table, language: String, among: [String], expect: [Row] }
        struct Row: Decodable, Sendable {
            let text: String, candidates: Rows
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                text = try c.decode(String.self); candidates = try c.decode(Rows.self)
            }
        }
        struct Ask: Decodable, Sendable {
            let word, language: String, among: [String], expect: Rows
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                word = try c.decode(String.self); language = try c.decode(String.self)
                among = try c.decode([String].self); expect = try c.decode(Rows.self)
            }
        }
        /// 글(`text`) ⟂ 되풀이 조각(`pieces` — [글, 몇 번]) ⟂ 바이트(`hex`).
        struct File: Decodable, Sendable {
            struct Piece: Decodable, Sendable {
                let text: String, times: Int
                init(from decoder: Decoder) throws {
                    var c = try decoder.unkeyedContainer()
                    text = try c.decode(String.self); times = try c.decode(Int.self)
                }
            }
            let id: String, text: String?, pieces: [Piece]?, hex: String?, code: String?, asks: [Ask]?
            /// 바이트 — `hex` 가 열여섯 진수 짝이 아니면 nil(시험이 실패한다).
            var data: Data? {
                if let pieces { return Data(pieces.map { String(repeating: $0.text, count: $0.times) }.joined().utf8) }
                if let hex {
                    let digits = hex.compactMap { $0.isASCII ? $0.hexDigitValue.map(UInt8.init) : nil }
                    guard digits.count == hex.count, digits.count.isMultiple(of: 2) else { return nil }
                    return Data(stride(from: 0, to: digits.count, by: 2).map { digits[$0] << 4 | digits[$0 + 1] })
                }
                return text.map { Data($0.utf8) }
            }
        }
        let tables: [String: JSONValue], cases: [Case], words: [List], readable: [File], unreadable: [File]
    }

    static let vectors: Vectors = {
        do { return try JSONDecoder().decode(Vectors.self, from: IsoDataFixture.data("model-words-vectors.json")) } catch { fatalError("\(error)") }
    }()
    static let tables: [String: ModelWords] = {
        do { return try vectors.tables.mapValues { try ModelWords(data: JSONEncoder().encode($0)) } } catch { fatalError("\(error)") }
    }()

    /// 바이트까지 견줄 글 — 후보마다 [모델 · 종류 · 낱말 · 맞음].
    static func line(_ rows: Rows) -> [UInt8] { Array(rows.map { $0.map { $0 ?? "\u{1}" }.joined(separator: "\u{2}") }.joined(separator: "\u{3}").utf8) }
    static func rows(_ candidates: [ModelWords.Candidate]) -> Rows { candidates.map { [$0.model, $0.kind, $0.word, $0.match.rawValue] } }
    static func code(_ data: Data) -> String {
        do { _ = try ModelWords(data: data); return "reads" } catch let error as ModelWords.Unreadable { return error.code } catch { return "\(error)" }
    }

    @Test("묻기 벡터", arguments: vectors.cases)
    func asks(_ c: Vectors.Case) throws {
        let got = Self.rows(try #require(Self.tables[c.table]).candidates(for: c.word, language: c.language, among: c.among))
        #expect(Self.line(got) == Self.line(c.expect), "\(c.id) \(got) ≠ \(c.expect)")
    }

    @Test("목록 벡터", arguments: vectors.words)
    func lists(_ c: Vectors.List) throws {
        let got = try #require(Self.tables[c.table]).words(language: c.language, among: c.among)
        #expect(got.map { Array($0.text.utf8) } == c.expect.map { Array($0.text.utf8) }, "\(c.id) \(got.map(\.text))")
        #expect(got.map { Self.line(Self.rows($0.candidates)) } == c.expect.map { Self.line($0.candidates) }, "\(c.id)")
    }

    @Test("읽히는 꼴", arguments: vectors.readable)
    func reads(_ c: Vectors.File) throws {
        let table = try ModelWords(data: #require(c.data, "\(c.id) — 바이트로 풀리지 않는다"))
        for ask in c.asks ?? [] {
            let got = Self.rows(table.candidates(for: ask.word, language: ask.language, among: ask.among))
            #expect(Self.line(got) == Self.line(ask.expect), "\(c.id) \(got)")
        }
    }

    @Test("못 읽는 꼴과 그 코드", arguments: vectors.unreadable)
    func refuses(_ c: Vectors.File) throws {
        #expect(Self.code(try #require(c.data, "\(c.id) — 바이트로 풀리지 않는다")) == c.code, "\(c.id)")
    }

    @Test("벡터의 열여섯 진수 — 짝이 아니거나 다른 글자면 바이트가 없다", arguments: [("7b7d", true), ("7b7", false), ("7bxd", false), ("７b", false)])
    func hexIsStrict(_ hex: String, _ fine: Bool) throws {
        let file = try JSONDecoder().decode(Vectors.File.self, from: JSONEncoder().encode(["id": "x", "hex": hex]))
        #expect((file.data != nil) == fine)
    }

    @Test("벡터마다 제 이름 · 표는 모두 쓰인다")
    func vectorsAreWhole() {
        let v = Self.vectors, ids = v.cases.map(\.id) + v.words.map(\.id) + v.readable.map(\.id) + v.unreadable.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 344)
        #expect(Set(v.cases.map(\.table) + v.words.map(\.table)) == Set(v.tables.keys))
    }

    // MARK: 문서

    static let document = SDKDocumentTests.document.deletingLastPathComponent().appendingPathComponent("MODEL-WORDS.md")

    @Test("계약 문서의 예문 = 벡터의 표 main")
    func theDocumentShowsTheVectorTable() throws {
        let text = try String(contentsOf: Self.document, encoding: .utf8)
        let block = try #require(text.components(separatedBy: "```json\n").dropFirst().first?.components(separatedBy: "\n```").first)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(block.utf8)) == Self.vectors.tables["main"])
        #expect(try ModelWords(data: Data(block.utf8)) == Self.tables["main"])
    }

    @Test("계약 문서의 수와 이름 = 코드")
    func theDocumentStatesTheLimits() throws {
        let text = try String(contentsOf: Self.document, encoding: .utf8)
        #expect(text.contains("`\(ModelWords.fileName)`"))
        #expect(text.contains("**Table version: \(ModelWordsFormat.version)**"))
        #expect(ModelWordsFormat.maxBytes == 2 << 20 && text.contains("2 MiB (\(ModelWordsFormat.maxBytes) bytes)"))
        #expect(text.contains("\(ModelWordsFormat.maxDepth) levels"))
        #expect(text.contains("over \(ModelWordsFormat.maxRaw) bytes, or over \(ModelWordsFormat.maxText) bytes once put into NFC"))
        #expect(text.contains("is at most \(ModelWordsFormat.maxReach):"))
        #expect(text.contains("**Rule 21.** The walk passes at most \(ModelWordsFormat.maxSteps) kinds"))
        for code in Set(Self.vectors.unreadable.compactMap(\.code)) { #expect(text.contains("`\(code)`"), "\(code)") }
        for rule in 1...33 { #expect(text.contains("**Rule \(rule).") || text.contains("**Rule \(rule) — "), "Rule \(rule)") }
    }

    // MARK: 불변식

    static let languages = ["ko", "ko-KR", "en", "pt", "pt-PT", "zh", "zh-Hans-CN", "fr", "tr", "de", "x", "", "_"]

    /// I1 · I2 · I3 — `asked` 는 물어볼 말들.
    static func invariants(_ table: ModelWords, _ language: String, _ models: [String], _ asked: [String]) {
        let rows = table.words(language: language, among: models)
        for row in rows {
            #expect(!row.candidates.isEmpty, "I1")
            #expect(line(Self.rows(table.candidates(for: row.text, language: language, among: models))) == line(Self.rows(row.candidates)), "I1 \(row.text)")
        }
        for said in asked where ModelWords.short(said) != nil {   // 긴 말은 아무것과도 안 맞는다(규칙 7)
            let got = table.candidates(for: said, language: language, among: models)
            let same = rows.filter { Array(ModelWords.fold($0.text).utf8) == Array(ModelWords.fold(said).utf8) }
            #expect(got.isEmpty == same.isEmpty, "I2 \(said)")
            for row in same { #expect(line(Self.rows(row.candidates)) == line(Self.rows(got)), "I2 \(said)") }
        }
        #expect(table.words(language: language, among: []).isEmpty, "I3")
        if ModelWords.tag(language).isEmpty { #expect(rows.isEmpty, "I3") }
        // 줄의 차례 — 접은 글자의 스칼라 수 · 접은 글자의 바이트 · 글자의 바이트
        for (a, b) in zip(rows, rows.dropFirst()) {
            let x = ModelWords.fold(a.text), y = ModelWords.fold(b.text)   // 같음도 바이트로
            let n = x.unicodeScalars.count, m = y.unicodeScalars.count
            #expect(n > m || n == m && (ModelWords.precedes(x, y) || Array(x.utf8) == Array(y.utf8) && ModelWords.precedes(a.text, b.text)), "\(a.text) · \(b.text)")
        }
    }

    @Test("불변식 — 벡터의 표마다", arguments: vectors.tables.keys.sorted())
    func invariantsOnVectors(_ name: String) throws {
        let table = try #require(Self.tables[name])
        guard case .object(let root)? = Self.vectors.tables[name] else { Issue.record("표가 객체가 아니다"); return }
        var models: [String] = []
        if case .object(let o)? = root["models"] { models = o.keys.sorted() }
        for language in Self.languages { for among in [models, models.reversed()] { Self.invariants(table, language, among, Self.vectors.cases.map(\.word)) } }
    }

    /// 씨앗을 고정한 수열(SplitMix64) — 몇 번을 돌려도 같은 표.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let spellings = ["ab", "AB", "a b", "a-b", "ａｂ", "b", "B ", "é", "e\u{301}", "É", "e\u{200D}\u{301}", "나", "\u{1102}\u{1161}", "나무", "나 무", "abc", "ab-c", "c", "", " ", "-", "’c", "'c", "ʼC"]
    static let tags = ["ko", "KO", "ko-KR", "ko_kr", "kor", "k", "en", "en-GB", "", "-", "zh-Hans", "zh-Hans-CN"]

    static func randomTable(_ rng: inout Seeded) -> (json: [String: JSONValue], models: [String]) {
        let kinds = ["k0", "k1", "k2", "k3", "k4"], models = ["m0", "m1", "m2", "m3", "m4", "m5", "é"]
        func words(_ rng: inout Seeded) -> JSONValue {
            var out: [String: JSONValue] = [:]
            for _ in 0..<Int.random(in: 0...3, using: &rng) {
                let count = Int.random(in: 0...4, using: &rng)
                out[tags.randomElement(using: &rng)!] = .array((0..<count).map { _ in .string(spellings.randomElement(using: &rng)!) })
            }
            return .object(out)
        }
        func table(_ names: [String], up: String, _ rng: inout Seeded) -> JSONValue {
            var out: [String: JSONValue] = [:]
            for name in names where Int.random(in: 0..<8, using: &rng) > 0 {
                var fields: [String: JSONValue] = ["words": words(&rng)]
                switch Int.random(in: 0..<6, using: &rng) {
                case 0: break
                case 1: fields[up] = "no-such-kind"
                default: fields[up] = .string(kinds.randomElement(using: &rng)!)
                }
                out[name] = Int.random(in: 0..<12, using: &rng) == 0 ? .null : .object(fields)
            }
            return .object(out)
        }
        return (["version": 1, "kinds": table(kinds, up: "parent", &rng), "models": table(models, up: "kind", &rng)], models + ["e\u{301}", "none"])
    }

    @Test("불변식 — 무작위 표 200", arguments: [UInt64(1), 2, 3, 4])
    func invariantsOnRandomTables(_ seed: UInt64) throws {
        var rng = Seeded(state: seed)
        for _ in 0..<50 {
            let (json, names) = Self.randomTable(&rng)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let table = try ModelWords(data: encoder.encode(json))
            let among = names.shuffled(using: &rng).prefix(Int.random(in: 1...names.count, using: &rng)) + [names[0]]
            Self.invariants(table, Self.tags.randomElement(using: &rng)!, Array(among), Self.spellings)
        }
    }

    @Test("글의 저장 꼴은 뜻이 없다 — Foundation 에서 온(이어지지 않은) 글로 물어도 같은 답")
    func bridgedTextAnswersAlike() throws {
        let name = "화분-모형-둘"
        let foreign = NSString(characters: Array(name.utf16), length: name.utf16.count) as String
        #expect(foreign.utf8.withContiguousStorageIfAvailable { _ in true } == nil, "the fixture: storage that is not contiguous")
        let table = try ModelWords(data: Data(#"{"version":1,"kinds":{"화분":{"words":{"ko":["화분"]}}},"models":{"화분-모형-둘":{"kind":"화분"}}}"#.utf8))
        #expect(table.candidates(for: "화분", language: "ko", among: [foreign]) == table.candidates(for: "화분", language: "ko", among: [name]))
        #expect(table.candidates(for: "화분", language: "ko", among: [foreign]).count == 1)
        #expect(table.words(language: "ko", among: [foreign]).map(\.text) == ["화분"])
        let asked = NSString(characters: Array("화분".utf16), length: "화분".utf16.count) as String
        #expect(table.candidates(for: asked, language: NSString(string: "ko-KR") as String, among: [foreign]).count == 1)
        #expect(Name(text: foreign) == Name(text: name) && Name(text: foreign).hashValue == Name(text: name).hashValue)
    }

    @Test("적힌 차례는 뜻이 없다 — 낱말을 섞고 되풀이해도 같은 표")
    func orderMeansNothing() throws {
        let a = try ModelWords(data: Data(#"{"version":1,"models":{"pot":{"words":{"ko":["분","화분"],"KO":["그릇"]}}}}"#.utf8))
        let b = try ModelWords(data: Data(#"{"models":{"pot":{"words":{"KO":["화분"," "],"ko":["그릇","분","화분"],"en":[]}}},"version":1.0,"about":3}"#.utf8))
        let c = try ModelWords(data: Data(#"{"version":1,"models":{"pot":{"words":{"ko":["분"]}}}}"#.utf8))
        #expect(a == b && a != c)
    }

    @Test("아무 바이트에도 죽지 않는다 — 바이트를 고치고 자르고 끼운 파일 4000")
    func brokenBytesNeverTrap() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // 씨앗이 같으면 같은 바이트를 고친다
        let whole = Array(try encoder.encode(#require(Self.vectors.tables["edges"])))
        #expect(String(decoding: whole, as: UTF8.self).hasPrefix(#"{"kinds":{"a":{"parent":"b","words""#), "키 차례가 고정되지 않았다")
        let known: Set = ["reads", "file.unreadable", "version.missing", "version.tooNew"]
        var rng = Seeded(state: 7), refused = 0
        for _ in 0..<4000 {
            var bytes = whole
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                let at = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<4, using: &rng) {
                case 0: bytes[at] = UInt8.random(in: 0...255, using: &rng)
                case 1: bytes.insert(Array("{}[]\",:\\-0e.u".utf8).randomElement(using: &rng)!, at: at)
                case 2: bytes.remove(at: at)
                default: bytes.removeSubrange(at...)
                }
                if bytes.isEmpty { bytes = [0] }
            }
            let code = Self.code(Data(bytes))
            #expect(known.contains(code), "\(code)")
            if code != "reads" { refused += 1 }
        }
        #expect(refused > 1000)
    }

    // MARK: 값의 상한

    /// 이 스레드가 쓴 CPU 시간(초) — 벽시계가 아니라 곁에서 도는 시험에 흔들리지 않는다.
    static func cpu(_ body: () throws -> Void) rethrows -> Double {
        func now() -> Double {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
        }
        let start = now()
        try body()
        return now() - start
    }

    /// 1 MiB 안의 나쁜 표 — 글과 부를 모델.
    static let worst: [(name: String, text: String, models: [String])] = {
        func models(_ n: Int, _ kind: (Int) -> String) -> String { (0..<n).map { #""m\#($0)":{"kind":"\#(kind($0))"}"# }.joined(separator: ",") }
        func table(_ kinds: String, _ models: String) -> String { #"{"version":1,"kinds":{\#(kinds)},"models":{\#(models)}}"# }
        let names = (0..<30000).map { "m\($0)" }
        let chain = (0..<22000).map { #""\#($0)":{"parent":"\#($0 + 1)","words":{"x":["w\#($0)"]}}"# }.joined(separator: ",")
        let bare = (0..<30000).map { #""\#($0)":{"parent":"\#(($0 + 1) % 30000)"}"# }.joined(separator: ",")
        let marks = (0..<500).map { #""\#($0)a\#(String(repeating: "\u{301}\u{316}", count: 250))""# }.joined(separator: ",")
        let wide = (0..<7000).map { #""w\#($0)""# }.joined(separator: ",")
        let acute = String(repeating: "e\u{301}", count: 20)
        let nfd = table((0..<62).map { #""\#(acute)\#($0)":{"parent":"\#(acute)\#($0 + 1)"}"# }.joined(separator: ","), models(8000) { "\(acute)\($0 % 62)" })
        let spread = (0..<10000).map { #""w\#(String(repeating: " ", count: $0 % 100))\#(String(repeating: "-", count: $0 / 100))""# }.joined(separator: ",")
        return [
            ("낱말이 다른 긴 사슬", table(chain, models(30000) { "\($0 % 20000)" }), names),
            ("긴 고리 — 모델마다 다른 자리에서", table(bare, models(30000) { "\($0)" }), names),
            ("낱말 많은 종류에 모델 많이 — 상한 가까이", table(#""k":{"words":{"x":[\#(wide)]}}"#, models(299) { _ in "k" }), Array(names.prefix(299))),
            ("NFD 이름의 62 겹 사슬에 모델 많이", nfd, names),
            ("닿지 않는 항목이 적은, 접으면 같은 글자", table(#""k":{"words":{"x":[\#(spread)]}}"#, #""m0":{"words":{"x":["w"]}}"#), ["m0"]),
            ("결합 글자가 이어진 낱말 · 키", #"{"version":1,"kinds":{\#(marks.replacingOccurrences(of: ",", with: ":{},")):{}},"models":{"m0":{"words":{"x":[\#(marks)]}}}}"#, names),
        ]
    }()

    @Test("나쁜 표도 크기만큼만 든다 — 읽기 · 묻기 · 목록의 CPU 시간", arguments: worst.indices)
    func costIsBounded(_ i: Int) throws {
        let (name, text, models) = Self.worst[i]
        #expect(text.utf8.count <= ModelWordsFormat.maxBytes && text.utf8.count > ModelWordsFormat.maxBytes / 100, "\(name) \(text.utf8.count)")
        let spent = try Self.cpu {
            let table = try ModelWords(data: Data(text.utf8))
            _ = table.candidates(for: "w1", language: "x", among: models)
            let rows = table.words(language: "x", among: models)
            #expect(rows.reduce(0) { $0 + $1.candidates.count } <= ModelWordsFormat.maxReach)
        }
        #expect(spent < 20, "\(name) — \(spent) 초")
        if ProcessInfo.processInfo.environment["MODEL_WORDS_COST"] == "1" { print("model-words cost", name, spent) }
    }

    @Test("긴 말 · 긴 이름은 접기 앞에서 거른다 — 결합 글자가 이어진 글의 CPU 시간")
    func longTextIsJudgedBeforeFolding() throws {
        let long = "a" + String(repeating: "\u{301}\u{316}", count: 250_000)
        let spent = try Self.cpu {   // 읽기도 안에서 잰다
            let table = try ModelWords(data: Data(#"{"version":1,"models":{"m":{"words":{"x":["\#(long)","ab"]}}}}"#.utf8))
            #expect(table.candidates(for: long, language: "x", among: ["m"]).isEmpty)
            #expect(table.candidates(for: "ab", language: "x", among: [long, "m"]).map(\.model) == ["m"])
            #expect(table.words(language: "x", among: [long, "m"]).map(\.text) == ["ab"])
            #expect(table.words(language: long, among: ["m"]).isEmpty && table.candidates(for: "ab", language: long, among: ["m"]).isEmpty)
        }
        #expect(spent < 1, "\(spent) 초")
    }

    @Test("앱의 의무(규칙 32) — 실은 표를 낼 언어와 모델로 물어 빈 답이면 빨강")
    func theShippedTableCheck() throws {
        func passes(_ shelf: URL, _ languages: [String], _ models: [String]) throws -> Bool {
            let table = try ModelWords.load(shelf: shelf)
            return languages.allSatisfy { !table.words(language: $0, among: models).isEmpty }
        }
        try TestScratch.withFolder("model-words") { folder in
            let file = folder.appendingPathComponent(ModelWords.fileName)
            #expect(try !passes(folder, ["ko"], ["pot"]))   // 파일이 없다
            for (text, fine) in [(#"{"version":1,"models":{"pot":{"words":{"ko":["분"]}}}}"#, true),   // 종류 없는 표도 선다
                                 (#"{"version":1,"kinds":{"k":{"words":{"ko":["분"]}}},"models":{"pot":{"kind":"k"}}}"#, true),
                                 (#"{"version":1}"#, false), (#"{"version":1,"models":{"pot":{}}}"#, false),
                                 (#"{"version":1,"models":{"other":{"words":{"ko":["분"]}}}}"#, false), (#"{"version":1,"models":{"pot":{"words":{"en":["pot"]}}}}"#, false)] {
                try Data(text.utf8).write(to: file)
                #expect(try passes(folder, ["ko"], ["pot"]) == fine, "\(text)")
            }
            for text in [#"{"version":2}"#, "{"] {
                try Data(text.utf8).write(to: file)
                #expect(throws: ModelWords.Unreadable.self) { try passes(folder, ["ko"], ["pot"]) }
            }
        }
        // 문서의 예문이 이 꼴이다
        #expect(try String(contentsOf: Self.document, encoding: .utf8).contains("#expect(!table.words(language: language, among: shippedModels).isEmpty)"))
    }

    @Test("접기의 지름길 — 그대로인 글자 · 소문자가 저 자신인 글자 · 빈칸이 유니코드와 같다")
    func shortcutsAgreeWithUnicode() {
        var wrong: [UInt32] = []
        for value in UInt32(0)...0xFFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = String(scalar)
            if ModelWords.isSettled(text), scalar.properties.canonicalCombiningClass != .notReordered
                || Array(text.precomposedStringWithCompatibilityMapping.unicodeScalars) != [scalar] { wrong.append(value) }
            switch value {
            case 0x00..<0x41, 0x5B..<0x80, 0x0300..<0x0370, 0x0590..<0x10A0, 0x1100..<0x13A0, 0x2E80..<0xA640, 0xAC00..<0xFB00, 0xFB50..<0xFF00:
                if scalar.properties.lowercaseMapping.unicodeScalars.elementsEqual([scalar]) == false { wrong.append(value) }
            default: break
            }
            // 빈칸은 접혀 사라진다 — 사라지는 것은 빈칸과 적힌 하이픈 · 폭 없는 글자뿐
            let gone = [0x2D, 0xAD, 0x2060, 0xFEFF].contains(value) || (0x2010...0x2015).contains(value) || (0x200B...0x200D).contains(value)
            if text.precomposedStringWithCompatibilityMapping.unicodeScalars.elementsEqual([scalar]), ModelWords.fold(text).isEmpty != (scalar.properties.isWhitespace || gone) { wrong.append(value) }
        }
        #expect(wrong.isEmpty, "\(wrong.prefix(8).map { String($0, radix: 16) })")
        // 그대로인 글자끼리 나란해도 그대로다
        var rng = Seeded(state: 11)
        let settled = (UInt32(0)...0xFFFF).compactMap(Unicode.Scalar.init).filter { ModelWords.isSettled(String($0)) }
        for _ in 0..<3000 {
            var view = String.UnicodeScalarView()
            for _ in 0..<12 { view.append(settled.randomElement(using: &rng)!) }
            let text = String(view)
            #expect(Array(text.precomposedStringWithCompatibilityMapping.utf8) == Array(text.utf8))
        }
    }

    // MARK: 공개 꼴

    @Test("열린 낱말 · 오류의 말 · 빈 표")
    func publicShapes() throws {
        #expect(ModelWords.Match(rawValue: "exact") == .exact && ModelWords.Match(rawValue: "broader") == .broader && ModelWords.Match(rawValue: "near").rawValue == "near")
        #expect(ModelWords().words(language: "ko", among: ["pot"]).isEmpty && ModelWords() == Self.tables["empty"])
        #expect(ModelWords.fileName == "model-words.json")
        let error = #expect(throws: ModelWords.Unreadable.self) { try ModelWords(data: Data(#"{"version":1,"models":{"pot":{"words":{"ko":["분",3]}}}}"#.utf8)) }
        #expect(error?.message.contains("models.pot.words.ko[1]") == true && error?.errorDescription == error?.message)
        // 자료의 자리가 0 에서 시작하지 않아도 같다
        #expect(try ModelWords(data: Data("xx{\"version\":1}".utf8).dropFirst(2)) == ModelWords())
    }

    // MARK: 서가 폴더

    @Test("서가 폴더 — 없는 폴더 · 없는 파일은 빈 표 · 있는 파일은 읽는다(링크 끝도)")
    func loadsFromAShelf() throws {
        try TestScratch.withFolder("model-words") { folder in
            #expect(try ModelWords.load(shelf: folder.appendingPathComponent("none")) == ModelWords())
            #expect(try ModelWords.load(shelf: folder) == ModelWords())
            let bytes = try JSONEncoder().encode(#require(Self.vectors.tables["main"]))
            try bytes.write(to: folder.appendingPathComponent("real.json"))
            let file = folder.appendingPathComponent(ModelWords.fileName)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: folder.appendingPathComponent("real.json"))
            #expect(try ModelWords.load(shelf: folder) == Self.tables["main"])
            let link = folder.appendingPathComponent("linked-shelf")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
            #expect(try ModelWords.load(shelf: link) == Self.tables["main"])
            // 하위 폴더는 보지 않는다
            let outer = folder.appendingPathComponent("outer")
            try FileManager.default.createDirectory(at: outer.appendingPathComponent("inner"), withIntermediateDirectories: true)
            try bytes.write(to: outer.appendingPathComponent("inner").appendingPathComponent(ModelWords.fileName))
            #expect(try ModelWords.load(shelf: outer) == ModelWords())
        }
    }

    @Test("서가 폴더 — 이름은 글자 그대로 · 있는데 못 읽으면 던진다")
    func loadRefuses() throws {
        func code(_ shelf: URL) -> String {
            do { _ = try ModelWords.load(shelf: shelf); return "reads" } catch let error as ModelWords.Unreadable { return error.code } catch { return "\(error)" }
        }
        try TestScratch.withFolder("model-words") { folder in
            func shelf(_ name: String) throws -> URL {
                let url = folder.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            }
            // 대소문자만 다른 이름은 다른 파일이다 — 볼륨이 가르지 않아도
            let other = try shelf("case")
            try Data("broken".utf8).write(to: other.appendingPathComponent("Model-Words.json"))
            #expect(try ModelWords.load(shelf: other) == ModelWords())
            let broken = try shelf("broken")
            try Data("{".utf8).write(to: broken.appendingPathComponent(ModelWords.fileName))
            #expect(code(broken) == "file.unreadable")
            let newer = try shelf("newer")
            try Data(#"{"version":2}"#.utf8).write(to: newer.appendingPathComponent(ModelWords.fileName))
            #expect(code(newer) == "version.tooNew")
            let directory = try shelf("directory")
            _ = try shelf("directory/\(ModelWords.fileName)")
            #expect(code(directory) == "file.unreadable")
            let dangling = try shelf("dangling")
            try FileManager.default.createSymbolicLink(at: dangling.appendingPathComponent(ModelWords.fileName), withDestinationURL: folder.appendingPathComponent("nowhere"))
            #expect(code(dangling) == "file.unreadable")
            for (bytes, want) in [(ModelWordsFormat.maxBytes, "reads"), (ModelWordsFormat.maxBytes + 1, "file.tooLarge"), (ModelWordsFormat.maxBytes * 3, "file.tooLarge")] {
                let big = try shelf("big-\(bytes)")
                try Data((#"{"version":1}"# + String(repeating: " ", count: bytes - 13)).utf8).write(to: big.appendingPathComponent(ModelWords.fileName))
                #expect(code(big) == want)
            }
            // 폴더가 아닌 자리
            let plain = folder.appendingPathComponent("plain")
            try Data().write(to: plain)
            #expect(code(plain) == "file.unreadable")
        }
    }
}

// 시험 이름 = 벡터 이름(자료를 통째로 찍지 않는다)
extension ModelWordsTests.Vectors.Case: CustomTestStringConvertible { var testDescription: String { id } }
extension ModelWordsTests.Vectors.List: CustomTestStringConvertible { var testDescription: String { id } }
extension ModelWordsTests.Vectors.File: CustomTestStringConvertible { var testDescription: String { id } }
