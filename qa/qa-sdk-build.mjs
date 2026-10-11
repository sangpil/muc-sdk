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

if (failures.length) {
  for (const f of failures) console.error(`✗ ${f}`);
  console.log(`=== qa-sdk-build FAIL — ${failures.length}건 ===`);
  process.exit(1);
}
console.log(`=== qa-sdk-build OK — SDK ${version} · 시험 ${total}건(대상 ${testTargets.length}) · 잎 · unsafeFlags 0 · 갈래 · 공개 적합 · ${tagWord} ===`);
