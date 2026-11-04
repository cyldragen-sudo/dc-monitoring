/**
 * Regression coverage for layout contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createModel, select } from "./core.mjs";
let api = {};
try {
  api = await import("./layout.mjs");
} catch {}
const raw = JSON.parse(
  await readFile(
    new URL("../data/infrastructure-test-payload.json", import.meta.url),
    "utf8",
  ),
);
function model() {
  return createModel(structuredClone(raw));
}
function ready() {
  assert.equal(
    typeof api.rackSlots,
    "function",
    "Image layout not implemented",
  );
}
test("rack elevation has bottom-up unit positions and retains excluded hardware", () => {
  ready();
  const m = model();
  m.servers = new Map([[13, m.servers.get(13)]]);
  const rows = api.rackSlots(m, 8);
  assert.equal(rows.length, 6);
  const top = rows.find((x) => x.id === 11);
  assert.equal(top.top, 0);
  assert.equal(top.height, 100 / 42);
  const s = rows.find((x) => x.id === 13);
  assert.ok(Math.abs(s.top - 40.476190476190474) < 1e-8);
  assert.equal(s.height, 200 / 42);
  assert.equal(s.excluded, false);
  const hidden = rows.find((x) => x.id === 14);
  assert.equal(hidden.excluded, true);
  assert.equal(hidden.u_start, 4);
  assert.equal(
    rows.some((x) => x.kind === "pdu"),
    false,
  );
});
test("bottom and top boundary devices stay inside the rack; invalid ranges fail explicitly", () => {
  ready();
  const m = model();
  const d = m.devices.get(13);
  d.u_start = 1;
  let x = api.rackSlots(m, 8).find((x) => x.id === 13);
  assert.equal(x.top + x.height, 100);
  d.u_start = 42;
  assert.throws(() => api.rackSlots(m, 8), /unit|range/i);
});
test("campus and hall targets reference only source children", () => {
  ready();
  const m = model();
  const site = api.layout(m, select(m, "site", 1));
  assert.equal(site.hotspots.length, 2);
  assert.deepEqual(
    site.hotspots.map((x) => x.id),
    [2, 27],
  );
  const room = api.layout(m, select(m, "room", 2));
  assert.deepEqual(
    room.hotspots.map((x) => x.id),
    [8, 17],
  );
  assert.ok(room.image);
});
test("hall inventory scales independently from the two-room campus navigation", () => {
  ready();
  const m = model();
  m.racks.set(999, {
    id: 999,
    room_id: 2,
    key: "Extra rack",
    height_u: 42,
    occupied_u: 0,
  });
  const room = api.layout(m, select(m, "room", 2));
  assert.equal(room.image, null);
  assert.deepEqual(
    room.hotspots.map((x) => x.id),
    [8, 17, 999],
  );
  const site = api.layout(m, select(m, "site", 1));
  assert.equal(site.image, "assets/campus.png");
  m.rooms.set(998, { id: 998, site_id: 1, name: "Зал C" });
  assert.equal(api.layout(m, select(m, "site", 1)).image, null);
});
test("no matching servers keeps buildings reachable but disables every server slot", () => {
  ready();
  const m = model();
  m.servers.clear();
  const room = api.layout(m, select(m, "room", 2));
  assert.equal(room.hotspots.length, 2);
  assert.ok(room.hotspots.every((x) => x.state === "empty"));
  const rows = api.rackSlots(m, 8);
  assert.equal(rows.filter((x) => x.kind === "server" && x.excluded).length, 4);
});
test("room support inventory survives server filters without pulling in another room", () => {
  assert.equal(
    typeof api.supportEquipment,
    "function",
    "Room equipment visibility not implemented",
  );
  const m = model();
  m.servers.clear();
  const devices = api.supportEquipment(m, select(m, "room", 2));
  assert.equal(devices.length, 6);
  assert.deepEqual(devices.map((d) => d.kind).sort(), [
    "access_controller",
    "chiller",
    "crac",
    "fire_sensor",
    "storage",
    "ups",
  ]);
  assert.ok(devices.every((d) => d.room_id === 2 && d.rack_id === null));
  assert.equal(devices.find((d) => d.kind === "crac").state, "warning");
  assert.deepEqual(
    api.supportEquipment(m, select(m, "rack", 8)).map((d) => d.key),
    ["PDU-R12-A", "PDU-R12-B"],
  );
});
test("long displayed names stay compact and keep distinguishing endings; short labels unchanged", () => {
  assert.equal(
    typeof api.displayLabel,
    "function",
    "Compact labels not implemented",
  );
  assert.equal(api.displayLabel("Hall A"), "Hall A");
  const a = api.displayLabel(
    "Зал для размещения инфраструктуры обработки транзакций и резервного копирования A",
  );
  const b = api.displayLabel(
    "Зал для размещения инфраструктуры обработки транзакций и резервного копирования B",
  );
  assert.ok(Array.from(a).length <= 26);
  assert.ok(a.endsWith("A"));
  assert.ok(b.endsWith("B"));
  assert.notEqual(a, b);
});
test("persistent labels fan out adjacent bottom servers without clipping", () => {
  assert.equal(typeof api.labelPositions, "function");
  const result = api.labelPositions(
    [
      { id: 1, top: 88, height: 4 },
      { id: 2, top: 92, height: 4 },
      { id: 3, top: 96, height: 4 },
    ],
    300,
    36,
  );
  assert.deepEqual(
    result.labels.map((x) => x.y),
    [210, 246, 282],
  );
  assert.deepEqual(
    result.labels.map((x) => x.id),
    [1, 2, 3],
  );
  assert.equal(api.labelPositions([], 300, 36).labels.length, 0);
  const dense = api.labelPositions(
    [
      { id: 1, top: 0, height: 2 },
      { id: 2, top: 2, height: 2 },
    ],
    40,
    36,
  );
  assert.ok(dense.height >= 72);
});
