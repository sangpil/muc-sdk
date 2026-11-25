import Foundation

// 모델의 말 이름 표(`model-words.json`) — 사람이 말하는 낱말로 서가의 모델을 찾는 손. 계약의 정본은 `Docs/MODEL-WORDS.md`(아래 「rule N」은 그 문서의 규칙 번호).
// 읽기만 한다(쓰는 손은 없다) · 값 하나라 어느 스레드에서든 쓴다 · 모델 파일 · 매니페스트를 읽지 않는다 — `load(shelf:)` 는 준 폴더의 그 이름 하나만 본다.

/// The words people say for a shelf's models — read from `model-words.json` beside them.
///
/// The contract — the file, the matching rules, what an app must do — is `Docs/MODEL-WORDS.md`.
public struct ModelWords: Equatable, Sendable {
    /// The file's name in the shelf folder, letter for letter.
    public static let fileName = "model-words.json"

    private var kinds = Entries()
    private var models = Entries()
    /// Folded word → its ordinal among all of the table's, in the order of rule 27. The words carry this number.
    private var ordinals: [Name: Int] = [:]

    /// The empty table — it names nothing.
    public init() {}

    /// Reads a table. A table is read whole or not at all — any fault throws `ModelWords.Unreadable`.
    public init(data: Data) throws {
        guard data.count <= ModelWordsFormat.maxBytes else {
            throw Unreadable(code: "file.tooLarge", message: "파일이 \(data.count) 바이트로 상한 \(ModelWordsFormat.maxBytes) 바이트를 넘는다")
        }
        let root: [Name: StrictJSON.Node]
        do {
            guard case .object(let object) = try StrictJSON.parse(data, depth: ModelWordsFormat.maxDepth, key: Self.name) else { throw Unreadable(shape: "맨 위", "객체여야") }
            root = object
        } catch let fault as StrictJSON.Fault {
            throw Unreadable(code: "file.unreadable", message: "JSON 으로 읽지 못한다 — \(fault.reason)(\(fault.offset) 바이트째)")
        }
        // 판을 안의 칸보다 먼저 잰다 — 새 판의 칸은 꼴이 다를 수 있다
        guard case .number(let version)? = root[Name(text: "version")], version.isFinite, version >= 1, version == version.rounded() else {
            throw Unreadable(code: "version.missing", message: "version — 1 이상의 정수여야 한다")
        }
        guard version <= Double(ModelWordsFormat.version) else {
            throw Unreadable(code: "version.tooNew", message: "더 새 판으로 쓰였다 — 이 SDK 는 판 \(ModelWordsFormat.version) 을 읽는다")
        }
        var folds: [Name: Int] = [:]   // 접은 낱말 → 만난 차례
        kinds = try Self.entries(root[Name(text: "kinds")], at: "kinds", up: "parent", &folds)
        models = try Self.entries(root[Name(text: "models")], at: "models", up: "kind", &folds)
        let order = folds.map { (fold: $0.key.text, met: $0.value, length: $0.key.text.unicodeScalars.count, head: Self.head($0.key.text)) }.sorted {
            if $0.length != $1.length { return $0.length > $1.length }
            return $0.head != $1.head ? $0.head < $1.head : Self.precedes($0.fold, $1.fold)
        }
        var moved = [Int](repeating: 0, count: order.count)   // 만난 차례 → 줄의 차례
        for (ordinal, row) in order.enumerated() { moved[row.met] = ordinal }
        ordinals = folds.mapValues { moved[$0] }
        let ids = kinds.at
        kinds.settle(moved, ids)
        models.settle(moved, ids)
        guard reaches(within: ModelWordsFormat.maxReach) else {
            throw Unreadable(code: "file.tooLarge", message: "모델마다 닿는 낱말의 합이 상한 \(ModelWordsFormat.maxReach) 을 넘는다")
        }
    }

