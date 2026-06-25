/**
 * Audit prefab collision vs catalog trigger/body defaults.
 * Run: node scripts/audit_prefab_catalog_sync.mjs
 */
import fs from "fs";
import path from "path";

const ROOT = path.resolve(import.meta.dirname, "..");
const cat = JSON.parse(
  fs.readFileSync(path.join(ROOT, "client/data/game_catalog.json"), "utf8")
);

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
  const r = parseFloat(m[1]);
  return { x: r * 2, y: r * 2, radius: r, type: "circle" };
}

function parseNodePos(text, nodePattern) {
  const re = new RegExp(
    nodePattern + `(?:[\\s\\S]*?position = Vector2\\(([^,]+), ([^)]+)\\))?`
  );
  const blockRe = new RegExp(nodePattern + "[\\s\\S]*?(?=\\[node |$)");
  const block = text.match(blockRe)?.[0] ?? "";
  const m = block.match(/position = Vector2\(([^,]+), ([^)]+)\)/);
  if (!m) return { x: 0, y: 0 };
  return { x: parseFloat(m[1]), y: parseFloat(m[2]) };
}

function approx(a, b, eps = 0.05) {
  return Math.abs(a - b) <= eps;
}

function matchRect(catalogShape, size, offset, margin = null) {
  if (!catalogShape || catalogShape.shape !== "rectangle") return false;
  const okSize =
    approx(catalogShape.size?.x ?? 0, size.x) &&
    approx(catalogShape.size?.y ?? 0, size.y);
  const okOffset =
    approx(catalogShape.offset?.x ?? 0, offset.x) &&
    approx(catalogShape.offset?.y ?? 0, offset.y);
  const okMargin =
    margin === null || approx(catalogShape.margin ?? 0, margin);
  return okSize && okOffset && okMargin;
}

function collectByKind(kind) {
  const items = [];
  for (const [levelId, level] of Object.entries(cat.levels ?? {})) {
    for (const [id, obj] of Object.entries(level.objects ?? {})) {
      if (obj.kind === kind) {
        items.push({ levelId, id, obj });
      }
    }
  }
  return items;
}

function summarizeShapeField(items, field) {
  const groups = new Map();
  for (const { id, obj } of items) {
    const s = obj[field];
    if (!s) continue;
    const key = JSON.stringify(s);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(id);
  }
  return groups;
}

const prefabSpecs = [
  {
    name: "key",
    path: "client/prefabs/key.tscn",
    kind: "key",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_key");
      return size ? { size, offset: { x: 0, y: 0 } } : null;
    },
  },
  {
    name: "button",
    path: "client/prefabs/button.tscn",
    kind: "button",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_button");
      const offset = parseNodePos(
        t,
        '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."'
      );
      return size ? { size, offset } : null;
    },
  },
  {
    name: "push_box (online)",
    path: "client/prefabs/online_push_box.tscn",
    kind: "push_box",
    field: "body",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_push_box");
      return size ? { size, offset: { x: 0, y: 0 } } : null;
    },
  },
  {
    name: "oxygen_tank",
    path: "client/prefabs/oxygen_tank.tscn",
    kind: "oxygen_tank",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_oxygen_tank");
      return size ? { size, offset: { x: 0, y: 0 } } : null;
    },
  },
  {
    name: "torch",
    path: "client/prefabs/torch.tscn",
    kind: "torch",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_qv1na");
      return size ? { size, offset: { x: 0, y: 0 } } : null;
    },
  },
  {
    name: "jet_nozzle",
    path: "client/prefabs/jet_nozzle.tscn",
    kind: "water_jet_nozzle",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_water_jet_nozzle");
      const offset = parseNodePos(
        t,
        '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."'
      );
      return size ? { size, offset } : null;
    },
  },
  {
    name: "extendable_barrier",
    path: "client/prefabs/extendable_barrier.tscn",
    kind: "extendable_barrier",
    field: "trigger",
    getShape: (t) => {
      const size = parseRectShape(t, "RectangleShape2D_extendable_barrier");
      return size ? { size, offset: { x: 0, y: 0 } } : null;
    },
  },
  {
    name: "chainsaw (hazard circle)",
    path: "client/prefabs/chainsaw.tscn",
    kind: "chainsaw",
    field: "trigger",
    getShape: (t) => {
      const c = parseCircleShape(t, "CircleShape2D_qe8ir");
      if (!c) return null;
      return {
        type: "circle",
        radius: c.radius,
        offset: parseNodePos(
          t,
          '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."'
        ),
      };
    },
  },
];

