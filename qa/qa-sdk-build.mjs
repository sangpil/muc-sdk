// qa-sdk-build.mjs — SDK(이 패키지 · 공개 저장소 `muc-sdk`)의 빌드 · 시험 · 경계 · 공개 적합 · 판 꼬리표 게이트. 이 저장소 안의 것만 읽는다(다른 저장소의 자리 0).
//
//   ① **혼자 선다** — `swift build` · `swift test` · 시험 대상(`Tests/*`)마다 0건이 아니다(0건 통과는 통과가 아니다 · Swift Testing 요약은 대상마다 한 줄).
//   ② **잎** — `swift package show-dependencies` 의 의존 0 · 매니페스트 의존 0 · 모든 타깃에 `unsafeFlags` 0(태그 의존으로 받는 패키지라 SwiftPM 이 거부한다).
//   ③ **갈래**(계약 ⟂ 런타임 ⟂ 시험 — 아래 `CONTRACT` · `RUNTIME` · `TEST` · 새 모듈은 한쪽에 적어야 선다 · 정본 `Docs/SDK.md` §1):
//      ⓐ 계약 소스의 `import` = Foundation · CryptoKit · CoreGraphics · SwiftUI · 계약 모듈 · 계약이 런타임 모듈을 물지 않는다
//      ⓑ 런타임 소스 = + 플랫폼 프레임워크(`PLATFORM`) · 런타임 모듈 · 소스는 통째로 `#if os(macOS)`(첫 줄 · 끝 줄)
//      ⓒ 시험 갈래 소스 = Foundation · 시험 아닌 타깃이 시험 갈래를 물지 않는다
//      ⓓ 소스에 자식 프로세스 · 저장소 자리 가정(`Process(` · `posix_spawn` · 제 자리 위로 오르는 상대 경로 리터럴 `"../…"` · `.git` · `#filePath`) 0
//   ④ **공개 적합(경성 0)** — 텍스트 파일 전부(확장자를 가리지 않는다 — NUL 바이트가 없으면 글 · 데이터 · 픽스처 · 확장자 없는 파일 포함)에
//      홈 · 볼륨 절대경로(사용자 홈 · 리눅스 홈 · 마운트한 볼륨 아래 · 물결표 홈 — OS 표준 자리 `Library` 아래는 뺀다 · `HOME`) 0 · 다른 저장소의 자리(그 파일에서 풀면 이 저장소 뿌리 밖으로 나가는 상대 경로 — `UP`) 0.
//      일반 검사만 든다 — 특정 이름의 목록은 공개 바이트에 실으면 그 목록이 곧 누출이라 이 저장소에 두지 않는다(소비자 쪽 게이트의 몫).
//   ⑤ **판 꼬리표** — `SDKVersion.current`(코드의 한 자리) = HEAD 에 꼬리표가 있으면 그 꼬리표 · README 의 설치 줄(`exact: "<판>"`) = 같은 판.
//      `Docs/SDK.md` §5 의 판 칸은 시험(`SDKDocumentTests`)이 잰다.
//   ⑥ **시험이 남긴 자리 0** — 자식에 범위 폴더(`TMPDIR` · `TEST_SCRATCH_ROOT`)를 주고 시험 뒤 범위 안 `test-scratch-*` · 새 `~/Library/Preferences/test-scratch-*.plist` 가 있으면 빨강.
//   ⑦ **공개 표면 깨짐 진단** — `swift package diagnose-api-breaking-changes <직전 꼬리표>`(기준 = HEAD 에서 닿는 가장 가까운 꼬리표 · 지금 판의 꼬리표는 뺀다).
//      보조 점검 — 소스의 public 선언 목록(멤버 포함 · `<둘레>.<종류> <이름>(<레이블>)`)을 직전 꼬리표의 것과 맞대 사라진 선언을 센다(도구가 못 보는 `public → package` 강등).
//      1.0 전(SDK 판 0.x)은 둘 다 수를 적기만 한다 · 1.0 뒤는 하나라도 있으면 빨강 — 주 판을 올리는 변경이면 `qa/api-major.txt` 에 **지금 판 글자**와 까닭 한 줄이
//      있을 때만 통과(판이 바뀌면 지난 선언은 무효 — 판 글자가 없는 선언 파일은 빨강).
//      기본 구현 없는 프로토콜 요구를 더한 것도 이 도구가 깨짐으로 센다. git 밖 · 기준 꼬리표 없음이면 건너뛴다(그 까닭을 적는다). `SDK_API_LIST=1` 이면 깨짐을 줄마다 찍는다.
//   ⑧ **공개 이름 = §2 표** — `Sources/**` 의 맨 위 `public` 타입 이름(struct · enum · class · protocol · typealias · actor) 집합 = `Docs/SDK.md` §2 표 첫 칸의 백틱 이름
//      (점 · 괄호 없는 이름) 집합(차집합 0 양방향) · 「종류를 얼린 이름」 표의 이름마다 선언 종류가 표와 같다(소비자의 범위 import 가 기댄다).
//   ⑨ **판 품은 기본 인자 0** — `public` 함수 · init 의 기본 인자 값에 `.current` · `currentVersion` · `Format.` · `Version` 글자가 없다(판은 이름으로 적는다 —
//      기본 인자는 부르는 쪽 목적 코드에 묻혀 증분 빌드가 판의 변경을 놓친다 · 판 없는 손은 오버로드로).
//
// 인자 없음 · macOS + Swift 툴체인 · git(⑤ 꼬리표 — 저장소가 아니면 「꼬리표 없음」) · 빌드 자리는 패키지의 `.build`.
// 사용: node qa/qa-sdk-build.mjs       SWIFT_BUILD_JOBS=6 node qa/qa-sdk-build.mjs

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { residueLine, residueScope, residueSelfTest } from "./lib/test-residue.mjs";

