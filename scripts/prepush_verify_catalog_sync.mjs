/**
 * Pre-push verification: catalog triggers vs client prefab geometry.
 * Run: node scripts/prepush_verify_catalog_sync.mjs
 */
import fs from "fs";
import path from "path";

const ROOT = path.resolve(import.meta.dirname, "..");

function readJson(rel) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8"));
}

function readText(rel) {
  return fs.readFileSync(path.join(ROOT, rel), "utf8");
}

function approx(a, b, eps = 0.01) {
  return Math.abs(a - b) <= eps;
}

function vec2Match(a, b, eps = 0.01) {
  return approx(a.x, b.x, eps) && approx(a.y, b.y, eps);
}

function sizeMatch(a, b, eps = 0.01) {
  return approx(a.x, b.x, eps) && approx(a.y, b.y, eps);
}

function parseTscnSize(text, subId) {
  const re = new RegExp(
    `\\[sub_resource type="RectangleShape2D" id="${subId}"\\][\\s\\S]*?size = Vector2\\(([^,]+), ([^)]+)\\)`
  );
  const m = text.match(re);
  if (!m) return null;
  return { x: parseFloat(m[1]), y: parseFloat(m[2]) };
}

function parseTscnVec2AfterId(text, nodePattern, prop) {
  const re = new RegExp(
    nodePattern + `[\\s\\S]*?${prop} = Vector2\\(([^,]+), ([^)]+)\\)`
  );
  const m = text.match(re);
  if (!m) return null;
  return { x: parseFloat(m[1]), y: parseFloat(m[2]) };
}

const failures = [];
const passes = [];

function pass(msg) {
  passes.push(msg);
}

function fail(msg) {
  failures.push(msg);
}

// --- Client vs server catalog ---
const clientCat = readJson("client/data/game_catalog.json");
const serverCat = readJson("server/data/game_catalog.json");
if (JSON.stringify(clientCat) === JSON.stringify(serverCat)) {
  pass("Client and server game_catalog.json are identical");
} else {
  fail("Client and server game_catalog.json differ");
}

// --- Player template ---
const playerShape = clientCat.player_templates?.default?.shape;
const playerSoda = readText("client/scenes/player_soda.tscn");
const playerRectSize = parseTscnSize(playerSoda, "RectangleShape2D_r0uhu");
const playerColPos = parseTscnVec2AfterId(
  playerSoda,
  '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."',
  "position"
);

if (
  playerShape?.type === "rectangle" &&
  playerRectSize &&
  playerColPos &&
  vec2Match(playerShape.offset, playerColPos) &&
  sizeMatch(playerShape.size, playerRectSize)
) {
  pass(
    `Player template matches player_soda.tscn collision (${playerShape.size.x}×${playerShape.size.y} @ ${playerShape.offset.x}, ${playerShape.offset.y})`
  );
} else {
  fail(
    `Player template mismatch: catalog=${JSON.stringify(playerShape)} scene size=${JSON.stringify(playerRectSize)} pos=${JSON.stringify(playerColPos)}`
  );
}

// --- Door prefab ---
const doorTscn = readText("client/prefabs/door.tscn");
const doorDetectSize = parseTscnSize(doorTscn, "RectangleShape2D_door_detection");
const doorDetectPos = parseTscnVec2AfterId(
  doorTscn,
  '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="DetectionArea"',
  "position"
) ?? { x: 0, y: 0 };

const doorEntries = [];
for (const level of Object.values(clientCat.levels ?? {})) {
  for (const [id, obj] of Object.entries(level.objects ?? {})) {
    if (obj.kind === "door") doorEntries.push({ id, trigger: obj.trigger });
  }
}

let doorOk = true;
for (const { id, trigger } of doorEntries) {
  if (
    !trigger ||
    trigger.margin !== 0 ||
    !vec2Match(trigger.offset, doorDetectPos) ||
    !sizeMatch(trigger.size, doorDetectSize)
  ) {
    fail(`Door ${id} trigger ${JSON.stringify(trigger)} != prefab detect ${JSON.stringify(doorDetectSize)} @ ${JSON.stringify(doorDetectPos)}`);
    doorOk = false;
  }
}
if (doorOk && doorEntries.length > 0) {
  pass(`${doorEntries.length} door catalog triggers match door.tscn DetectionArea (${doorDetectSize.x}×${doorDetectSize.y} @ ${doorDetectPos.x}, ${doorDetectPos.y})`);
}

