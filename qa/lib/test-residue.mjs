// test-residue.mjs — SDK 저장소의 손(시험 묶음 · Swift 툴체인이 남기는 부산물을 한 자리에 가두고 끝에 센다). 다른 저장소(빌더 · 프로젝트)에 같은 역할의 손이
// 제각기 있다 — 묶지 않는다(저장소마다 제 게이트가 제 손을 쓴다). 쓰는 곳: `qa/qa-sdk-build.mjs`.
//
// 두 가지를 막는다(`$TMPDIR` 에 쌓이는 시험 폴더 · `~/Library/Preferences` 에 남는 시험 plist):
//   ⓐ **Swift 툴체인의 찌꺼기** — `swift build|test|package` 는 부를 때마다 `$TMPDIR` 에 `TemporaryDirectory.XXXXXX`(빈 폴더)와 빌드 자리마다의
//      잠금 파일(`<경로의 / 를 _ 로>.lock` · `…_workspace-state.json.lock`)을 남긴다. 자식 프로세스에 이 범위의 `TMPDIR` 을 주면 그것들이 범위 안에
//      떨어지고 범위와 함께 지워진다(xcodebuild 가 띄우는 시험 실행기에는 `TEST_RUNNER_` 머리로 같은 값이 간다).
//   ⓑ **시험이 남긴 자리** — 시험의 임시 폴더 · 파일 · 설정 도메인은 SDK `TestScratch` 한 벌로만 만든다(무는 쪽의 경계 게이트가 소스에서 잰다). 그 손은
//      환경 `TEST_SCRATCH_ROOT` 가 있으면 그 밑에 만든다 — 범위가 그 값을 주고, 끝에 범위 안에 `test-scratch-*` 가 남았으면 **시험이 지우지 않은 것**이다.
//      (Foundation 의 `temporaryDirectory` 는 macOS 에서 `TMPDIR` 을 읽지 않는다 — 그래서 시험 쪽은 환경 칸 하나를 따로 둔다.)
//
// 쓰는 법(게이트):
//   import { residueScope } from "./lib/test-residue.mjs";
//   const scope = residueScope("qa-sdk-build");      // 범위 폴더를 만든다 · 프로세스가 끝나면(실패 · 신호 포함) 지운다
//   spawnSync("swift", [...], { env: scope.env });    // 자식마다 scope.env
//   const left = scope.check();                       // 범위 안의 `test-scratch-*` (남은 것 이름 목록 — 비어야 한다)
//
// 범위 폴더는 `$TMPDIR/test-residue-<이름>-XXXXXX/` 하나다 — 같은 기계에서 함께 도는 다른 실행과 섞이지 않는다(셈은 제 범위 안만 본다).
// 범위는 `mkdtemp` 로 실행마다 유일하고 `TEST_SCRATCH_ROOT` 도 그 실행의 env 로만 간다 — **범위 안의 `test-scratch-*` 는 그 실행이 남긴 것이다**(거르지 않는다).
// 실행 표지(`TEST_SCRATCH_RUN` · 실행기에는 `TEST_RUNNER_TEST_SCRATCH_RUN`)는 **진단 정보**다: `TestScratch` 가 이름 머리에 넣으니(`test-scratch-<표지>-…`) 남은 자리에
// 표지가 없으면 env 를 받지 못한 프로세스(손으로 띄운 자식 · 실행기 머리를 빠뜨린 길)가 쓴 것이라 실패 줄이 따로 이름 댄다. 자기 시험 `residueSelfTest`.

import { randomBytes } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const SCRATCH_PREFIX = "test-scratch-";
let hooked = false;
const scopes = new Set();

const PREFS = join(homedir(), "Library", "Preferences");
const scratchPrefs = () => { try { return readdirSync(PREFS).filter((n) => n.startsWith(SCRATCH_PREFIX)); } catch { return []; } };

function removeAll() {
  for (const dir of scopes) { try { rmSync(dir, { recursive: true, force: true }); } catch {} }
  scopes.clear();
}

/// 신호로도 못 지운 범위(SIGKILL — 게이트가 죽임을 당했다) — 같은 머리의 한 시간 넘은 범위를 먼저 걷는다(돌고 있는 게이트의 범위는 한 시간 안이다).
function sweepStale() {
  let names = [];
  try { names = readdirSync(tmpdir()); } catch { return; }
  for (const n of names) {
    if (!n.startsWith("test-residue-")) continue;
    const p = join(tmpdir(), n);
    try { if (Date.now() - statSync(p).mtimeMs > 3600_000) rmSync(p, { recursive: true, force: true }); } catch {}
  }
}

