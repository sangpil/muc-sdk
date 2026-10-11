import Foundation

/// SDK 판 — **한 자리**. 정본 `Docs/SDK.md`(이 패키지) §5 의 판 칸과 같은 글자다(`ProjectFormatTests.SDKDocumentTests` 가 둘을 맞댄다 — 한쪽만 고치면 빨강) ·
/// 저장소의 판 꼬리표도 이 값이다(공개 저장소 `muc-sdk` — 게이트 `qa/qa-sdk-build.mjs` 가 맞댄다).
/// 엔진이 이 값을 읽어 싣는다(개선 요청의 맥락 `ctx.sdk`). 판을 올리는 규칙은 `Docs/SDK.md` §5 의 표.
public enum SDKVersion {
    public static let current = "0.15.0"
}
