// qa-map.mjs — SDK 저장소의 지도 게이트: 처음 읽는 사람(사람 · AI 에이전트)이 따라가는 지도(README → `Docs/SDK.md` §1 · §2 → 모듈 머리 → 시험)가
// 실제 모듈과 같다. 지도는 `Docs/SDK.md` §2 맨 위의 「모듈 지도」 표 하나다(머리 줄 `| 모듈 | 갈래 | …`).
//
//   ① **모듈 = 표** — `Package.swift` 의 타깃(시험 타깃 뺌) = `Sources/` 폴더 = 지도 표의 모듈(양방향 · 빠짐 · 남음 빨강) ·
//      제품(`.library`) = §2 의 모듈 절 머리(`**`<모듈>`**`) · 제품이 아닌 타깃만 표의 갈래 칸에 「제품 아님」.
//   ② **갈래 = §1** — 표의 갈래 칸 첫 낱말(계약 · 런타임 · 시험) = §1 갈래 표에서 그 모듈이 든 줄.
//   ③ **시작점 = 실재** — 시작점 칸의 이름마다 그 모듈 `Sources/<모듈>/` 의 맨 위 `public` 타입이다(`<타입>.<손>(…)` 꼴은 그 모듈의 `public func <손>` ·
//      Swift 소스가 없는 C 심은 그 폴더의 함수 선언).
//   ④ **머리 = 표** — 머리 칸이 가리키는 파일이 그 모듈 폴더 안에 있고, 앞 주석에 `// 모듈 `<모듈>`` 머리가 있으며 그 머리의 `시작점` 줄 이름 = 표의 시작점 칸.
//   ⑤ **시험 = 표** — 시험 칸이 가리키는 폴더 = `Tests/` 폴더 = `Package.swift` 의 시험 타깃(양방향).
//   ⑥ **변이 자기 시험** — 표에서 한 줄을 뺀 문서 · 시작점에 없는 이름을 넣은 문서를 같은 검사에 먹여 빨강이 나는지 잰다(검사가 늘 초록인 꼴을 막는다).
//
// 인자 없음 · 빌드 없음(매니페스트는 글로 읽는다). 사용: node qa/qa-map.mjs

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DOC = join(ROOT, "Docs", "SDK.md");
const read = (f) => readFileSync(f, "utf8");
const dirsOf = (d) => existsSync(d) ? readdirSync(d).filter((e) => statSync(join(d, e)).isDirectory()).sort() : [];
const filesUnder = (d) => !existsSync(d) ? [] : readdirSync(d).flatMap((e) => { const f = join(d, e); return statSync(f).isDirectory() ? filesUnder(f) : [f]; });
const diff = (a, b) => [...a].filter((x) => !b.has(x)).sort();

