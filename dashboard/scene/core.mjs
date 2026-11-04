/**
 * Infrastructure payload boundary, physical hierarchy and basic scope totals.
 * The iframe receives UTF-8 JSON encoded as base64 in its URL fragment; it never
 * connects to PostgreSQL. Inventory maps include physical objects even when the
 * filtered servers map excludes them. SQL owns snapshot/freshness decisions; this
 * module preserves null telemetry rather than manufacturing readings.
 */
export const COLORS = {
  healthy: "#7BCB9B",
  warning: "#E4B459",
  critical: "#ED747E",
  unknown: "#AAA5B1",
  maintenance: "#8AAFE0",
  free: "#67616F",
  empty: "#67616F",
};
export const STATUS = {
  healthy: "Healthy",
  warning: "Warning",
  critical: "Critical",
  unknown: "No recent data",
  maintenance: "Maintenance",
  free: "Unused",
  empty: "No matches",
};
const integer = (x) => Number.isSafeInteger(x) && x >= 0;
/**
 * Decode the fragment as base64 bytes, then UTF-8 JSON. Reject missing or
 * oversized input (two million characters) before allocating the decoded payload.
 * Malformed base64/UTF-8/JSON propagates to the entry point error UI.
 */
export function decodePayload(hash) {
  const raw = hash.replace(/^#/, "");
  if (!raw || raw.length > 2e6) throw Error("Missing scene payload");
  return JSON.parse(
    new TextDecoder().decode(
      Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)),
    ),
  );
}
/**
 * Expand compact column/value rows and shared history axes in place, then build
 * ID-indexed Maps. Numeric filters must be nonnegative safe integers; entity IDs
 * must also be nonzero and unique. Validate physical references before rendering.
 * The returned model retains data for metric definitions and original filters.
 */
export function createModel(data) {
  if (!data || !data.filters || !data.as_of)
    throw Error("Invalid scene payload");
  for (const [k, v] of Object.entries(data.filters))
    if (!integer(v)) throw Error("Invalid parameter " + k);
  // The live payload shares repeated column names and timestamps to keep the native iframe URL small.
  for (const key of ["sites", "rooms", "racks", "devices", "servers"])
    if (data[key + "_columns"])
      data[key] = data[key].map((row) =>
        Array.isArray(row)
          ? Object.fromEntries(
              data[key + "_columns"].map((name, i) => [name, row[i]]),
            )
          : row,
      );
  for (const server of data.servers || []) {
    if (data.history_times)
      server.history = (server.history || []).map((row, i) =>
        Array.isArray(row)
          ? {
              ...data.history_times[i],
              cpu: row[0],
              memory: row[1],
              temperature: row[2],
            }
          : row,
      );
    for (const disk of server.disks || [])
      if (Array.isArray(disk.metrics))
        disk.metrics = Object.fromEntries(
          data.disk_metric_codes.map((code, i) => [code, disk.metrics[i]]),
        );
  }
  for (const device of data.devices || [])
    for (const port of device.ports || [])
      if (Array.isArray(port.metrics))
        port.metrics = Object.fromEntries(
          data.port_metric_codes.map((code, i) => [code, port.metrics[i]]),
        );
  const m = { data, filters: data.filters };
  for (const key of ["sites", "rooms", "racks", "devices", "servers"]) {
    if (!Array.isArray(data[key])) throw Error("Missing " + key);
    m[key] = new Map();
    for (const item of data[key]) {
      if (!integer(item.id) || !item.id || m[key].has(item.id))
        throw Error("Invalid " + key + " ID");
      m[key].set(item.id, item);
    }
  }
  for (const r of m.rooms.values())
    if (!m.sites.has(r.site_id)) throw Error("Unknown site");
  for (const r of m.racks.values())
    if (!m.rooms.has(r.room_id)) throw Error("Unknown room");
  for (const d of m.devices.values())
    if (
      !m.rooms.has(d.room_id) ||
      (d.rack_id !== null && !m.racks.has(d.rack_id))
    )
      throw Error("Unknown rack or room");
  for (const s of m.servers.values())
    if (!m.devices.has(s.id)) throw Error("Unknown server");
  return m;
}
/**
 * Create a fresh hierarchy state for a requested inventory ID. Resolve rack, room
 * and site ancestry from inventory rather than trusting URL-provided parents.
 * Server selections must belong to the filtered servers map; switch selections
 * must identify a switch. Invalid or orphaned targets throw.
 */
export function select(m, level, id = 0) {
  const s = { level, siteId: 0, roomId: 0, rackId: 0, serverId: 0 };
  if (level === "network") return s;
  if (level === "switch") {
    if (m.devices.get(id)?.kind !== "switch")
      throw Error("Unknown network device");
    s.deviceId = id;
    s.rackId = m.devices.get(id).rack_id;
  } else if (level === "server") {
    if (!m.servers.has(id)) throw Error("Server is outside filter");
    s.serverId = id;
    s.rackId = m.devices.get(id).rack_id;
  } else if (level === "rack") s.rackId = id;
  else if (level === "room") s.roomId = id;
  else if (level === "site") s.siteId = id;
  else throw Error("Unknown level");
  if (s.rackId) {
    const r = m.racks.get(s.rackId);
    if (!r) throw Error("Unknown rack");
    s.roomId = r.room_id;
  }
  if (s.roomId) {
    const r = m.rooms.get(s.roomId);
    if (!r) throw Error("Unknown room");
    s.siteId = r.site_id;
  }
  if (!m.sites.has(s.siteId)) throw Error("Unknown site");
  return s;
}
/**
 * Resolve deep links in priority order: explicit scene target and component, IT
 * return server, selected site, then network. Non-server/switch targets focus their
 * room. The IT return opens the rack with that server selected, preserving context.
 */
