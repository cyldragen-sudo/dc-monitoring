/**
 * Regression coverage for navigation contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createModel, select } from "./core.mjs";
let nextView;
try {
  ({ nextView } = await import("./navigation.mjs"));
} catch {}
const raw = JSON.parse(
  await readFile(
    new URL("../data/infrastructure-test-payload.json", import.meta.url),
    "utf8",
  ),
);
test("return from a non-default server preserves that exact server in its rack", () => {
  assert.equal(
    typeof nextView,
    "function",
    "Return selection preservation not implemented",
  );
  const m = createModel(structuredClone(raw));
  const s = nextView(m, select(m, "server", 14), "rack", 8);
  assert.equal(s.serverId, 14);
  assert.equal(s.rackId, 8);
});
test("rack selection cannot retain a filtered-out or foreign-rack server", () => {
  assert.equal(
    typeof nextView,
    "function",
    "Return selection preservation not implemented",
  );
  const m = createModel(structuredClone(raw));
  const prior = select(m, "server", 14);
  m.servers.delete(14);
  assert.equal(nextView(m, prior, "rack", 8).serverId, 13);
  const other = nextView(m, prior, "rack", 17);
  assert.notEqual(other.serverId, 14);
  assert.equal(m.servers.get(other.serverId).rack_id, 17);
  m.servers.clear();
  assert.equal(nextView(m, prior, "rack", 8).serverId, 0);
});
test("automatic choice ranks critical before warning and missing before healthy regardless of source order", () => {
  const m = createModel(structuredClone(raw));
  m.servers.get(14).state = "critical";
  m.servers.get(14).cpu = 1;
  assert.equal(nextView(m, select(m, "room", 2), "rack", 8).serverId, 14);
  m.servers.get(14).state = "healthy";
  m.servers.get(13).state = "healthy";
  m.servers.get(13).incidents = [];
  m.servers.get(13).incident_count = 0;
  m.servers.get(15).state = "unknown";
  assert.equal(nextView(m, select(m, "room", 2), "rack", 8).serverId, 15);
});
test("healthy default is highest CPU or RAM with deterministic tie ordering", () => {
  const m = createModel(structuredClone(raw));
  for (const s of m.servers.values()) {
    s.state = "healthy";
    s.incidents = [];
    s.incident_count = 0;
    s.unavailable_metrics = 0;
    s.cpu = 10;
    s.memory = 20;
  }
  m.servers.get(16).memory = 88;
  assert.equal(nextView(m, select(m, "room", 2), "rack", 8).serverId, 16);
  m.servers = new Map([...m.servers].reverse());
  assert.equal(nextView(m, select(m, "room", 2), "rack", 8).serverId, 16);
  m.servers.get(16).memory = 20;
  assert.equal(nextView(m, select(m, "room", 2), "rack", 8).serverId, 14);
});
