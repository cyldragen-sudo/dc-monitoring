/**
 * Pure interpretation of database-backed metric definitions. Values stay in
 * their source units (percent, degrees Celsius, watts, and disk/network units).
 * Validity bounds are inclusive; warning/critical thresholds are strictly above.
 * These helpers do not infer freshness from browser time: SQL already returns null
 * for unusable readings. A missing definition cannot establish a healthy state.
 */
/**
 * Return {value,state,fraction} without mutating inputs. Invalid/out-of-range
 * values produce null and unknown. A valid value without a definition stays visible
 * but unknown. fraction exists only when the definition has a usable numeric range.
 */
export function metricReading(value, definition) {
  const d = definition || {};
  const valid =
    Number.isFinite(value) &&
    (d.valid_min == null || value >= d.valid_min) &&
    (d.valid_max == null || value <= d.valid_max);
  if (!valid) return { value: null, state: "unknown", fraction: null };
  const state = !definition
    ? "unknown"
    : Number.isFinite(d.critical_above) && value > d.critical_above
      ? "critical"
      : Number.isFinite(d.warning_above) && value > d.warning_above
        ? "warning"
        : "healthy";
  return {
    value,
    state,
    fraction:
      Number.isFinite(d.valid_max) && d.valid_max > d.valid_min
        ? (value - d.valid_min) / (d.valid_max - d.valid_min)
        : null,
  };
}
/**
 * Split chronological history into contiguous valid segments with original
 * indices for SVG x positions. Statistics include known samples only; an entirely
 * missing series has null min/max/mean and no segments.
 */
export function historySeries(history, key, definition) {
  const segments = [],
    values = [];
  let segment = [];
  for (const [index, point] of history.entries()) {
    const v = metricReading(point[key], definition).value;
    if (v === null) {
      if (segment.length) segments.push(segment);
      segment = [];
    } else {
      values.push(v);
      segment.push({ index, value: v });
    }
  }
  if (segment.length) segments.push(segment);
  return {
    segments,
    min: values.length ? Math.min(...values) : null,
    max: values.length ? Math.max(...values) : null,
    mean: values.length
      ? values.reduce((a, b) => a + b, 0) / values.length
      : null,
  };
}
/**
 * Return an ascending attention rank: critical=0, warning=1, unknown=2,
 * maintenance=3, healthy=4. Incidents, unavailable readings and defined component
 * thresholds can worsen the reported server state, but never improve it.
 */
export function serverAttention(server, definitions = {}) {
  let rank =
    { critical: 0, warning: 1, unknown: 2, maintenance: 3, healthy: 4 }[
      server.state
    ] ?? 2;
  if (server.incident_count > 0 || server.incidents?.length)
    rank = Math.min(rank, 1);
  if (
    server.unavailable_metrics > 0 ||
    !Number.isFinite(server.cpu) ||
    !Number.isFinite(server.memory)
  )
    rank = Math.min(rank, 2);
  for (const [key, code] of [
    ["cpu", "cpu_pct"],
    ["memory", "memory_pct"],
    ["temperature", "inlet_c"],
    ["disk_used_pct", "disk_used_pct"],
    ["disk_c", "disk_c"],
    ["disk_busy_pct", "disk_busy_pct"],
  ])
    if (definitions[code] && key in server) {
      const r = metricReading(server[key], definitions[code]);
      rank = Math.min(
        rank,
        { critical: 0, warning: 1, unknown: 2, healthy: 4 }[r.state],
      );
    }
  return rank;
}
/**
 * Return the larger valid CPU/RAM percentage for selection tie-breaking.
 * The -1 sentinel sorts a server without a valid 0–100 reading below known loads.
 */
export function loadScore(s) {
  return Math.max(
    ...[s.cpu, s.memory].filter(
      (x) => Number.isFinite(x) && x >= 0 && x <= 100,
    ),
    -1,
  );
}
