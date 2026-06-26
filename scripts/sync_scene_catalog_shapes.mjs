/**
 * Sync catalog trigger/body shapes from level scenes (prefab base × instance scale).
 * Run: node scripts/sync_scene_catalog_shapes.mjs [--check]
 */
import fs from "fs";
import path from "path";

const ROOT = path.resolve(import.meta.dirname, "..");
const CHECK_ONLY = process.argv.includes("--check");

const CLIENT_CATALOG = path.join(ROOT, "client/data/game_catalog.json");
const SERVER_CATALOG = path.join(ROOT, "server/data/game_catalog.json");

function round(n) {
  return Math.round(n * 1000) / 1000;
}

function readTscn(rel) {
  return fs.readFileSync(path.join(ROOT, rel), "utf8");
}

function parseRectShape(text, subId) {
  const re = new RegExp(
    `\\[sub_resource type="RectangleShape2D" id="${subId}"\\][\\s\\S]*?size = Vector2\\(([^,]+), ([^)]+)\\)`
  );
  const m = text.match(re);
  if (!m) return null;
  return { x: parseFloat(m[1]), y: parseFloat(m[2]) };
}

function parseCircleShape(text, subId) {
  const re = new RegExp(
    `\\[sub_resource type="CircleShape2D" id="${subId}"\\][\\s\\S]*?radius = ([\\d.]+)`
  );
  const m = text.match(re);
  if (!m) return null;
  return parseFloat(m[1]);
}

function parseNodePosInBlock(block) {
  const m = block.match(/position = Vector2\(([^,]+), ([^)]+)\)/);
  if (!m) return { x: 0, y: 0 };
  return { x: parseFloat(m[1]), y: parseFloat(m[2]) };
}

function parseExtResources(text) {
  const map = {};
  for (const line of text.split("\n")) {
    const m = line.match(
      /\[ext_resource[^\n]*path="([^"]+)"[^\n]*id="([^"]+)"/
    );
    if (m) map[m[2]] = m[1];
  }
  return map;
}

function parseSceneNodes(text) {
  const nodes = [];
  const parts = text.split(/(?=\[node )/);
  for (const part of parts) {
    if (!part.startsWith("[node ")) continue;
    const header = part.split("\n")[0];
    const syncM = part.match(/^sync_id = "([^"]+)"/m);
    if (!syncM) continue;
    const instM = header.match(/instance=ExtResource\("([^"]+)"/);
    const scaleM = part.match(/^scale = Vector2\(([^,]+), ([^)]+)\)/m);
    nodes.push({
      sync_id: syncM[1],
      ext_id: instM?.[1] ?? "",
      scale: scaleM
        ? { x: parseFloat(scaleM[1]), y: parseFloat(scaleM[2]) }
        : { x: 1, y: 1 },
    });
  }
  return nodes;
}

