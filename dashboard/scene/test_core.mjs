/**
 * Regression coverage for core contracts using synthetic in-memory fixtures.
 * Run with node --test; no DOM, FineReport installation or database is needed.
 * Fixtures deliberately distinguish physical inventory from selected telemetry
 * and include empty/invalid inputs where the associated contract requires them.
 * Legacy Cyrillic fixture values, where present, are test data rather than prose.
 */
import test from "node:test";
import assert from "node:assert/strict";
let api = {};
try {
  api = await import("./core.mjs");
} catch {}
const fixture = {
  as_of: "2026-10-21T14:32:00+03:00",
  filters: {
    p_system: 9,
    p_env: 1,
    p_software: 3,
    p_site: 1,
    p_scene_server: 11,
  },
  sites: [{ id: 1, name: "North" }],
  rooms: [{ id: 2, site_id: 1, name: "Hall A" }],
  racks: [{ id: 8, room_id: 2, height_u: 42, occupied_u: 10, key: "R12" }],
  devices: [
    {
      id: 11,
      key: "SRV-12-07",
      kind: "server",
      room_id: 2,
      rack_id: 8,
      u_start: 24,
      u_height: 2,
    },
    {
      id: 12,
      key: "excluded",
      kind: "server",
      room_id: 2,
      rack_id: 8,
      u_start: 4,
      u_height: 2,
    },
  ],
  servers: [
    {
      id: 11,
      key: "SRV-12-07",
      rack_id: 8,
      site_id: 1,
      power_w: 420,
      state: "warning",
      cpu: 62,
      memory: 71,
      temperature: 29.4,
      incident_count: 1,
      incidents: [{ key: "INC-1042" }],
    },
  ],
};
function model(data = fixture) {
  assert.equal(
    typeof api.createModel,
    "function",
    "3D state contract is not implemented",
  );
  return api.createModel(structuredClone(data));
}
test("return from IT opens the actual rack and preserves selected server", () => {
  const m = model();
  assert.deepEqual(api.initialState(m), {
    level: "rack",
    siteId: 1,
    roomId: 2,
    rackId: 8,
    serverId: 11,
  });
});
test("drilldown and back preserve physical ancestry", () => {
  const m = model();
  const s = api.select(m, "server", 11);
  assert.equal(s.roomId, 2);
  assert.equal(api.parentState(m, s).level, "rack");
  assert.equal(api.parentState(m, api.select(m, "rack", 8)).roomId, 2);
});
test("excluded server cannot silently open another card", () => {
  const m = model();
  assert.throws(() => api.select(m, "server", 12), /filter/i);
  assert.throws(() => api.cardUrl(m, 12, "http://localhost:8075"), /filter/i);
});
test("card link stays local and carries numeric scope", () => {
  const m = model();
  const u = new URL(
    api.cardUrl(
      m,
      11,
      "http://localhost:8075/webroot/DC_MONITORING_3D/index.html",
    ),
  );
  assert.equal(u.origin, "http://localhost:8075");
  assert.equal(u.pathname, "/webroot/decision/view/duchamp");
  assert.equal(u.searchParams.get("p_system"), "9");
  assert.equal(u.searchParams.get("p_software"), "3");
  assert.equal(u.searchParams.get("p_server"), "11");
  assert.equal(u.searchParams.get("page_number"), "2");
  assert.throws(() => api.cardUrl(m, 11, "javascript:alert(1)"));
});
test("inventory capacity differs from selected-server metrics", () => {
  const m = model();
  const s = api.stats(m, api.select(m, "rack", 8));
  assert.equal(s.serverCount, 1);
  assert.equal(s.occupiedU, 10);
  assert.equal(s.freeU, 32);
  assert.equal(s.powerKw, 0.42);
  assert.equal(s.state, "warning");
});
test("empty and partial telemetry cannot appear healthy or zero power", () => {
  const a = structuredClone(fixture);
  a.servers = [];
  a.filters.p_scene_server = 0;
  const m = model(a);
  assert.equal(api.stats(m, api.initialState(m)).state, "empty");
  assert.equal(api.stats(m, api.initialState(m)).powerKw, null);
  a.servers = [
    ...fixture.servers,
    { id: 12, rack_id: 8, power_w: null, state: "healthy", incidents: [] },
  ];
  const b = model(a);
  assert.equal(api.stats(b, api.initialState(b)).powerKw, null);
});
test("invalid payload and orphaned references fail explicitly", () => {
  model();
  assert.throws(() => api.decodePayload("not-json"));
  const a = structuredClone(fixture);
  a.devices[0].rack_id = 999;
  assert.throws(() => api.createModel(a), /rack/i);
  const b = structuredClone(fixture);
  b.filters.p_env = "1&admin=true";
  assert.throws(() => api.createModel(b), /parameter/i);
});
