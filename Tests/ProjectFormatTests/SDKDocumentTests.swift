import Foundation
import ProjectFormat
import Testing

// SDK 판 — 코드의 한 자리(`SDKVersion.current`) = 정본 문서(이 패키지의 `Docs/SDK.md` §5 「**SDK 판: x.y.z**」). 한쪽만 고치면 빨강.
// 문서는 이 패키지 안이다 — 이 파일에서 세 칸 위가 패키지 뿌리(`Tests/ProjectFormatTests/` → 뿌리)라 어느 체크아웃 · 어느 저장소에서든 같은 자리다.
@Suite("SDK 판 — 코드 = 정본 문서")
struct SDKDocumentTests {
    static let document = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/SDK.md")

    @Test("SDK.md §5 의 판 칸 = SDKVersion.current")
    func theDocumentStatesTheSDKVersion() throws {
        let text = try String(contentsOf: Self.document, encoding: .utf8)
        #expect(text.contains("**SDK 판: \(SDKVersion.current)**"), "SDK.md §5 의 판 칸이 코드(`SDKVersion.current` = \(SDKVersion.current))와 다르다")
        #expect(SDKVersion.current.split(separator: ".").count == 3 && SDKVersion.current.split(separator: ".").allSatisfy { Int($0) != nil }, "판은 x.y.z 정수 셋(저장소의 판 꼬리표)")
    }
}
