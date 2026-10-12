// sample-model.mjs — 시험 표본 `Tests/ProjectFormatTests/Fixtures/sample-model.isodata`(판 4 모델 파일)를 규칙으로 짓는다.
// 표본은 손으로 고치지 않는다 — 이 스크립트가 유일한 원천이고, 기본 동작은 표본이 지은 바이트와 같은지 재는 것이다(다르면 빨강 · 러너가 부른다).
//
//   무엇을 덮나 — 형식의 꼴을 한 번 이상씩: 층 둘 · 엔티티 넷(한 엔티티는 목업) · 공통 필드 묶음 하나 · 값 타입 하나 · 데이터셋 둘(레코드 · 시계 ·
//     다음 번호 · 삶 블록이 든 벌 ⟂ 라벨만 든 벌) · 열 타입(id · text · int · enum · ref · value · instant · money · decimal) · 참조 onDelete 둘(restrict · setNull) ·
//     규칙 넷(forbidden + when · sameAs · unique · code) · 별칭 둘 · 상태(목업 엔티티 · 예약 필드 · 미구현 묶음 필드) · CloudKit 경고 하나(필수인데 기본값이
//     없는 열거) · Swift 이름 칸(`swift.model`) · 스키마 판(`revision`).
//   무엇으로 — 정원 낱말(화분 · 식물 · 물 주기 · 수확)의 중립 모델. 날짜는 2040 년 뒤의 10년 격자(생년 포함) · 수는 둥근 값.
//   규칙으로 서는 칸 — 삶 블록 시대의 id 는 레코드 UUID 규약(`IsoDataIDs` — 기본 머리 `com.makeusclever.isodata/<스키마>`)으로 이
//     표본 레코드 하나에서 낸다(다른 출처의 해시가 섞이지 않게).
//   바이트 — 쓰개(`IsoDataFile.encoded()`)가 쓰는 꼴: 키 정렬 · 들여쓰기 두 칸 · `"키" : 값` · 빈 배열은 빈 줄 하나 · 슬래시를 풀어 쓴다 · 끝 줄바꿈 없음.
//     시험 `IsoDataFileTests` 가 같은 바이트를 쓰개로 다시 찍어 맞댄다(쓰개의 꼴이 바뀌면 그 시험이 먼저 빨강이다).
//
// 사용: node qa/sample-model.mjs            표본 = 지은 바이트인가(다르면 빨강)
//       node qa/sample-model.mjs --write    표본을 다시 쓴다

import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURE = join(ROOT, "Tests", "ProjectFormatTests", "Fixtures", "sample-model.isodata");