    /// Reads the table of a shelf folder. No such file is the empty table; a file that is there and cannot be read throws.
    public static func load(shelf: URL) throws -> ModelWords {
        do {
            // 이름을 글자 그대로 견준다 — 대소문자를 가르지 않는 볼륨에서도 같은 답
            guard try FileManager.default.contentsOfDirectory(atPath: shelf.path).contains(fileName) else { return ModelWords() }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ModelWords()
        } catch {
            throw Unreadable(code: "file.unreadable", message: "서가 폴더를 읽지 못한다 — \(error.localizedDescription)")
        }
        let data: Data
        do {
            let file = try FileHandle(forReadingFrom: shelf.appendingPathComponent(fileName))
            defer { try? file.close() }
            data = try file.read(upToCount: ModelWordsFormat.maxBytes + 1) ?? Data()   // 상한보다 한 바이트 더 — 큰 파일을 다 읽지 않고 거절한다
        } catch {
            throw Unreadable(code: "file.unreadable", message: "\(fileName) 을 읽지 못한다 — \(error.localizedDescription)")
        }
        return try ModelWords(data: data)
    }

    /// What `word` names among `models` — each model at most once, the closest match first, ties in the order of `models` (rules 17–24).
    ///
    /// `word` is matched whole: particles, plurals and parts of a sentence are the caller's to cut. Too long (rule 7), it matches nothing.
    public func candidates(for word: String, language: String, among models: [String]) -> [Candidate] {
        let asked = Self.tag(language)
        guard !asked.isEmpty, let word = Self.short(word), let ordinal = ordinals[Name(text: Self.fold(word))] else { return [] }
        func hit(_ entry: Entry) -> String? {
            entry.words(asked).filter { $0.ordinal == ordinal }.map(\.text).min(by: Self.precedes)
        }
        var own = [String??](repeating: nil, count: kinds.entries.count)                              // 종류마다 낱말을 한 번 훑는다
        var above = [(rank: Int, kind: Int, word: String)??](repeating: nil, count: kinds.entries.count)   // 종류마다 사슬을 한 번 걷는다
        func climbed(_ first: Int) -> (rank: Int, kind: Int, word: String)? {
            if let known = above[first] { return known }
            var found: (rank: Int, kind: Int, word: String)?
            climb(from: first) { rank, kind in
                if own[kind] == nil { own[kind] = .some(hit(kinds.entries[kind])) }
                if let word = own[kind]! { found = (rank, kind, word) }
                return found == nil
            }
            above[first] = .some(found)
            return found
        }
        var out: [(rank: Int, candidate: Candidate)] = []
        for (name, entry) in listed(models) {
            if let word = hit(entry) {
                out.append((0, Candidate(model: name, kind: nil, word: word, match: .at(0))))
            } else if let first = entry.above, let found = climbed(first) {
                out.append((found.rank, Candidate(model: name, kind: kinds.entries[found.kind].name, word: found.word, match: .at(found.rank))))
            }
        }
        return out.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.candidate)
    }

    /// Every word that names something among `models`, longest first, each with its answer (rules 25–27).
    ///
    /// The words are those of the named models and of the kinds on their walks. For scanning a sentence: the text of each row is a word as the table writes it, in NFC. What only folding equates — another case, another
    /// normal form, full-width letters, other hyphens and spaces — is not listed, and folding is not a call of its own: the caller scans with its own normalizing.
    public func words(language: String, among models: [String]) -> [Word] {
        let asked = Self.tag(language)
        guard !asked.isEmpty else { return [] }
        let models = listed(models)
        // 줄(접은 낱말)마다 닿은 모델 · 적힌 글자 — 글은 번호로 들어 답이 커도 줄을 지을 때만 커진다
        var texts: [String] = []
        var hits = [[Hit]](repeating: [], count: ordinals.count)
        var spellings = [[String]](repeating: [], count: ordinals.count)
        func lines(_ entry: Entry) -> [(ordinal: Int, text: Int)] {
            var out: [Int: Int] = [:]
            for word in entry.words(asked) {
                spellings[word.ordinal].append(word.text)
                if let at = out[word.ordinal] {
                    if Self.precedes(word.text, texts[at]) { texts[at] = word.text }
                } else {
                    out[word.ordinal] = texts.count
                    texts.append(word.text)
                }
            }
            return out.map { ($0.key, $0.value) }
        }
        // 모델 제 낱말
        var own = [Set<Int>](repeating: [], count: models.count)
        var under: [Int: [Int]] = [:]   // 종류 → 그 종류의 모델 — 사슬 하나를 한 번만 걸어 나눠 쓴다
        for (model, named) in models.enumerated() {
            let lines = lines(named.entry)
            for line in lines { hits[line.ordinal].append(Hit(rank: 0, model: model, kind: -1, text: line.text)) }
            if let first = named.entry.above {
                under[first, default: []].append(model)
                own[model] = Set(lines.lazy.map(\.ordinal))
            }
        }
        // 종류와 그 위의 낱말 — 가까운 것이 이긴다
        var known = [[(ordinal: Int, text: Int)]?](repeating: nil, count: kinds.entries.count)
        var last = [Int](repeating: -1, count: ordinals.count)
        for (first, models) in under {
            climb(from: first) { rank, kind in
                if known[kind] == nil { known[kind] = lines(kinds.entries[kind]) }
                for line in known[kind]! where last[line.ordinal] != first {
                    last[line.ordinal] = first
                    for model in models where !own[model].contains(line.ordinal) { hits[line.ordinal].append(Hit(rank: rank, model: model, kind: kind, text: line.text)) }
                }
                return true
            }
        }
        var out: [Word] = []
        for ordinal in hits.indices where !hits[ordinal].isEmpty {
            let candidates = hits[ordinal].sorted { ($0.rank, $0.model) < ($1.rank, $1.model) }.map { hit in
                Candidate(model: models[Int(hit.model)].name, kind: hit.kind < 0 ? nil : kinds.entries[Int(hit.kind)].name, word: texts[Int(hit.text)], match: .at(Int(hit.rank)))
            }
            hits[ordinal] = []
            var last: String?
            for text in spellings[ordinal].sorted(by: Self.precedes) where text != last {
                out.append(Word(text: text, candidates: candidates))
                last = text
            }
        }
        return out
    }

    /// One word the table lists, with its answer.
    public struct Word: Hashable, Sendable {
        /// The word as the table writes it, in NFC.
        public let text: String
        /// The answer to `candidates(for: text, …)` with the same language and models. Never empty.
        public let candidates: [Candidate]
    }

    /// One model a word names.
    public struct Candidate: Hashable, Sendable {
        /// The model's name, as the caller gave it.
        public let model: String
        /// The kind whose word it was, in NFC — nil for the model's own.
        public let kind: String?
        /// The matched word as the table writes it, in NFC (rule 22).
        public let word: String
        public let match: Match
    }

    /// How close the word is to the model. An open word — a newer SDK may know more than `exact` and `broader`.
    public struct Match: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// The model's own word, or its kind's.
        public static let exact = Match(rawValue: "exact")
        /// A word of a kind above the model's kind.
        public static let broader = Match(rawValue: "broader")
    }

    /// Why a table cannot be read. Nothing of such a table is used.
    public struct Unreadable: Error, Equatable, Sendable {
        /// `file.unreadable` · `file.tooLarge` · `version.missing` · `version.tooNew`.
        public let code: String
        /// For people — not part of the contract.
        public let message: String
    }
}

