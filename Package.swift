// swift-tools-version: 6.1
import PackageDescription

// 엔진 SDK — 엔진(빌더)과 프로젝트(앱) 사이의 **얇은 계약** 한 패키지. 의존 방향은 하나다: 엔진 → SDK ← 프로젝트.
// SDK 는 잎이다 — 어떤 패키지도 물지 않는다(프로젝트 · 엔진 · 리뷰 킷 · 빌더 코어 0). 정본 = `Docs/SDK.md`(모듈 · 판 · 변경 규칙) · 공개 저장소 `muc-sdk`(MIT — `LICENSE`).
// 모듈은 세 갈래다 — **계약**(플랫폼 중립 · iOS 앱도 문다) · **런타임**(macOS 전용 · 미리보기 호스트 · 엔진의 도구가 문다 · 앱은 물지 않는다) · **시험**(시험 타깃만).
//
// 계약:
//   ProjectFormat   : 프로젝트 문서의 형식 — SDK 가 읽고 쓰는 형식의 판 상수(데이터 · 안 · IA — **한 자리**) · 판 읽개(`FormatStamp`) ·
//                     업그레이드 사슬의 꼴(`UpgradeStep` · `UpgradeChain` — 스텝의 몸은 엔진 쪽 타깃) ·
//                     `.isodata` 레코드 UUID 규약(`IsoDataIDs`) · `.isodata` 의 꼴과 읽기 규율(`IsoDataFile` · `DataModelFile` · `DataSchema` · 검증 둘 · 모르는 키 보존) · CloudKit 호환 규칙(`CloudKitRules`) · 공유 데이터 모델 칸(`SharedDataModel`) · 안 파일의 꼴(`DesignFile`) · 화면 구성요소(`ScreenComponent`) ·
//                     배선 고르기(`IAWiring`) · 폼팩터 낱말(`FormFactor`) · JSON 값(`JSONValue`). Foundation · CryptoKit 만(CoreGraphics 값 꼴은 Foundation 이 싣는다).
//   ScreenMarks     : 화면 요소 표식(`.snapID`) — 프로젝트의 화면 코드가 요소에 이름을 달고, 엔진의 도구가 그 경계를 모은다. SwiftUI 만.
//                     표식이 앵커 · 탭을 거는 것은 트레이트 `ActiveMarks` ∧ macOS 일 때뿐이다(아래) — 그 밖에서는 값이 0인 빈 모디파이어다.
//   DesignTokens    : 디자인 토큰의 꼴 — 색(`HexColor` · `ThemeInfo` · `ColorEntry` · 공급자 `ColorTokenProvider` · 정본 읽개 `SoTColorProvider` · 이름 표기
//                     `ColorRoleNaming`) · 스케일(`ScaleKind` · `ScaleEntry` · `ScaleTokenProvider` · `SoTScaleProvider` · 생성 열거 꼴 `NamedScaleEnum` ·
//                     `EnumScaleProvider`). 값(생성물 · 실행 시점 등록부 · SwiftUI 색으로 옮기는 플랫폼 손)은 프로젝트의 것이다. Foundation · SwiftUI(`ColorScheme`).
//   LaunchTrace     : 창 열기 실측 훅(`OpenTrace` — `MUC_OPEN_TRACE=1` ∧ DEBUG 일 때만) — 프로젝트의 화면 코드와 엔진의 도구가 같은 눈금에 표지를 남긴다. Foundation 만.
//   PreviewProtocol : 엔진 ⟂ 미리보기 호스트의 말(프로토콜 판 `PreviewProtocolVersion` — 한 자리) — 메시지 열(Codable · 평평한 `type` 칸) · 줄 JSON + 길이 접두
//                     프레이밍 · 최신값 우선(`Coalescer`) · 프레임 형식 · 시계 · 소켓 경로 규칙 · 요소 경계(`SnapFrame`) · 그린 글줄과 요소 바탕(`DrawnText` · `DrawnStyle`) · Style 서술(`StyleSchema` · 칸 · 절 · 칸 종류 —
//                     `hello` 에 실리고 엔진이 안 파일을 재는 잣대). Foundation · SDK `ProjectFormat`(JSON 값) · `DesignTokens`(스케일 종류).
//
// 런타임(macOS 전용 — 소스는 `#if os(macOS)` · iOS 에서는 빈 모듈 · 앱 제품의 의존 닫힘에 들면 무는 쪽의 경계 게이트가 빨강):
//   CShm            : POSIX `shm_open` 이 가변 인자 C 함수라 Swift 에서 바로 못 부른다 — 고정 인자로 감싼 C 심 한 줄(제품 아님 · `PreviewWire` 만 문다).
//   PreviewWire     : 전송 — 유닉스 소켓 상주 연결(`Connection` · `UnixSocket`) · 공유 메모리 칸(`SharedRegion` — POSIX shm ⟂ `/tmp` mmap). 엔진 · 호스트가 함께 문다.
//   PreviewHostKit  : 호스트 런타임 — 진입점(`PreviewHost.main(name:screens:layers:ia:frames:tokensBuilt:arguments:onTokensChanged:)`) · 화면 등록 프로토콜(`PreviewScreen` · `PreviewSession`) · 렌더러
//                     (`ImageRenderer.cgImage` 바이트 그대로) · 연결 = 세션(듣기 하나에 연결 여럿) · 자기 창 모드 · 프레임 수집(`FrameSink` · `collectFrames`) ·
//                     그린 글줄 · 요소 바탕 읽기(청한 장을 벡터 한 쪽으로 다시 그려 CoreGraphics PDF 걷기 · PDFKit 으로). **프로젝트를 모른다.**
//
// 시험(시험 타깃만 문다 — 제품 타깃이 물면 무는 쪽의 경계 게이트가 빨강):
//   TestScratch     : 시험의 임시 자리 한 벌 — 임시 폴더 · 파일 자리 · 설정 도메인(임시 폴더 안의 plist)을 만들고 끝에 지운다. 엔진 · 프로젝트의 시험이 다 이것만 쓴다
//                     (무는 쪽의 경계 게이트). Foundation 만.
//
// **플랫폼 바닥 = 가장 낮은 소비자**(프로젝트 코어 패키지의 macOS 14 · iOS 17). 앱(iOS 18 · macOS 15)과
// 엔진(macOS 15)은 그 위에서 그대로 문다. 계약 모듈은 AppKit · UIKit · RealityKit 을 쓰지 않는다 — 셋 중 하나가 필요한 것은 런타임 모듈이거나 SDK 가 아니다.
//
// 이름 — 패키지 이름 = 저장소 이름 `muc-sdk`(정체성). 무는 쪽은 `.package(url: …/muc-sdk.git, exact: <판>)` · 제품 참조 `package: "muc-sdk"` 다(경로 의존으로
// 무는 소비자도 `name: "muc-sdk"` 로 같은 글자). 모듈 · 타입 · 트레이트 · define 에는 제품 이름을 쓰지 않는다.
let package = Package(
    name: "muc-sdk",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ProjectFormat", targets: ["ProjectFormat"]),
        .library(name: "ScreenMarks", targets: ["ScreenMarks"]),
        .library(name: "DesignTokens", targets: ["DesignTokens"]),
        .library(name: "LaunchTrace", targets: ["LaunchTrace"]),
        .library(name: "PreviewProtocol", targets: ["PreviewProtocol"]),
        // 런타임(macOS 전용) — 앱(iOS)이 링크하는 제품과 따로 둔다
        .library(name: "PreviewWire", targets: ["PreviewWire"]),
        .library(name: "PreviewHostKit", targets: ["PreviewHostKit"]),
        // 시험 — 시험 타깃만 문다
        .library(name: "TestScratch", targets: ["TestScratch"]),
    ],
    // `ActiveMarks` — `.snapID` 가 앵커 프리퍼런스로 경계를 올리고 탭을 받는다(도구 빌드). 기본 꺼짐 — 켜는 쪽은 프로젝트 패키지의 도구 트레이트다
    // (프로젝트 패키지가 제 도구 트레이트를 켜면 이 트레이트를 넘긴다). 둘이 겹쳐야 선다(macOS ∧ 트레이트):
    // iOS 에서는 트레이트와 무관하게 늘 꺼진다 — 앱 타깃이 이 제품을 의존으로 물면 패키지 설정이 그대로 따라오므로 iOS 앱에선 이 조건이 마지막 방벽이다.
    traits: [
        .trait(name: "ActiveMarks", description: "화면 요소 표식(.snapID)에 앵커 · 탭 손을 건다 — 도구 빌드만 켠다"),
    ],
    targets: [
        .target(name: "ProjectFormat"),
        .target(name: "ScreenMarks",
                swiftSettings: [.define("ACTIVE_MARKS", .when(platforms: [.macOS], traits: ["ActiveMarks"]))]),
        .target(name: "DesignTokens"),
        .target(name: "LaunchTrace"),
        .target(name: "PreviewProtocol", dependencies: ["ProjectFormat", "DesignTokens"]),
        .target(name: "CShm"),
        .target(name: "PreviewWire", dependencies: ["PreviewProtocol", "CShm"]),
        .target(name: "PreviewHostKit", dependencies: ["PreviewProtocol", "ProjectFormat", "PreviewWire", "ScreenMarks", "LaunchTrace"]),
        .target(name: "TestScratch"),
        // 모델 파일 표본(`Fixtures/`)은 시험이 제 자리에서 읽는다(자원으로 싣지 않는다)
        .testTarget(name: "ProjectFormatTests", dependencies: ["ProjectFormat", "TestScratch"], exclude: ["Fixtures"]),
        .testTarget(name: "DesignTokensTests", dependencies: ["DesignTokens", "TestScratch"]),
        .testTarget(name: "TestScratchTests", dependencies: ["TestScratch"]),
        .testTarget(name: "LaunchTraceTests", dependencies: ["LaunchTrace"]),
        // 표식 시험은 표식의 몸과 같은 조건(macOS ∧ 트레이트)으로 갈린다 — 꺼진 빌드에서만 「빈 모디파이어」를 잰다
        .testTarget(name: "ScreenMarksTests", dependencies: ["ScreenMarks"],
                    swiftSettings: [.define("ACTIVE_MARKS", .when(platforms: [.macOS], traits: ["ActiveMarks"]))]),
        // 꼴 지문 기록(`protocol-shapes.txt` — 판마다 한 줄 · 덧붙이기 전용)은 시험이 제 자리에서 읽는다(자원으로 싣지 않는다)
        .testTarget(name: "PreviewProtocolTests", dependencies: ["PreviewProtocol", "ProjectFormat"], exclude: ["protocol-shapes.txt"]),
        // 소켓 · 공유 메모리 시험은 짧은 자리만 쓴다 — 소켓은 이어진 한 쌍(`socketpair` — 경로 없음) · shm 이름은 pid + 난수(`/mucp.<pid>.<n>` · 31바이트 안)
        .testTarget(name: "PreviewWireTests", dependencies: ["PreviewWire", "PreviewProtocol"]),
        .testTarget(name: "PreviewHostKitTests", dependencies: ["PreviewHostKit", "PreviewProtocol", "PreviewWire"]),
    ]
)