export function initialState(m) {
  const target = m.devices.get(m.filters.p_scene_target);
  if (target) {
    if (target.kind === "server" && m.servers.has(target.id))
      return {
        ...select(m, "server", target.id),
        partTarget: m.filters.p_scene_part || 0,
      };
    if (target.kind === "switch")
      return {
        ...select(m, "switch", target.id),
        partTarget: m.filters.p_scene_part || 0,
      };
    if (target.kind !== "server")
      return { ...select(m, "room", target.room_id), focusDeviceId: target.id };
  }
  if (m.servers.has(m.filters.p_scene_server)) {
    const s = select(m, "server", m.filters.p_scene_server);
    s.level = "rack";
    return s;
  }
  return m.sites.has(m.filters.p_site)
    ? select(m, "site", m.filters.p_site)
    : select(m, "network");
}
/**
 * Move one physical level upward. Server/switch parents are their rack; site and
 * network both lead to the network overview. The new state clears component focus.
 */
export function parentState(m, s) {
  return ["server", "switch"].includes(s.level)
    ? select(m, "rack", s.rackId)
    : s.level === "rack"
      ? select(m, "room", s.roomId)
      : s.level === "room"
        ? select(m, "site", s.siteId)
        : select(m, "network");
}
/**
 * Return navigable children with their level tags. Rack inventory includes
 * excluded servers, marked disabled, so physical occupancy stays visible while
 * filtered telemetry and card navigation remain restricted.
 */
export function children(m, s) {
  if (s.level === "network")
    return [...m.sites.values()].map((x) => ({ ...x, level: "site" }));
  if (s.level === "site")
    return [...m.rooms.values()]
      .filter((x) => x.site_id === s.siteId)
      .map((x) => ({ ...x, level: "room" }));
  if (s.level === "room")
    return [...m.racks.values()]
      .filter((x) => x.room_id === s.roomId)
      .map((x) => ({ ...x, level: "rack" }));
  return [...m.devices.values()]
    .filter((x) => x.rack_id === s.rackId && x.kind === "server")
    .map((x) => ({ ...x, level: "server", excluded: !m.servers.has(x.id) }));
}
/**
 * Aggregate filtered servers in the selected physical ancestry. Occupancy sums
 * all installed devices through rack.occupied_u; incidents deduplicate by key.
 * Power converts W to kW only with complete server coverage. Temperature is the
 * maximum known reading; an empty server scope has state empty and null power.
 */
export function stats(m, s) {
  const racks = [...m.racks.values()].filter(
    (r) =>
      (!s.rackId || r.id === s.rackId) &&
      (!s.roomId || r.room_id === s.roomId) &&
      (!s.siteId || m.rooms.get(r.room_id).site_id === s.siteId),
  );
  const ids = new Set(racks.map((x) => x.id));
  const servers = [...m.servers.values()].filter(
    (x) => ids.has(x.rack_id) && (s.level !== "server" || x.id === s.serverId),
  );
  const states = new Set(
    servers.map((x) =>
      x.unavailable_metrics > 0 && x.state === "healthy" ? "unknown" : x.state,
    ),
  );
  const state = servers.length
    ? ["critical", "warning", "unknown", "maintenance", "healthy"].find((x) =>
        states.has(x),
      ) || "unknown"
    : "empty";
  const incidentIds = new Set(
    servers.flatMap((x) => (x.incidents || []).map((i) => i.key)),
  );
  const occupiedU = racks.reduce((n, r) => n + r.occupied_u, 0),
    capacity = racks.reduce((n, r) => n + r.height_u, 0);
  return {
    servers,
    serverCount: servers.length,
    rackCount: racks.length,
    occupiedU,
    freeU: capacity - occupiedU,
    capacity,
    state,
    incidentCount: incidentIds.size,
    powerKw:
      servers.length && servers.every((x) => Number.isFinite(x.power_w))
        ? servers.reduce((n, x) => n + x.power_w, 0) / 1000
        : null,
    maxTemp: servers.some((x) => Number.isFinite(x.temperature))
      ? Math.max(
          ...servers
            .filter((x) => Number.isFinite(x.temperature))
            .map((x) => x.temperature),
        )
      : null,
  };
}
/**
 * Build the IT page (FineVIS page 2) URL on an HTTP(S) origin. Preserve system,
 * environment and software scope, use the server’s actual site, reset pagination,
 * and set p_scene_server for returning to the rack. The encoded viewlet value is
 * intentional: URLSearchParams applies the transport encoding expected by FineVIS.
 */
export function cardUrl(m, id, base) {
  if (!m.servers.has(id)) throw Error("Server is outside filter");
  const origin = new URL(base);
  if (!["http:", "https:"].includes(origin.protocol))
    throw Error("Invalid origin");
  const url = new URL("/webroot/decision/view/duchamp", origin.origin),
    s = m.servers.get(id);
  url.searchParams.set(
    "viewlet",
    "DC_MONITORING%2FInfrastructure_Overview.fvs",
  );
  url.searchParams.set("page_number", "2");
  for (const k of ["p_system", "p_env", "p_software"])
    url.searchParams.set(k, String(m.filters[k] || 0));
  for (const [k, v] of Object.entries({
    p_site: s.site_id,
    p_server: id,
    p_page: 1,
    p_scene_server: id,
  }))
    url.searchParams.set(k, String(v));
  return url.href;
}
/**
 * Format finite numbers for English display with optional source units. Null,
 * undefined and non-finite values become No data, never a numeric zero.
 */
export function format(value, unit = "", digits = 1) {
  return Number.isFinite(value)
    ? new Intl.NumberFormat("en-GB", { maximumFractionDigits: digits }).format(
        value,
      ) + (unit ? " " + unit : "")
    : "No data";
}
