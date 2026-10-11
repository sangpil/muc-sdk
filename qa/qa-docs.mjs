// qa-docs.mjs — SDK 저장소의 문서 게이트: 이 저장소의 `.md` 마다 ① 상대 링크가 이 저장소 안의 실물을 가리키고(뿌리 밖으로 나가는 링크 0) · 앵커가 그 문서의 머리에 있고
// ② 본문이 현재형이다(날짜 `YYYY-MM-DD` 0 — 이력은 git 이 갖는다 · 코드 블록 안은 셈 밖). 외부 링크(`http…`)는 재지 않는다.
// 인자 없음 · 빌드 없음. 사용: node qa/qa-docs.mjs

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const docs = [];
const walk = (d) => { for (const e of readdirSync(d)) { if ([".build", ".swiftpm", ".git", "node_modules"].includes(e)) continue; const f = join(d, e); if (statSync(f).isDirectory()) walk(f); else if (e.endsWith(".md")) docs.push(f); } };
walk(ROOT);

/// 머리 → 앵커(GitHub 꼴 — 소문자 · 글자 · 수 · 공백 · `-` 만 남기고 공백은 `-`).
const slug = (h) => h.trim().toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, "").replace(/\s/g, "-");
const anchorsOf = (text) => new Set(text.split("\n").filter((l) => /^#{1,6} /.test(l)).map((l) => slug(l.replace(/^#+ /, ""))));
const prose = (text) => text.replace(/```[\s\S]*?```/g, "").replace(/`[^`\n]*`/g, "");

const failures = [];
let links = 0, anchors = 0;
for (const f of docs) {
  const text = readFileSync(f, "utf8");
  for (const m of prose(text).matchAll(/\]\(([^)\s]+)\)/g)) {
    const target = m[1];
    if (/^[a-z]+:/i.test(target)) continue;
    const [path, anchor] = target.split("#");
    const file = path ? resolve(dirname(f), path) : f;
    links += 1;
    if (relative(ROOT, file).startsWith("..")) { failures.push(`${relative(ROOT, f)} — 저장소 밖을 가리키는 링크 ${target}`); continue; }
    if (!existsSync(file)) { failures.push(`${relative(ROOT, f)} — 없는 자리 ${target}`); continue; }
    if (anchor) {
      anchors += 1;
      if (file.endsWith(".md") && !anchorsOf(readFileSync(file, "utf8")).has(anchor)) failures.push(`${relative(ROOT, f)} — 없는 앵커 ${target}`);
    }
  }
  prose(text).split("\n").forEach((l, i) => { if (/\b20\d\d-\d\d-\d\d\b/.test(l)) failures.push(`${relative(ROOT, f)}:${i + 1} — 날짜(현재형만 · 이력은 git): ${l.trim().slice(0, 100)}`); });
}
if (failures.length) {
  for (const x of failures) console.error(`✗ ${x}`);
  console.log(`=== qa-docs(SDK) FAIL — ${failures.length}건 ===`);
  process.exit(1);
}
console.log(`=== qa-docs(SDK) OK — 문서 ${docs.length} · 링크 ${links} · 앵커 ${anchors} · 날짜 0 ===`);