extension ModelWords.Unreadable: LocalizedError {
    public var errorDescription: String? { message }

    /// A field of the wrong shape.
    init(shape path: String, _ want: String) { self.init(code: "file.unreadable", message: "\(path) — \(want) 한다") }
}

// MARK: - 표 안

extension ModelWords {
    /// A kind or a model: what is above it, and its words by language. Names are in NFC.
    struct Entry: Equatable, Sendable {
        let name: String
        /// The kind above, by name and by its ordinal among the kinds — no ordinal when the table does not have it.
        var up: Name?
        var above: Int?
        /// Words by tag, both sorted and without repeats — the order in the file means nothing (rule 5).
        var lists: [(tag: [UInt8], words: [Spelled])] = []
        /// How many words the entry writes — blank, repeated and too long ones too. A table that writes a word twice is still the same table.
        var written = 0

        static func == (a: Entry, b: Entry) -> Bool { a.up == b.up && a.lists.elementsEqual(b.lists) { $0.tag == $1.tag && $0.words == $1.words } }

        /// The words of every list whose tag is a segment prefix of the asked tag, or the other way round (rule 29).
        func words(_ asked: [UInt8]) -> [Spelled] {
            lists.lazy.filter { asked.starts(with: $0.tag) || $0.tag.starts(with: asked) }.flatMap(\.words)
        }
    }

    /// A word in NFC, and the ordinal of its folded form.
    struct Spelled: Equatable, Sendable { let text: String, ordinal: Int }

    /// The kinds or the models by name.
    struct Entries: Equatable, Sendable {
        var at: [Name: Int] = [:]
        var entries: [Entry] = []

