import Foundation

// JSON(RFC 8259)을 글자 그대로 읽는 안쪽 손 — 어느 OS 에서든 같은 답이다. 계약(`Docs/MODEL-WORDS.md`)이 거절하는 것을 거절하고 받는 것을 받는다.
// Foundation 의 읽개 둘은 답이 갈리고 OS 판에 기댄다 — 끝 쉼표 · BOM · UTF-16 · 겹친 키를 조용히 받고, 무시하는 칸의 `01` · 깨진 UTF-8 은 하나만 거절하고,
// 배정도를 넘는 수가 무시하는 칸에 있어도 하나는 파일째 거절하고, 중첩이 한도에 딱 닿은 잘린 글에서 프로세스가 멈춘다.
// 그래서 크기와 깊이를 먼저 정하고 스스로 읽는다(재귀는 깊이 상한 안).

/// A text compared and hashed by its UTF-8. The text is in NFC, so that is canonical equivalence too (and Swift need not normalize it again).
struct Name: Hashable, Sendable {
    let text: String
    static func == (a: Name, b: Name) -> Bool { a.text.utf8.elementsEqual(b.text.utf8) }
    /// One way for every text — a text whose storage is not contiguous (bridged from Foundation) is copied first, so that equal names hash alike.
    func hash(into hasher: inout Hasher) {
        var text = text
        text.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    }
}

struct StrictJSON {
    /// One JSON value. A number is its IEEE double (`1e400` is infinity) — nothing here needs more.
    enum Node {
        case null, bool
        case number(Double)
        case string(String)
        case array([Node])
        case object([Name: Node])
    }

    /// Where the text stops being JSON.
    struct Fault: Error { let offset: Int, reason: String }

    /// Reads one JSON text. Objects and arrays nest at most `depth` levels, the outermost one included; `key` gives a key as it is kept, or nil for one too long.
    static func parse(_ data: Data, depth: Int, key: @escaping (String) -> Name?) throws -> Node {
        var reader = StrictJSON(bytes: [UInt8](data), limit: depth, key: key)
        // 깨진 UTF-8 은 풀면서 U+FFFD 로 바뀌어 바이트가 달라진다
        guard String(decoding: reader.bytes, as: UTF8.self).utf8.elementsEqual(reader.bytes) else { throw Fault(offset: 0, reason: "UTF-8 이 아니다") }
        reader.blank()
        let node = try reader.value(level: 1)
        reader.blank()
        guard reader.at == reader.bytes.count else { throw reader.fault("값 뒤에 글자가 더 있다") }
        return node
    }

    private let bytes: [UInt8]
    private let limit: Int
    private let key: (String) -> Name?
    private var at = 0

    private init(bytes: [UInt8], limit: Int, key: @escaping (String) -> Name?) { self.bytes = bytes; self.limit = limit; self.key = key }

    private func fault(_ reason: String) -> Fault { Fault(offset: at, reason: reason) }
    /// The byte here — 0 past the end (a raw NUL is never valid JSON either).
    private var byte: UInt8 { at < bytes.count ? bytes[at] : 0 }

    private mutating func blank() {
        while byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { at += 1 }
    }

    private mutating func take(_ text: StaticString) throws {
        for want in UnsafeBufferPointer(start: text.utf8Start, count: text.utf8CodeUnitCount) {
            guard byte == want else { throw fault("모르는 낱말") }
            at += 1
        }
    }

