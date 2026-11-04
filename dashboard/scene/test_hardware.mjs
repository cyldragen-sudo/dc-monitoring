/**
 * Regression coverage for hardware contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { diskHealth, portHealth, networkHealth } from "./hardware.mjs";
const defs = {
  disk_used_pct: {
    valid_min: 0,
    valid_max: 100,
    warning_above: 80,
    critical_above: 95,
  },
  disk_c: {
    valid_min: -20,
    valid_max: 100,
    warning_above: 45,
    critical_above: 55,
  },
  disk_latency_ms: { valid_min: 0, warning_above: 20, critical_above: 40 },
  disk_busy_pct: {
    valid_min: 0,
    valid_max: 100,
    warning_above: 80,
    critical_above: 95,
  },
  disk_smart_errors: { valid_min: 0, warning_above: 0, critical_above: 5 },
  net_util_pct: {
    valid_min: 0,
    valid_max: 100,
    warning_above: 80,
    critical_above: 95,
  },
  net_errors_s: { valid_min: 0, warning_above: 0, critical_above: 10 },
  net_discards_s: { valid_min: 0, warning_above: 0, critical_above: 20 },
  net_link_up: { valid_min: 0, valid_max: 1 },
};
test("disk capacity, thermal, IO and SMART problems combine", () => {
  assert.equal(
    diskHealth(
      {
        metrics: {
          disk_used_pct: 97,
          disk_c: 58,
          disk_latency_ms: 42,
          disk_busy_pct: 98,
          disk_smart_errors: 1,
        },
      },
      defs,
    ),
    "critical",
  );
});
test("missing disk reading never becomes healthy zero", () => {
  assert.equal(
    diskHealth(
      {
        metrics: {
          disk_used_pct: 40,
          disk_c: null,
          disk_latency_ms: 3,
          disk_busy_pct: 20,
          disk_smart_errors: 0,
        },
      },
      defs,
    ),
    "unknown",
  );
});
test("unconnected ports are free, connected down ports are critical", () => {
  assert.equal(
    portHealth({ linked: false, metrics: { net_link_up: 0 } }, defs),
    "free",
  );
  assert.equal(
    portHealth({ linked: true, metrics: { net_link_up: 0 } }, defs),
    "critical",
  );
});
test("port errors propagate even at low utilization", () => {
  const port = {
    linked: true,
    metrics: {
      net_link_up: 1,
      net_util_pct: 20,
      net_errors_s: 3,
      net_discards_s: 0,
    },
  };
  assert.equal(portHealth(port, defs), "warning");
  assert.equal(
    networkHealth({ state: "healthy", ports: [port] }, defs),
    "warning",
  );
});
