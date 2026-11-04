/**
 * Pure helpers for the Issues and History pages. Their payloads contain named
 * objects rather than the compact scene tables. Time comparisons use ISO instants;
 * labels use Europe/Moscow. History controls crop an existing two-hour payload
 * without querying the server. Navigation carries only the known numeric report
 * parameters and keeps the report on the current FineReport origin.
 */
import { metricReading } from "./metrics.mjs";
export const UNITS = {
  percent: "%",
  C: "°C",
  celsius: "°C",
  bytes: "bytes",
  GiB: "GiB",
  W: "W",
  Mbps: "Mbps",
  "MiB/s": "MiB/s",
  ms: "ms",
  IOPS: "IOPS",
  count: "",
  boolean: "",
  rpm: "rpm",
  "errors/s": "/s",
  "packets/s": "pkt/s",
};
export const CATEGORY = {
  disk: "Disks",
  network: "Network",
  server: "Servers",
  equipment: "Facility equipment",
  incident: "Incidents",
};
export const timeLabel = (at) =>
  at
    ? new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Moscow",
        hour: "2-digit",
        minute: "2-digit",
      }).format(new Date(at))
    : "Unknown";
/**
 * Reuse validity/threshold rules and add the connected-port-down exception.
 * Unusable values remain unknown; this function never interpolates history.
 */
export function seriesState(series, value) {
  const r = metricReading(value, series);
  return r.state === "unknown"
    ? "unknown"
    : series.code === "net_link_up" && series.linked && r.value === 0
      ? "critical"
      : r.state;
}
/**
 * Pair the shared ISO timestamp axis with values and crop inclusively to the
 * requested minute interval ending at asOf. Missing array entries become null.
 */
export function periodPoints(times, values, asOf, minutes) {
  const end = Date.parse(asOf),
    start = end - minutes * 60000;
  return times
    .map((at, i) => ({ at, value: values[i] ?? null }))
    .filter((p) => Date.parse(p.at) >= start && Date.parse(p.at) <= end);
}
/**
 * Emit an initial non-healthy marker and each subsequent severity change.
 * The initial marker means already present at window start, not a known onset.
 */
export function transitions(series, points) {
  const events = [];
  let previous = null;
  points.forEach((p, i) => {
    const severity = seriesState(series, p.value);
    if ((i === 0 && severity !== "healthy") || (i > 0 && severity !== previous))
      events.push({
        at: p.at,
        severity,
        value: p.value,
        initial: i === 0,
        code: series.code,
        name: series.name,
      });
    previous = severity;
  });
  return events;
}
/**
 * Apply independent severity/category predicates and a case-insensitive English
 * substring search across identity, location, component, title and reason fields.
 */
export function filterProblems(
  rows,
  { severity = "all", category = "all", search = "" } = {},
) {
  const q = search.trim().toLocaleLowerCase("en");
  return rows.filter(
    (r) =>
      (severity === "all" || r.severity === severity) &&
      (category === "all" || r.category === category) &&
      (!q ||
        [r.key, r.part, r.title, r.site_name, r.room_name, r.rack_key, r.reason]
          .join(" ")
          .toLocaleLowerCase("en")
          .includes(q)),
  );
}
/**
 * Build a same-report link preserving the four scope filters. Page 3 sets the
 * scene device and part target and clears the legacy server target; page 5 sets
 * history device and series. Other pages receive scope only. Disk target_part is
 * a one-based selector; network target_part is a port ID.
 */
export function targetUrl(filters, target, page, origin) {
  const u = new URL("/webroot/decision/view/duchamp", origin);
  u.searchParams.set("viewlet", "DC_MONITORING%2FInfrastructure_Overview.fvs");
  u.searchParams.set("page_number", String(page));
  for (const k of ["p_system", "p_env", "p_software", "p_site"])
    u.searchParams.set(k, String(filters[k] || 0));
  if (page === 3) {
    u.searchParams.set(
      "p_scene_target",
      String(target.device_id || target.id || 0),
    );
    u.searchParams.set("p_scene_part", String(target.target_part || 0));
    u.searchParams.set("p_scene_server", "0");
  }
  if (page === 5) {
    u.searchParams.set(
      "p_history_device",
      String(target.device_id || target.id || 0),
    );
    u.searchParams.set("p_history_series", String(target.series_id || 0));
  }
  return u.href;
}
