# muc-sdk — 엔진 ⟂ 프로젝트 사이의 얇은 계약

엔진(MUC Life Builder — 빌더)과 프로젝트(앱 · 그 코어 · 미리보기 호스트 · 프로젝트 도구)가 **함께 무는 단 하나의 패키지**의 단독 정본이다 — 모듈 · 세 갈래(계약 ⟂ 런타임 ⟂ 시험) ·
의존 방향 · SDK 판 · 프로토콜 판 · 형식이 자라는 규칙 · 1.0 의 약속 · 공개 표면의 변경 규칙 · SDK 에 들지 않는 것과 그 까닭. 이 저장소는 **공개**다 — `public` 한 줄이 곧 외부 프로젝트와의 약속이다(§6).
파일 형식의 열기 판정 · 판을 올리는 차례 · 프로젝트 폴더의 꼴(`muc.json`) · SDK 가 디코드하지 않는 형식의 판은 빌더(엔진)가 갖는다 — 이 문서는 SDK 에 든 꼴과 상수만 다룬다.

몸 — 이 저장소 뿌리의 [`Package.swift`](../Package.swift)(SwiftPM 패키지 `muc-sdk`). 시험 — `Tests/ProjectFormatTests` · `ScreenMarksTests` · `DesignTokensTests` · `LaunchTraceTests` · `PreviewProtocolTests` ·
`PreviewWireTests` · `PreviewHostKitTests` · `TestScratchTests`(게이트 [`qa/qa-sdk-build.mjs`](../qa/qa-sdk-build.mjs) — 대상마다 0건이면 빨강 · 잎 · 갈래 · 공개 적합 · 판 꼬리표 · 공개 표면 깨짐 진단 · 공개 이름 = §2 표 · 판 품은 기본 인자 0 · 모델 파일 표본은 [`qa/sample-model.mjs`](../qa/sample-model.mjs) 가 짓고 잰다).

## 1. 의존 방향 — 하나

```
엔진(빌더) ──▶ SDK ◀── 프로젝트(앱 · 코어 · 미리보기 호스트 · 프로젝트 도구)
```

- **SDK 는 잎이다** — 어떤 패키지도 물지 않는다(프로젝트 · 엔진 · 빌더의 렌더 코어 · 리뷰 킷 0). 게이트 `qa-sdk-build` 가 경성 0 으로 잰다.
- **모듈은 세 갈래다** — 게이트가 갈래마다 잰다(갈래 목록은 그 게이트 머리의 한 곳 · 새 모듈은 한쪽에 적어야 선다).

  | 갈래 | 모듈 | 무엇을 무나 | 누가 무나 |
  |---|---|---|---|
  | **계약** — 플랫폼 중립 | `ProjectFormat` · `ScreenMarks` · `DesignTokens` · `LaunchTrace` · `PreviewProtocol` | Foundation · CryptoKit · CoreGraphics · SwiftUI · 계약 모듈 | 엔진 · 프로젝트(앱 제품 포함) · 미리보기 호스트 |
  | **런타임** — macOS 전용 | `PreviewWire`(+ C 심 `CShm`) · `PreviewHostKit` | 계약의 것 + 플랫폼 프레임워크(Darwin · AppKit · Observation · ImageIO · UniformTypeIdentifiers · PDFKit) + 런타임 모듈 | 미리보기 호스트(프로젝트가 자기 코드로 빌드한 실행물) · 엔진의 도구 · 프로젝트의 호스트 시험 — **앱은 물지 않는다** |
  | **시험** — 시험 타깃만 | `TestScratch` | Foundation | 엔진 · 프로젝트의 **시험 타깃** — 제품 타깃(앱 제품 · 실행물 · 도구 라이브러리)이 물면 무는 쪽의 경계 게이트가 빨강 |

  런타임 모듈의 Swift 소스는 통째로 `#if os(macOS)` 안이다(iOS 에서는 빈 모듈) · 제품도 계약과 따로 선다 — 앱이 링크하는 제품의 의존 닫힘에 런타임 제품이 들면
  무는 쪽(프로젝트)의 경계 게이트가 빨강이다(iOS 빌드에 macOS 전용 코드가 섞이는 길을 막는다). 계약 모듈은 런타임 모듈을 물지 않는다.
  런타임이 SDK 에 드는 까닭: 미리보기 호스트는 **프로젝트의 실행물**이라 엔진 내부를 물 수 없고, 호스트와 엔진이 같은 전송 · 같은 호스트 표면을 한 벌로 나눠야 한다.
- **엔진은 프로젝트를 모른다** · **프로젝트는 엔진 내부를 모른다** — 둘이 나누는 이름은 SDK 의 공개 표면뿐이다(프로젝트가 앱에 싣는 엔진 런타임 — 렌더 코어 · 리뷰 킷 — 은
  빌더 배포 패키지에서 받는다 · §4). 그 방향은 양쪽 저장소의 경계 게이트가 잰다.
- 소비자는 SDK 를 **판을 못 박은 의존 한 줄**로 문다 — `.package(url: "https://github.com/sangpil/muc-sdk.git", exact: "<판>")` · 제품 참조는 `.product(name: …, package: "muc-sdk")`.
  한 그래프에 두 판이 들면 SwiftPM 이 해석에서 거부한다(빌더 배포 패키지와 프로젝트가 같은 판을 물어야 선다 — 핀 어긋남은 조용히 지나가지 않는다).
- 소비자의 툴체인은 **Swift 6.1 이상**이다 — 이 패키지의 매니페스트가 트레이트를 쓰는 `swift-tools-version: 6.1` 이다. 표식 트레이트 `ActiveMarks` 는 소비자가 제 트레이트로 넘긴다
  (`.package(url: …, exact: …, traits: [.trait(name: "ActiveMarks", condition: .when(traits: ["<제 도구 트레이트>"]))])` — 그 매니페스트도 6.1 · 예시는 [README](../README.md)).

| 소비자 | 무는 제품 |
|---|---|
| 엔진(빌더 — 앱 · CLI · 도구 패키지 · 렌더 코어 · 편집기) | `ProjectFormat` · `DesignTokens` · `ScreenMarks` · `LaunchTrace` · `PreviewProtocol` · `PreviewWire`(미리보기 클라이언트 · 원격 화면 창) · `PreviewHostKit`(창 없는 렌더 · 커밋 눈금) |
| 프로젝트의 앱 제품 · 코어 패키지 | `ProjectFormat` · `ScreenMarks` · `DesignTokens` · `LaunchTrace` |
| 프로젝트의 미리보기 호스트 · 프로젝트 도구(엔진 내부를 물지 않는다) | 위 넷 + `PreviewProtocol` · `PreviewHostKit` |
| 시험 타깃 — 엔진 · 프로젝트 | `TestScratch`(시험의 임시 자리 한 벌) + 제 대상의 제품 · 호스트 시험은 `PreviewHostKit`(렌더러 · 세션 꼴) |

**앱 제품의 공개 표면은 프로젝트의 것이다** — SDK 의 타입을 앱 타깃(Xcode)의 소스나 그 제품의 생성물이 쓰면 그 제품이 그 이름만 범위를 좁혀 다시 낼 수 있다
(예 — 화면 데이터 제품이 `ScreenComponent` 를 · 토큰 제품이 생성물이 쓰는 `HexColor` · `ThemeInfo` · `ColorEntry` 를). 쓰는 자리가 없는 이름은 다시 내지 않는다.
그 밖의 소비자(엔진 · 제품 · 도구 타깃 · 시험)는 SDK 모듈을 직접 `import` 한다.

## 2. 모듈

