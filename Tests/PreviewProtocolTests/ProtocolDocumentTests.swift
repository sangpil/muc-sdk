import DesignTokens
import Foundation
import PreviewProtocol
import Testing

// 프로토콜 판 — 코드의 한 자리(`PreviewProtocolVersion.current`) = 정본 문서(이 패키지의 `Docs/SDK.md` §5 「**프로토콜 판: N**」) ·
// 빌드된 표 요약의 한 단은 디자인 토큰의 스케일 한 단과 한 꼴(`ScaleEntry`)이고 줄 꼴은 이름 · pt 두 칸 그대로다(쓰임 · Apple 대응은 줄에 싣지 않는다).
@Suite("프로토콜 판 · 빌드된 표의 꼴")
struct ProtocolDocumentTests {
    static let document = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/SDK.md")

    @Test("SDK.md §5 의 프로토콜 판 글자 = PreviewProtocolVersion.current")
    func theDocumentStatesThisProtocolVersion() throws {
        let text = try String(contentsOf: Self.document, encoding: .utf8)
        #expect(text.contains("**프로토콜 판: \(PreviewProtocolVersion.current)**"), "SDK.md §5 의 프로토콜 판 글자가 코드와 다르다")
    }

    /// 요약의 한 단 = `ScaleEntry` 한 꼴 — 줄에는 이름 · pt 두 칸만(쓰임 · Apple 대응은 싣지 않는다 · 읽으면 빈 쓰임) · 공급자에서 세운 요약도 이름 · pt 만 든다.
    @Test("BuiltTokens 의 한 단 — ScaleEntry · 줄은 이름 · pt 두 칸")
    func aBuiltStepIsAScaleEntryOnTheWireAsTwoFields() throws {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let full = ScaleEntry(name: "title", pt: 28, doc: "제목", apple: "title(28)")
        let built = BuiltTokens(scales: ["type": [full]], layout: [ScaleEntry(name: "gap-wide", pt: 10, doc: "줄 간격")], colors: [], themes: ["light"])
        let line = String(decoding: try e.encode(built), as: UTF8.self)
        #expect(line == #"{"colors":[],"layout":[{"name":"gap-wide","pt":10}],"scales":{"type":[{"name":"title","pt":28}]},"themes":["light"]}"#, "\(line)")
        let back = try JSONDecoder().decode(BuiltTokens.self, from: Data(line.utf8))
        #expect(back.scales["type"] == [ScaleEntry(name: "title", pt: 28)], "읽으면 빈 쓰임 · Apple 대응 없음")
        #expect(back.layout == [ScaleEntry(name: "gap-wide", pt: 10)])
        let sorted = BuiltTokens(scales: Scales([.type: [full]]), layout: [ScaleEntry(name: "gap-wide", pt: 10, doc: "줄 간격")], colors: NoColors())
        #expect(sorted.scales["type"] == [ScaleEntry(name: "title", pt: 28)], "공급자에서 세운 요약은 이름 · pt 만")
        #expect(!sorted.differs(from: back.with(themes: [])), "같은 단 · 같은 간격 역할 — 쓰임은 맞대지 않는다")
    }
}

private extension BuiltTokens {
    func with(themes: [String]) -> BuiltTokens { var t = self; t.themes = themes; return t }
}

private struct Scales: ScaleTokenProvider {
    let byKind: [ScaleKind: [ScaleEntry]]
    init(_ byKind: [ScaleKind: [ScaleEntry]]) { self.byKind = byKind }
    func entries(_ kind: ScaleKind) -> [ScaleEntry] { byKind[kind] ?? [] }
}

private struct NoColors: ColorTokenProvider {
    func themes() -> [ThemeInfo] { [] }
    func entries() -> [ColorEntry] { [] }
}
