/**
 * Regression coverage for operations contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
import {
  periodPoints,
  transitions,
  seriesState,
  filterProblems,
  targetUrl,
} from "./operations-core.mjs";
import { createModel, initialState } from "./core.mjs";
const end = "2026-10-21T14:32:00+03:00",
  times = Array.from({ length: 25 }, (_, i) =>
    new Date(Date.parse(end) - (24 - i) * 300000).toISOString(),
  );
test("periods are inclusive, bounded and retain missing values", () => {
  for (const [minutes, count] of [
    [30, 7],
    [60, 13],
    [120, 25],
  ])
    assert.equal(
      periodPoints(
        times,
        times.map((_, i) => (i === 24 ? null : i)),
        end,
        minutes,
      ).length,
      count,
    );
  assert.equal(periodPoints(times, [], end, 30).at(-1).value, null);
});
test("existing incident at window start is not fabricated as new onset", () => {
  const s = {
    name: "Disk",
    code: "disk_c",
    warning_above: 45,
    critical_above: 55,
    valid_min: 0,
    valid_max: 100,
  };
  const e = transitions(s, [
    { at: times[0], value: 58 },
    { at: times[1], value: 58 },
    { at: times[2], value: null },
    { at: times[3], value: 40 },
  ]);
  assert.deepEqual(
    e.map((x) => [x.severity, x.initial]),
    [
      ["critical", true],
      ["unknown", false],
      ["healthy", false],
    ],
  );
});
test("disconnected unused ports are normal, linked down ports critical", () => {
  assert.equal(
    seriesState(
      { code: "net_link_up", linked: false, valid_min: 0, valid_max: 1 },
      0,
    ),
    "healthy",
  );
  assert.equal(
    seriesState(
      { code: "net_link_up", linked: true, valid_min: 0, valid_max: 1 },
      0,
    ),
    "critical",
  );
  assert.equal(
    seriesState({ code: "net_link_up", linked: true }, null),
    "unknown",
  );
});
test("search and category/severity intersect, unknown is not a zero measurement", () => {
  const rows = [
    { key: "SRV-1", part: "sdb", severity: "critical", category: "disk" },
    { key: "SRV-2", severity: "unknown", category: "server", value: null },
  ];
  assert.equal(
    filterProblems(rows, {
      search: "SDB",
      severity: "critical",
      category: "disk",
    }).length,
    1,
  );
  assert.equal(
    filterProblems(rows, { search: "sdb", category: "server" }).length,
    0,
  );
  assert.equal(filterProblems(rows, { severity: "unknown" })[0].value, null);
});
test("deep links retain all filters and exact device/series/part", () => {
  const f = { p_system: 612, p_env: 1, p_software: 1, p_site: 54 },
    target = { device_id: 91, series_id: 12456, target_part: 2 };
  const h = new URL(targetUrl(f, target, 5, "http://localhost:8075"));
  assert.equal(h.searchParams.get("p_history_device"), "91");
  assert.equal(h.searchParams.get("p_history_series"), "12456");
  for (const [k, v] of Object.entries(f))
    assert.equal(h.searchParams.get(k), String(v));
  const u = new URL(targetUrl(f, target, 3, "http://localhost:8075"));
  assert.equal(u.searchParams.get("p_scene_target"), "91");
  assert.equal(u.searchParams.get("p_scene_part"), "2");
});
test("exact server, switch port and engineering targets resolve correctly", () => {
  const data = {
    as_of: end,
    filters: { p_scene_target: 11, p_scene_part: 2 },
    sites: [{ id: 1 }],
    rooms: [{ id: 2, site_id: 1 }],
    racks: [{ id: 8, room_id: 2 }],
    devices: [
      { id: 11, kind: "server", rack_id: 8, room_id: 2 },
      { id: 12, kind: "switch", rack_id: 8, room_id: 2 },
      { id: 13, kind: "crac", rack_id: null, room_id: 2 },
    ],
    servers: [{ id: 11 }],
  };
  const m = createModel(data);
  assert.equal(initialState(m).level, "server");
  assert.equal(initialState(m).partTarget, 2);
  m.filters.p_scene_target = 12;
  m.filters.p_scene_part = 99;
  assert.equal(initialState(m).deviceId, 12);
  assert.equal(initialState(m).partTarget, 99);
  m.filters.p_scene_target = 13;
  assert.equal(initialState(m).roomId, 2);
  assert.equal(initialState(m).focusDeviceId, 13);
});
