import CryptoKit
import DesignTokens
import Foundation
import PreviewProtocol
import ProjectFormat
import Testing

// 꼴 변경 게이트 — 메시지 꼴(종류 · 칸 키 · 값의 꼴 · 낱말)이 바뀌었는데 판이 그대로면 빨강. 정본 `Docs/SDK.md` §5.
// 이 시험은 상수 자체(꼴 · 지문)만 잰다 — 정본 문서(이 패키지의 `Docs/SDK.md`)의 판 글자 맞대기는 `ProtocolDocumentTests`.
//
//   지문   : 메시지 종류마다 칸을 **빠짐없이** 채운 표본을 지금 판의 줄로 써서(`ProtocolDialect.current`) 키 경로와 값의 꼴(글자 · 수 · 참거짓 · JSON 값)을 모으고,
//            키마다 **선택인가**(그 키를 줄에서 걷어도 지금 판의 디코더가 읽는가 — `optional <경로>` 줄)를 더하고,
//            낱말 목록(칸 종류 · hello 의 쪽 · 공유 메모리 종류 · 구성 칸 종류 · 프레임 형식 — 열린 꼴은 아는 낱말 `known`)을 더한 서술 한 벌의 SHA-256 앞 16자.
//            선택 칸을 더하거나 필수 칸을 선택으로 바꿔도 지문이 바뀐다(선택 칸도 판을 올린다).
//   기록   : `protocol-shapes.txt` — 판마다 한 줄 `<판> <지문>` · 덧붙이기 전용(지난 판의 줄은 고치지 않는다). 지금 판의 줄과 다르면
//            「판을 올리고 지문 한 줄을 더하라」로 실패한다 — 판을 올려 새 줄을 더하면 초록(바이트를 박은 시험이 아니라 판마다의 기록이다).
//   빠짐   : 표본의 칸이 비면(nil · 빈 배열 · 빈 사전) 지문이 그 칸을 못 본다 — 그것도 빨강(「표본을 채워라」 · 모르는 칸 주머니 `extra` 는 꼴이 아니라 뺀다). 메시지 종류 · 칸 종류가 늘면
//            아래 `covered` 의 switch 가 컴파일되지 않는다 — 표본을 더하라는 뜻이다.
//   셈법   : 이 파일의 셈법을 바꾸면(꼴이 바뀐 것이 아니다) 지금 판의 줄만 새 셈으로 고친다 — 지난 판의 줄은 그대로 둔다.
//   JSON 값: 프로젝트가 뜻을 정하는 칸(`JSONValue` · Style 값 사전)은 꼴이 없다 — 표본은 표 `§json`(값) · `§`(사전 키)로 채우고 지문은 `json` · `{}` 로 적는다.

@Suite struct PreviewProtocolShapeTests {
    static let json: JSONValue = "§json"
    static let values: StyleValues = ["§": json]
    static let element = StyleElement(id: "card", label: "카드", snapPrefix: "card", effects: [.glass])
    static let schema = StyleSchema(screen: "s", elements: [element],
                                    fields: [StyleField(name: "cardGap", kind: .scalar(.space), element: element, label: "간격")],
                                    texts: [StyleText(name: "cardTitle", element: element, label: "제목", maxLength: 40)],
                                    slots: [StyleSlot(name: "cardPicture", element: element, snap: "card.picture", label: "그림", kinds: ["isomodel"])],
                                    defaults: values)
    static let timing = HostTiming(recv: 1, start: 2, rendered: 3, sent: 4)
    static let text = DrawnText(text: "t", rect: CGRect(x: 0, y: 0, width: 1, height: 1), font: "F", size: 1, weight: 400, color: "#000000", element: "a")
    static let style = DrawnStyle(id: "a", background: "#ffffff", radius: 1)
    static let shared = SharedMemoryInfo(kind: .posix, name: "/m", slotBytes: 1, slots: 3)
    static let ia = IAInfo(appScreens: ["s"], entryWords: [.init(control: "plus", label: "＋")], entryHands: ["s": ["plus"]],
                           aliases: ["old": "s"], planned: ["p"])
    static let frame = DeviceFrameInfo(id: "phone", platform: "iphone", name: "Phone", symbol: "iphone", size: Size(w: 1, h: 2), corner: 1,
                                       safeTop: 1, safeBottom: 1, scene: .init(name: "Phone", bands: Insets(top: 1)))
    static let built = BuiltTokens(scales: ["space": [.init(name: "md", pt: 1, doc: "d", apple: "a")]], layout: [.init(name: "gap-wide", pt: 1, doc: "d", apple: "a")],
                                   colors: [.init(name: "bg", values: ["light": "#ffffff"])], themes: ["light"])
    static let composition = LayerComposition(
        nodeKeys: [.init(key: "chrome", label: "끝")],
        fields: [CompositionField(key: "topLeft", kind: .choice, label: "상단 좌", choices: [.init(value: "a", label: "A", symbol: "a")],
                                  defaultValue: json, help: "h", when: "bottom", of: "topButtons")],
        hubItem: [CompositionField(key: "label", kind: .text, label: "이름", choices: [.init(value: "a", label: "A", symbol: "a")],
                                   defaultValue: json, help: "h", when: "w", of: "o")])