/// 실행 표지의 꼴(범위가 짓는 `r<pid>x<hex6>`) — 남은 자리 이름에 이것이 없으면 env 없이 쓴 프로세스다.
const RUN_MARK = new RegExp(`^${SCRATCH_PREFIX}r\\d+x[0-9a-f]{6}-`);

/// 범위 하나 — `env` 를 자식 프로세스에 준다. `check()` 는 남은 시험 자리 이름 목록 · `dispose()` 는 지금 지운다(끝에 저절로도 지운다).
export function residueScope(label) {
  sweepStale();
  const dir = mkdtempSync(join(tmpdir(), `test-residue-${label}-`));
  scopes.add(dir);
  if (!hooked) {
    hooked = true;
    process.on("exit", removeAll);
    for (const s of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(s, () => { removeAll(); process.exit(130); });
  }
  const slash = `${dir}/`;
  const run = `r${process.pid}x${randomBytes(3).toString("hex")}`;   // 이 실행의 표지(영숫자 · TestScratch 가 이름 머리에)
  const env = { ...process.env, TMPDIR: slash, TEST_SCRATCH_ROOT: slash, TEST_RUNNER_TMPDIR: slash, TEST_RUNNER_TEST_SCRATCH_ROOT: slash,
                TEST_SCRATCH_RUN: run, TEST_RUNNER_TEST_SCRATCH_RUN: run };
  const prefsBefore = new Set(scratchPrefs());
  return {
    dir,
    env,
    run,
    /// 시험이 지우지 않은 자리 — 범위 안의 `test-scratch-*` 이름(설정 도메인은 그 폴더 안의 plist 라 여기서 함께 보인다) +
    /// `~/Library/Preferences` 에 새로 선 `test-scratch-*.plist`(TestScratch 는 거기 쓰지 않는다 — 서면 손이 갈라진 것이다).
    check() {
      let names = [];
      try { names = readdirSync(dir); } catch {}
      const prefs = scratchPrefs().filter((n) => !prefsBefore.has(n)).map((n) => `~/Library/Preferences/${n}`);
      return [...names.filter((n) => n.startsWith(SCRATCH_PREFIX)).sort(), ...prefs.sort()];
    },
    dispose() { try { rmSync(dir, { recursive: true, force: true }); } catch {} scopes.delete(dir); },
  };
}

/// 실패 한 줄의 꼴 — 남은 것 앞 여덟 + 수 · 범위 안인데 실행 표지가 없는 이름은 따로(env 를 받지 못한 프로세스가 썼다).
export function residueLine(left) {
  const unmarked = left.filter((n) => n.startsWith(SCRATCH_PREFIX) && !RUN_MARK.test(n));
  const why = unmarked.length ? ` · 표지 없음 ${unmarked.length}(${unmarked.slice(0, 4).join(" · ")} — TEST_SCRATCH_RUN 없이 쓴 프로세스 의심: 손으로 띄운 자식 · TEST_RUNNER_ 머리)` : "";
  return `시험이 임시 자리를 남겼다 ${left.length} — ${left.slice(0, 8).join(" · ")}${left.length > 8 ? " …" : ""}${why}(SDK TestScratch 로 만들고 끝에 지운다 — defer · addTeardownBlock · withFolder · 바탕 일은 지우기 전에 기다린다)`;
}

/// 자기 시험 — 범위 하나에 제 표지 · 다른 표지 · 표지 없는 자리를 심고, 셈이 **셋 다** 내는지(범위 안은 그 실행의 것 — 거르지 않는다) ·
/// 실패 줄이 표지 없는 것만 따로 이름 대는지 잰다. 맞으면 빈 문자열 · 틀리면 까닭 한 줄. 게이트가 셈 앞에 부른다.
export function residueSelfTest() {
  const s = residueScope("selftest");
  try {
    const mine = `${SCRATCH_PREFIX}${s.run}-mine-1`, other = `${SCRATCH_PREFIX}r1x000000-other-2`, bare = `${SCRATCH_PREFIX}host-thumbnails-3`;
    for (const n of [mine, other, bare]) mkdirSync(join(s.dir, n));
    const got = s.check(), want = [mine, other, bare].sort();
    if (JSON.stringify(got) !== JSON.stringify(want)) return `남은 자리 셈이 범위 안의 자리를 걸렀다 — ${got.join(" · ")} ≠ ${want.join(" · ")}`;
    const line = residueLine(got);
    if (!line.includes(`표지 없음 1(${bare}`)) return `실패 줄이 표지 없는 자리를 따로 이름 대지 않는다 — ${line}`;
    return "";
  } finally { s.dispose(); }
}