const PREFAB_SPECS = {
  "res://prefabs/key.tscn": {
    field: "trigger",
    margin: 2,
    getBase: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_key");
      return size ? { shape: "rectangle", size, offset: { x: 0, y: 0 } } : null;
    },
  },
  "res://prefabs/button.tscn": {
    field: "trigger",
    margin: 0,
    getBase: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_button");
      const block = t.match(
        /\[node name="CollisionShape2D" type="CollisionShape2D" parent="\."[\s\S]*?(?=\[node |$)/
      )?.[0];
      const offset = parseNodePosInBlock(block ?? "");
      return size ? { shape: "rectangle", size, offset } : null;
    },
  },
  "res://prefabs/online_push_box.tscn": {
    field: "body",
    getBase: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_push_box");
      return size ? { shape: "rectangle", size, offset: { x: 0, y: 0 } } : null;
    },
  },
  "res://prefabs/oxygen_tank.tscn": {
    field: "trigger",
    margin: 4,
    getBase: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_oxygen_tank");
      return size ? { shape: "rectangle", size, offset: { x: 0, y: 0 } } : null;
    },
  },
  "res://prefabs/chainsaw.tscn": {
    field: "trigger",
    margin: 0,
    getBase: (t) => {
      const areaBlock = t.match(
        /\[node name="Area2D" type="Area2D"[\s\S]*?(?=\[node |$)/
      )?.[0];
      const colBlock = areaBlock?.match(
        /\[node name="CollisionShape2D"[\s\S]*?(?=\[node |$)/
      )?.[0];
      const radius = parseCircleShape(t, "CircleShape2D_1nbne");
      if (!radius) return null;
      const offset = parseNodePosInBlock(colBlock ?? "");
      return { shape: "circle", radius, offset };
    },
  },
};

const prefabCache = {};

function getPrefabSpec(resPath) {
  if (!PREFAB_SPECS[resPath]) return null;
  if (!prefabCache[resPath]) {
    const text = readTscn(resPath.replace("res://", "client/"));
    prefabCache[resPath] = PREFAB_SPECS[resPath].getBase(text);
  }
  return prefabCache[resPath];
}

function scaleShape(base, sx, sy, margin) {
  if (base.shape === "circle") {
    const trigger = {
      shape: "circle",
      radius: round(base.radius * sx),
      offset: { x: round(base.offset.x * sx), y: round(base.offset.y * sy) },
    };
    if (margin != null) trigger.margin = margin;
    return trigger;
  }
  const trigger = {
    shape: "rectangle",
    size: { x: round(base.size.x * sx), y: round(base.size.y * sy) },
    offset: { x: round(base.offset.x * sx), y: round(base.offset.y * sy) },
  };
  if (margin != null) trigger.margin = margin;
  return trigger;
}

function shapesEqual(a, b) {
  if (!a || !b) return false;
  if (a.shape !== b.shape) return false;
  if (a.shape === "circle") {
    return (
      round(a.radius) === round(b.radius) &&
      round(a.offset?.x ?? 0) === round(b.offset?.x ?? 0) &&
      round(a.offset?.y ?? 0) === round(b.offset?.y ?? 0) &&
      (a.margin ?? 0) === (b.margin ?? 0)
    );
  }
  return (
    round(a.size?.x ?? 0) === round(b.size?.x ?? 0) &&
    round(a.size?.y ?? 0) === round(b.size?.y ?? 0) &&
    round(a.offset?.x ?? 0) === round(b.offset?.x ?? 0) &&
    round(a.offset?.y ?? 0) === round(b.offset?.y ?? 0) &&
    (a.margin ?? 0) === (b.margin ?? 0)
  );
}

const catalog = JSON.parse(fs.readFileSync(CLIENT_CATALOG, "utf8"));
const changes = [];

for (const [levelId, level] of Object.entries(catalog.levels ?? {})) {
  const scenePath = String(level.scene_path ?? "").replace("res://", "client/");
  if (!scenePath || !fs.existsSync(path.join(ROOT, scenePath))) continue;

  const sceneText = readTscn(scenePath);
  const extMap = parseExtResources(sceneText);
  const sceneNodes = parseSceneNodes(sceneText);
  const bySyncId = new Map(sceneNodes.map((n) => [n.sync_id, n]));

  for (const [objId, obj] of Object.entries(level.objects ?? {})) {
    const specPath = bySyncId.get(objId);
    if (!specPath) continue;

    const resPath = extMap[specPath.ext_id];
    const prefabSpec = PREFAB_SPECS[resPath];
    const base = getPrefabSpec(resPath);
    if (!prefabSpec || !base) continue;

    const expected = scaleShape(
      base,
      specPath.scale.x,
      specPath.scale.y,
      prefabSpec.margin
    );
    const field = prefabSpec.field;
    const current = obj[field];
    if (shapesEqual(current, expected)) continue;

    changes.push({
      levelId,
      objId,
      field,
      from: current,
      to: expected,
    });
    if (!CHECK_ONLY) obj[field] = expected;
  }
}

console.log("=== SCENE → CATALOG SHAPE SYNC ===\n");
if (changes.length === 0) {
  console.log("No shape changes needed.");
} else {
  for (const c of changes) {
    console.log(
      `UPDATE ${c.levelId} ${c.objId} ${c.field}: ${JSON.stringify(c.from)} -> ${JSON.stringify(c.to)}`
    );
  }
  console.log(`\nTotal: ${changes.length} change(s)`);
}

if (!CHECK_ONLY && changes.length > 0) {
  const json = JSON.stringify(catalog, null, 2) + "\n";
  fs.writeFileSync(CLIENT_CATALOG, json);
  fs.writeFileSync(SERVER_CATALOG, json);
  console.log("Written client + server game_catalog.json");
}