console.log("=== PREFAB vs CATALOG AUDIT ===\n");

for (const spec of prefabSpecs) {
  const text = readTscn(spec.path);
  const prefabShape = spec.getShape(text);
  const items = collectByKind(spec.kind);
  if (items.length === 0) {
    console.log(`— ${spec.name}: no catalog entries for kind "${spec.kind}"`);
    continue;
  }

  const groups = summarizeShapeField(items, spec.field);
  console.log(`\n## ${spec.name} (${items.length} catalog entries, field: ${spec.field})`);
  console.log(
    `Prefab:`,
    prefabShape?.type === "circle"
      ? `circle r=${prefabShape.radius} offset (${prefabShape.offset.x}, ${prefabShape.offset.y})`
      : `rect ${prefabShape?.size?.x}×${prefabShape?.size?.y} offset (${prefabShape?.offset?.x}, ${prefabShape?.offset?.y})`
  );

  let allMatch = true;
  let mismatchCount = 0;
  for (const [json, ids] of groups.entries()) {
    const catalogShape = JSON.parse(json);
    let matches = false;
    if (prefabShape?.type === "circle") {
      matches =
        catalogShape.shape === "circle" &&
        approx(catalogShape.radius ?? 0, prefabShape.radius) &&
        approx(catalogShape.offset?.x ?? 0, prefabShape.offset.x) &&
        approx(catalogShape.offset?.y ?? 0, prefabShape.offset.y);
    } else if (prefabShape) {
      matches = matchRect(
        { ...catalogShape, shape: catalogShape.shape ?? "rectangle" },
        prefabShape.size,
        prefabShape.offset,
        catalogShape.margin ?? 0
      );
    }
    const label = matches ? "OK" : "MISMATCH";
    if (!matches) {
      allMatch = false;
      mismatchCount += ids.length;
    }
    console.log(
      `  [${label}] ${ids.length} entries — catalog: ${json.slice(0, 120)}${json.length > 120 ? "…" : ""}`
    );
    if (!matches && ids.length <= 3) {
      console.log(`    ids: ${ids.join(", ")}`);
    } else if (!matches) {
      console.log(`    ids: ${ids.slice(0, 3).join(", ")}… (+${ids.length - 3})`);
    }
  }
  console.log(
    allMatch
      ? `  → SYNC OK`
      : `  → NEEDS SYNC: ${mismatchCount}/${items.length} entries differ from prefab`
  );
}

// fragile_platform - not in catalog as standard kind, check if any
const fragileKinds = ["fragile_platform", "fragile"];
for (const k of fragileKinds) {
  const n = collectByKind(k).length;
  if (n) console.log(`\nNote: fragile kind "${k}" has ${n} catalog entries`);
}

// fragile platform prefab info
const fragile = readTscn("client/prefabs/fragile_platform.tscn");
const fpSize = parseRectShape(fragile, "RectangleShape2D_6104h");
const fpBodyPos = parseNodePos(
  fragile,
  '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."'
);
const fpDetectPos = parseNodePos(
  fragile,
  '\\[node name="CollisionShape2D" type="CollisionShape2D" parent="StandDetector"'
);
console.log("\n## fragile_platform.tscn (no standard catalog kind — scene-only object)");
console.log(
  `  Body/StandDetector: ${fpSize?.x}×${fpSize?.y}, body pos (${fpBodyPos.x}, ${fpBodyPos.y}), stand pos (${fpDetectPos.x}, ${fpDetectPos.y})`
);
console.log("  → Not in game_catalog sync pipeline unless added as object kind");

console.log("\n=== DONE ===\n");