        static func == (a: Entries, b: Entries) -> Bool {
            a.at.count == b.at.count && a.at.allSatisfy { name, i in b.at[name].map { a.entries[i] == b.entries[$0] } ?? false }
        }

        /// Gives every word its ordinal and every entry the ordinal of the kind above.
        mutating func settle(_ ordinals: [Int], _ kinds: [Name: Int]) {
            for e in entries.indices {
                entries[e].above = entries[e].up.flatMap { kinds[$0] }
                entries[e].lists = entries[e].lists.map { ($0.tag, $0.words.map { Spelled(text: $0.text, ordinal: ordinals[$0.ordinal]) }) }
            }
        }
    }

    /// One candidate of a row, in numbers (`kind` -1 — the model's own word).
    private struct Hit {
        let rank, model, kind, text: Int32
        init(rank: Int, model: Int, kind: Int, text: Int) { (self.rank, self.model, self.kind, self.text) = (Int32(rank), Int32(model), Int32(kind), Int32(text)) }
    }

    /// The named models the table knows, each once, in the caller's order.
    private func listed(_ names: [String]) -> [(name: String, entry: Entry)] {
        var seen = [Bool](repeating: false, count: models.entries.count)
        return names.compactMap { given in
            guard let name = Self.name(given), let at = models.at[name], !seen[at] else { return nil }
            seen[at] = true
            return (given, models.entries[at])
        }
    }

    /// Whether the words every model reaches, as many as are written, in all languages, stay within the bound (rule 7).
    private func reaches(within bound: Int) -> Bool {
        var above = [Int?](repeating: nil, count: kinds.entries.count)   // 종류마다 사슬을 한 번 걷는다
        var passed = [Int](repeating: -1, count: kinds.entries.count)
        var sum = 0
        for model in models.entries {
            sum += model.written
            if let first = model.above {
                if above[first] == nil {
                    var written = 0
                    climb(from: first) { _, kind in
                        guard passed[kind] != first else { return false }   // 고리 — 한 종류는 한 번(rule 21)
                        passed[kind] = first
                        written += kinds.entries[kind].written
                        return true
                    }
                    above[first] = written
                }
                sum += above[first]!
            }
            if sum > bound { return false }
        }
        return true
    }

    /// A kind and the kinds above, each with its rank — at most 64 of them, up to a kind the table does not have (rule 21), until `step` says stop.
    /// A loop runs out of the 64: what a kind answers the second time is never closer than the first.
    private func climb(from first: Int, _ step: (_ rank: Int, _ kind: Int) -> Bool) {
        var above: Int? = first, rank = 1
        while rank <= ModelWordsFormat.maxSteps, let kind = above, step(rank, kind) { (above, rank) = (kinds.entries[kind].above, rank + 1) }
    }

    /// Byte order of the UTF-8 (rules 22 and 27).
    static func precedes(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

    /// The first eight bytes of the UTF-8 as a number in the same order — most comparisons end here.
    private static func head(_ text: String) -> UInt64 {
        var out: UInt64 = 0, shift: UInt64 = 64
        for byte in text.utf8.prefix(8) { shift -= 8; out |= UInt64(byte) << shift }
        return out
    }

    /// A language tag as bytes — ASCII letters lowered, `_` read as `-`, empty segments dropped, every segment closed by `-`,
    /// so that a byte prefix is a segment prefix (rule 28). No segment, or a tag too long — no bytes.
    static func tag(_ language: String) -> [UInt8] {
        guard let language = short(language) else { return [] }
        return language.utf8.split { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_") }.flatMap { segment in
            segment.map { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) ? $0 | 0x20 : $0 } + [UInt8(ascii: "-")]
        }
    }

    /// What matching compares (rule 13): NFKC · lower case scalar by scalar · white space and hyphens out · one apostrophe · NFC.
    static func fold(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in (isSettled(text) ? text : text.precomposedStringWithCompatibilityMapping).unicodeScalars {
            switch scalar.value {
            case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: break   // White_Space
            case 0x2D, 0xAD, 0x2010...0x2015, 0x200B...0x200D, 0x2060, 0xFEFF: break
            case 0x2019, 0x02BC: out.append("'")
            case 0x41...0x5A: out.append(Unicode.Scalar(UInt8(scalar.value | 0x20)))
            case 0x00..<0x80, 0x0300..<0x0370, 0x0590..<0x10A0, 0x1100..<0x13A0, 0x2E80..<0xA640, 0xAC00..<0xFB00, 0xFB50..<0xFF00:
                out.append(scalar)   // 소문자가 저 자신인 글 — 대응을 찾지 않는다
            default: out.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return nfc(String(out))
    }

    /// Scalars that stay themselves under NFC, NFKC and next to one another — the common letters. Nothing made of them needs normalizing.
    static func isSettled(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00..<0x80, 0xC0...0xFF, 0x3041...0x3096, 0x30A1...0x30FA, 0x4E00...0x9FFF, 0xAC00...0xD7A3: true
            default: false
            }
        }
    }