**모듈 지도** — 모듈마다 한 줄: 누가 부르나 · 어디서 읽기 시작하나(시작점 타입) · 무엇을 지키나 · 그 모듈의 머리 주석(파일 맨 위 `` // 모듈 `<이름>` `` 묶음 — 무엇 · 누가 부르나 · 지키는 것 · 시작점) · 시험 폴더.
게이트 [`qa/qa-map.mjs`](../qa/qa-map.mjs) 가 이 표를 `Package.swift` 의 타깃 · `Sources/` 폴더 · `Tests/` 폴더 · 머리 주석 · 소스의 공개 타입과 양방향으로 맞댄다(빠짐 · 남음 빨강).

| 모듈 | 갈래 | 누가 부르나 | 시작점 타입 | 지키는 것 | 머리 주석 | 시험 |
|---|---|---|---|---|---|---|
| **ProjectFormat** | 계약 | 엔진 · 프로젝트(앱 제품 포함) · 미리보기 호스트 | `IsoDataFile` · `DesignFile` · `IADoc` · `FormatStamp` · `JSONValue` | 판을 몸보다 먼저 읽는다 · 모르는 키는 보존해 되쓴다 · SDK 가 읽고 쓰는 형식의 판 상수는 한 자리 | [Formats.swift](../Sources/ProjectFormat/Formats.swift) | [ProjectFormatTests](../Tests/ProjectFormatTests) |
| **ScreenMarks** | 계약 | 프로젝트의 화면 코드(앱 제품 포함) · 엔진의 도구 · `PreviewHostKit` | `View.snapID(_:)` · `SnapPreferenceKey` · `SnapTapKey` | 표식의 몸은 `ActiveMarks` ∧ macOS 일 때만 — 그 밖엔 값이 0인 빈 모디파이어 | [SnapID.swift](../Sources/ScreenMarks/SnapID.swift) | [ScreenMarksTests](../Tests/ScreenMarksTests) |
| **DesignTokens** | 계약 | 엔진의 도구 · 프로젝트(토큰 생성물 · 미리보기 호스트) · `PreviewProtocol` | `HexColor` · `ColorTokenProvider` · `SoTColorProvider` · `SoTScaleProvider` | 꼴만 든다 — 토큰의 값과 플랫폼 색 손은 프로젝트의 것 | [Colors.swift](../Sources/DesignTokens/Colors.swift) | [DesignTokensTests](../Tests/DesignTokensTests) |
| **LaunchTrace** | 계약 | 프로젝트의 화면 코드 · 엔진의 도구 · `PreviewHostKit` | `OpenTrace` | `MUC_OPEN_TRACE=1` ∧ DEBUG 일 때만 잰다 — 그 밖엔 몸이 빈 함수 | [OpenTrace.swift](../Sources/LaunchTrace/OpenTrace.swift) | [LaunchTraceTests](../Tests/LaunchTraceTests) |
| **PreviewProtocol** | 계약 | 엔진의 미리보기 클라이언트 · 미리보기 호스트 · `PreviewWire` · `PreviewHostKit` | `Message` · `Hello` · `ProtocolJudge` · `Framing` · `StyleSchema` | 메시지 꼴이 바뀌면 프로토콜 판을 올린다 · 엔진이 판정자 | [Messages.swift](../Sources/PreviewProtocol/Messages.swift) | [PreviewProtocolTests](../Tests/PreviewProtocolTests) |
| **CShm** | 런타임 · 제품 아님(C 심) | `PreviewWire` 만 | `cshm_open` | 고정 인자로 감싼 한 줄 밖의 일을 하지 않는다 | [CShm.h](../Sources/CShm/include/CShm.h) | — (`PreviewWireTests` 가 공유 메모리로 잰다) |
| **PreviewWire** | 런타임 | 엔진(미리보기 클라이언트 · 원격 화면 창) · `PreviewHostKit` — 앱은 물지 않는다 | `Connection` · `UnixSocket` · `SharedRegion` | 상대의 판에 없는 메시지는 보내지 않는다 · 상대가 죽으면 `onClose` 한 번 | [Connection.swift](../Sources/PreviewWire/Connection.swift) | [PreviewWireTests](../Tests/PreviewWireTests) |
| **PreviewHostKit** | 런타임 | 미리보기 호스트 실행물 · 호스트 시험 · 엔진의 도구 — 앱은 물지 않는다 | `PreviewHost` · `PreviewScreen` · `PreviewSession` · `FrameRenderer` | 프로젝트를 모른다 · 연결 = 세션 · 엔진의 수명에 묶인다 | [PreviewHost.swift](../Sources/PreviewHostKit/PreviewHost.swift) | [PreviewHostKitTests](../Tests/PreviewHostKitTests) |
| **TestScratch** | 시험 | 엔진 · 프로젝트 · SDK 의 시험 타깃만 | `TestScratch` | 만든 자리는 그 시험이 끝날 때 지운다 | [TestScratch.swift](../Sources/TestScratch/TestScratch.swift) | [TestScratchTests](../Tests/TestScratchTests) |

아래는 모듈마다의 공개 이름 전부다(공개 표면 = 이 표들 · §6). 표의 **약속** 열 — **프로젝트**(앱 · 코어 · 미리보기 호스트 · 프로젝트 도구가 무는 이름) ⟂ **엔진**(엔진의 도구가 무는 판 상수 · 사슬 꼴 · 메시지 열 · 전송 · 렌더러).
둘 다 소스 호환 약속은 같다(§5) — 다른 것은 깨는 변경의 비용이다(엔진 표면만 깨는 변경은 엔진 한 저장소가 같은 판에서 따라가고 프로젝트 영향은 0 이다).

**`ProjectFormat`** — 프로젝트 문서의 형식. Foundation · CryptoKit 만.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `SDKVersion` | 엔진 | SDK 판 — **한 자리**(`current` — §5 의 판 칸과 같은 글자 · SDK 시험 `SDKDocumentTests` 가 둘을 맞댄다 · 저장소의 판 꼬리표도 이 값). 엔진이 읽어 싣는다(개선 요청의 맥락 `ctx.sdk`) |
| `IsoDataFormat` · `DesignFormat` · `IAFormat` · `FormatVersions` | 엔진 | **SDK 가 직접 읽고 쓰는 형식**(모델 파일 · 안 파일 · IA 문서)의 판 상수 — **한 자리**(읽는 최신 · 가장 옛 판 · 쓰는 바닥) · 형식마다 판 범위 한 벌(`versions` — 가장 옛 판 · 최신 · 쓰는 바닥 · 판 칸 이름). 판 상수는 그 형식을 디코드하는 모듈과 함께 산다 — 씬 · 모델 · 배선의 판은 그 형식을 읽는 엔진 쪽이 갖는다(§4) |
| `FormatStamp` | 엔진 | 판 읽개 — 문서 맨 위의 정수 칸(`version` · `schema`)을 몸을 풀기 전에 읽는다(참/거짓 · 소수는 판이 아니다) |
| `UpgradeStep` · `UpgradeEffect` · `UpgradeChain` · `UpgradeOutcome` · `UpgradeError` · `JSONValue.holdsSomething` | 엔진 | 형식 업그레이드 사슬의 **꼴** — 스텝 하나(한 판 → 다음 판 · JSON 값 → JSON 값 · 순수 · 갈래 항등 ⟂ 값 바꿈 ⟂ 잃음(잃는 칸 이름) · 기계 낱말 `key` · 요약 한 줄 · 그 문서가 실제로 잃는 칸) · 형식마다의 사슬(가장 옛 판 → 최신 · 쓰는 바닥 판 `writeFloor` · 판 범위 한 벌로 세우기 `init(versions:steps:)` · 간격마다 스텝 하나 — 불변식 `violations` · 길 `path(from:)` · 한 번 돌기 `upgrade` — 판 칸은 사슬이 스텝마다 찍는다 · 잃음 스텝의 몸이 칸을 걷지 않으면 `UpgradeError.lossyStepKept`) · 결과(올릴 것인가 `needsUpgrade` = 실제로 잃는 칸 ∨ 길에 값 바꿈 · 쓸 판 `to` = max(마지막 값 바꿈 · 잃음 스텝의 판, 쓰는 바닥) — 최신이 아니다 · 쓸 판의 문서 · 밟은 스텝 · 잃는 칸) · 칸에 내용이 들었나(빈 배열 · 빈 글자 · 널은 아니다). **스텝의 몸은 SDK 에 없다** — 엔진 쪽 별도 타깃이 갖는다 |
| `IsoDataIDs` | 프로젝트 | `.isodata` 레코드의 스토어 UUID 규약(RFC 4122 v5 · 이름공간 `<머리>/<스키마>` — 머리는 스키마의 `idNamespace` · 없으면 `defaultNamespace` `com.makeusclever.isodata` · UUID 꼴 id 는 그대로) — 데이터 도구가 내는 id 와 코어가 앉히는 행이 바이트째 같아야 씬 결합이 선다 · 앉은 행을 지키는 스키마는 그 행을 앉힌 머리를 적는다 |
| `IsoDataFile` · `IsoDataError` · `LifeFile` · `DataModelFile` · `DataSet` · `DataRecord` · `DataClock` · `DataSchema` · `DataNames` · `DataLayer` · `DataEntity` · `DataField` · `DataType` · `DataStatus` · `DataOnDelete` · `DataAlias` · `DataTrait` · `DataValueType` · `DataRule` · `DataRuleCheck` · `SchemaValidation` · `RecordValidation` · `RecordIssue` · `DataDates` | 프로젝트 | `.isodata` 의 **형식 계약**(꼴 · 인코딩 · 검증 둘 — 이것까지가 SDK · 생성물(Swift 스키마 · 문서 울타리) · 새 행 id 는 엔진의 데이터 도구) — 한 형식 두 모양(삶 파일은 통째로 나른다 · 모델 파일은 스키마 · 데이터셋) · 판을 먼저 읽고 미래 판은 이름 대고 거부(`allowingNewer` = 읽기 전용 창) · 스키마가 먼저 선다(틀리면 경로를 대고 파일째 거부) · **모르는 키는 보존하고 알린다**(꼴마다 `extra` · 자리마다 한 줄 `DataModelFile.unknownKeys`) · 물러난 키(`migrated` · 엔티티와 필드의 `sql` — 판 4 의 저장 백엔드 생성 사본)는 알리지 않고 들고 되쓴다 · 모르는 낱말(형 `DataType.unknown` · 상태 · 삭제 규칙 · 규칙 `DataRuleCheck.other`)은 글자 그대로 들고 경고(`SchemaValidation.warnings` — 읽기 전용으로 다룬다) · 스키마의 선택 칸 `idNamespace`(UUID 머리) · `revision`(스키마 판 — 공유 모델의 맞물림) · 레코드 오류는 행마다 `issues`(파일을 거부하지 않는다) · 상한 자름 · 최소 판으로 쓰기 · 키 정렬 · 이름 낱말 규칙(`DataNames.words`). 엔진의 데이터 도구 · 데이터 창과 프로젝트의 도구(엔진 내부 없이 모델 파일을 읽는다)가 같은 한 벌을 문다. 읽기 규율(① 판 먼저 · ② 스키마 먼저 · ③ 모르는 키 보존 · ④ 레코드 오류는 행 단위)은 `DataModelCoding` 머리가 번호째 든다 |
| `CloudKitRules` · `SchemaIssue` | 프로젝트 | CloudKit 호환 규칙 — 모델 파일 스키마가 CloudKit 프라이빗 컨테이너에 동기화되는 스토어의 스키마로 서는가(실재 엔티티 · 필드만): 필드는 선택이거나 기본값 · 참조는 선택 · 삭제 규칙은 `setNull` · `cascade` · 고유 규칙 없음 · 모르는 형 없음 · 관계 짝은 대상 쪽 목록으로 지어진다(짝을 지을 수 없는 참조 목록은 스키마 검증이 거부) · 두 판 사이는 칸 더하기만(`evolutionProblems` — 레코드 종류 · 칸을 빼거나 이름을 바꾸지 않는다 · 선택 → 필수 금지 · 형 바꿈 금지 · 열거 값은 더하기만 · 이름은 스토어가 보는 `swift.model` · `swift.property`). 엔진의 데이터 검사와 프로젝트의 스키마 패키지 시험 · 도구가 같은 답을 낸다 · 문제 하나 = 경로와 까닭 |
| `SharedDataModel` · `SharedModelLockstep` | 프로젝트 | 공유 데이터 모델 — 여러 앱 프로젝트가 같은 데이터(같은 모델 파일 · 같은 스키마 패키지 · 같은 저장 컨테이너)를 함께 읽고 고칠 때 매니페스트가 그 모델을 가리키는 칸의 꼴(`id` 역 DNS 정체 · `model` 모델 파일 상대 경로 — 프로젝트 폴더 밖 허용 · `package` 스키마 패키지 폴더 · `revision` 채택한 스키마 판 · `cloudKitContainer` · `appGroup` 저장 컨테이너 식별자 한 자리 · 모르는 칸 보존 · 값 규칙 `problems`)과 맞물림(같은 id · 프로젝트마다 채택한 판 = 모델의 `schema.revision` · 저장 컨테이너가 같다). 매니페스트의 어느 자리에 싣는가 · 경로를 어떻게 푸는가는 매니페스트를 읽는 엔진의 몫 |
| `DesignFile` | 프로젝트 | 안 파일(`<화면>/<안>.design.json`)의 꼴 — 자리 · 이름들 · 판(`version(_:)` — 맨 위 정수 칸 · 없으면 `DesignFormat.version`) · 머리(확정 · 만든 때 · 판) · Style 값 채우기 · 의견 폴더 이름 · 바이트 규칙(`encoder` · `decoder` — 엔진이 안 파일을 쓰는 한 벌 · 프로젝트 시험이 같은 규칙으로 바이트 동치를 잰다). Style 의 **꼴**(화면마다의 값 타입)은 프로젝트의 것이라 사전으로만 다룬다 |
| `ScreenComponent` | 프로젝트 | 안 파일 `components` 칸 한 줄(일반 · 씬 · 모델 · 영역 · 조작 · 구성요소와 영역의 모르는 칸 보존 `extra`) + 관대한 읽기(모르는 종류 · 깨진 줄은 건너뛴다 — 종류는 닫힌 열거: 새 종류는 앱이 그리는 코드와 함께 온다) · 칸 크기 → 그릴 픽셀의 셈 한 벌 |
| `IAWiring` | 프로젝트 | 배선 고르기 — 배선 → 확정 → 가장 최근(안) ⟂ 배선 → 이름 순 첫(씬) |
| `FormFactor` | 프로젝트 | 폼팩터 낱말 — 매니페스트 `platforms` 와 IA 플랫폼 칸의 한 벌 · 열린 꼴(아는 낱말 `iphone` · `ipad` · `mac` = `known` · 모르는 낱말도 글자 그대로) · **어느 폼팩터도 필수가 아니다** — 플랫폼 목록은 비지 않고 겹치지 않으면 선다(맥 전용 · iPad 전용 포함 · `problems(in:)`) |
| `IADoc` · `ScreenNode` · `ScreenData` · `ScreenEntry` · `ScreenJump` · `JumpEntry` · `Hub` | 프로젝트 | IA 문서(`paths.ia`)의 꼴 — 마디 · 점프 · 허브 · 읽는 엔티티 · 제안 표지 · 진입 선택(`ScreenEntry` — 어느 화면 · 무엇을(열린 낱말 `ScreenEntry.Kind`) · 요소 · 선택 칸 · 있으면 `via` 는 그 선택에서 지은 글이고 어긋나면 글이 이긴다 · 못 읽는 꼴이면 마디째 거부하지 않고 읽은 그대로 모르는 칸으로 든다) · 꼴마다 모르는 칸 보존(`extra`). **프로젝트 낱말은 글자 · JSON 그대로 든다**: 진입 손 `JumpEntry.control` 은 글자 · 크롬 구성 `ScreenNode.chrome` · `chromeChart` 와 내비 항목 `Hub.items` 는 `JSONValue`(읽은 그대로 쓴다 — 파일 꼴 불변 · 형식 판 1) · 허브 종류는 열린 꼴. 엔진(저장소 · 화면 지도)과 미리보기 호스트(층 자료 `PreviewProtocol.LayerContext` — 크롬의 구성 · 탭 슬롯을 호스트가 이 문서에서 셈한다)가 함께 문다 |
| `JSONValue` · `JSONValueError` | 프로젝트 | JSON 값 한 덩이(널 · 참거짓 · 수 · 큰 정수 · 글자 · 배열 · 객체 — 수의 정본 꼴: Double 로 정확히 담기는 수는 `number` · 크기 2^53 을 넘는 정수는 `integer`(Int64 — 시각 ns · 큰 id 가 깎이지 않는다) · `int(_:)` · `integerValue` · `numberValue`) — 프로젝트가 뜻을 정하는 칸(IA 의 크롬 구성 · 내비 항목 · 안 파일의 Style 값) · 모르는 칸 주머니(`extra`) · 엔진 명령의 결과 · 미리보기 호스트의 조절판 값이 같은 한 벌이다. 정수로 떨어지는 수는 정수로 쓴다 · 쓸 때 키 정렬(`text`) · Codable 값 → JSON 값(`from`) · → JSON 객체(`dictionary(from:)` — 객체가 아니면 던진다) · JSON 값 → 프로젝트의 타입(`decode` — 칸의 꼴은 그 타입의 Codable 이 정한다) · 글자 · 수 · 배열 · 사전 리터럴 |

**`ScreenMarks`** — 화면 요소 표식. SwiftUI 만.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `View.snapID(_:)` · `SnapPreferenceKey` · `SnapTapKey` · `\.snapTap` | 프로젝트 | 프로젝트의 화면 코드가 요소에 이름을 달고, 호스트 런타임의 프레임 수집(`PreviewHostKit.FrameSink`)이 그 경계를 모은다(엔진의 화면 위 오버레이도 같은 키를 읽는다). 앵커 · 탭은 `ACTIVE_MARKS` 일 때만 선다(탭은 받는 손 `snapTap` 이 걸렸을 때만 — 없으면 앱의 손을 가리지 않는다 · 호스트 자기 창) · 표식은 레이아웃을 바꾸지 않는다(켬 ⟂ 끔 같은 프레임 · 안쪽 정렬 안내선이 overlay 등 바깥에 그대로 닿는다) — 트레이트 `ActiveMarks` ∧ macOS(iOS 는 늘 꺼짐). 트레이트를 넘기는 것은 프로젝트 패키지의 도구 트레이트다 — 앱 빌드에서 표식은 값이 0인 빈 모디파이어다. 키 · 탭 환경값(꼴)은 트레이트와 무관하게 늘 선다 — 읽는 쪽이 트레이트 배선 없이 컴파일되고, 꺼진 빌드에서는 아무도 쓰지 않아 늘 비어 있다 |

**`DesignTokens`** — 디자인 토큰의 꼴. Foundation · SwiftUI(외양 `ColorScheme` · 색 `Color`).

| 이름 | 약속 | 무엇 |
|---|---|---|
| `HexColor` · `Color(_: HexColor)` | 프로젝트 | 색 하나(sRGB 8비트 + 알파) — 읽기(`#rgb` · `#rrggbb` · `#rrggbbaa` · `0x` · `rgb()` · `rgba()`) · hex 글 · 표시 글 · `CGColor` · 휘도 · 대비 · SwiftUI 색(`Color(_:)` — `Color(.sRGB, …)` 성분 그대로 · 엔진의 도구가 쓴다). 앱 제품의 SwiftUI 색 손(플랫폼 색 경로)은 프로젝트가 든다(§4) — 두 손이 같은 값(풀어 본 성분 · 그린 픽셀)임을 프로젝트의 시험이 macOS · iOS 에서 잰다 |
| `ThemeInfo` · `ColorEntry` | 프로젝트 | 테마 한 벌의 머리(이름 · 외양 기준 · 설명) · 역할 하나(이름 · 쓰임 · Apple 대응 · 테마별 값) |
| `ColorValue` | 엔진 | 색 칸의 값 하나(저장 꼴 camel ⟂ `#hex`)를 공급자로 푼다 — 정본 실명(역색인 → `ColorRoleNaming` 글자 규칙) · 아는가 · 테마 값 · 화면 이름 · 리터럴(규약 한 벌 — 엔진의 조절판 · 쓰임 셈이 쓴다) |
| `ColorTokenProvider` · `SoTColorProvider` · `ColorRoleNaming` | 프로젝트 | 색 공급자 프로토콜 · 정본 읽개(`tokens.json` 의 `semantic.themes` — 테마 · 역할 차례는 파일의 줄 차례 · `{primitive…}` 참조 사슬 풀기 · 수정 시각이 바뀌면 다시 읽기 · 곁 칸 둘 `sceneSlotAliases()` · `roleGroups()`) · 역할 이름 표기(kebab ⟂ camel) |
| `SceneSlotNaming` | 프로젝트 | 씬 칸 → 씬 역할 규칙 — **`scene-` + kebab(칸)**(`lawn` → `scene-lawn`) · 규칙 밖 칸은 정본 곁 칸 `semantic.$sceneSlots`(칸 → 역할 · 데이터)가 든다. 렌더 코어의 씬 색 해소기(칸 → 기본 색)에 답하는 쪽이 쓴다 — 엔진의 씬 해소기와 프로젝트 앱의 해소기가 한 답 |
| `ColorRoleGroups` | 엔진 | 색 역할의 묶음(토큰 창 · 색 고르기의 절과 차례) — 정본 곁 칸 `semantic.$group`(`$order` 묶음 차례 · `$fallback` · 역할 이름 → 묶음 · 끝이 `*` 인 키는 앞머리) · 고르는 차례 = 같은 이름 → 가장 긴 앞머리 → `$fallback` · 칸이 없으면 묶음 없음(`none`) |
| `ScaleKind` · `ScaleEntry` · `ScaleTokenProvider` · `SoTScaleProvider` · `NamedScaleEnum` · `EnumScaleProvider` | 프로젝트 | 스케일 — 종류(열린 꼴: 아는 종류 `space` · `radius` · `type` = `known` · 모르는 종류는 공급자가 빈 목록) · 한 단 · 공급자 프로토콜 · 정본 읽개 · 생성 열거의 꼴 · 열거 공급자 · 정본 읽개는 간격 역할(`semantic.layout` — `layout()` · 숫자 ⟂ `{primitive.space.<단>}` 참조)과 간격 이름 → pt(`spacePt` — 스케일의 단 → 역할)도 낸다 |

**`LaunchTrace`** — 창 열기 실측 훅. Foundation 만.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `OpenTrace` | 프로젝트 | 창 하나가 서기까지를 재는 자(`MUC_OPEN_TRACE=1` ∧ DEBUG 일 때만 — 그 밖엔 몸이 빈 함수) — 표지(`mark` · `first`) · 세기(`count`) · 소요(`span`) · 메인 정지 감시 + 첫 유휴(`arm`). 시각의 기준은 프로세스 시작 · 출력은 표준 오류. 프로젝트의 화면 코드와 엔진의 도구가 같은 눈금에 표지를 남긴다 |

**`PreviewProtocol`** — 엔진 ⟂ 미리보기 호스트의 말. Foundation · SDK `ProjectFormat`(JSON 값) · `DesignTokens`(스케일 종류). 흐름은 엔진이 호스트를 띄운다 → 엔진이 붙는다(연결 = 세션) → 호스트 `hello`(등록부 · 층 · 프레임 형식 · 프로젝트 데이터 — IA 낱말 · 기기 틀 · 빌드된 표 요약) → 엔진 `hello`(전송 선택 · 공유 메모리 자리) → `render`(값과 함께) → `frame` … 조절판 `patch`(최신값 우선) → `frame` · 자기 창 모드면 `window`(자리 · 크기 · 엔진 창 번호) → `patch` → `ack` · 끝 `bye`.
**안 파일 · IA 문서(프로젝트 문서)는 엔진만 읽고 쓴다** — 호스트는 문서를 열지 않고 `render` 가 싣는 값(화면의 Style 값 · 층의 값과 자료)과 `patch` 를 받는다.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `PreviewProtocolVersion` · `ProtocolDialect.Step` · `ProtocolDialect.chain` · `ProtocolDialect.v1` · `ProtocolDialect.v2` · `ProtocolDialect.v3` · `ProtocolDialect.v4` · `ProtocolDialect.v5` | 엔진 | 프로토콜 판 — **한 자리**(`current` — 지금 6 · §5) · 엔진이 받는 바닥 판(`oldest` — 2) · 바닥부터 지금 판 바로 아래까지의 말(`previous`) · 한 판 사이의 스텝(그 판 ⟂ 다음 판 — 올리는 손 · 내리는 손 · 내리는 손이 nil 이면 그 판에 없는 메시지) · 스텝을 이은 말(`chain` — 올리기는 차례대로 · 내리기는 거꾸로) · 스텝 `v1to2`(판 2 의 새 hello 칸을 걷는다) · `v2to3`(이름 없는 조절판 칸에 칸 키를 채운다) · `v3to4`(hello 의 Style 서술마다 문구 목록을 걷는다 — `render` · `patch` 는 그대로) · `v4to5`(hello 의 Style 서술마다 자리 목록을 걷는다 — `render` · `patch` 는 그대로) · `v5to6`(`render` 의 청함 `drawn` 과 프레임 머리의 `texts` · `styles` 를 걷는다 — 판 5 호스트의 머리는 글줄 없음 = nil) |
| `ProtocolJudge` · `ProtocolDialect` · `ProtocolMismatch` · `ProtocolDialectError` | 엔진 | 판 맞대기 — **엔진이 판정자**다: 호스트 hello 의 첫 줄에서 몸을 풀기 전에 판만 읽어(`dialect(greeting:)` — 판 읽개 `FormatStamp`) 그 판의 말이 있으면 그 말로 받고(`judge(host:)` — 같은 판 · 바닥까지의 옛 판) 그 밖은 사람 말 한 줄로 거절한다(`hostNewer` — 빌더를 올린다 ⟂ `hostTooOld` — 프로젝트를 받아 온다). 판 하나의 말 = 그 판의 줄 ⟂ 지금 판의 메시지(지금 판은 Codable 그대로 · 옛 판은 줄을 올리고 내리는 손 한 쌍 — 정수는 정수 그대로 · 그 판에 없는 메시지는 줄을 짓지 않는다 `encodeIfSpoken` ⟂ `encode` 는 `notSpoken`) · 호스트 쪽 규칙(`hostAccepts` — 엔진이 같거나 새 판이면 받는다) · 이 엔진(`engine` — 지금 판 + `previous`) |
| `Message` · `Hello` · `RenderRequest` · `FrameHeader` · `Patch` · `Edit` · `TokensChanged` · `ShotRequest` · `WindowRequest` · `Ack` · `ErrorMessage` · `Bye` · `Size` · `HostTiming` · `FramePayload` · `SharedMemoryInfo` | 엔진 | 메시지 열 가지(평평한 `type` 칸 · JSON 한 줄 = 메시지 하나)와 그 몸. `render` 는 화면의 Style 값(`style` — 서술로 잰 사전 · nil = 서술의 기본값)과 겹칠 층(`layers`) · 픽스처 갈아 끼우기(`fixture` — 프로젝트가 뜻을 정하는 JSON · nil = 상태의 픽스처) · 층만(`layersOnly` — 투명한 장에 층만)을 싣고 그 화면의 값을 갈아 끼운다 · 그린 글줄 · 요소 바탕의 청함(`drawn` — 장마다 값이 드는 일이라 한 장을 남길 때만)을 싣고 · 프레임 머리는 요소 경계와 요소 목록(`elements` — 경계 수 대조) · 층 보고(`layers` — `LayerReport`) · 그린 글줄과 요소 바탕(`texts` · `styles` — `drawn` 을 청한 장에만 · 경계 수 대조에 들지 않는다 · 청하지 않았거나 판 5 호스트면 nil)을 싣는다(본체의 요소 = `screenElements`) · 창 요청은 자리 · 크기 · 엔진 창 번호(`above` — 그 바로 위 보통 층) · 보이는 부분(`clip` — 엔진의 자리가 스크롤 · 창 끝에 잘렸으면 호스트 창은 그 부분만 덮고 화면은 제 크기 그대로)을 싣는다 · 프레임 바이트는 줄 뒤에 길이 접두로 오거나(소켓) 공유 메모리 칸 번호만 실린다(전송 종류는 열린 꼴 — 모르는 종류면 호스트는 소켓으로 보낸다) · `patch` 는 칸 여럿(`edits[]`)을 한 번에 싣는다 · 값 = 칸 종류의 저장 꼴(문구면 저장 꼴의 글자 — 칸 이름 = 문구 이름) · 메시지 종류(`Message`)는 닫힌 열거다 — 적합한 상대에게서 모르는 종류는 오지 않는다(§5) |
| `LayerReport` · `Insets` | 엔진 | 층 하나가 이번 장에 낸 것 — 요소 id · 푼 자료(프로젝트가 뜻을 정하는 JSON — 크롬이면 본체를 비켜선 구성 · 픽스처의 도구) · 덮는 띠(`cover` — 위 · 왼쪽 · 아래 · 오른쪽 pt · 엔진이 그 아래에 제 그림(씬 썸네일)을 놓을 때 비켜설 자리) · 엔진은 뜻을 모른 채 프로젝트의 엔진 쪽 손에 넘긴다 |
| `LayerContext` | 프로젝트 | 층 자료의 엔진 쪽 꼴 — 층이 얹힐 화면(IA 마디 id) + 그 프로젝트의 IA 문서(`ProjectFormat.IADoc`). 엔진이 문서에서 채워 `LayerState.data` 로 싣고(`data()`) 호스트가 푼다(`init(data:)`) — 그 문서에서 무엇을 셈하는가(크롬의 구성 · 탭 슬롯 · 유도 규칙)는 프로젝트(호스트)가 정한다 |
| `ScreenInfo` · `LayerInfo` · `LayerState` | 프로젝트 | `hello.screens` · `hello.layers` 한 칸(등록부 이름 · 상태 · Style 서술 — 안의 이름 · 값은 싣지 않는다 · 화면은 픽스처가 데이터로 고른 색 역할의 수 `fixtureColorUsage` · 층은 구성 서술 `composition` — 둘 다 선택) · `render.layers` 한 칸(층 이름 · 그 층의 Style 값 · 자료 — 프로젝트가 뜻을 정하는 JSON(크롬이면 `LayerContext` — 화면 + IA 문서) · 엔진이 문서에서 읽어 넘기고 뜻을 모른다) |
| `IAInfo` · `DeviceFrameInfo` · `BuiltTokens` | 프로젝트 | hello 의 프로젝트 데이터(셋 다 선택 — 싣지 않은 호스트면 엔진은 그 칸 없는 길로): IA 낱말(앱이 여는 화면 · 진입 손의 낱말과 이름 · 탭마다 손 · 옛 낱말 → IA id · 앱에 뷰가 아직 없는 화면) · 기기 틀(낱말 · 폼팩터 · 크기 · 코너 · 안전영역 · 편집기 기기 틀의 씬 띠 — 띠가 없으면 크롬 층의 `cover`) · 빌드된 표 요약(스케일 · 간격 역할 · 색 역할 × 테마 · 테마 — 공급자 둘에서 세우고(`init(scales:layout:colors:)`) 맞댄다 `differs` — 테마는 집합으로). IA 낱말 · 기기 틀의 칸은 **모두 선택**(빠지면 빈 값 · 0 · 모르는 칸은 `extra` 로 보존 · 빈 값 `init()`). 값은 전부 프로젝트가 정한다 |
| `LayerComposition` · `CompositionField` | 프로젝트 | 층의 구성 서술 — 층이 IA 문서에서 읽는 칸(마디의 구성 칸 `nodeKeys` · 구성 객체의 칸 `fields` · 허브 슬롯 항목의 칸 `hubItem`)과 칸마다 종류(열린 꼴 — 아는 종류 `bool` · `text` · `symbol` · `choice` · `symbols` · `labels` · `subset` · `slot` = `known` · JSON 꼴과 편집기의 컨트롤 · 모르는 종류는 꼴을 재지 않는다) · 이름 · 고를 값 · 읽기의 기본값 · 도움말 · 보이는 조건(`when`) · 기준 칸(`of`). 엔진은 이것으로 일반 편집기의 칸을 세우고 IA 문서의 그 칸을 읽기에서 잰다(`problems` — 서술 밖 칸 · 널은 재지 않는다) |
| `CalloutValues` · `CalloutAnchor` | 프로젝트 | 콜아웃 층의 **푼 값** — 프로젝트의 콜아웃 안을 호스트가 그 장의 테마로 푼 것(치수 pt · 색 `#rrggbb[aa]`) · 호스트가 층 보고(`LayerReport.data`)로 내고(`data()` — 제 판 칸 `v` 를 싣는다 · `formatVersion`) 엔진이 읽어(`init(data:)` — 판 칸이 없으면 1) 렌더 코어의 콜아웃 값을 칸 대 칸 짓는다(카드는 씬을 읽어 서므로 엔진이 그린다) · 칸은 모두 선택(빠지면 기본값 · 모르는 칸 보존) · 짚은 자리(`anchor` — 그림 폭 · 높이의 비율 · 없으면 엔진이 가운데를 짚는다 · 계약은 비율 두 수만 — 그림 안의 점으로 푸는 손 `point(in:)` 은 엔진 쪽) |
| `FieldKind` · `StyleElement` · `StyleField` · `StyleText` · `StyleSlot` · `StyleSchema` · `StyleValues` · `StyleSchemaError` · `StyleTextError` · `StyleSlotError` · `StyleEdit` · `StyleEditError` · `JSONValue.pt` · `JSONValue.token` · `JSONValue.scalarToken` · `JSONValue.scalarPt` | 프로젝트 | Style **서술** — 프로젝트가 화면 · 층마다 내는 데이터(절 · 칸(키 · 종류 · 절 · 이름 — 이름은 선택: 호스트가 지은 이름 ⟂ nil 이면 엔진이 제 규칙으로 짓는다) · 문구 · 기본값). 칸 종류(스칼라 — 종류는 `ScaleKind` · 색 · 토글 — `color` · `bool` 밖의 낱말은 스칼라 종류로 읽는다)의 저장 꼴을 잰다(`normalize` — 빠진 칸 채우기 · 스칼라의 남는 열쇠 떼기 · 서술 밖 칸 빼기 · 꼴이 틀리면 거부) · **문구**(`StyleText` · 서술의 `texts` — 디자이너가 조절판에서 바꾸는 화면의 글: 키 · 절 · 이름(선택) · 최대 길이(글자 수 · 없으면 `defaultMaxLength`))는 칸 종류가 아니라 기본값(빈 목록)이 있는 따로 선 목록이다 — 값은 같은 Style 값 사전의 글자 칸 · 기본 글은 `defaults` 의 같은 칸 · 저장 꼴(`StyleText.normalized` — 한 줄 라벨: 글 속 줄바꿈은 공백 하나 · 앞뒤 공백을 자소 묶음 단위로 걷기 · 최대 길이(1 이상 — 코드로 지으면 `precondition` · 줄에서는 디코드 오류)에서 자르기 · 빈 글 = 기본 글 · `normalize` 는 글자가 아닌 값 · 칸 · 다른 문구와 겹치는 이름을 `StyleTextError` 로 거부 · 값도 기본 글도 없으면 칸과 같은 `StyleSchemaError.missing`) · 사전으로 다루는 화면 코드의 읽개(`StyleSchema.text(_:in:)` — 관대한 읽기: 빈 글 · 글자 아닌 값은 기본 글) · **자리**(`StyleSlot` · 서술의 `slots` — 화면 코드만 아는 이미지 자리를 호스트가 선언한다: 키 · 절 · 그 자리 요소의 표식(`snap` — 선택 · 미리보기에서 누르면 엔진이 이 칸을 고른다) · 이름(선택) · 받는 종류(`kinds` — 열린 낱말 목록 · 1 개 이상 · 낱말은 ASCII 영문자 · 숫자 · `-` · `_` · 대소문자를 가린다(참조의 종류 규칙과 같다 — 어기면 디코드 오류) · 없으면 `defaultKinds` = `isomodel`))는 문구와 같은 따로 선 목록이다 — 값은 같은 Style 값 사전의 글자 칸: 빈 글(원래 이미지) ⟂ 참조 `<종류>:<이름>`(`StyleSlot.Reference` — **서가** = 프로젝트가 정하는 폴더 · 참조의 이름은 그 폴더의 파일 이름(확장자 없이) · 그 폴더를 정하고 이름을 파일로 푸는 것은 호스트 · 앱의 몫(이 SDK 는 값의 꼴만 약속한다) · 빈 이름 · 경로 글자(`/` · `\`) · 이름 전체가 `.` · `..` · 점으로 시작(숨긴 파일) · 앞뒤 공백 · 줄바꿈 · 제어 문자 · 서식 문자(이름 위장)는 꼴이 아니다 · `parse` · `text`) · 기본 값은 `defaults` 의 같은 칸(없으면 빈 글 — 문구와 달리 `missing` 이 아니다) · **빈 글은 값이다**(원래 이미지를 고른 것 — 기본 값으로 돌아가지 않는다) · 저장 꼴(`StyleSlot.normalized` — 받지 않는 종류의 참조는 빈 글로 정규화: 문구의 강제 정규화와 같은 뜻 · 호스트가 `kinds` 를 좁혀도 옛 안 파일이 열린다) · `normalize` 는 글자 아닌 값 · 꼴 아닌 값 · 칸 · 문구 · 다른 자리와 겹치는 이름을 `StyleSlotError` 로 거부 · 읽개(`StyleSchema.slot(_:in:)` — 관대한 읽기: 글자 아님 · 꼴 아님 · 받지 않는 종류는 빈 글) · 그 값을 읽어 사진 대신 모델을 그리는 것은 호스트 · 앱의 화면 코드다(엔진은 경계 위에 덮어 그리지 않는다) · 자리를 모르는 엔진(프로토콜 판 4 이하)은 판정이 막고(판 5 호스트를 `hostNewer`) 판 4 호스트에게는 새 엔진이 자리 목록을 걷어 말한다(`v4to5` — 실려 온 자리 값은 그 호스트가 서술 밖 칸으로 뺀다 · 화면은 원래 이미지) · 프로젝트의 Style 타입은 문구를 `String` 칸으로 든다(앱 · 호스트의 화면 코드가 그 칸을 읽는다) · 문구를 모르는 상대 — 엔진(프로토콜 판 3 이하)은 판정이 막는다(판 4 호스트를 `hostNewer` 로 거절 — 문구 값이 조용히 빠지는 짝은 와이어에서 서지 않는다) · 판 3 호스트에게는 새 엔진이 서술의 문구 목록을 걷어 말하고(`v3to4`) 실려 온 문구 값은 그 호스트가 서술 밖 칸으로 뺀다(화면은 기본 글) · 서술 디코더가 모르는 키를 넘기는 것은 읽기 방어일 뿐이다 · 스칼라 저장 꼴을 만드는 손(`pt` · `token`)과 읽는 손(`scalarToken` · `scalarPt` — 토큰이 pt 를 앞선다 · `normalize` 와 같은 규칙) · 칸 목록(`StyleField.list` — 절을 단다) · 절 고르기(`StyleElement.of`) · 값 하나를 프로젝트의 Style 타입에 넣는 손(`StyleEdit.setting` — Codable 왕복 · 없는 칸은 거부 · 호스트가 `patch` 를 받는 자리와 엔진의 조절판이 같은 손). 호스트가 `hello` 에 싣고 엔진이 같은 값으로 안 파일을 잰다(엔진의 안 문서 손) |
| `SnapFrame` | 엔진 | 요소 하나의 경계(pt · 화면 좌상단 원점 · 소수 둘째 자리) — 프레임 머리의 `snapFrames` · 찍기의 `frames.json` 이 같은 꼴 |
| `DrawnText` · `DrawnStyle` | 엔진 | 화면이 **그린** 글줄 하나(글 — 앞뒤 공백을 걷은 한 줄 · 감긴 글은 줄마다 · 상자(글리프의 진행 폭 × 글꼴의 올림 · 내림) · 글꼴의 PostScript 이름(묶음 표지 · 가변 인스턴스 꼬리를 걷은 것 — `.` 으로 시작하면 플랫폼의 시스템 UI 글꼴 · 한 줄에 대체 글꼴이 섞이면 첫 조각의 것) · 크기(pt) · 굵기(1–1000 — 글꼴의 굵기 축 값 ⟂ 이름의 굵기 낱말 ⟂ 400) · 색(`#rrggbb[aa]` · sRGB · 겹친 불투명도까지 · 단색이 아니면 nil) · 줄을 품은 가장 안쪽 요소(`element` — 줄의 가운데를 품는 경계 중 가장 작은 것 · 없으면 nil))와 요소 하나의 그린 바탕(그 요소의 경계와 네 변이 0.5 pt 안으로 맞게 칠한 면 중 가장 위의 것 — 색 · 모서리 반경(pt — 연속 곡률 모서리면 그 모서리를 낳은 반경) · 그런 면이 없는 요소는 싣지 않는다) — 프레임 머리의 `texts` · `styles`. **화면 코드는 아무것도 달지 않는다** — 호스트가 그 장을 벡터로 한 번 더 그려 읽는다(`PreviewHostKit`) |
| `Framing` · `Inbound` · `PayloadBuffer` | 엔진 | 줄 꼴 — JSON 한 줄 + (소켓 프레임이면) u32 LE 길이 접두 바이트 · 줄은 판 하나의 말로 쓰고 읽는다(`header(_:)` — 지금 판 ⟂ `header(_:dialect:)` ⟂ 그 판에 없으면 nil `headerIfSpoken(_:dialect:)`). 받는 줄의 디코더는 SDK 안의 손이다(연결이 쓴다 · 조각 먹이기와 목적지 버퍼로 바로 읽기를 같은 상태로 든다 · 엔진 쪽은 첫 줄에서 말을 고른다) |
| `Coalescer` | 엔진 | 최신값 우선 — 진행 중 요청이 한도(기본 1)에 차면 칸마다 마지막 값만 쌓았다가 답이 오면 한 묶음으로 · 값 통째(`render`)를 보낼 때 쌓인 값을 버린다(`discardPending`) |
| `FrameFormat` · `PreviewClock` · `SocketPath` | 엔진 | 프레임 픽셀 형식(`RGBA8-premultipliedLast` · sRGB — `ImageRenderer.cgImage` 의 꼴 그대로 · 줄 바이트는 머리가 갖는다) · 두 프로세스가 같이 읽는 시계(`CLOCK_UPTIME_RAW`) · 소켓 자리(`/tmp/mucp-<폴더 경로 FNV-1a 64>.sock` — `sun_path` 103바이트 안) |

**`PreviewWire`** — 전송(런타임 · macOS 전용). 계약 + Darwin · C 심 `CShm`(POSIX `shm_open` 이 가변 인자라 고정 인자로 감싼 한 줄 — 제품 아님).

| 이름 | 약속 | 무엇 |
|---|---|---|
| `Connection` · `WireStats` | 엔진 | 상주 연결 하나 — 쓰기는 락 하나로 줄 세워 `writev`(머리 + 몸 한 번 · 몸 복사 0 · 상대의 판에 없는 메시지는 보내지 않고 거짓) · 읽기는 전용 스레드(프레임 몸은 목적지 버퍼로 바로) · 상대가 죽으면 `onClose` 한 번 · 전송 계측 · 읽고 쓰는 판의 말(`init(fd:)` — 지금 판 ⟂ `init(fd:dialect:)`) · 엔진 쪽은 판정자를 넘겨(`start(judge:)`) 첫 줄에서 고른 말로 받은 hello 를 넘기기 전에 갈아 타고, 판이 맞지 않으면 끊고 `onClose` 에 `ProtocolMismatch` |
| `UnixSocket` | 엔진 | 유닉스 스트림 소켓 — 듣기 · 받기 · 붙기 · 이어진 한 쌍 · 소켓 버퍼 4 MB |
| `SharedRegion` | 엔진 | 공유 메모리 칸(POSIX shm ⟂ `/tmp` mmap 파일) — 엔진이 만들고(호스트가 죽어도 남는다) 호스트가 연다 · 칸 셋을 돌려 쓴다 · 모르는 전송 종류는 이름 대고 거절 |

**`PreviewHostKit`** — 호스트 런타임(macOS 전용). 계약 + AppKit · SwiftUI · CoreGraphics · ImageIO · UniformTypeIdentifiers · PDFKit · Observation · SDK `ScreenMarks` · `LaunchTrace` · `PreviewWire`. **프로젝트를 모른다** — 프로젝트의 호스트 실행물이 등록부를 넘긴다.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `PreviewHost` | 프로젝트 | 진입점 `PreviewHost.main(name:screens:layers:ia:frames:tokensBuilt:arguments:onTokensChanged:)`(`ia` · `frames` · `tokensBuilt` = hello 에 싣는 프로젝트 데이터 · 기본 nil · `arguments` 기본 = 실행 인자 · `onTokensChanged` = 엔진의 `tokensChanged` 를 받았을 때 프로젝트가 토큰을 다시 읽는 손 · 기본 빈 손) — `--socket <경로>` ⟂ `--folder <프로젝트 폴더>` · `--activity none` · 등록부 셈 · 소켓 듣기 · **연결 = 세션**(듣기는 프로세스 수명 동안 열려 있어 같은 자리로 연결을 여럿 받는다 — 세션마다 hello · seq · 공유 메모리 · 창이 따로 · 세션이 닫히면 그 세션의 창 · 칸을 거둔다) · `hello` 를 NSApplication 을 세우기 전에 · 엔진이 떠나면 끝난다(연결이 모두 끊기고 짧은 유예 안에 다시 붙지 않거나 · 붙기 전이라도 띄운 프로세스가 끝나면 — 고아로 남지 않는다 · 소켓 파일은 끝날 때 지운다) · 모르는 인자는 건너뛴다 |
| `PreviewScreen` · `PreviewSession` · `RenderContext` · `PreviewHostError` | 프로젝트 | 프로젝트가 화면을 꽂는 자리 — 화면 하나의 `hello` 칸 · 상태로 서는 살아 있는 값(`render` 의 값 받기 `load(style:layers:fixture:)` — 같은 값이면 그대로 · 칸 바꾸기 · 틀까지 합친 뷰 · 요소 경계 · 요소 목록 · 층 보고 `layerReports` · 그리기 전 준비 `prepare(_:)` — 비동기 · 그 장의 틀(`RenderContext` — 크기 · 테마 · 창 없는 렌더인가)을 받아 그 틀로 그린 그림이 기다리는 원천(모델 그림 · 파일 읽기)이 끝날 때 돌아온다 · 외양마다 다른 그림은 그 외양의 것을 데운다(캐시는 이름과 외양으로) · 실패한 원천은 대체 그림으로 두고 던지지 않는다 · 기본 구현은 곧장 · 호스트는 장을 그리기 전마다(`render` · `patch` · 토큰 바뀜 · `shot` · 자기 창) 기다리고 그 사이 온 메시지는 차례대로 뒤에 선다(patch 는 합쳐진다) — 창 없는 장도 첫 장부터 그 값의 그림 · 시간으로 기다리지 않는다(원천의 끝이 신호) · 호스트의 시한(20 초 — 엔진이 장을 기다리는 시한 안)을 넘기거나 세션이 닫히면 호스트가 준비를 취소하고(협력 취소) 그때의 값으로 그리거나(시한 — 그 장이 끝난 장이다: 원천이 나중에 차도 다시 그리라는 신호가 없다) 그리지 않는다(닫힘 — 남은 우편도 버린다) · 채택자가 지킬 것: 원천은 취소를 보고 놓는다(무시하면 그 준비가 다음 장의 준비와 겹쳐 불릴 수 있다 — 진행 중인 일을 나눠 기다린다) · `context.offscreen` 은 그 요청이 내는 장 기준(`render` 는 자기 창이 있어도 창 없는 장의 틀 · `window` 만 창의 틀)이라 캐시 열쇠로 쓰지 않는다 · 와이어는 그대로(프로토콜 판을 올리지 않는다)) · 한 장의 바깥 조건(크기 · 테마 · 층 · 창 없는 렌더 · 층만 · 앱 손 · 스크롤 흉내 · 요소 탭 통로) |
| `FrameRenderer` | 프로젝트 | 창 없는 렌더 — `ImageRenderer.cgImage` 의 바이트 그대로(꼴이 다르면 바꿔 쓰지 않고 거절) · 렌더러 다시 쓰기(같은 render 와 그 위의 patch 사이에서만 — 다른 render 는 새 렌더러: 다시 쓴 렌더러는 앞 장의 뷰 그래프를 들고 있다) · 프로젝트의 호스트 시험이 같은 렌더러로 그린 장을 잰다. 그림을 파일로 쓰는 손(호스트의 `shot`)은 SDK 안의 손이다 · **그린 글줄 · 요소 바탕 읽기**(`render.drawn` 을 청한 장 — 같은 렌더러로 그 장을 PDF 한 쪽에 한 번 더 그려(`ImageRenderer.render`) 내용 흐름을 공개 손(`CGPDFScanner`)으로 걷고 글의 문자열은 `PDFKit` 이 푼 글자로 · 소속 요소 · 바탕은 그 장의 요소 경계로 가린다 · 못 잡는 것: 래스터로만 그리는 것(이미지 안의 글 · AppKit 을 감싼 뷰) · 단색이 아닌 글의 색 · 테두리만 그린 바탕)도 SDK 안의 손이다 |
| `HostCommit` | 엔진 | 다음 커밋 뒤 한 번(`beforeWaiting` 관찰자 — 호스트 자기 창의 「창에 반영 끝」 · 엔진의 기준선 창도 같은 눈금을 쓴다). 자기 창(Xcode Previews 방식 — 활성화하지 않는 key 패널 · 엔진 창 번호 위 보통 층 · 보이는 부분만 덮기)은 SDK 안의 손이다 |
| `FrameSink` · `View.collectFrames(into:)` | 프로젝트 | 프레임 수집 — `.snapID` 앵커를 뿌리에서 모아 `SnapFrame` 으로(`ImageRenderer` 안에서도 돈다 · 위 → 왼쪽 → id 차례) |
| `HostTrace` | 프로젝트 | 호스트의 기동 · 첫 프레임 구간 추적(`PREVIEW_TRACE=1` 일 때만 표준 오류 · `PreviewClock` ms) — 창 열기 실측 `LaunchTrace.OpenTrace` 와 쓰임이 다르다(이것은 미리보기 호스트 프로세스의 표지) |

**`TestScratch`** — 시험의 임시 자리 한 벌(시험 갈래 · 시험 타깃만). Foundation 만.

| 이름 | 약속 | 무엇 |
|---|---|---|
| `TestScratch` · `TestScratch.Defaults` | 프로젝트 | 임시 폴더(`folder` — 만든다) · 임시 자리(`location` — 만들지 않는다 · `ext` · `isDirectory`) · 지우기(`remove`) · 빌려 쓰기(`withFolder`) · 설정 도메인(`defaults` — suite 이름 = 임시 폴더 안 plist 의 절대 경로라 `~/Library/Preferences` 에 쓰지 않는다 · `remove()` 가 폴더째 지운다 · `withDefaults`). 이름은 늘 `test-scratch-<이름>-<UUID>` · 뿌리는 환경 `TEST_SCRATCH_ROOT` ⟂ `temporaryDirectory` — 게이트가 범위 폴더를 주고 시험 묶음 뒤 남은 `test-scratch-*` 를 센다(빌더의 시험 찌꺼기 게이트). 엔진 · 프로젝트의 시험 소스는 임시 자리를 이 손으로만 만든다 — 시험 하나가 끝날 때 걷는 손은 시험 틀마다 하나다(XCTest · Swift Testing 마다 엔진 · 프로젝트 쪽에 둔다) |

### 종류를 얼린 이름

앱 제품이 범위를 좁혀 다시 내는 이름(§1 — `import struct ProjectFormat.ScreenComponent` 꼴)은 **선언 종류까지** 약속이다 — 종류가 바뀌면(struct → enum) 그 범위 import 가 깨진다. 게이트 `qa-sdk-build` ⑧ 이 이 표와 소스를 맞댄다. 모듈째 다시 내는 `ScreenMarks` · 트레이트 `ActiveMarks` · define `ACTIVE_MARKS` 도 이름째 약속이다.

| 이름 | 종류 | 다시 내는 꼴 |
|---|---|---|
| `ScreenComponent` | struct | 화면 데이터 제품의 범위 import |
| `IAWiring` | enum | IA 제품의 범위 import |
| `HexColor` | struct | 토큰 제품의 범위 import(생성물이 쓴다) |
| `ThemeInfo` | struct | 토큰 제품의 범위 import |
| `ColorEntry` | struct | 토큰 제품의 범위 import |
| `FormFactor` | struct | IA 제품의 타입 별칭(열린 꼴 — 상수 · `known` 으로 쓴다) |

## 3. SDK 에 드는 기준

타입 · 상수 하나가 SDK 에 드는 것은 다섯이 **모두** 설 때다 — 하나라도 안 서면 들지 않는다(§4).

1. **양쪽이 문다** — 엔진과 프로젝트가 같은 이름을 쓴다 · 또는 두 벌로 서면 안 되는 형식 상수 · 규약이다(시험 갈래는 양쪽의 **시험**이 문다).
2. **플랫폼 중립 — 아니면 함께 무는 런타임** — 계약은 Foundation · CryptoKit · CoreGraphics · SwiftUI 만으로 iOS · macOS 둘 다 컴파일된다.
   플랫폼 프레임워크(AppKit · ImageIO …)가 필요한 것은 **미리보기 호스트(프로젝트의 실행물)와 엔진이 함께 무는 런타임**일 때만 런타임 갈래로 든다(§1 — macOS 전용 · 앱 제품의 의존 닫힘 밖 · 소스는 통째로 `#if os(macOS)`).
   UIKit · RealityKit 이 필요하거나 한쪽만 무는 런타임은 SDK 가 아니다. Swift 에서 부를 수 없는 시스템 호출(가변 인자 C 함수)은 런타임 모듈만 무는 C 심(고정 인자로 감싼 한 줄 · 제품 아님)으로 든다.
3. **잎에 머문다** — 프로젝트 모듈 · 엔진 모듈을 `import` 하지 않는다.
4. **자리를 가정하지 않는다** — 저장소 뿌리 · git · 다른 저장소의 자리 · 자식 프로세스 · 특정 프로젝트의 파일 자리가 없다.
5. **프로젝트의 값이 아니다** — 프로젝트가 정하는 값(화면 이름 목록 · 토큰 · 크롬 낱말)은 프로젝트에 남고, SDK 는 그 값을 담는 꼴만 갖는다.

플랫폼 바닥은 **가장 낮은 소비자**다(지금 macOS 14 · iOS 17 — 프로젝트의 코어 패키지) — 앱(iOS 18 · macOS 15)과 엔진(macOS 15)은 그 위에서 그대로 문다.

## 4. SDK 에 들지 않는 것

| 무엇 | 자리 | 까닭(§3 의 몇 번) |
|---|---|---|
| 렌더 코어(씬 · 카메라 · 입력 · 오프스크린 그림) · 리뷰 킷(의견 기록 · 저장 · 작성기) | **빌더**(비공개 배포 패키지 — 프로젝트가 빌더에서 받아 앱에 싣는 런타임) | ② 렌더 코어는 RealityKit · UIKit(터치) · AppKit(포인터)을 쓴다 — 계약이 아니라 앱이 싣는 **엔진 런타임**이다. 리뷰 킷은 다섯이 다 서지만 렌더 코어 · 편집기와 한 배포 패키지로 함께 간다 |
| 씬(`.isoscene`) · 모델(`.isomodel`) · 배선(`graph.json`)의 형식 판 상수 | 그 형식을 디코드하는 쪽 — 렌더 코어(씬 · 모델) · 엔진의 도구(배선) | ① 판 상수는 그 형식을 읽는 모듈과 함께 산다 — SDK 는 이 형식을 디코드하지 않는다(그 칸 하나가 SDK 판을 올리지 않게). 판 범위의 꼴(`FormatVersions`)과 사슬의 꼴(`UpgradeChain`)은 SDK 에 있어 그쪽도 같은 꼴로 낸다 |
| 엔진의 도구 몸 — IA · 배선 · 안 문서의 저장소 · 코덱 · 자동 배치 · 쓰임 셈 · 미리보기 클라이언트 · 호스트 프로세스 · 호스트 빌드 손 · 원격 화면 창 · 화면 위 오버레이 · 계측 하니스 · 매니페스트(`muc.json`) · 토큰 정본 편집기 · 그림 파일 쓰기(PNG) · 조절판 칸 이름 짓기와 낱말 사전 · 형 · 상태 · 구성요소 종류의 사람 말 이름 | 엔진(빌더) | ① 엔진의 도구가 여닫는 손이다(앱은 읽지 않는다) · ④ 자식 프로세스(호스트 · 빌드 · 생성기)를 띄운다 · UI 낱말은 엔진의 UI 다(공개 계약은 중립 — §6) — 문서 · 메시지의 **꼴**(`IADoc` · `DesignFile` · `PreviewProtocol` · `ScreenMarks` · `SnapFrame` · `FrameSink`) · 매니페스트에 싣는 공유 데이터 칸의 꼴(`SharedDataModel`)과 전송(`PreviewWire`)만 SDK 에 든다 |
| 저장 백엔드의 생성물 — SQL 투영 · 차이 · 마이그레이션 · 소유 열 · 접근 정책 | SDK 밖(쓰는 쪽) | ⑤ 백엔드(스토어 · 서버)의 가정이다 — 모델 파일 형식은 백엔드를 모른다. 판 4 의 생성 사본 칸(`migrated` · 엔티티와 필드의 `sql`)은 물러난 키로 읽은 그대로 들고 되쓴다(§2 `IsoDataFile`) |
| 프로젝트의 값 — 화면 Style 타입 · IA 상수의 꼴(생성물) · 시드의 결정적 id 규칙 · 토큰의 값(생성물 · 실행 시점 등록부) · 앱 제품의 플랫폼 색 손(UIKit ⟂ AppKit 경로) · 제품의 계측 훅 | 프로젝트 | ⑤ 값이 프로젝트의 화면 목록 · 생성물 · 규칙이다 · ② 플랫폼 색 손은 UIKit · AppKit 을 쓴다 — SDK 는 그 값을 담는 꼴(`DesignTokens` · `PreviewProtocol.StyleSchema`)만 갖는다. 엔진은 Style 을 사전으로만 다루고 그 잣대는 프로젝트가 내는 서술이다 |

## 5. 판

**SDK 판: 1.5.0** — 계약 동결(아래 「1.0 의 약속」 — 공개 표면을 깨는 변경은 주 판에서만). 코드의 한 자리는 `ProjectFormat.SDKVersion.current` 이고 이 칸과 같은 글자다
(SDK 시험 `SDKDocumentTests` 가 이 문서를 패키지 안 자리로 읽어 맞댄다 — 한쪽만 고치면 빨강). **저장소의 판 꼬리표가 이 값이다** — 게이트 `qa-sdk-build` 가 HEAD 의 꼬리표(있으면)와 맞댄다 ·
한 번 찍은 꼬리표는 다시 찍지 않는다(소비자의 `Package.resolved` 가 그 revision 을 쥔다) — 고치면 판을 올린다.

**프로토콜 판: 6** — 미리보기 호스트 ⟂ 엔진의 말(`PreviewProtocolVersion.current` — 코드의 한 자리 · 이 칸과 같은 글자를 SDK 시험 `ProtocolDocumentTests` 가 맞댄다). SDK 판과 따로 센다.
SDK 1.3 으로 핀을 올린 프로젝트의 미리보기 호스트는 프로토콜 판 5 로 말한다(**자리를 하나도 선언하지 않아도 판 5** — 호스트는 늘 제 판으로 hello 를 보낸다 · 문구의 판 4 와 같은 결정) — 빌더(엔진)도 SDK 1.3 이상이어야 한다(옛 빌더는 「빌더를 업데이트하세요」로 거절한다 · SDK 1.1 · 1.2 의 호스트는 판 4).
SDK 1.4 는 프로토콜 판을 올리지 않는다 — 더한 것은 호스트 런타임의 손 하나(`PreviewSession.prepare(_:)` · 기본 구현은 곧장)라 와이어가 그대로다: 1.4 호스트 ⟂ 1.3 엔진 · 1.3 호스트 ⟂ 1.4 엔진이 다 선다(1.3 호스트는 예전처럼 그린다 — 비동기 원천의 첫 창 없는 장이 빈 자리일 수 있다) · 내림 길이 필요 없다.
SDK 1.5 로 핀을 올린 프로젝트의 미리보기 호스트는 프로토콜 판 6 으로 말한다(`render.drawn` · 프레임 머리의 `texts` · `styles` — 청하지 않으면 칸이 없다) — 빌더(엔진)도 SDK 1.5 이상이어야 한다(옛 빌더는 「빌더를 업데이트하세요」로 거절한다 · 판 6 엔진은 1.3 · 1.4 의 판 5 호스트를 판 5 의 말로 받는다 — 청함을 걷어 말하고 그 호스트의 머리는 글줄 없음 = nil). 화면 코드 · 표식은 그대로다(앱에 다는 것 0).
엔진과 호스트는 서로 다른 SDK 로 빌드될 수 있다 — 다른 Mac 의 빌더는 배포본(늦다)이고, 그 Mac 의 미리보기 호스트는 그 Mac 이 받은 프로젝트의 SDK 로 짓는다(앞선다).

- **메시지 꼴(종류 · 칸 키 · 칸의 뜻)이 바뀌면 판을 올린다 — 선택 칸을 더하는 것도.** 엔진이 호스트에 청하는 칸을 옛 호스트가 모른 채 무시하면 그림이 조용히 틀리므로 판 없이 더하지 않는다 · 올림의 비용은 스텝 하나다(아래). 꼴의 지문(메시지 종류 · 칸 키 경로와 값의 꼴 · 선택 칸 · 낱말)은 `Tests/PreviewProtocolTests/protocol-shapes.txt` 가 판마다 한 줄로 든다(덧붙이기 전용) — 꼴이 바뀌었는데 판이 그대로면 `PreviewProtocolShapeTests` 가 「판을 올리고 지문 한 줄을 더하라」로 빨강이다. 키는 그대로 두고 뜻만 바꾼 것은 지문이 못 보므로 바꾸는 쪽이 판을 올린다.
- **판을 올리는 변경은 한 판 사이의 스텝 하나를 더한다**(`ProtocolDialect.Step` — 그 판의 줄을 다음 판의 꼴로 올리는 손 · 내리는 손 · 내리는 손이 nil 이면 그 판에 없는 메시지라 보내지 않는다) — 옛 판마다의 말은 스텝을 이어 짓는다(`ProtocolDialect.chain`). **엔진은 바닥 판(`PreviewProtocolVersion.oldest` — 지금 2)부터 지금 판까지 전부 받는다**(`previous` = 바닥 … 지금 판 바로 아래 — 판마다 말이 하나씩 없으면 빨강).
- **엔진이 판정자다**(`ProtocolJudge`) — 호스트 hello 의 판에 맞는 말이 있으면 그 말로 받고, 호스트가 새 판이면 「미리보기 호스트가 이 빌더보다 새 판입니다 — 빌더를 업데이트하세요」 · 바닥보다 옛 판이면 「… 옛 판입니다 — 프로젝트를 pull 하고 다시 여세요」를 창에 보이고 연결을 닫는다. 호스트는 엔진보다 새것을 거절하지 않는다(새 엔진이 호스트의 판으로 말한다) — 엔진 hello 의 판이 제 판보다 옛것일 때만 같은 사람 말을 오류로 보내고 끊는다. 그래서 **적합한 상대에게서 모르는 메시지 종류는 오지 않는다** — 엔진은 호스트의 판으로 말하고(그 판에 없는 메시지는 내리는 손이 지운다) 호스트가 더 새 판이면 판정에서 끊는다(메시지 열거에 「모르는 종류」 갈래가 없는 까닭).
- **연결 = 세션.** 호스트 프로세스는 같은 소켓 자리로 연결을 여럿 받을 수 있다(세션마다 hello · seq · 공유 메모리 · 창이 따로 — 연결이 식별자라 메시지에 세션 칸이 없다). 엔진은 같은 자리에 다시 붙을 수 있고, 거절(`ENOENT` · `ECONNREFUSED`)이면 새 호스트를 띄운다. 첫 연결 뒤 듣기를 닫는 호스트도 적합하다.
- **자료 안의 꼴은 그 형식의 판이 가른다** — 프로젝트가 뜻을 정하는 JSON 칸(층 자료 · 층 보고)은 지문이 `json` 한 낱말로만 본다. 그 안에 실리는 SDK 꼴은 제 판을 싣는다(IA 문서 `IADoc.version` · 콜아웃 값 `CalloutValues.version` — 칸 `v`).
- **판은 공개 손의 기본 인자로 두지 않는다**(`Hello.protocolVersion` · `ProtocolJudge.hostAccepts(host:)` 는 필수 · 판 없는 손은 오버로드 — `Framing.header(_:)` ⟂ `header(_:dialect:)` · `Connection.init(fd:)` ⟂ `init(fd:dialect:)` · `IADoc.init(nodes:jumps:hubs:)` ⟂ `init(version:…)` · `LifeFile.init(body:)` ⟂ `init(body:version:)`) — 기본 인자는 부르는 쪽 목적 코드에 들어가고 그 소스엔 판의 이름이 없어 증분 빌드가 판의 변경을 놓친다(한 실행물에 두 판). 판 없는 손의 몸은 SDK 안이라 판은 SDK 목적 코드에 남는다. 게이트 `qa-sdk-build` ⑨ 가 잰다.
- hello 의 `type` · `protocolVersion` 두 칸은 판이 올라도 이름 · 자리(줄의 맨 위 객체 · 정수)가 그대로다 — 판정이 몸을 풀기 전에 이 둘만 읽는다.

**형식이 자라는 규칙** — SDK 가 읽고 쓰는 **파일**(모델 파일 · 안 파일 · IA 문서)과 매니페스트의 공유 데이터 칸. **와이어**(미리보기 메시지 — hello 의 프로젝트 데이터 · 층 자료 · 층 보고 포함)는 위의 판 규칙이 이긴다:
와이어에 칸을 더하는 것은 프로토콜 판을 올린다(선택 칸도) · 와이어 꼴의 `extra` 는 **읽기 방어**다(판을 올리지 않고 칸을 더해도 된다는 뜻이 아니다 — 판정을 거친 상대가 보낸
뜻밖의 칸 · 자료 안 꼴의 제 판(`CalloutValues.version`)이 가르는 칸을 잃지 않고 들 뿐이다).

- **모르는 키는 보존한다** — 꼴마다 `extra`(이 SDK 가 모르는 칸 — 읽은 그대로 들고 되쓴다 · 아는 칸과 이름이 겹치면 아는 칸이 이긴다). 같은 판에 칸이 더해져도 옛 읽개가 열어 저장하면 그 칸이 사라지지 않는다. 모델 파일은 자리마다 한 줄로 알린다(`DataModelFile.unknownKeys` — 읽는 쪽이 읽기 전용으로 열지 정한다).
- **파일에 칸을 더하는 것은 형식 판을 올리지 않는다**(빠진 칸 = 옛 뜻 · 모르는 칸 = 보존) — 칸의 뜻을 바꾸거나 빼는 것만 판을 올린다(와이어는 위의 판 규칙). 모델 파일 판 4 는 칸 더하기(`idNamespace` · `revision`)와 물러난 키(`migrated` · `sql`)를 판 안에서 든다.
- **열린 꼴**(`FormFactor` · `ScaleKind` · `DataStatus` · `DataOnDelete` · `CompositionField.Kind` · `SharedMemoryInfo.Kind` · `Hub.Kind` · `ScreenEntry.Kind`) — 낱말 그대로 드는 `RawRepresentable` 구조체 + 아는 상수 + `known`. 아는 낱말을 더하는 것은 부 판이다(파일 · 와이어의 글자가 그대로라 소비자 소스가 깨지지 않는다 — 소비자는 이 꼴을 `switch` 로 전수하지 않는다 · `default` 를 둔다).
- **페이로드 열거의 모르는 갈래**(`DataType.unknown` · `DataRuleCheck.other`) — 이 SDK 가 모르는 형 · 규칙을 읽은 그대로 든다(재지 않는다 · 경고). 닫힌 열거(`Message` · `Hello.Role` · `UpgradeEffect` · `FramePayload` · `ScreenComponent.Kind` · `FieldKind`)에 갈래를 더하거나 갈래의 연관값을 바꾸는 것은 주 판이다 — 소비자의 전수 `switch` 를 깬다(`ScreenComponent.Kind` 는 앱이 그리는 코드와 함께 오는 종류라 닫아 둔다 · 모르는 종류는 관대한 읽기가 건너뛴다). 1.x 에서 새 말이 필요하면 닫힌 열거를 늘리지 않고 있는 갈래의 몸(구조체)에 기본값 있는 새 칸을 더한다 — 옛 상대가 그 칸을 몰라 무시해도 뜻이 틀리지 않을 때만이고, 아니면 새 갈래는 다음 주 판(2.0)에 싣는다(예 — 문구는 `FieldKind` 의 갈래가 아니라 Style 서술의 기본값 있는 목록 `StyleSchema.texts` 다: 서술에 문구가 없는 호스트는 빈 목록과 같고 화면은 기본 글로 선다 · 와이어의 옛 엔진은 프로토콜 판이 막는다 · 이미지 자리 `StyleSchema.slots` 도 같은 길이다).
- **공개 오류 열거도 닫힌 열거다**(`IsoDataError` · `ProtocolMismatch` · `UpgradeError` · `StyleSchemaError` · …) — 갈래를 더하면 소비자의 전수 `switch` 가 깨진다(주 판 · 게이트 `qa-sdk-build` ⑦ 이 깨짐으로 센다). 1.x 에서 새 오류는 **새 오류 타입**으로 더한다(부 판 — 예: 문구가 서지 않는 까닭은 `StyleSchemaError` 의 갈래가 아니라 새 타입 `StyleTextError` · 자리는 `StyleSlotError`). 오류 · 문제의 사람 말(`description` · `reason`)은 계약 밖이다(문구를 고치는 것은 수 판).

SDK 판이 오르는 때:

| 바뀌는 것 | SDK 판 |
|---|---|
| 공개 표면을 깬다 — 공개 이름 · 제품 · 트레이트를 빼거나 · 이름 · 꼴 · 뜻 · 선언 종류를 바꾼다 · 닫힌 열거(공개 오류 열거 포함)에 갈래를 더하거나 연관값을 바꾼다 · 기본 구현 없는 프로토콜 요구를 더한다 | 주(2.0 — 1.x 안에서는 내지 않는다) |
| 덧붙인다 — 새 타입 · 새 메서드 · 기본값 있는 새 칸 · 열린 꼴에 아는 낱말 · 새 오류 타입 · 형식 판 상수를 올린다 · 프로토콜 판을 올린다(위 — 기본값 있는 새 칸처럼 모르는 상대가 무시해도 뜻이 틀리지 않는 덧붙임만 · 메시지 종류를 더하는 것은 닫힌 열거의 갈래라 주 판) | 부 |
| 공개 표면이 그대로인 고침 · 사람 말 문구 | 수 |

**1.0 의 약속** — 「프로젝트가 문 1.0 의 공개 표면(§2 의 표 · 프로젝트 ⟂ 엔진 두 약속 모두)을 이후의 1.x SDK 가 계속 지킨다」: 소스 호환(공개 이름 · 꼴 · 선언 종류 · 제품 · 트레이트 — 기준선은 HEAD 에서 닿는 가장 가까운 꼬리표(지금 판의 꼬리표 포함 · HEAD 가 지금 판 꼬리표 그 자체면 그 앞 꼬리표) · 1.x 의 꼬리표 사슬은 1.0.0 에서 시작하므로 1.0.0 표면이 바닥이다 · 게이트 `qa-sdk-build` ⑦ 이 기준선과 맞대 깨짐 하나면 빨강 · 주 판을 올리는 변경만 `qa/api-major.txt` 에 그 판 글자와 까닭을 적어 통과) · 파일 호환(1.x 의 읽개는 1.0 이 쓴 파일을 읽고 모르는 칸을 보존한다) · 와이어 호환(1.x 엔진은 바닥 판부터 받는다). 약속 밖 — SDK 안의 손(`package`) · 사람 말 문구 · SDK 가 디코드하지 않는 형식(§4).

## 6. 변경 규칙

- **공개 표면 = §2 의 표**다 — `public` 은 표에 있는 이름만 연다(게이트 `qa-sdk-build` ⑧ 이 소스의 맨 위 공개 타입과 표의 이름을 양방향으로 맞댄다 · 범위 import 로 다시 내는 이름은 선언 종류까지 「종류를 얼린 이름」 표와 맞댄다). 이 저장소는 공개라 **`public` 한 줄이 곧 외부 약속**이다 — 이름을 더하면 표에 한 줄 · 시험 하나를 함께 더하고 §5 의 판을 올린다. SDK 안 모듈끼리만 쓰는 손은 `package` 다(표에 없다 · 약속 밖).
- **새 프로토콜 요구는 기본 구현과 함께** 더한다 — 기본 구현 없는 요구는 그 프로토콜을 따르는 소비자를 깬다(게이트 ⑦ 이 깨짐으로 센다).
- **상수 · 규약은 한 자리**다 — SDK 에 든 값을 소비자가 다시 적지 않는다(읽는다). 소비자에 남는 것은 그 값의 뜻(판마다 무엇을 담는가)뿐이다.
- **코드 식별자에 제품 이름을 쓰지 않는다** — 모듈 · 타입 · 트레이트 · define 은 중립 이름이다. 패키지 이름 = 저장소 이름 `muc-sdk`(정체성 — 소비자의 `package:` 글자). **공개 계약은 사람 말 UI 를 들지 않는다** — 형 · 상태 · 구성요소 종류의 이름 · 조절판 칸 이름의 규칙 · 낱말 사전은 그것을 보이는 엔진의 것이다(오류 문구는 남되 계약 밖 — §5).
- **공개 적합** — 텍스트 파일 전부(소스 · 시험 · 픽스처 · 문서 · 매니페스트 · 게이트 — 확장자를 가리지 않는다)에 홈 · 볼륨 절대경로(OS 표준 자리 `Library` 아래는 뺀다)와 이 저장소 뿌리 밖을 가리키는 상대 경로가 없다. 게이트 `qa-sdk-build` ④ 가 경성 0 으로 잰다. 시험 재료 · 예시는 합성 값과 중립 이름으로 쓴다 — 특정 사람 · 조직 · 제품의 글자를 싣지 않는다. 날짜 · 수 · 라벨은 실재하는 데이터에서 옮기지 않고 **누가 봐도 합성인 값**(둥근 해 · 규칙적 간격 — 표본의 날짜는 생년까지 2040 년 뒤의 10년 격자 · 색은 `#102030` 꼴의 규칙적 값)으로 짓는다. 이름 · 모양(엔티티 · 열거 값 · 규칙 · 데이터셋 · 색 역할 · Style 칸)도 실재하는 프로젝트의 것을 옷만 바꿔 옮기지 않는다 — 형식의 꼴을 덮는 중립 모델(정원 낱말)로 짓는다. **모델 파일 표본(`Tests/ProjectFormatTests/Fixtures/sample-model.isodata`)은 규칙으로 짓는다** — 원천은 [`qa/sample-model.mjs`](../qa/sample-model.mjs) 하나(덮는 꼴 · 날짜 격자 · 레코드 UUID 규약으로 낸 id) · 러너가 표본 = 지은 바이트를 잰다 · 손으로 고치지 않는다. 주석은 까닭을 지금형으로 적는다 — 내부 작업의 표지(작업 번호 · 실측한 날짜 · 그날의 셈)를 싣지 않는다.
- **SDK 를 무는 줄은 소비자 패키지마다 한 줄**이다(판을 못 박은 의존) — 소비자의 다른 자리는 SDK 의 자리를 모른다.
- **새 모듈은 갈래(계약 ⟂ 런타임 ⟂ 시험)를 정해 들인다** — §1 의 표 · 게이트의 갈래 목록에 한 줄씩. 런타임 모듈의 Swift 소스는 통째로 `#if os(macOS)` 안이고, 런타임이 새 플랫폼 프레임워크를 물면 게이트의 허용 목록에 한 줄과 까닭을 함께 적는다.
- 옮기는 쪽이 SDK 에 넣는 것은 §3 의 다섯이 설 때뿐이다 — 안 서는 것을 넣으려면 기준을 먼저 바꾸고(이 문서) 게이트가 그것을 잰다.
