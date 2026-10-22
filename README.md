# muc-sdk

The thin contract between **MUC Life Builder** (the engine) and the projects it opens — your app, its core packages, its preview host and its project tool.
Both sides depend on this one Swift package; it depends on nothing.

엔진(MUC Life Builder)과 그 엔진이 여는 프로젝트(앱 · 코어 · 미리보기 호스트 · 프로젝트 도구)가 함께 무는 **얇은 계약** 한 패키지다. 이 패키지는 아무것도 물지 않는다(잎).

```
engine (builder) ──▶ muc-sdk ◀── project (app · core · preview host · project tool)
```

## Reading order · 읽는 차례

For AI agents and first-time readers — five stops, each pointing to the next. Docs and source comments past this README are in Korean.
AI 에이전트 · 처음 읽는 사람용 — 다섯 곳을 차례로 읽는다.

1. **This README** — what the package is, how to install it, its products. · 이 문서 — 무엇 · 설치 · 제품.
2. **[Docs/SDK.md §1](Docs/SDK.md#1-의존-방향--하나)** — the one dependency direction and the three branches (contract · runtime · test). · 의존 방향 하나와 세 갈래.
3. **[Docs/SDK.md §2](Docs/SDK.md#2-모듈)** — the module map (who calls each module, where to start, what it guarantees), then every public name. · 모듈 지도(누가 부르나 · 시작점 타입 · 지키는 것) · 이어서 공개 이름 전부.
4. **The module head** — the `` // 모듈 `<Name>` `` comment block at the top of the file the map names: what · who calls · invariants · starting types. · 지도가 가리키는 파일 맨 위의 모듈 머리 주석.
5. **[Tests/](Tests)** — one test target per module; the tests pin what the docs state. · 시험 폴더 — 문서가 말하는 것을 시험이 붙든다.

`node qa/qa-map.mjs` keeps this map true: the map in §2 must match `Package.swift`, `Sources/`, `Tests/`, the module heads and the real public types.
지도는 게이트가 실제 모듈과 맞댄다.

## Install · 설치

Pin an exact version — the engine and your project must resolve the same one.
판을 못 박는다(`exact:`) — 한 그래프에 두 판이 들면 SwiftPM 이 해석에서 거부한다.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sangpil/muc-sdk.git", exact: "1.6.1"),
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
A mark never changes layout — with the trait on or off, the marked view keeps the same frame and its alignment guides still reach the parent (overlays included).
`.snapID` 는 트레이트 `ActiveMarks` 가 켜졌을 때만(그리고 macOS 에서만 — iOS 는 늘 꺼짐) 앵커 · 탭을 건다. 제 패키지의 트레이트로 넘긴다 — 앱 빌드엔 없고 도구 빌드에만 선다.
표식은 레이아웃을 바꾸지 않는다 — 트레이트가 켜지든 꺼지든 표식 단 뷰의 프레임이 같고, 정렬 안내선이 바깥(overlay 포함)에 그대로 닿는다.

```swift
// swift-tools-version: 6.1
// Package.swift
let package = Package(
    name: "MyApp",
    traits: [
        .trait(name: "ToolBuild", description: "Element marks for the engine's tools"),   // off by default · 기본 꺼짐
    ],
    dependencies: [
        .package(url: "https://github.com/sangpil/muc-sdk.git", exact: "1.6.1",
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
| `PreviewHostKit` | runtime (macOS) | Preview host runtime — `PreviewHost.main(…)`, screen/session protocols, renderer, drawn text · background readback · 호스트 런타임 |
| `TestScratch` | test · 시험 | Scratch folders and defaults for tests only · 시험의 임시 자리 한 벌 |

Your app links contract products only. Your preview host (an executable in your own package that the engine builds and launches) links `PreviewHostKit`.
앱은 계약 제품만 문다 · 미리보기 호스트(프로젝트가 제 패키지에 두는 실행물 — 엔진이 빌드해 띄운다)가 런타임 제품을 문다.

## Versioning · 판

- **SDK version** = `ProjectFormat.SDKVersion.current` = the repository tag. Tags are never moved; a fix bumps the version.
  SDK 판 = 저장소의 판 꼬리표 · 한 번 찍은 꼬리표는 다시 찍지 않는다.
- **Protocol version** (`PreviewProtocolVersion.current`) is counted separately; the engine accepts every version from the floor (`oldest`) up to the current one. One preview host process serves many connections — one connection is one session.
  프로토콜 판은 따로 센다 · 엔진이 바닥 판부터 지금 판까지 전부 받는다 · 호스트 하나가 연결을 여럿 받는다(연결 = 세션).
- **Pinning SDK 1.1 moves your preview host to protocol version 4** — the builder (engine) must be on SDK 1.1 or newer too; an older builder refuses the host with "update the builder".
  SDK 1.1 로 핀을 올린 프로젝트의 호스트는 프로토콜 판 4 — 빌더(엔진)도 1.1 이상이어야 한다(옛 빌더는 「빌더를 업데이트하세요」로 거절).
- **SDK 1.2 adds an optional field to the IA document** (`ScreenNode.entry` — which screen · what kind of control · which element). The protocol stays at version 4 and the IA format at version 1; a 1.1 reader keeps the field as an unknown key.
  SDK 1.2 는 IA 문서에 선택 칸 하나(`ScreenNode.entry` — 어느 화면 · 무엇을 · 요소)를 더한다 — 프로토콜 판 4 · IA 형식 판 1 그대로 · 1.1 읽개는 모르는 칸으로 보존한다.
- **SDK 1.3 adds image slots to the style schema** (`StyleSlot` · `StyleSchema.slots` — the host declares where an image sits; the value is one string in the style dictionary: empty = the original image, or `isomodel:<name>`). The shelf is a folder the project chooses; the name is a file name in that folder without its extension, and resolving it is up to the host and the app — the SDK promises only the value's shape. The host and the app draw the model in that place. This moves the preview host to protocol version 5 even if it declares no slots — the builder must be on SDK 1.3 or newer too.
  SDK 1.3 은 Style 서술에 이미지 자리를 더한다(`StyleSlot` · `StyleSchema.slots` — 호스트가 이미지 자리를 선언 · 값은 Style 값 사전의 글자 하나: 빈 글 = 원래 이미지 ⟂ `isomodel:<이름>`). 서가는 프로젝트가 정하는 폴더 — 이름은 그 폴더의 파일 이름(확장자 없이)이고 풀이는 호스트 · 앱 몫(SDK 는 값의 꼴만 약속한다). 그 자리에 모델을 그리는 것은 호스트와 앱 — 자리를 선언하지 않아도 호스트는 프로토콜 판 5 · 빌더도 1.3 이상이어야 한다.
- **SDK 1.4 lets a preview session wait before a frame** (`PreviewSession.prepare(_ context: RenderContext)` — async, default returns at once; the context is the frame's size · theme · offscreen flag, so a session warms the picture for that appearance — key its cache by name *and* appearance). The host awaits it before every picture it draws (`render` · `patch` · tokens changed · `shot` · its own window), so an offscreen frame shows a slot's model from the first frame instead of an empty slot while the model is still being drawn. Messages that arrive meanwhile wait their turn (patches merge). A preparation that outlives the host's limit (20 s, inside the engine's wait) or a session that closes meanwhile is cancelled — cooperative cancellation; a frame cut at the limit is final (no redraw signal follows), and a source that ignores cancellation may be asked again while still running, so share in-flight work. Nothing on the wire changes — the protocol stays at version 5, so a 1.4 host works with a 1.3 builder and a 1.3 host works with a 1.4 builder (it draws as before). A session that implements nothing draws exactly what it drew on 1.3.
  SDK 1.4 는 미리보기 세션이 장을 그리기 전에 기다릴 손을 더한다(`PreviewSession.prepare(_ context: RenderContext)` — 비동기 · 기본은 곧장 · 문맥 = 그 장의 크기 · 테마 · 창 없는 렌더인가 — 그 외양의 그림을 데운다 · 캐시는 이름과 외양으로). 호스트가 그리기 전마다(`render` · `patch` · 토큰 바뀜 · `shot` · 자기 창) 기다려서, 창 없는 장도 모델을 그리는 중의 빈 자리가 아니라 첫 장부터 자리의 모델을 그린다. 그 사이 온 메시지는 차례대로 뒤에 선다(patch 는 합쳐진다). 호스트의 시한(20 초 — 엔진이 기다리는 시한 안)을 넘긴 준비 · 그 사이 닫힌 세션의 준비는 취소된다(협력 취소 — 시한에 잘린 장은 끝난 장이고 다시 그리라는 신호가 없다 · 취소를 무시한 원천은 다음 준비와 겹쳐 불릴 수 있어 진행 중인 일을 나눠 기다린다). 와이어는 그대로다 — 프로토콜 판 5 라 1.4 호스트 ⟂ 1.3 빌더 · 1.3 호스트 ⟂ 1.4 빌더가 다 선다(1.3 호스트는 예전처럼 그린다). 아무것도 구현하지 않은 세션은 1.3 과 같은 장을 낸다.
- **SDK 1.5 reads back the text and backgrounds a screen drew** — a render may ask for them (`RenderRequest.drawn`); the host draws that frame once more as a vector page and reads it (public CoreGraphics PDF scanning · PDFKit), and the frame header carries every drawn text line (`DrawnText` — string · box · font name · size · weight · color · the innermost marked element around it) and, per marked element, the fill painted exactly on its bounds (`DrawnStyle` — color · corner radius). Screen code adds nothing — no new modifier; elements already marked with `.snapID` get their text and background. Protocol version 6 (a 1.5 host needs a 1.5 builder; a 1.5 builder still talks to 1.3 · 1.4 hosts and reads "no text" from them).
  SDK 1.5 는 화면이 그린 글줄 · 바탕을 읽어 싣는다 — render 가 청하면(`RenderRequest.drawn`) 호스트가 그 장을 벡터 한 쪽으로 한 번 더 그려 읽고(공개 CoreGraphics PDF 걷기 · PDFKit), 프레임 머리에 그린 글줄 전부(`DrawnText` — 글 · 상자 · 글꼴 이름 · 크기 · 굵기 · 색 · 그 줄을 품은 가장 안쪽 표식 요소)와 표식 요소마다 그 경계에 칠한 바탕(`DrawnStyle` — 색 · 모서리 반경)을 싣는다. 화면 코드는 아무것도 달지 않는다 — 새 모디파이어 없음 · `.snapID` 를 이미 단 요소의 글자 · 바탕이 잡힌다. 프로토콜 판 6(1.5 호스트는 1.5 빌더가 받는다 · 1.5 빌더는 1.3 · 1.4 호스트와도 말하고 그 호스트의 머리는 글줄 없음).
  **1.5.1** keeps the spaces inside a drawn line — one space per drawn space glyph (a non-breaking space or a tab comes as one U+0020), one space where a font-fallback run left only a gap (between Hangul words in the system font), leading and trailing spaces trimmed — and reading a drawn page leaves no CoreGraphics PDF error line on stderr. Protocol stays at version 6.
  **1.5.1** 은 그린 글줄 안의 공백을 싣는다 — 그린 공백 글자마다 공백 하나(줄바꿈 없는 공백 · 탭은 U+0020 하나) · 글꼴 대체 런이 벌림만 남긴 자리(시스템 글꼴의 한글 낱말 사이)에 공백 하나 · 앞뒤 공백은 다듬는다 — 호스트가 stderr 에 CoreGraphics PDF 오류 줄을 찍지 않는다. 프로토콜 판은 6 그대로.
- **SDK 1.6 lets a style element declare the system effects it uses** (`StyleElement.effects` — an open vocabulary `StyleEffect`: `glass` · `material` · `blur` · `shadow` · `motion`, unknown words kept as they are). It is a statement of fact — "this element is drawn with glass" — so the engine marks exactly that element instead of guessing from field names; whether a renderer can draw the effect is the engine's call. One line in the schema: `StyleElement(id: "card", label: "Card", snapPrefix: "garden.card", effects: [.glass])`; the old initializer stays. Protocol version 7 even if no element declares an effect (a 1.6 host needs a 1.6 builder; a 1.6 builder still talks to 1.5 hosts and reads "nothing declared" from them).
  SDK 1.6 은 Style 서술의 절이 제가 쓰는 시스템 효과를 선언하게 한다(`StyleElement.effects` — 열린 낱말 `StyleEffect`: `glass` · `material` · `blur` · `shadow` · `motion` · 모르는 낱말도 그대로 든다). 사실의 선언이다 — 「이 요소는 유리로 그려진다」 — 엔진은 칸 이름으로 짐작하지 않고 그 요소에만 표지를 단다 · 어느 렌더가 그 효과를 그리지 못하는가는 엔진의 판단이다. 서술에 한 줄: `StyleElement(id: "card", label: "카드", snapPrefix: "garden.card", effects: [.glass])` · 옛 이니셜라이저는 그대로. 효과를 하나도 선언하지 않아도 프로토콜 판 7(1.6 호스트는 1.6 빌더가 받는다 · 1.6 빌더는 1.5 호스트와도 말하고 그 호스트의 서술은 선언 없음).
  **1.6.1** reads the drawn text and backgrounds of a frame with a material in it: the vector pass alone draws materials in their inactive appearance (public `materialActiveAppearance`, macOS 15+ — the PNG stays as it is), so the page no longer turns into one raster image with no lines; a material element's background is that solid approximation (an element that declares `effects: [.material]` tells the engine so), and fills stacked on one element's bounds give their composited visible color. Glass wrapped around content is not drawn offscreen at all — not in the PNG either — so draw glass as an approximation when `RenderContext.offscreen` is true, or lay it as a background layer. Protocol stays at version 7.
  **1.6.1** 은 머티리얼이 있는 장의 그린 글줄 · 바탕을 읽는다 — 벡터 그림에서만 머티리얼을 비활성 외양으로 그려(공개 `materialActiveAppearance` · macOS 15 이상 · PNG 는 그대로) 그 장이 글줄 없는 래스터 한 장이 되지 않는다 · 머티리얼 요소의 바탕은 그 단색 근사다(`effects: [.material]` 을 선언한 요소면 엔진이 안다) · 한 요소의 경계에 겹친 칠은 합성한 보이는 색이다. 내용에 바로 씌운 유리는 창 없는 그림에 아예 그려지지 않는다(PNG 에도 없다) — `RenderContext.offscreen` 이 참이면 유리를 근사로 그리거나 바탕 층에 깐다. 프로토콜 판은 7 그대로.
- **Formats grow by adding fields**: readers keep unknown keys and write them back (`extra`), open vocabularies (`FormFactor`, `ScaleKind`, …) carry unknown words as they are. No form factor is required — Mac-only and iPad-only projects are valid.
  형식은 칸 더하기로 자란다 — 모르는 키는 보존해 되쓰고, 열린 낱말은 모르는 낱말도 그대로 든다 · 어느 폼팩터도 필수가 아니다(맥 전용 · iPad 전용도 선다).
- **1.0 freezes the contract**: the public surface a project uses keeps compiling across 1.x (source · file · wire compatibility — the gate diagnoses API breakage against the previous tag). Breaking changes only in a major version (2.0); additions (new types · methods · fields with defaults) bump the minor; fixes bump the patch.
  1.0 은 계약 동결 — 프로젝트가 문 공개 표면을 1.x 가 계속 지킨다(소스 · 파일 · 와이어 호환 · 게이트가 직전 꼬리표와 깨짐을 맞댄다). 깨는 변경은 주 판(2.0)에서만 · 덧붙임(새 타입 · 새 메서드 · 기본값 있는 새 칸)은 부 판 · 고침은 수 판.

The contract — modules, the three branches, version rules, what is *not* in the SDK — is [Docs/SDK.md](Docs/SDK.md) (Korean).
계약의 정본은 [Docs/SDK.md](Docs/SDK.md).

## Checks · 게이트

```sh
node qa/run-all.mjs        # qa-sdk-build (builds alone · tests per target · leaf · branches · public fit · tag · API breakage · public names = contract table · no versioned default arguments) + qa-docs + qa-map (module map = manifest · folders · module heads) + sample-model (test fixture = generated bytes)
```

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 MakeUsClever.