const QA = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(QA, "..");
const JOBS = process.env.SWIFT_BUILD_JOBS ? ["-j", process.env.SWIFT_BUILD_JOBS] : [];

// 갈래 — 정본 `Docs/SDK.md` §1
const CONTRACT = ["ProjectFormat", "ScreenMarks", "DesignTokens", "LaunchTrace", "PreviewProtocol"];
const RUNTIME = ["CShm", "PreviewWire", "PreviewHostKit"];
const TEST = ["TestScratch"];
const CONTRACT_IMPORTS = new Set(["Foundation", "CryptoKit", "CoreGraphics", "SwiftUI", "Testing", ...CONTRACT]);
const PLATFORM = ["Darwin", "AppKit", "Observation", "ImageIO", "UniformTypeIdentifiers"];
const RUNTIME_IMPORTS = new Set([...CONTRACT_IMPORTS, ...PLATFORM, ...RUNTIME]);
const TEST_IMPORTS = new Set(["Foundation"]);

// 공개 적합 — 홈 절대경로 · 뿌리 밖으로 오르는 상대 경로(그 파일의 폴더에서 푼다)
const HOME = /(?<![\w.-])\/(?:Users|home|Volumes)\/[^\s/"'`)]|(?<![\w.~-])~\/(?!Library\/)/;
const UP = /(?<![\w.])((?:\.\.\/)+)([^\s"'`)\]>]*)/g;

const fail = (msg) => { console.error(`✗ ${msg}`); console.log(`=== qa-sdk-build FAIL — ${msg.split("\n")[0]} ===`); process.exit(1); };
if (process.platform !== "darwin") fail("macOS 에서만 돈다(런타임 갈래 · SwiftUI)");
if (!existsSync(join(ROOT, "Package.swift"))) fail(`패키지 없음: ${ROOT}/Package.swift`);
const scope = residueScope("qa-sdk-build");
const run = (args) => {
  const t0 = Date.now();
  const r = spawnSync(args[0], args.slice(1), { cwd: ROOT, encoding: "utf8", maxBuffer: 64 << 20, env: scope.env });
  return { ok: r.status === 0, out: (r.stdout || "") + (r.stderr || ""), sec: Math.round((Date.now() - t0) / 1000) };
};
const explain = (out) => { for (const l of out.split("\n").filter((l) => /error:|failed/.test(l)).slice(0, 30)) console.error(`  ${l.trim()}`); };
const walk = (d, keep) => !existsSync(d) ? [] : readdirSync(d).flatMap((e) => {
  if (e === ".build" || e === ".swiftpm" || e === "node_modules" || e === ".git") return [];
  const f = join(d, e);
  return statSync(f).isDirectory() ? walk(f, keep) : keep(e) ? [f] : [];
});
const rel = (f) => relative(ROOT, f);
const failures = [];
console.log(`qa-sdk-build — ${ROOT}`);

// ① 혼자 선다 · 시험 대상마다
const b = run(["swift", "build", ...JOBS]);
if (!b.ok) { explain(b.out); fail(`swift build 실패 (${b.sec}s)`); }
const t = run(["swift", "test", ...JOBS]);
const runs = [...t.out.matchAll(/Test run with (\d+) tests? in \d+ suites? (passed|failed)/g)];
const xct = [...t.out.matchAll(/Executed (\d+) tests?, with (?:\d+ tests? skipped and )?(\d+) failures?/g)];
if (!t.ok || runs.some((m) => m[2] !== "passed") || xct.some((m) => Number(m[2]) > 0)) { explain(t.out); fail(`swift test 실패 (${t.sec}s)`); }
const dump = JSON.parse(run(["swift", "package", "dump-package"]).out.replace(/^[^{]*/, ""));
const testTargets = dump.targets.filter((x) => x.type === "test").map((x) => x.name);
const nonEmpty = runs.filter((m) => Number(m[1]) > 0).length;
const total = runs.reduce((n, m) => n + Number(m[1]), 0);
if (nonEmpty < testTargets.length) { explain(t.out); fail(`시험 대상 ${testTargets.length} 중 ${nonEmpty} 만 돌았다 — 대상마다 0건이면 빨강(${testTargets.join(" · ")})`); }
console.log(`  ✓ ① 혼자 선다 · swift test ${total}건 · 대상 ${testTargets.length}(${b.sec + t.sec}s)`);

// ② 잎 · unsafeFlags 0
const deps = JSON.parse(run(["swift", "package", "show-dependencies", "--format", "json"]).out.replace(/^[^{]*/, "")).dependencies;
if (deps.length || (dump.dependencies || []).length) failures.push(`② SDK 가 패키지를 문다(잎이어야 한다): ${deps.map((d) => d.identity).join(" · ")}`);
const unsafe = dump.targets.filter((x) => JSON.stringify(x.settings || []).includes("unsafeFlags")).map((x) => x.name);
if (unsafe.length) failures.push(`② unsafeFlags 가 든 타깃 — ${unsafe.join(" · ")}(태그 의존으로 받는 패키지는 SwiftPM 이 거부한다)`);
console.log(`  ${deps.length + unsafe.length ? "✗" : "✓"} ② 잎 — 의존 ${deps.length} · unsafeFlags ${unsafe.length}`);

// ③ 갈래
const modules = dump.targets.filter((x) => x.type !== "test").map((x) => x.name);
const loose = modules.filter((m) => ![...CONTRACT, ...RUNTIME, ...TEST].includes(m));
if (loose.length) failures.push(`③ 갈래가 적히지 않은 모듈 — ${loose.join(" · ")}(이 게이트의 CONTRACT · RUNTIME · TEST 와 Docs/SDK.md §1 에 한 줄)`);
const depsOf = (x) => (x.dependencies || []).map((d) => (d.byName || d.target || d.product || [])[0]).filter(Boolean);
const c2r = dump.targets.filter((x) => CONTRACT.includes(x.name)).flatMap((x) => depsOf(x).filter((d) => RUNTIME.includes(d)).map((d) => `${x.name} → ${d}`));
if (c2r.length) failures.push(`③ⓐ 계약 모듈이 런타임 모듈을 문다 — ${c2r.join(" · ")}`);
const testLeak = dump.targets.filter((x) => x.type !== "test" && !TEST.includes(x.name)).flatMap((x) => depsOf(x).filter((d) => TEST.includes(d)).map((d) => `${x.name} → ${d}`));
if (testLeak.length) failures.push(`③ⓒ 시험 아닌 타깃이 시험 갈래를 문다 — ${testLeak.join(" · ")}`);
const runtimeTests = new Set(dump.targets.filter((x) => x.type === "test" && depsOf(x).some((d) => RUNTIME.includes(d))).map((x) => x.name));
const side = (f) => {
  const m = /^(Sources|Tests)\/([^/]+)\//.exec(rel(f));
  if (!m) return "contract";
  if (m[1] === "Sources" && TEST.includes(m[2])) return "test";
  return (m[1] === "Sources" ? RUNTIME.includes(m[2]) : runtimeTests.has(m[2])) ? "runtime" : "contract";
};
const allowed = { contract: CONTRACT_IMPORTS, runtime: RUNTIME_IMPORTS, test: TEST_IMPORTS };
const badImports = [], assumptions = [], unguarded = [];
for (const f of walk(join(ROOT, "Sources"), (e) => e.endsWith(".swift")).concat(walk(join(ROOT, "Tests"), (e) => e.endsWith(".swift")))) {
  const text = readFileSync(f, "utf8"), s = side(f), inTests = rel(f).startsWith("Tests/");
  text.split("\n").forEach((line, i) => {
    const m = /^\s*(?:@testable\s+|@_exported\s+)?import\s+(?:(?:struct|class|enum|protocol|func|var|typealias)\s+)?([A-Za-z_]\w*)/.exec(line);
    if (m && !allowed[s].has(m[1]) && !(inTests && (TEST.includes(m[1]) || CONTRACT.includes(m[1]) || RUNTIME.includes(m[1])))) badImports.push(`${rel(f)}:${i + 1} [${s}] — ${line.trim()}`);
    if (!inTests) {
      const code = line.replace(/\/\/.*$/, "");
      if (/\bProcess\s*\(|\bNSTask\b|posix_spawn|"node"|"(?:\.\.\/)+|\.git\b|#filePath/.test(code)) assumptions.push(`${rel(f)}:${i + 1} — ${line.trim()}`);
    }
  });
  if (s === "runtime" && rel(f).startsWith("Sources/")) {
    const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
    if (lines[0] !== "#if os(macOS)" || lines[lines.length - 1] !== "#endif") unguarded.push(rel(f));
  }
}
if (badImports.length) failures.push(`③ 갈래의 허용 목록 밖 import:\n    ${badImports.join("\n    ")}`);
if (assumptions.length) failures.push(`③ⓓ 소스에 자식 프로세스 · 저장소 자리 가정:\n    ${assumptions.join("\n    ")}`);
if (unguarded.length) failures.push(`③ⓑ 런타임 소스가 통째로 \`#if os(macOS)\` 안이 아니다 — ${unguarded.join(" · ")}`);
console.log(`  ${loose.length + c2r.length + testLeak.length + badImports.length + assumptions.length + unguarded.length ? "✗" : "✓"} ③ 갈래 — 계약 ${modules.filter((m) => CONTRACT.includes(m)).length} · 런타임 ${modules.filter((m) => RUNTIME.includes(m)).length} · 시험 ${modules.filter((m) => TEST.includes(m)).length} · 허용 밖 import ${badImports.length} · 자리 가정 ${assumptions.length} · macOS 밖 런타임 ${unguarded.length}`);

// ④ 공개 적합 — 텍스트 파일 전부(NUL 없는 파일 · 확장자 무관 · 빌드 산출 · git 밖)
const hits = [];
let scanned = 0, binaries = 0;
for (const f of walk(ROOT, () => true)) {
  const buf = readFileSync(f);
  if (buf.includes(0)) { binaries += 1; continue; }
  scanned += 1;
  buf.toString("utf8").split("\n").forEach((line, i) => {
    const at = `${rel(f)}:${i + 1} — ${line.trim().slice(0, 140)}`;
    if (HOME.test(line)) { hits.push(`[홈 · 볼륨 절대경로] ${at}`); return; }
    for (const m of line.matchAll(UP)) {
      if (relative(ROOT, resolve(dirname(f), m[1] + m[2])).startsWith("..")) { hits.push(`[뿌리 밖 상대 경로] ${at}`); return; }
    }
  });
}
if (hits.length) failures.push(`④ 공개 적합 — 홈 · 볼륨 절대경로 · 이 저장소 뿌리 밖을 가리키는 상대 경로가 있다(경성 0):\n    ${hits.join("\n    ")}`);
console.log(`  ${hits.length ? "✗" : "✓"} ④ 공개 적합 — 텍스트 파일 ${scanned}(이진 ${binaries} 건너뜀) · 홈 경로 · 뿌리 밖 자리 ${hits.length}`);

// ⑤ 판 꼬리표
const version = (/public static let current = "([0-9]+\.[0-9]+\.[0-9]+)"/.exec(readFileSync(join(ROOT, "Sources/ProjectFormat/SDKVersion.swift"), "utf8")) || [])[1];
if (!version) failures.push("⑤ SDKVersion.current 를 못 읽었다(x.y.z)");
const readme = existsSync(join(ROOT, "README.md")) ? readFileSync(join(ROOT, "README.md"), "utf8") : "";
const pinned = [...readme.matchAll(/exact:\s*"([^"]+)"/g)].map((m) => m[1]);
if (!pinned.length || pinned.some((p) => p !== version)) failures.push(`⑤ README 의 설치 줄 판 [${pinned.join(" · ")}] ≠ SDKVersion.current ${version}`);
const top = spawnSync("git", ["-C", ROOT, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
let tagWord = "git 밖 — 꼬리표 없음";
if (top.status === 0) {
  const tags = (spawnSync("git", ["-C", ROOT, "tag", "--points-at", "HEAD"], { encoding: "utf8" }).stdout || "").split("\n").filter(Boolean);
  if (resolve(top.stdout.trim()) !== ROOT) tagWord = `다른 저장소 안의 폴더(${relative(top.stdout.trim(), ROOT)}) — 꼬리표는 SDK 저장소의 몫`;
  else if (tags.length && !tags.includes(version)) failures.push(`⑤ HEAD 의 꼬리표 [${tags.join(" · ")}] ≠ SDKVersion.current ${version}(꼬리표 = 판)`);
  else tagWord = tags.length ? `HEAD 꼬리표 ${version}` : "HEAD 꼬리표 없음";
}
console.log(`  ${failures.some((f) => f.startsWith("⑤")) ? "✗" : "✓"} ⑤ 판 — SDKVersion ${version} · README 설치 줄 ${pinned.join(" · ")} · ${tagWord}`);

// ⑥ 시험이 남긴 자리
const selfBad = residueSelfTest();
if (selfBad) failures.push(`⑥ ${selfBad}`);
const left = scope.check();
if (left.length) failures.push(`⑥ ${residueLine(left)}`);
console.log(`  ${selfBad || left.length ? "✗" : "✓"} ⑥ 시험이 남긴 자리 ${left.length}`);

// ⑦ 공개 표면 깨짐 진단 — 진단 도구 + 보조 점검(소스의 public 선언 목록 ⟂ 직전 꼬리표 — `public → package` 강등 · 빼기를 도구가 못 보는 자리)
const major = Number((version || "0").split(".")[0]);
// 주 판 선언 — `qa/api-major.txt` 에 지금 판 글자(SDKVersion)가 적혀 있을 때만 유효(판이 바뀌면 지난 선언은 무효)
const majorNote = existsSync(join(QA, "api-major.txt")) ? readFileSync(join(QA, "api-major.txt"), "utf8") : "";
const majorDeclared = !!version && majorNote.split(/\s+/).includes(version);
/// 소스 한 벌의 public 선언 — `<둘레 타입>.<종류> <이름>(<레이블>)` 집합(줄 단위 · 둘레는 중괄호 깊이로 · 주석 · 글자 리터럴은 걷고 센다).
const publicDecls = (files) => {
  const out = new Set();
  for (const text of files) {
    const stack = [];
    let depth = 0;
    for (const raw of text.split("\n")) {
      const line = raw.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/\/\/.*$/, "");
      const scope = stack.map((s) => s.name).join(".");
      const t = /\b(struct|enum|class|protocol|extension|actor)\s+([A-Za-z_][\w.]*)/.exec(line);
      const d = /\bpublic\b(?:\s+(?:static|final|convenience|nonisolated|mutating|override|indirect|class))*\s+(func|var|let|init[?!]?|subscript|struct|enum|class|protocol|typealias|actor)\b\s*([^\s(<:={]*)/.exec(line);
      if (d) {
        const labels = d[1].startsWith("init") || d[1] === "func" || d[1] === "subscript"
          ? ((/\(([^)]*)\)?/.exec(line.slice(d.index + d[0].length)) || [])[1] || "").split(",").map((p) => p.trim().split(/[\s:]/)[0]).join(",") : "";
        out.add(`${scope ? scope + "." : ""}${d[1]} ${d[2]}${labels ? `(${labels})` : ""}`);
      }
      for (const ch of line) {
        if (ch === "{") { depth += 1; if (t && !stack.some((s) => s.depth === depth)) stack.push({ name: t[2], depth }); }
        else if (ch === "}") { if (stack.length && stack[stack.length - 1].depth === depth) stack.pop(); depth -= 1; }
      }
    }
  }
  return out;
};
let diagWord;
let declWord = "";
const inRepo = top.status === 0 && resolve(top.stdout.trim()) === ROOT;
const lastTag = inRepo ? (spawnSync("git", ["-C", ROOT, "describe", "--tags", "--abbrev=0", "--exclude", version || "", "HEAD"], { encoding: "utf8" }).stdout || "").trim() : "";
if (!lastTag) diagWord = "기준 꼬리표 없음(git 밖 · 첫 판) — 건너뜀";
else {
  const d = run(["swift", "package", "diagnose-api-breaking-changes", lastTag, ...JOBS]);
  const breaks = d.out.split("\n").filter((l) => /API breakage:/.test(l)).map((l) => l.replace(/^.*API breakage:\s*/, "").trim());
  const ran = /No breaking changes detected|API breakage:/.test(d.out);
  if (!ran) failures.push(`⑦ 깨짐 진단이 돌지 않았다(${lastTag}):\n    ${d.out.split("\n").filter((l) => /error/i.test(l)).slice(0, 10).join("\n    ")}`);
  else if (major >= 1 && breaks.length && !majorDeclared) {
    failures.push(`⑦ 공개 표면 깨짐 ${breaks.length} — ${lastTag} 대비(1.0 뒤 · 주 판을 올리는 변경이면 qa/api-major.txt 에 지금 판 글자 ${version} 와 까닭 한 줄):\n    ${breaks.slice(0, 40).join("\n    ")}`);
  }
  diagWord = `${lastTag} 대비 깨짐 ${breaks.length}${major < 1 ? "(1.0 전 — 적기만)" : ""}`;
  if (process.env.SDK_API_LIST && breaks.length) console.log(`    ${breaks.join("\n    ")}`);
  // 보조 점검 — 직전 꼬리표의 public 선언 가운데 지금 소스에 없는 것(빼기 · 이름 바꿈 · package 로 강등)
  const tagFiles = (spawnSync("git", ["-C", ROOT, "ls-tree", "-r", "--name-only", lastTag, "--", "Sources"], { encoding: "utf8" }).stdout || "")
    .split("\n").filter((f) => f.endsWith(".swift"))
    .map((f) => spawnSync("git", ["-C", ROOT, "show", `${lastTag}:${f}`], { encoding: "utf8", maxBuffer: 64 << 20 }).stdout || "");
  const before = publicDecls(tagFiles);
  const now = publicDecls(walk(join(ROOT, "Sources"), (e) => e.endsWith(".swift")).map((f) => readFileSync(f, "utf8")));
  const gone = [...before].filter((x) => !now.has(x)).sort();
  if (!before.size) failures.push(`⑦ 직전 꼬리표 ${lastTag} 의 public 선언을 못 읽었다(보조 점검이 거짓 초록이 된다)`);
  else if (major >= 1 && gone.length && !majorDeclared) {
    failures.push(`⑦ 직전 꼬리표 ${lastTag} 의 public 선언 ${gone.length} 이 사라졌다(빼기 · 이름 바꿈 · package 강등 — 1.0 뒤 · 주 판이면 qa/api-major.txt 에 지금 판 글자):\n    ${gone.slice(0, 40).join("\n    ")}`);
  }
  declWord = ` · public 선언 ${before.size} → ${now.size}(사라짐 ${gone.length})`;
  if (process.env.SDK_API_LIST && gone.length) console.log(`    사라진 public 선언:\n    ${gone.join("\n    ")}`);
}
if (majorNote && !majorDeclared) failures.push(`⑦ qa/api-major.txt 에 지금 판 글자 ${version} 가 없다 — 지난 판의 주 판 선언이다(지우거나 이 판의 까닭으로 고친다)`);
console.log(`  ${failures.some((f) => f.startsWith("⑦")) ? "✗" : "✓"} ⑦ 공개 표면 깨짐 진단 — ${diagWord}${declWord}`);

// ⑧ 공개 이름 = SDK.md §2 표 · 종류를 얼린 이름
const sourceNames = new Map();
for (const f of walk(join(ROOT, "Sources"), (e) => e.endsWith(".swift"))) {
  for (const m of readFileSync(f, "utf8").matchAll(/^public (?:final |indirect )?(struct|enum|class|protocol|typealias|actor) ([A-Za-z_]\w*)/gm)) sourceNames.set(m[2], m[1]);
}
const sdkDoc = readFileSync(join(ROOT, "Docs", "SDK.md"), "utf8");
const sec2 = sdkDoc.split(/^## /m).find((x) => x.startsWith("2. ")) || "";
const docNames = new Set();
for (const line of sec2.split("\n").filter((l) => /^\|\s*`/.test(l))) {
  for (const m of (line.split("|")[1] || "").matchAll(/`([^`]+)`/g)) if (/^[A-Za-z_]\w*$/.test(m[1])) docNames.add(m[1]);
}
const frozen = sdkDoc.split(/^### /m).find((x) => x.startsWith("종류를 얼린 이름")) || "";
const frozenRows = frozen.split("\n").map((l) => /^\|\s*`([A-Za-z_]\w*)`\s*\|\s*`?(struct|enum|class|protocol|typealias|actor)`?\s*\|/.exec(l)).filter(Boolean);
const undocumented = [...sourceNames.keys()].filter((n) => !docNames.has(n)).sort();
const phantom = [...docNames].filter((n) => !sourceNames.has(n)).sort();
const kindDrift = frozenRows.filter((m) => sourceNames.get(m[1]) !== m[2]).map((m) => `${m[1]} 표 ${m[2]} ≠ 소스 ${sourceNames.get(m[1]) || "없음"}`);
if (!frozenRows.length) failures.push("⑧ 「종류를 얼린 이름」 표를 못 읽었다(Docs/SDK.md ### 종류를 얼린 이름)");
if (undocumented.length) failures.push(`⑧ 표에 없는 공개 이름 ${undocumented.length} — ${undocumented.join(" · ")}(Docs/SDK.md §2 표에 한 줄 · 또는 public 을 거둔다)`);
if (phantom.length) failures.push(`⑧ 소스에 없는 표의 이름 ${phantom.length} — ${phantom.join(" · ")}`);
if (kindDrift.length) failures.push(`⑧ 종류를 얼린 이름의 선언 종류가 바뀌었다 — ${kindDrift.join(" · ")}(소비자의 범위 import 가 깨진다)`);
console.log(`  ${undocumented.length + phantom.length + kindDrift.length || !frozenRows.length ? "✗" : "✓"} ⑧ 공개 이름 = SDK.md §2 표 — 소스 ${sourceNames.size} · 표 ${docNames.size} · 종류 얼림 ${frozenRows.length}`);

// ⑨ 판 품은 기본 인자 0 — public 함수 · init 의 괄호 안(괄호 짝을 센다)에서 `= <값>` 마다
const VERSIONED = /\.current\b|currentVersion|Format\.|Version/;
const versionedDefaults = [];
for (const f of walk(join(ROOT, "Sources"), (e) => e.endsWith(".swift"))) {
  const text = readFileSync(f, "utf8");
  for (const m of text.matchAll(/public\s+(?:(?:static|convenience|nonisolated|mutating|override)\s+)*(?:init[?!]?|func\s+[^(\s<]+)\s*(?:<[^>]*>)?\(/g)) {
    let depth = 1, i = m.index + m[0].length;
    const start = i;
    while (i < text.length && depth > 0) { if (text[i] === "(") depth += 1; else if (text[i] === ")") depth -= 1; i += 1; }
    for (const d of text.slice(start, i - 1).matchAll(/=\s*([^,]+)/g)) {
      if (VERSIONED.test(d[1])) versionedDefaults.push(`${rel(f)}:${text.slice(0, m.index).split("\n").length} — = ${d[1].trim().slice(0, 60)}`);
    }
  }
}
if (versionedDefaults.length) failures.push(`⑨ 판 품은 기본 인자 ${versionedDefaults.length} — 오버로드로(판 없는 손의 몸이 판을 든다):\n    ${versionedDefaults.join("\n    ")}`);
console.log(`  ${versionedDefaults.length ? "✗" : "✓"} ⑨ 판 품은 기본 인자 ${versionedDefaults.length}`);

if (failures.length) {
  for (const f of failures) console.error(`✗ ${f}`);
  console.log(`=== qa-sdk-build FAIL — ${failures.length}건 ===`);
  process.exit(1);
}
console.log(`=== qa-sdk-build OK — SDK ${version} · 시험 ${total}건(대상 ${testTargets.length}) · 잎 · unsafeFlags 0 · 갈래 · 공개 적합 · ${tagWord} · 깨짐 진단 ${diagWord} · 공개 이름 = 표 · 판 품은 기본 인자 0 ===`);