    /// 종류마다 칸을 빠짐없이 채운 표본(같은 종류 여럿이면 지문은 합친다 — 프레임 바이트 자리 둘).
    static let samples: [Message] = [
        .hello(Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: 1, name: "h",
                     screens: [ScreenInfo(name: "s", states: ["normal"], style: schema, fixtureColorUsage: ["bg": 1])],
                     layers: [LayerInfo(name: "chrome", style: schema, composition: composition)],
                     formats: [.rgba8sRGB], shared: shared, ia: ia, frames: [frame], tokensBuilt: built)),
        .render(RenderRequest(seq: 1, screen: "s", state: "normal", style: values, theme: "dark", size: Size(w: 1, h: 1), scale: 2,
                              layers: [LayerState(name: "chrome", style: values, data: json)], frames: true, scroll: 1, fixture: json, layersOnly: true,
                              drawn: true)),
        .frame(FrameHeader(seq: 1, applied: 1, w: 1, h: 1, stride: 4, scale: 2, format: .rgba8sRGB,
                           snapFrames: [SnapFrame(id: "a", rect: CGRect(x: 0, y: 0, width: 1, height: 1))], elements: ["a"],
                           layers: [LayerReport(name: "chrome", elements: ["a"], data: json, cover: Insets(top: 1))],
                           texts: [text], styles: [style], ms: 0,
                           payload: .inline(bytes: 4), timing: timing)),
        .frame(FrameHeader(seq: 1, applied: 1, w: 1, h: 1, stride: 4, scale: 2, format: .rgba8sRGB,
                           snapFrames: [SnapFrame(id: "a", rect: CGRect(x: 0, y: 0, width: 1, height: 1))], elements: ["a"],
                           layers: [LayerReport(name: "chrome", elements: ["a"], data: json, cover: Insets(top: 1))],
                           texts: [text], styles: [style], ms: 0,
                           payload: .slot(index: 0, bytes: 4), timing: timing)),
        .patch(Patch(seq: 1, edits: [Edit(field: "cardGap", value: json, layer: "chrome")])),
        .tokensChanged(TokensChanged(seq: 1)),
        .shot(ShotRequest(seq: 1, path: "/p.png")),
        .window(WindowRequest(seq: 1, x: 0, y: 0, show: true, w: 1, h: 1, above: 1, clip: CGRect(x: 0, y: 0, width: 1, height: 1))),
        .ack(Ack(seq: 1, applied: 1, ms: 0, timing: timing, changed: true)),
        .error(ErrorMessage(seq: 1, message: "m")),
        .bye(Bye(reason: "r")),
    ]

    /// 메시지 종류 · 칸 종류가 늘면 여기가 컴파일되지 않는다 — 표본(`samples`) · 낱말(`fieldKinds`)에 더하고 이 switch 를 고친다.
    static func covered(_ m: Message) -> String {
        switch m {
        case .hello: "hello"; case .render: "render"; case .frame: "frame"; case .patch: "patch"; case .tokensChanged: "tokensChanged"
        case .shot: "shot"; case .window: "window"; case .ack: "ack"; case .error: "error"; case .bye: "bye"
        }
    }
    static let kinds = ["ack", "bye", "error", "frame", "hello", "patch", "render", "shot", "tokensChanged", "window"]
    static func covered(_ k: FieldKind) {
        switch k {
        case .scalar, .color, .bool: break
        }
    }
    static let fieldKinds: [FieldKind] = [.scalar(.space), .scalar(.radius), .scalar(.type), .color, .bool]

    // MARK: 지문

    /// 꼴 서술 — 정렬한 줄들(종류 · 키 경로와 값의 꼴 · 낱말).
    static func shape() throws -> String {
        var lines = Set<String>()
        for m in samples {
            guard let top = try JSONSerialization.jsonObject(with: ProtocolDialect.current.encode(m)) as? [String: Any] else { throw ShapeError.notObject }
            for (k, v) in top where k != "type" { walk(v, "\(m.type).\(k)", into: &lines) }
            // 선택 칸 — 그 키를 (배열 안이면 모든 원소에서) 걷어도 읽히면 선택
            for path in keyPaths(top, []) where path != ["type"] {
                let cut = removing(top, path[...])
                let data = try JSONSerialization.data(withJSONObject: cut)
                if (try? ProtocolDialect.current.decode(data)) != nil { lines.insert("optional \(m.type).\(path.joined(separator: "."))") }
            }
        }
        func words(_ name: String, _ ws: [String]) -> String { "vocab \(name) " + ws.sorted().joined(separator: " ") }
        let kindWords = try fieldKinds.map { k -> String in
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(k), options: .fragmentsAllowed) as! String
        }
        let head = ["kinds " + Set(samples.map(\.type)).sorted().joined(separator: " "),
                    words("FieldKind", kindWords),
                    words("Hello.Role", Hello.Role.allCases.map(\.rawValue)),
                    words("SharedMemoryInfo.Kind", SharedMemoryInfo.Kind.known.map(\.rawValue)),
                    words("CompositionField.Kind", CompositionField.Kind.known.map(\.rawValue)),
                    words("StyleEffect", StyleEffect.known.map(\.rawValue)),
                    "vocab FrameFormat.rgba8sRGB \(FrameFormat.rgba8sRGB.pixel) \(FrameFormat.rgba8sRGB.colorSpace)"]
        return (head + lines.sorted()).joined(separator: "\n")
    }

    static func walk(_ v: Any, _ path: String, into out: inout Set<String>) {
        switch v {
        case let o as [String: Any]:
            if o.count == 1, let inner = o["§"] { walk(inner, path + "{}", into: &out); return }
            for (k, x) in o { walk(x, "\(path).\(k)", into: &out) }
        case let a as [Any]:
            for x in a { walk(x, path + "[]", into: &out) }
        case let s as String:
            out.insert("\(path) \(s == "§json" ? "json" : "string")")
        case let n as NSNumber:
            out.insert("\(path) \(CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number")")
        default:
            out.insert("\(path) null")
        }
    }

    /// 줄 안의 키 경로 전부 — 배열은 `[]` 마디 · Style 값 사전의 표(`§`)는 뺀다.
    static func keyPaths(_ v: Any, _ prefix: [String]) -> Set<[String]> {
        switch v {
        case let o as [String: Any]:
            var out = Set<[String]>()
            for (k, x) in o where k != "§" { out.insert(prefix + [k]); out.formUnion(keyPaths(x, prefix + [k])) }
            return out
        case let a as [Any]:
            return a.reduce(into: Set<[String]>()) { $0.formUnion(keyPaths($1, prefix + ["[]"])) }
        default:
            return []
        }
    }

    /// 경로의 키를 걷은 줄(배열 마디면 모든 원소에서).
    static func removing(_ v: Any, _ path: ArraySlice<String>) -> Any {
        guard let head = path.first else { return v }
        let rest = path.dropFirst()
        if head == "[]", let a = v as? [Any] { return a.map { removing($0, rest) } }
        guard var o = v as? [String: Any] else { return v }
        if rest.isEmpty { o.removeValue(forKey: head) } else if let x = o[head] { o[head] = removing(x, rest) }
        return o
    }

    static func digest(_ shape: String) -> String {
        SHA256.hash(data: Data(shape.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// 표본의 빈 칸 — nil · 빈 배열 · 빈 사전(JSON 값 안은 보지 않는다).
    static func holes(_ v: Any, _ path: String, into out: inout [String]) {
        if v is JSONValue { return }
        let mirror = Mirror(reflecting: v)
        switch mirror.displayStyle {
        case .optional:
            if let c = mirror.children.first { holes(c.value, path, into: &out) } else { out.append(path) }
        case .collection, .set, .dictionary:
            if mirror.children.isEmpty { out.append(path + "(빈)") }
            for c in mirror.children { holes(c.value, path + "[]", into: &out) }
        case .struct, .class, .enum, .tuple:
            // `extra` = 모르는 칸 주머니(꼴이 아니다 — 지문 밖)
            for c in mirror.children where c.label != "extra" { holes(c.value, path + "." + (c.label ?? "_"), into: &out) }
        default: return
        }
    }

    enum ShapeError: Error { case notObject }

    // MARK: 기록

    static let recordURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("protocol-shapes.txt")

    /// `<판> <지문>` 줄들(주석 `#` · 빈 줄 빼고).
    static func records() throws -> [(version: Int, digest: String)] {
        try String(contentsOf: recordURL, encoding: .utf8).split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { return nil }
            let parts = line.split(separator: " ")
            guard parts.count == 2, let v = Int(parts[0]) else { throw RecordError.badLine(line) }
            return (v, String(parts[1]))
        }
    }
    enum RecordError: Error { case badLine(String) }

    // MARK: 시험

    @Test func samplesCoverEveryKindAndEveryField() throws {
        #expect(Self.samples.map(Self.covered) == Self.samples.map(\.type))
        #expect(Set(Self.samples.map(\.type)) == Set(Self.kinds), "메시지 종류마다 표본 하나 이상")
        Self.fieldKinds.forEach(Self.covered)
        let scalars = Self.fieldKinds.compactMap { k -> ScaleKind? in if case .scalar(let s) = k { s } else { nil } }
        #expect(Set(scalars) == Set(ScaleKind.known), "스칼라 칸 종류 표본 = 아는 스케일 종류 전부")
        var empty: [String] = []
        for m in Self.samples { Self.holes(m, m.type, into: &empty) }
        #expect(empty.isEmpty, "표본의 빈 칸 — 지문이 이 칸을 못 본다 · 표본에 값을 채워라: \(empty.joined(separator: " · "))")
    }

    /// 지금 판의 꼴이 그 판의 지문 줄과 같다 — 다르면 판을 올리고 지문 한 줄을 더한다.
    @Test func theShapeOfThisVersionIsRecorded() throws {
        let now = PreviewProtocolVersion.current
        let shape = try Self.shape()
        let mark = Self.digest(shape)
        let rows = try Self.records()
        guard let last = rows.last else { Issue.record("지문 기록이 비었다 — protocol-shapes.txt 에 한 줄: `1 \(mark)`\n지금 꼴:\n\(shape)"); return }
        #expect(rows.map(\.version) == Array(1...max(1, last.version)), "판마다 한 줄 — 1 부터 빈 판 없이 오름차순(덧붙이기 전용)")
        #expect(last.version <= now, "지문 기록이 판(\(now))보다 앞섰다 — `PreviewProtocolVersion.current` 를 \(last.version) 로")
        guard last.version == now else {
            Issue.record("판 \(now) 의 지문 줄이 없다 — protocol-shapes.txt 끝에 한 줄을 더하라: `\(now) \(mark)`\n지금 꼴:\n\(shape)")
            return
        }
        #expect(last.digest == mark, """
            메시지 꼴이 판 \(now) 의 지문과 다르다 — 판을 올리고(`PreviewProtocolVersion.current = \(now + 1)` · 엔진이 판 \(now) 을 받는 말을 \
            `PreviewProtocolVersion.previous` 에) protocol-shapes.txt 끝에 지문 한 줄을 더하라: `\(now + 1) \(mark)`
            지금 꼴:
            \(shape)
            """)
    }
}
