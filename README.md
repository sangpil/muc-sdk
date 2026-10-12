# muc-sdk

The thin contract between **MUC Life Builder** (the engine) and the projects it opens — your app, its core packages, its preview host and its project tool.
Both sides depend on this one Swift package; it depends on nothing.

엔진(MUC Life Builder)과 그 엔진이 여는 프로젝트(앱 · 코어 · 미리보기 호스트 · 프로젝트 도구)가 함께 무는 **얇은 계약** 한 패키지다. 이 패키지는 아무것도 물지 않는다(잎).

```
engine (builder) ──▶ muc-sdk ◀── project (app · core · preview host · project tool)
```

## Install · 설치

Pin an exact version — the engine and your project must resolve the same one.
판을 못 박는다(`exact:`) — 한 그래프에 두 판이 들면 SwiftPM 이 해석에서 거부한다.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sangpil/muc-sdk.git", exact: "0.16.0"),
],
targets: [
    .target(name: "MyScreens", dependencies: [
        .product(name: "ProjectFormat", package: "muc-sdk"),
        .product(name: "ScreenMarks", package: "muc-sdk"),
    ]),
]
```

Platforms: macOS 14 · iOS 17 (runtime products are macOS only).
Toolchain: Swift 6.1 or newer — this package's manifest is `swift-tools-version: 6.1` (package traits).
툴체인: Swift 6.1 이상 — 이 패키지의 매니페스트가 트레이트를 쓰는 `swift-tools-version: 6.1` 이다.

### Element marks in your tool build · 도구 빌드에서 요소 표식 켜기

`.snapID` is an empty modifier unless the `ActiveMarks` trait is on (and only on macOS — iOS is always off).
Pass it from a trait of your own, so your app build never carries it and your tool build does. Using traits needs `swift-tools-version: 6.1` in your manifest too.
`.snapID` 는 트레이트 `ActiveMarks` 가 켜졌을 때만(그리고 macOS 에서만 — iOS 는 늘 꺼짐) 앵커 · 탭을 건다. 제 패키지의 트레이트로 넘긴다 — 앱 빌드엔 없고 도구 빌드에만 선다.

```swift
// swift-tools-version: 6.1
// Package.swift
let package = Package(
    name: "MyApp",
    traits: [
        .trait(name: "ToolBuild", description: "Element marks for the engine's tools"),   // off by default · 기본 꺼짐
    ],
    dependencies: [
        .package(url: "https://github.com/sangpil/muc-sdk.git", exact: "0.16.0",
                 traits: [.trait(name: "ActiveMarks", condition: .when(traits: ["ToolBuild"]))]),
    ],
    targets: [
        .target(name: "MyScreens", dependencies: [.product(name: "ScreenMarks", package: "muc-sdk")]),
    ]
)
```

```sh
swift build --traits ToolBuild     # tool build — marks on (macOS) · 도구 빌드
swift build                        # app build — marks are empty modifiers · 앱 빌드
```

## Products · 제품

| Product | Branch · 갈래 | What · 무엇 |
|---|---|---|
| `ProjectFormat` | contract · 계약 | Project document formats — version constants, version reader, upgrade-chain shape, `.isodata` model files, design files, screen components, IA document, JSON value · 프로젝트 문서의 형식 |
| `ScreenMarks` | contract | Element marks `.snapID` — active only with the `ActiveMarks` trait on macOS · 화면 요소 표식 |
| `DesignTokens` | contract | Design token shapes — colors, scales, providers, source-of-truth readers · 디자인 토큰의 꼴 |
| `LaunchTrace` | contract | Window-open timing hook `OpenTrace` · 창 열기 실측 훅 |
| `PreviewProtocol` | contract | Engine ⟂ preview host messages, framing, protocol version, style schema · 엔진 ⟂ 미리보기 호스트의 말 |
| `PreviewWire` | runtime (macOS) | Transport — Unix socket connection, shared memory · 전송 |
| `PreviewHostKit` | runtime (macOS) | Preview host runtime — `PreviewHost.main(…)`, screen/session protocols, renderer · 호스트 런타임 |
| `TestScratch` | test · 시험 | Scratch folders and defaults for tests only · 시험의 임시 자리 한 벌 |

Your app links contract products only. Your preview host (an executable in your own package that the engine builds and launches) links `PreviewHostKit`.
앱은 계약 제품만 문다 · 미리보기 호스트(프로젝트가 제 패키지에 두는 실행물 — 엔진이 빌드해 띄운다)가 런타임 제품을 문다.

## Versioning · 판

- **SDK version** = `ProjectFormat.SDKVersion.current` = the repository tag. Tags are never moved; a fix bumps the version.
  SDK 판 = 저장소의 판 꼬리표 · 한 번 찍은 꼬리표는 다시 찍지 않는다.
- **Protocol version** (`PreviewProtocolVersion.current`) is counted separately; the engine accepts every version from the floor (`oldest`) up to the current one. One preview host process serves many connections — one connection is one session.
  프로토콜 판은 따로 센다 · 엔진이 바닥 판부터 지금 판까지 전부 받는다 · 호스트 하나가 연결을 여럿 받는다(연결 = 세션).
- **Formats grow by adding fields**: readers keep unknown keys and write them back (`extra`), open vocabularies (`FormFactor`, `ScaleKind`, …) carry unknown words as they are. No form factor is required — Mac-only and iPad-only projects are valid.
  형식은 칸 더하기로 자란다 — 모르는 키는 보존해 되쓰고, 열린 낱말은 모르는 낱말도 그대로 든다 · 어느 폼팩터도 필수가 아니다(맥 전용 · iPad 전용도 선다).
- 0.x is a public beta: removing or changing a public name bumps the minor version. **1.0 promises** that the public surface a project uses keeps compiling across 1.x (source · file · wire compatibility — the gate diagnoses API breakage against the previous tag).
  0.x 는 공개 베타 — 공개 이름을 빼거나 바꾸면 부 판. 1.0 은 프로젝트가 문 공개 표면을 1.x 가 계속 지킨다는 약속이다(소스 · 파일 · 와이어 호환 · 게이트가 직전 꼬리표와 깨짐을 맞댄다).

The contract — modules, the three branches, version rules, what is *not* in the SDK — is [Docs/SDK.md](Docs/SDK.md) (Korean).
계약의 정본은 [Docs/SDK.md](Docs/SDK.md).

## Checks · 게이트

```sh
node qa/run-all.mjs        # qa-sdk-build (builds alone · tests per target · leaf · branches · public fit · tag · API breakage · public names = contract table · no versioned default arguments) + qa-docs + sample-model (test fixture = generated bytes)
```

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 MakeUsClever.