// --- Goal prefab ---
const goalTscn = readText("client/prefabs/level_goal.tscn");
const goalSize = parseTscnSize(goalTscn, "RectangleShape2D_f47rt");
const goalPos = { x: 0, y: 0 };

const goalEntries = [];
for (const level of Object.values(clientCat.levels ?? {})) {
  for (const [id, obj] of Object.entries(level.objects ?? {})) {
    if (obj.kind === "goal") goalEntries.push({ id, trigger: obj.trigger });
  }
}

let goalOk = true;
for (const { id, trigger } of goalEntries) {
  if (
    !trigger ||
    trigger.margin !== 0 ||
    !vec2Match(trigger.offset, goalPos) ||
    !sizeMatch(trigger.size, goalSize)
  ) {
    fail(`Goal ${id} trigger ${JSON.stringify(trigger)} != prefab ${JSON.stringify(goalSize)} @ origin`);
    goalOk = false;
  }
}
if (goalOk && goalEntries.length > 0) {
  pass(`${goalEntries.length} goal catalog triggers match level_goal.tscn (${goalSize.x}×${goalSize.y})`);
}

// --- Spike prefab AABB math ---
const BASE_W = 10.5;
const BASE_H = 10.5;
const BASE_CX = 0.25;
const BASE_CY = -4.75;

const spikeConfig = {
  level02_spike_01: { sx: 1, sy: 1, rot: 0 },
  level03_spike_01: { sx: 1, sy: 1, rot: 0 },
  level03_spike_02: { sx: 1, sy: 1, rot: 0 },
  level03_spike_03: { sx: 1, sy: 1, rot: 0 },
  water02_spike_a: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_b: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_c: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_d: { sx: 1.2, sy: 1.2, rot: Math.PI },
  water02_spike_e: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_f: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_g: { sx: 1.2, sy: 1.2, rot: 0 },
  water02_spike_h: { sx: 1.2, sy: 1.2, rot: Math.PI },
  water03_spike_a: { sx: 1.5, sy: 1.5, rot: 0 },
  water03_spike_b: { sx: 1.5, sy: 1.5, rot: 0 },
};
for (let i = 1; i <= 11; i++) {
  spikeConfig[`dark05_spike_${String(i).padStart(2, "0")}`] = { sx: 4, sy: 4, rot: 0 };
}

function expectedSpikeTrigger(sx, sy, rot) {
  let cx = BASE_CX * sx;
  let cy = BASE_CY * sy;
  if (rot !== 0) {
    cx = -BASE_CX * sx;
    cy = -BASE_CY * sy;
  }
  return {
    offset: { x: cx, y: cy },
    size: { x: BASE_W * sx, y: BASE_H * sy },
    margin: 0,
  };
}

let spikeOk = true;
let spikeCount = 0;
for (const level of Object.values(clientCat.levels ?? {})) {
  for (const [id, obj] of Object.entries(level.objects ?? {})) {
    const cfg = spikeConfig[id];
    if (!cfg || obj.kind !== "hazard") continue;
    spikeCount++;
    const exp = expectedSpikeTrigger(cfg.sx, cfg.sy, cfg.rot);
    const tr = obj.trigger;
    if (
      tr.margin !== 0 ||
      !vec2Match(tr.offset, exp.offset) ||
      !sizeMatch(tr.size, exp.size)
    ) {
      fail(`Spike ${id}: catalog ${JSON.stringify(tr)} != expected ${JSON.stringify(exp)}`);
      spikeOk = false;
    }
  }
}
if (spikeOk && spikeCount > 0) {
  pass(`${spikeCount} spike/hazard catalog triggers match spike.tscn AABB math`);
}

// --- Spike polygon unchanged in prefab ---
const spikeTscn = readText("client/prefabs/spike.tscn");
if (spikeTscn.includes("polygon = PackedVector2Array(-5, 4.5, 0.25, -6, 5.5, 4.5)")) {
  pass("spike.tscn collision polygon matches audit baseline");
} else {
  fail("spike.tscn polygon differs from expected baseline");
}

// --- Summary ---
console.log("\n=== PRE-PUSH CATALOG SYNC CHECK ===\n");
for (const p of passes) console.log("OK  ", p);
for (const f of failures) console.log("FAIL", f);
console.log(`\n${passes.length} passed, ${failures.length} failed\n`);
process.exit(failures.length > 0 ? 1 : 0);
