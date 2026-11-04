/**
 * Scope aggregation shared by cards, hotspots and infrastructure summaries.
 * Server metrics follow system/environment/software/site filters; facility and
 * network equipment follow the physical location. Maxima use known valid values
 * and expose coverage, so a partial maximum is a lower bound, never a zero fill.
 */
import { stats } from "./core.mjs";
import { metricReading, serverAttention } from "./metrics.mjs";
/**
 * Find the maximum valid reading, with known/total coverage and a partial flag.
 * The aggregate state is evaluated using the same source definition as each server.
 */
function load(servers, key, definition) {
  const readings = servers
    .map((s) => metricReading(s[key], definition))
    .filter((r) => r.value !== null);
  const value = readings.length
    ? Math.max(...readings.map((r) => r.value))
    : null;
  return {
    ...metricReading(value, definition),
    known: readings.length,
    total: servers.length,
    partial: readings.length > 0 && readings.length < servers.length,
  };
}
/**
 * Combine filtered server totals with all non-server equipment in the physical
 * scope. Server attention ranks determine critical/warning counts; missingCount
 * can overlap those counts. No selected servers yields empty even if equipment
 * is present. Equipment issues/missing counts remain independently visible.
 */
export function aggregateScope(m, state) {
  const base = stats(m, state),
    defs = m.data.metric_definitions || {},
    servers = base.servers;
  const ranks = servers.map((s) => serverAttention(s, defs));
  const missingCount = servers.filter(
    (s) =>
      s.state === "unknown" ||
      s.unavailable_metrics > 0 ||
      [
        ["cpu", "cpu_pct"],
        ["memory", "memory_pct"],
        ["temperature", "inlet_c"],
      ].some(([key, code]) => metricReading(s[key], defs[code]).value === null),
  ).length;
  const equipment = [...m.devices.values()].filter(
    (d) =>
      d.kind !== "server" &&
      (!state.rackId || d.rack_id === state.rackId) &&
      (!state.roomId || d.room_id === state.roomId) &&
      (!state.siteId || m.rooms.get(d.room_id)?.site_id === state.siteId),
  );
  const equipmentIssues = equipment.filter((d) =>
      ["critical", "warning"].includes(d.state),
    ).length,
    equipmentMissing = equipment.filter((d) => d.state === "unknown").length;
  const states = new Set([
    ...ranks.map(
      (r) => ["critical", "warning", "unknown", "maintenance", "healthy"][r],
    ),
    ...equipment.map((d) => d.state),
  ]);
  return {
    ...base,
    state: servers.length
      ? ["critical", "warning", "unknown", "maintenance", "healthy"].find((x) =>
          states.has(x),
        ) || "unknown"
      : "empty",
    cpuLoad: load(servers, "cpu", defs.cpu_pct),
    ramLoad: load(servers, "memory", defs.memory_pct),
    equipmentState:
      ["critical", "warning", "unknown", "maintenance", "healthy"].find((x) =>
        equipment.some((d) => d.state === x),
      ) || "healthy",
    criticalCount: ranks.filter((r) => r === 0).length,
    warningCount: ranks.filter((r) => r === 1).length,
    missingCount,
    equipmentIssues,
    equipmentMissing,
  };
}
