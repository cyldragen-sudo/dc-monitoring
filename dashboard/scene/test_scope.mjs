/**
 * Regression coverage for scope contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createModel, select } from "./core.mjs";
let aggregateScope;
try {
  ({ aggregateScope } = await import("./scope.mjs"));
} catch {}
const raw = JSON.parse(
  await readFile(
    new URL("../data/infrastructure-test-payload.json", import.meta.url),
    "utf8",
  ),
);
const defs = {
  cpu_pct: {
    valid_min: 0,
    valid_max: 100,
    warning_above: 80,
    critical_above: 95,
  },
  memory_pct: {
    valid_min: 0,
    valid_max: 100,
    warning_above: 85,
    critical_above: 95,
  },
  inlet_c: {
    valid_min: -40,
    valid_max: 100,
    warning_above: 28,
    critical_above: 32,
  },
};
function model() {
  assert.equal(
    typeof aggregateScope,
    "function",
    "Scope health not implemented",
  );
  const d = structuredClone(raw);
  d.metric_definitions = defs;
  return createModel(d);
}
test("scope maxima preserve exact thresholds, partial coverage and zero", () => {
  const m = model();
  for (const s of m.servers.values()) {
    s.cpu = 0;
    s.memory = 0;
    s.temperature = 22;
    s.state = "healthy";
    s.incidents = [];
    s.incident_count = 0;
    s.unavailable_metrics = 0;
  }
  m.servers.get(13).cpu = 80;
  m.servers.get(14).cpu = null;
  m.servers.get(15).memory = 95;
  const a = aggregateScope(m, select(m, "rack", 8));
  assert.equal(a.cpuLoad.value, 80);
  assert.equal(a.cpuLoad.state, "healthy");
  assert.equal(a.cpuLoad.known, 3);
  assert.equal(a.cpuLoad.total, 4);
  assert.equal(a.cpuLoad.partial, true);
  assert.equal(a.ramLoad.state, "warning");
  assert.equal(a.missingCount, 1);
  m.servers.get(13).cpu = 80.1;
  assert.equal(
    aggregateScope(m, select(m, "rack", 8)).cpuLoad.state,
    "warning",
  );
  m.servers.get(13).cpu = 101;
  const b = aggregateScope(m, select(m, "rack", 8));
  assert.equal(b.cpuLoad.value, 0);
  assert.equal(b.cpuLoad.known, 2);
  assert.equal(b.missingCount, 2);
});
test("severity counts remain distinct, missing can overlap warning, incidents deduplicate", () => {
  const m = model();
  for (const s of m.servers.values()) {
    s.cpu = 10;
    s.memory = 10;
    s.temperature = 22;
    s.state = "healthy";
    s.incidents = [];
    s.incident_count = 0;
    s.unavailable_metrics = 0;
  }
  m.servers.get(13).cpu = 96;
  m.servers.get(14).memory = 90;
  m.servers.get(14).cpu = null;
  for (const id of [13, 14])
    m.servers.get(id).incidents = [{ key: "INC-1042" }];
  const a = aggregateScope(m, select(m, "rack", 8));
  assert.equal(a.state, "critical");
  assert.equal(a.criticalCount, 1);
  assert.equal(a.warningCount, 1);
  assert.equal(a.missingCount, 1);
  assert.equal(a.incidentCount, 1);
});
test("engineering issues follow physical hierarchy and never include server devices", () => {
  const m = model();
  m.devices.get(9).state = "critical";
  m.devices.get(11).state = "unknown";
  m.devices.get(14).state = "critical";
  const rack = aggregateScope(m, select(m, "rack", 8));
  assert.equal(rack.equipmentIssues, 1);
  assert.equal(rack.equipmentMissing, 1);
  assert.equal(rack.state, "critical");
  assert.equal(aggregateScope(m, select(m, "room", 2)).equipmentIssues, 2);
  assert.equal(aggregateScope(m, select(m, "site", 1)).equipmentIssues, 2);
  assert.equal(aggregateScope(m, select(m, "site", 54)).equipmentIssues, 0);
});
test("filter restrictions and empty/all-null states preserve physical equipment only", () => {
  const m = model();
  m.servers = new Map([[13, m.servers.get(13)]]);
  const a = aggregateScope(m, select(m, "site", 1));
  assert.equal(a.cpuLoad.total, 1);
  assert.equal(a.cpuLoad.value, 62);
  assert.equal(a.equipmentIssues, 1);
  m.servers.get(13).cpu = null;
  assert.equal(aggregateScope(m, select(m, "site", 1)).cpuLoad.value, null);
  m.servers.clear();
  const empty = aggregateScope(m, select(m, "site", 1));
  assert.equal(empty.state, "empty");
  assert.equal(empty.cpuLoad.value, null);
  assert.equal(empty.cpuLoad.total, 0);
  assert.equal(
    empty.criticalCount + empty.warningCount + empty.missingCount,
    0,
  );
  assert.equal(empty.equipmentIssues, 1);
  assert.equal(empty.incidentCount, 0);
});