// 매니페스트 — 주석을 걷고 제품 · 타깃 · 시험 타깃 이름을 글로 읽는다
const manifest = read(join(ROOT, "Package.swift")).split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");
const products = new Set([...manifest.matchAll(/\.library\(\s*name:\s*"([^"]+)"/g)].map((m) => m[1]));
const targets = new Set([...manifest.matchAll(/\.target\(\s*name:\s*"([^"]+)"/g)].map((m) => m[1]));
const testTargets = new Set([...manifest.matchAll(/\.testTarget\(\s*name:\s*"([^"]+)"/g)].map((m) => m[1]));
const sourceDirs = new Set(dirsOf(join(ROOT, "Sources")));
const testDirs = new Set(dirsOf(join(ROOT, "Tests")));

/// 모듈의 맨 위 public 타입 · public func 이름 · (C 심) 함수 선언 이름.
const surface = new Map();
for (const m of sourceDirs) {
  const files = filesUnder(join(ROOT, "Sources", m));
  const swift = files.filter((f) => f.endsWith(".swift")).map(read).join("\n");
  const types = new Set([...swift.matchAll(/^public (?:final |indirect )?(?:struct|enum|class|protocol|typealias|actor) ([A-Za-z_]\w*)/gm)].map((x) => x[1]));
  const funcs = new Set([...swift.matchAll(/\bpublic (?:static )?func ([A-Za-z_]\w*)/g)].map((x) => x[1]));
  const cFuncs = new Set(files.filter((f) => /\.[ch]$/.test(f)).flatMap((f) => [...read(f).matchAll(/^\s*[A-Za-z_][\w\s*]*?\b([A-Za-z_]\w*)\s*\([^;{]*\)\s*;/gm)].map((x) => x[1])));
  surface.set(m, { types, funcs, cFuncs, hasSwift: swift.length > 0 });
}

/// 이름 하나가 그 모듈에 실재하는가.
const real = (m, name) => {
  const s = surface.get(m);
  if (!s) return false;
  const member = /^([A-Za-z_]\w*)\.([A-Za-z_]\w*)\(/.exec(name);
  if (member) return s.funcs.has(member[2]);
  if (!/^[A-Za-z_]\w*$/.test(name)) return false;
  return s.hasSwift ? s.types.has(name) : s.cFuncs.has(name);
};

const ticks = (cell) => [...(cell || "").matchAll(/`([^`]+)`/g)].map((x) => x[1]);
const links = (cell) => [...(cell || "").matchAll(/\]\(([^)\s]+)\)/g)].map((x) => resolve(dirname(DOC), x[1].split("#")[0]));

/// 문서 한 벌을 잰다 — 실패 목록과 셈을 낸다(변이 자기 시험이 같은 손을 부른다).
function audit(doc) {
  const failures = [];
  const sec = (n) => doc.split(/^## /m).find((x) => x.startsWith(`${n}. `)) || "";
  const sec1 = sec(1), sec2 = sec(2);
  const lines = sec2.split("\n");
  const head = lines.findIndex((l) => /^\|\s*모듈\s*\|\s*갈래\s*\|/.test(l));
  if (head < 0) return { failures: ["§2 의 모듈 지도 표(머리 줄 `| 모듈 | 갈래 | …`)를 못 찾았다"], rows: [] };
  const cols = lines[head].split("|").slice(1, -1).map((c) => c.trim());
  const at = (name) => cols.indexOf(name);
  for (const c of ["모듈", "갈래", "시작점 타입", "머리 주석", "시험"]) if (at(c) < 0) failures.push(`모듈 지도 표에 칸 「${c}」 가 없다`);
  if (failures.length) return { failures, rows: [] };
  const rows = [];
  for (const l of lines.slice(head + 2)) {
    if (!/^\|/.test(l)) break;
    const cells = l.split("|").slice(1, -1).map((c) => c.trim());
    const name = (/\*\*([A-Za-z_]\w*)\*\*/.exec(cells[at("모듈")]) || [])[1];
    if (!name) { failures.push(`모듈 지도 표의 줄에 모듈 이름(**이름**)이 없다: ${l.slice(0, 80)}`); continue; }
    rows.push({ name, branch: cells[at("갈래")], starts: ticks(cells[at("시작점 타입")]), heads: links(cells[at("머리 주석")]), tests: links(cells[at("시험")]) });
  }
  const mapped = new Set(rows.map((r) => r.name));

  // ① 모듈 = 표
  const dup = rows.map((r) => r.name).filter((n, i, a) => a.indexOf(n) !== i);
  if (dup.length) failures.push(`① 모듈 지도 표에 두 번 든 모듈 — ${dup.join(" · ")}`);
  for (const [what, set] of [["Package.swift 타깃", targets], ["Sources/ 폴더", sourceDirs]]) {
    const missing = diff(set, mapped), extra = diff(mapped, set);
    if (missing.length) failures.push(`① ${what}에 있고 모듈 지도 표에 없다 — ${missing.join(" · ")}`);
    if (extra.length) failures.push(`① 모듈 지도 표에 있고 ${what}에 없다 — ${extra.join(" · ")}`);
  }
  const sections = new Set([...sec2.matchAll(/^\*\*`([A-Za-z_]\w*)`\*\* —/gm)].map((x) => x[1]));
  const noSection = diff(products, sections), noProduct = diff(sections, products);
  if (noSection.length) failures.push(`① 제품인데 §2 의 모듈 절(**\`이름\`** —)이 없다 — ${noSection.join(" · ")}`);
  if (noProduct.length) failures.push(`① §2 의 모듈 절이 있는데 제품이 아니다 — ${noProduct.join(" · ")}`);
  for (const r of rows) {
    const marked = /제품 아님/.test(r.branch);
    if (products.has(r.name) === marked) failures.push(`① ${r.name} — 제품 ${products.has(r.name) ? "인데 갈래 칸에 「제품 아님」" : "이 아닌데 갈래 칸에 「제품 아님」이 없다"}`);
  }

  // ② 갈래 = §1
  const branchOf = new Map();
  for (const l of sec1.split("\n")) {
    const b = /^\s*\|\s*\*\*(계약|런타임|시험)\*\*/.exec(l);
    if (b) for (const n of ticks(l.split("|")[2])) if (/^[A-Za-z_]\w*$/.test(n)) branchOf.set(n, b[1]);
  }
  if (!branchOf.size) failures.push("② §1 의 갈래 표(**계약** · **런타임** · **시험** 줄)를 못 읽었다");
  for (const r of rows) {
    const word = (/^(계약|런타임|시험)/.exec(r.branch) || [])[1];
    if (!word) failures.push(`② ${r.name} — 갈래 칸이 계약 · 런타임 · 시험으로 시작하지 않는다: ${r.branch}`);
    else if (branchOf.size && branchOf.get(r.name) !== word) failures.push(`② ${r.name} — 지도의 갈래 ${word} ≠ §1 의 갈래 ${branchOf.get(r.name) || "없음"}`);
  }

  // ③ 시작점 = 실재 · ④ 머리 = 표
  for (const r of rows) {
    if (!r.starts.length) failures.push(`③ ${r.name} — 시작점 타입 칸이 비었다`);
    const fake = r.starts.filter((n) => !real(r.name, n));
    if (fake.length) failures.push(`③ ${r.name} — 시작점 칸의 이름이 그 모듈에 없다: ${fake.join(" · ")}`);
    if (r.heads.length !== 1) { failures.push(`④ ${r.name} — 머리 주석 칸이 파일 하나를 가리키지 않는다(${r.heads.length})`); continue; }
    const f = r.heads[0];
    if (!f.startsWith(join(ROOT, "Sources", r.name) + sep) || !existsSync(f)) { failures.push(`④ ${r.name} — 머리 파일이 그 모듈 폴더 안에 없다: ${relative(ROOT, f)}`); continue; }
    const top = read(f).split("\n").slice(0, 60);
    const i = top.findIndex((l) => l.startsWith(`// 모듈 \`${r.name}\``));
    if (i < 0) { failures.push(`④ ${r.name} — ${relative(ROOT, f)} 앞 주석에 \`// 모듈 \`${r.name}\`\` 머리가 없다`); continue; }
    const startLine = top.slice(i, i + 12).find((l) => /^\/\/\s+시작점\s*:/.test(l));
    if (!startLine) { failures.push(`④ ${r.name} — 머리에 \`시작점 :\` 줄이 없다(${relative(ROOT, f)})`); continue; }
    const inHead = new Set(ticks(startLine)), inMap = new Set(r.starts);
    const a = diff(inMap, inHead), b = diff(inHead, inMap);
    if (a.length || b.length) failures.push(`④ ${r.name} — 머리의 시작점 ≠ 지도의 시작점(지도에만 ${a.join(" · ") || "0"} · 머리에만 ${b.join(" · ") || "0"})`);
  }

  // ⑤ 시험 = 표
  const tested = new Set(rows.flatMap((r) => r.tests.map((t) => relative(join(ROOT, "Tests"), t))));
  for (const [what, set] of [["Tests/ 폴더", testDirs], ["Package.swift 시험 타깃", testTargets]]) {
    const missing = diff(set, tested), extra = diff(tested, set);
    if (missing.length) failures.push(`⑤ ${what}에 있고 지도의 시험 칸에 없다 — ${missing.join(" · ")}`);
    if (extra.length) failures.push(`⑤ 지도의 시험 칸에 있고 ${what}에 없다 — ${extra.join(" · ")}`);
  }
  return { failures, rows };
}

const doc = read(DOC);
const { failures, rows } = audit(doc);

// ⑥ 변이 자기 시험 — 한 줄 빼기 · 없는 시작점 넣기는 빨강이어야 한다
const rowLines = doc.split("\n").filter((l) => /^\|\s*\*\*[A-Za-z_]\w*\*\*\s*\|/.test(l));
const mutants = [];
if (rowLines.length) {
  mutants.push(["표에서 한 줄 빼기", doc.replace(rowLines[rowLines.length - 1] + "\n", "")]);
  const cells = rowLines[0].split("|");
  const startCol = doc.split("\n").find((l) => /^\|\s*모듈\s*\|\s*갈래\s*\|/.test(l)).split("|").map((c) => c.trim()).indexOf("시작점 타입");
  cells[startCol] = `${cells[startCol]} · \`NoSuchStartType\``;
  mutants.push(["없는 시작점 넣기", doc.replace(rowLines[0], cells.join("|"))]);
}
const survived = mutants.filter(([, d]) => audit(d).failures.length === 0).map(([n]) => n);
if (mutants.length < 2) failures.push("⑥ 변이를 짓지 못했다(표의 줄을 못 읽었다)");
if (survived.length) failures.push(`⑥ 변이가 살아남았다(검사가 못 잡는다) — ${survived.join(" · ")}`);

if (failures.length) {
  for (const x of failures) console.error(`✗ ${x}`);
  console.log(`=== qa-map(SDK) FAIL — ${failures.length}건 ===`);
  process.exit(1);
}
console.log(`=== qa-map(SDK) OK — 모듈 ${rows.length} = 타깃 ${targets.size} = Sources ${sourceDirs.size} · 제품 ${products.size} = 모듈 절 · 시작점 ${rows.reduce((n, r) => n + r.starts.length, 0)} 실재 · 머리 ${rows.length} · 시험 ${testDirs.size} · 변이 ${mutants.length} 빨강 ===`);
