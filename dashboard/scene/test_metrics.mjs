/**
 * Regression coverage for metrics contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
let api = {};
try {
  api = await import("./metrics.mjs");
} catch {}
const cpu = {
  valid_min: 0,
  valid_max: 100,
  warning_above: 80,
  critical_above: 95,
};
test("gauge colors honor source thresholds strictly and never render missing as zero", () => {
  assert.equal(typeof api.metricReading, "function");
  for (const [v, state] of [
    [0, "healthy"],
    [80, "healthy"],
    [80.1, "warning"],
    [95, "warning"],
    [95.1, "critical"],
    [null, "unknown"],
    [-1, "unknown"],
    [101, "unknown"],
  ])
    assert.equal(api.metricReading(v, cpu).state, state);
  assert.equal(api.metricReading(null, cpu).value, null);
  assert.equal(api.metricReading(62, cpu).fraction, 0.62);
});
test("history plot preserves null gaps and statistics use only known samples", () => {
  assert.equal(typeof api.historySeries, "function");
  const p = api.historySeries(
    [{ cpu: 20 }, { cpu: 30 }, { cpu: null }, { cpu: 90 }],
    "cpu",
    cpu,
  );
  assert.equal(p.segments.length, 2);
  assert.deepEqual(
    p.segments.map((s) => s.map((v) => v.index)),
    [[0, 1], [3]],
  );
  assert.equal(p.min, 20);
  assert.equal(p.max, 90);
  assert.ok(Math.abs(p.mean - 46.6666666667) < 1e-8);
  assert.equal(api.historySeries([{ cpu: null }], "cpu", cpu).mean, null);
});