// ── 레코드 UUID 규약(RFC 4122 v5) — `IsoDataIDs` 와 같은 셈 ────────────────────────────────────────────
const URL_NS = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";
function uuid5(ns, name) {
  const b = createHash("sha1").update(Buffer.concat([Buffer.from(ns.replace(/-/g, ""), "hex"), Buffer.from(name, "utf8")])).digest().subarray(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
const recordUUID = (schema, entity, id) => uuid5(uuid5(URL_NS, `com.makeusclever.isodata/${schema}`), `${entity}/${id}`);

// ── 날짜 격자 — 2040 년 뒤 · 10년 간격 ─────────────────────────────────────────────────────────────
const year = (y) => `${y}-01-01`;
const at = (y) => `${y}-01-01T00:00:00Z`;
const BIRTH = 2040, FIRST = 2050, NOW = 2060;

// ── 스키마 — 정원 낱말의 중립 모델 ─────────────────────────────────────────────────────────────────
const SCHEMA = "sample";
const schema = {
  name: SCHEMA,
  revision: 1,
  layers: [{ id: "ground", label: "마당" }, { id: "shed", label: "헛간" }],
  entities: [
    {
      name: "Pot", label: "화분", layer: "ground", doc: "흙을 담는 그릇",
      aliases: [{ word: "화분", lens: "선반 · 목록", doc: "식물이 심기는 자리" }],
      fields: [
        { name: "id", type: "id" },
        { name: "label", type: "text", default: "", doc: "이름표" },
        { name: "glaze", type: "text", default: "", doc: "유약 이름" },
      ],
      rules: [{ id: "label-unique", doc: "이름표는 겹치지 않는다", check: { unique: ["label"] } }],
      swift: { model: "Pot" },
    },
    {
      name: "Plant", label: "식물", layer: "ground", doc: "화분에 심긴 것 하나",
      fields: [
        { name: "id", type: "id" },
        { name: "name", type: "text", default: "" },
        { name: "latin", type: "text", optional: true, doc: "학명" },
        { name: "kind", type: { enum: ["herb", "flower", "shrub"] }, doc: "갈래" },
        { name: "potId", type: { ref: "Pot", onDelete: "restrict" }, optional: true, doc: "심긴 화분" },
      ],
    },
    {
      name: "Watering", label: "물 주기", layer: "ground", doc: "물을 준 한 번",
      aliases: [{ word: "물 주기", lens: "달력" }],
      uses: ["Tagged"],
      fields: [
        { name: "id", type: "id" },
        { name: "plantId", type: { ref: "Plant", onDelete: "setNull" }, optional: true, doc: "받은 식물" },
        { name: "potId", type: { ref: "Pot", onDelete: "restrict" }, optional: true, doc: "받은 화분" },
        { name: "method", type: { enum: ["can", "hose", "rain"] }, default: "can", doc: "주는 법" },
        { name: "amountMl", type: "int", optional: true, doc: "양(mL)" },
        { name: "at", type: "instant", optional: true, doc: "준 시각" },
        { name: "note", type: "text", optional: true, status: "seam", doc: "메모 칸" },
      ],
      rules: [
        { id: "rain-no-amount", doc: "빗물은 양을 적지 않는다", check: { forbidden: "amountMl", when: { method: ["rain"] } } },
        { id: "pot-of-plant", doc: "물 받은 화분은 그 식물의 화분이다", check: { sameAs: { field: "potId", via: "plantId.potId" } } },
        { id: "daily-cap", doc: "하루에 준 물의 합은 화분이 받는 양을 넘지 않는다", code: "Sources/Rules/DailyCap.swift" },
      ],
      swift: { model: "Watering" },
    },
    {
      name: "Harvest", label: "수확", layer: "shed", status: "mock", doc: "거둔 것 한 번",
      fields: [
        { name: "id", type: "id" },
        { name: "title", type: "text", default: "" },
        { name: "amount", type: "money", default: 0, doc: "판 값" },
        { name: "measure", type: { value: "Measure" }, optional: true },
      ],
    },
  ],
  traits: [{ name: "Tagged", doc: "표 하나 → [표] 절", fields: [{ name: "tagId", type: "text", optional: true, status: "unbuilt", doc: "null = 표가 없음" }] }],
  values: [{ name: "Measure", fields: [{ name: "grams", type: "decimal", optional: true }] }],
};

// ── 데이터셋 — 레코드 · 시계 · 다음 번호 · 삶 블록이 든 벌 ⟂ 라벨만 든 벌 ──────────────────────────────────
const records = {
  Pot: [{ id: "pot-1", label: "창가 화분", glaze: "청자" }],
  Plant: [{ id: "plant-1", name: "바질", kind: "herb", potId: "pot-1" }],
  Watering: [
    { id: "watering-1", method: "rain", at: at(FIRST) },
    { id: "watering-2", plantId: "plant-1", potId: "pot-1", method: "can", amountMl: 200, at: at(NOW) },
  ],
  Harvest: [{ id: "harvest-1", title: "첫 수확", amount: 100, measure: { grams: 2 } }],
};
const datasets = {
  spring: {
    label: "봄",
    clock: { now: at(NOW), tz: "UTC" },
    records,
    nextIDs: { Watering: 3 },
    life: {
      derived: true,
      domain: { birth: year(BIRTH), lifeExpectancy: 90 },
      eras: [{ id: recordUUID(SCHEMA, "Watering", "watering-1"), label: "Era 1", from: year(FIRST), to: year(NOW) }],
      milestones: [],
      series: [],
    },
  },
  bare: { label: "맨땅" },
};

const model = { datasets, schema, version: 4 };

// ── 쓰개의 꼴 ─────────────────────────────────────────────────────────────────────────────────────
function write(v, ind = "") {
  if (v === null || typeof v === "boolean") return String(v);
  if (typeof v === "number") { if (!Number.isInteger(v)) throw new Error(`정수가 아닌 수 ${v} — 표본은 정수만 쓴다(소수의 글꼴은 쓰개가 정한다)`); return String(v); }
  if (typeof v === "string") { if (/[\u0000-\u001f\u2028\u2029]/.test(v)) throw new Error(`제어 글자가 든 글 — ${JSON.stringify(v)}`); return JSON.stringify(v); }
  const next = ind + "  ";
  if (Array.isArray(v)) return v.length ? `[\n${v.map((x) => next + write(x, next)).join(",\n")}\n${ind}]` : `[\n\n${ind}]`;
  const keys = Object.keys(v).sort();
  return keys.length ? `{\n${keys.map((k) => `${next}${JSON.stringify(k)} : ${write(v[k], next)}`).join(",\n")}\n${ind}}` : `{\n\n${ind}}`;
}
const bytes = write(model);

if (process.argv.includes("--write")) {
  writeFileSync(FIXTURE, bytes);
  console.log(`=== sample-model — 썼다 ${FIXTURE.slice(ROOT.length + 1)} (${Buffer.byteLength(bytes)} 바이트) ===`);
} else {
  const now = existsSync(FIXTURE) ? readFileSync(FIXTURE, "utf8") : null;
  if (now !== bytes) {
    console.error(`✗ 표본 ${FIXTURE.slice(ROOT.length + 1)} 이 지은 바이트와 다르다${now === null ? "(파일 없음)" : ""} — 손으로 고치지 않는다: 이 스크립트를 고치고 --write`);
    console.log("=== sample-model FAIL ===");
    process.exit(1);
  }
  console.log(`=== sample-model OK — 표본 = 지은 바이트(${Buffer.byteLength(bytes)} 바이트) ===`);
}