    /// NFC in Swift's own storage — a bridged string is slow to compare.
    static func nfc(_ text: String) -> String {
        if isSettled(text) { return text }
        var out = text.precomposedStringWithCanonicalMapping
        out.makeContiguousUTF8()
        return out
    }

    /// The text in NFC — nil when it is too long (rule 7). The bytes as they came are looked at first: a long run of marks is slow to put in order.
    static func short(_ text: String) -> String? {
        guard text.utf8.count <= ModelWordsFormat.maxRaw else { return nil }
        let out = nfc(text)
        return out.utf8.count <= ModelWordsFormat.maxText ? out : nil
    }

    /// A key, a kind's id or a model's name as it is kept — nil when it is too long.
    static func name(_ text: String) -> Name? { short(text).map(Name.init) }

    // MARK: 읽기 — 자리마다 「없음」 ⟂ 「형 틀림」(rule 3)

    /// An object, or nothing when it is absent or null.
    private static func object(_ node: StrictJSON.Node?, at path: String) throws -> [Name: StrictJSON.Node] {
        switch node {
        case nil, .null: return [:]
        case .object(let object): return object
        default: throw Unreadable(shape: path, "객체여야")
        }
    }

    private static func entries(_ node: StrictJSON.Node?, at path: String, up: String, _ folds: inout [Name: Int]) throws -> Entries {
        var out = Entries()
        for (name, node) in try object(node, at: path) {
            let here = "\(path).\(name.text)"
            if case .null = node { continue }   // null 은 안 적은 것 · {} 는 적은 것(rule 4)
            let fields = try object(node, at: here)
            var entry = Entry(name: name.text)
            switch fields[Name(text: up)] {
            case nil, .null: break
            case .string(let id):
                guard let id = Self.name(id) else { throw Unreadable(code: "file.unreadable", message: "\(here).\(up) — 너무 길다") }
                entry.up = id.text.isEmpty ? nil : id
            default: throw Unreadable(shape: "\(here).\(up)", "글이어야")
            }
            var lists: [[UInt8]: [Spelled]] = [:]
            for (language, list) in try object(fields[Name(text: "words")], at: "\(here).words") {
                let spot = "\(here).words.\(language.text)"
                let items: [StrictJSON.Node]
                switch list {
                case .null: continue
                case .array(let array): items = array
                default: throw Unreadable(shape: spot, "배열이어야")
                }
                entry.written += items.count
                var words: [Spelled] = []
                for (at, item) in items.enumerated() {
                    guard case .string(let text) = item else { throw Unreadable(shape: "\(spot)[\(at)]", "글이어야") }
                    guard let written = short(text) else { continue }   // 긴 낱말은 낱말이 아니다(rule 16)
                    let fold = Name(text: fold(written))
                    if fold.text.isEmpty { continue }
                    let ordinal = folds[fold] ?? folds.count
                    folds[fold] = ordinal
                    words.append(Spelled(text: written, ordinal: ordinal))
                }
                let tag = tag(language.text)
                if !tag.isEmpty, !words.isEmpty { lists[tag, default: []] += words }
            }
            entry.lists = lists.map { tag, words in
                var last: String?
                return (tag, words.sorted { precedes($0.text, $1.text) }.filter { defer { last = $0.text }; return $0.text != last })
            }.sorted { $0.tag.lexicographicallyPrecedes($1.tag) }
            out.at[name] = out.entries.count
            out.entries.append(entry)
        }
        return out
    }
}

private extension ModelWords.Match {
    /// Rank 0 is the model's own word, 1 its kind's, more is above (rule 17).
    static func at(_ rank: Int) -> Self { rank <= 1 ? .exact : .broader }
}
