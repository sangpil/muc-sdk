// run-all.mjs — SDK 저장소의 전건 러너: 이 저장소의 게이트 전부를 차례로 돌린다(하나라도 빨강이면 빨강). 변경을 올리기 전에 도는 게이트다.
//   qa-docs.mjs      문서 링크 · 앵커 · 현재형
//   qa-map.mjs       모듈 지도(Docs/SDK.md §2) = 매니페스트 타깃 · Sources · Tests · 모듈 머리 주석 · 실재 시작점
//   sample-model.mjs 모델 파일 시험 표본 = 규칙으로 지은 바이트(손으로 고치지 않는다)
//   qa-sdk-build.mjs 빌드 · 시험(대상마다) · 잎 · 갈래 · 공개 적합 · 판 꼬리표 · 시험이 남긴 자리
// 인자 없음. 사용: node qa/run-all.mjs

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const QA = dirname(fileURLToPath(import.meta.url));
const SUITES = ["qa-docs.mjs", "qa-map.mjs", "sample-model.mjs", "qa-sdk-build.mjs"];
const t0 = Date.now();
const results = SUITES.map((s) => {
  const t = Date.now();
  const r = spawnSync(process.execPath, [join(QA, s)], { stdio: "inherit" });
  return { s, ok: r.status === 0, sec: Math.round((Date.now() - t) / 1000) };
});
for (const r of results) console.log(`  ${r.ok ? "✓" : "✗"} ${r.s} (${r.sec}s)`);
const bad = results.filter((r) => !r.ok);
console.log(`=== run-all(SDK) ${bad.length ? "FAIL" : "OK"} — ${results.length - bad.length}/${results.length} · ${Math.round((Date.now() - t0) / 1000)}s ===`);
process.exit(bad.length ? 1 : 0);