    private mutating func value(level: Int) throws -> Node {
        switch byte {
        case UInt8(ascii: "{"): return try object(level: level)
        case UInt8(ascii: "["): return try array(level: level)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "n"): try take("null"); return .null
        case UInt8(ascii: "t"): try take("true"); return .bool
        case UInt8(ascii: "f"): try take("false"); return .bool
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw fault("값이 아니다")
        }
    }

    /// Opens an object or an array — true when it closes at once.
    private mutating func open(level: Int, close: UInt8) throws -> Bool {
        guard level <= limit else { throw fault("중첩이 \(limit) 겹을 넘는다") }
        at += 1
        blank()
        guard byte == close else { return false }
        at += 1
        return true
    }

    /// After a member — true when the object or array closes here, false when a comma brings another member.
    private mutating func closes(_ close: UInt8) throws -> Bool {
        blank()
        if byte == close { at += 1; return true }
        guard byte == UInt8(ascii: ",") else { throw fault("쉼표나 닫는 괄호가 없다") }
        at += 1
        blank()
        return false
    }

    private mutating func array(level: Int) throws -> Node {
        var out: [Node] = []
        if try open(level: level, close: UInt8(ascii: "]")) { return .array(out) }
        repeat { out.append(try value(level: level + 1)) } while try !closes(UInt8(ascii: "]"))
        return .array(out)
    }

    private mutating func object(level: Int) throws -> Node {
        var out: [Name: Node] = [:]
        if try open(level: level, close: UInt8(ascii: "}")) { return .object(out) }
        repeat {
            guard byte == UInt8(ascii: "\"") else { throw fault("키가 글이 아니다") }
            guard let key = key(try string()) else { throw fault("키가 너무 길다") }
            blank()
            guard byte == UInt8(ascii: ":") else { throw fault("키 뒤에 쌍점이 없다") }
            at += 1
            blank()
            let member = try value(level: level + 1)
            // 키는 NFC 로 들어 NFC 가 같은 두 키는 같은 키다(계약 규칙 6)
            guard out.updateValue(member, forKey: key) == nil else { throw fault("같은 키 둘 ‘\(key.text)’") }
        } while try !closes(UInt8(ascii: "}"))
        return .object(out)
    }

    private mutating func digits() throws {
        guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { throw fault("수의 꼴이 아니다") }
        while (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { at += 1 }
    }

    private mutating func number() throws -> Double {
        let start = at
        if byte == UInt8(ascii: "-") { at += 1 }
        if byte == UInt8(ascii: "0") { at += 1 } else { try digits() }
        if byte == UInt8(ascii: ".") { at += 1; try digits() }
        if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
            at += 1
            if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") { at += 1 }
            try digits()
        }
        guard let number = Double(String(decoding: bytes[start..<at], as: UTF8.self)) else { throw fault("수의 꼴이 아니다") }
        return number
    }

    private mutating func string() throws -> String {
        at += 1
        var out = "", start = at
        while true {
            switch byte {
            case UInt8(ascii: "\""):
                out += String(decoding: bytes[start..<at], as: UTF8.self)
                at += 1
                return out
            case UInt8(ascii: "\\"):
                out += String(decoding: bytes[start..<at], as: UTF8.self)
                at += 1
                out.unicodeScalars.append(try escape())
                start = at
            case 0..<0x20:
                throw fault(at < bytes.count ? "글 안의 제어 글자" : "닫히지 않은 글")
            default:
                at += 1
            }
        }
    }

    private mutating func escape() throws -> Unicode.Scalar {
        let letter = byte
        at += 1
        switch letter {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{08}"
        case UInt8(ascii: "f"): return "\u{0C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"):
            let high = try hex()
            if let scalar = Unicode.Scalar(high) { return scalar }
            guard high < 0xDC00, byte == UInt8(ascii: "\\") else { throw fault("짝 없는 서러게이트") }
            at += 1
            guard byte == UInt8(ascii: "u") else { throw fault("짝 없는 서러게이트") }
            at += 1
            let low = try hex()
            guard (0xDC00...0xDFFF).contains(low), let scalar = Unicode.Scalar(0x10000 + (high - 0xD800) << 10 + (low - 0xDC00)) else { throw fault("짝 없는 서러게이트") }
            return scalar
        default: throw fault("모르는 이스케이프")
        }
    }

    private mutating func hex() throws -> UInt32 {
        var out: UInt32 = 0
        for _ in 0..<4 {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw fault("\\u 뒤는 열여섯 진수 넷이다")
            }
            out = out << 4 | UInt32(digit)
            at += 1
        }
        return out
    }
}
