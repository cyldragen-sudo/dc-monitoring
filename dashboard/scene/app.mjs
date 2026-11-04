/**
 * Browser entry point for the Infrastructure iframe and compact overview.
 * FineVIS supplies a base64 scene payload through location.hash and an optional
 * view=overview query parameter. The model owns data and the local state owns
 * drilldown; report links reload FineVIS when a broader site scope is required.
 * DOM content is built with textContent. Replaced visualizations release observers
 * through cleanup; invalid payloads show a retry message instead of partial data.
 */
import { switchSummary } from "./hardware-widgets.mjs";
import { networkHealth } from "./hardware.mjs";
import {
  createModel,
  decodePayload,
  initialState,
  select,
  parentState,
  stats,
  children,
  cardUrl,
  format,
  COLORS,
  STATUS,
} from "./core.mjs";
import {
  gauge,
  signal,
  trend,
  loadIndicator,
  problemBadges,
} from "./metric-widgets.mjs";
import { nextView } from "./navigation.mjs";
import { aggregateScope } from "./scope.mjs";
import { supportEquipment, displayLabel } from "./layout.mjs";
import { renderIllustration } from "./illustration.mjs";
import { statusLegend } from "./campus.mjs";
import { targetUrl } from "./operations-core.mjs";

const $ = (id) => document.getElementById(id),
  el = (tag, text, cls) => {
    const x = document.createElement(tag);
    if (text !== undefined) x.textContent = text;
    if (cls) x.className = cls;
    return x;
  };
let m, state, cleanup;
const overview =
  new URLSearchParams(location.search).get("view") === "overview";
document.body.classList.toggle("overview-mode", overview);
/**
 * Create a normal button with textContent and the supplied action callback.
 */
function button(text, action, cls) {
  const b = el("button", text, cls);
  b.type = "button";
  b.onclick = action;
  return b;
}
/**
 * Replace the application with a readable failure state and explicit retry.
 * Partially decoded or inconsistent inventory is never rendered as a valid scene.
 */
function error(message) {
  $("app").hidden = true;
  const box = $("error");
  box.hidden = false;
  box.replaceChildren(
    el("strong", "Infrastructure unavailable"),
    el("p", message),
    button("Retry", () => location.reload()),
  );
}
/**
 * Reload report page 3 with a chosen site, retaining system/environment/software
 * and clearing the legacy server target. A new SQL payload can then cover that site.
 */
function reportScene(siteId) {
  const u = new URL("/webroot/decision/view/duchamp", location.origin);
  u.searchParams.set("viewlet", "DC_MONITORING%2FInfrastructure_Overview.fvs");
  u.searchParams.set("page_number", "3");
  for (const k of ["p_system", "p_env", "p_software"])
    u.searchParams.set(k, String(m.filters[k] || 0));
  u.searchParams.set("p_site", String(siteId));
  u.searchParams.set("p_scene_server", "0");
  window.top.location.href = u.href;
}
/**
 * Navigate locally when the current payload covers the destination. Leaving a
 * site filter or explicit target deep link reloads FineVIS for a wider scope.
 * Invalid local targets are logged and leave the existing rendered view intact.
 */
function navigate(level, id = 0) {
  if (m.filters.p_scene_target && ["site", "network"].includes(level))
    return reportScene(level === "network" ? 0 : id);
  if (
    m.filters.p_site &&
    ((level === "site" && id !== m.filters.p_site) || level === "network")
  )
    return reportScene(level === "network" ? 0 : id);
  try {
    state = nextView(m, state, level, id);
    draw();
  } catch (e) {
    console.warn(e.message);
  }
}
/**
 * Resolve the current level’s human-readable name from validated inventory.
 */
function title() {
  if (state.level === "switch") return m.devices.get(state.deviceId).key;
  return state.level === "network"
    ? "DC network"
    : state.level === "site"
      ? m.sites.get(state.siteId).name
      : state.level === "room"
        ? m.rooms.get(state.roomId).name
        : state.level === "rack"
          ? "Rack " + m.racks.get(state.rackId).key
          : m.servers.get(state.serverId).key;
}
/**
 * Render a status label and color, falling back to unknown for unexpected codes.
 */
function statusNode(stateName) {
  const node = el(
    "div",
    "●  " + (STATUS[stateName] || STATUS.unknown),
    "status",
  );
  node.style.color = COLORS[stateName] || COLORS.unknown;
  return node;
}
/**
 * Create a top-frame report link to history for this inventory device.
 */
function historyLink(deviceId) {
  const a = el("a", "Metric history →", "secondary");
  a.href = targetUrl(m.filters, { device_id: deviceId }, 5, location.origin);
  a.target = "_top";
  return a;
}
/**
 * Populate the selected-server sidebar with source-defined gauges, hardware
 * capacity, placement, incidents and links to IT/history. Freshness warnings refer
 * to the SQL snapshot, and the selection reason describes local rack selection.
 */
function serverDetails(serverId) {
  const s = m.servers.get(serverId),
    d = m.devices.get(serverId);
  if (!s) return;
  const panel = $("details");
  panel.append(
    el("h3", "Selected server"),
    el("h2", s.key),
    statusNode(s.state),
  );
  panel.append(
    el(
      "p",
      m.racks.get(d.rack_id).key +
        " · U" +
        d.u_start +
        "–" +
        (d.u_start + d.u_height - 1),
      "sub",
    ),
  );
  const defs = m.data.metric_definitions || {};
  panel.append(
    el(
      "p",
      state.selectionReason || "Selected from IT details",
      "selection-reason",
    ),
  );
  const grid = el("div", undefined, "metric-grid");
  grid.append(
    gauge("CPU", s.cpu, defs.cpu_pct),
    gauge("RAM", s.memory, defs.memory_pct),
    signal("Power", s.power_w, "W", defs.power_w),
    signal("Inlet air", s.temperature, "°C", defs.inlet_c),
  );
  panel.append(grid);
  panel.append(
    el(
      "p",
      (s.model || "Server") +
        " · " +
        format(s.cpu_cores, "cores", 0) +
        " · " +
        format(s.memory_gib, "GiB", 0),
      "sub",
    ),
  );
  if (s.unavailable_metrics > 0)
    panel.append(el("p", "Some readings are stale or missing", "sub"));
  const actions = el("div", undefined, "server-actions");
  const link = el("a", "IT details →", "primary");
  link.href = cardUrl(m, s.id, location.href);
  link.target = "_top";
  actions.append(link);
  if (state.level !== "server")
    actions.append(
      button("Open server →", () => navigate("server", s.id), "secondary"),
    );
  panel.append(actions);
  panel.append(historyLink(s.id));
  for (const incident of s.incidents || []) {
    const box = el("div", undefined, "incident");
    box.append(el("b", incident.key), el("span", incident.title));
    panel.append(box);
  }
}
/**
 * Rebuild breadcrumbs, scope KPIs and the detail sidebar from model/state.
 * Scope maxima include coverage; physical occupancy and support equipment include
 * all inventory. Server and switch detail modes replace those summaries with
 * device-specific information. Lists retain excluded servers as disabled entries.
 */
function drawUI() {
  const isScope = !["server", "switch"].includes(state.level),
    scope = isScope ? aggregateScope(m, state) : stats(m, state);
  $("scene-title").textContent = title();
  $("scene-status").textContent =
    "● " +
    STATUS[scope.state] +
    (isScope && state.level !== "network"
      ? (scope.criticalCount ? " · critical: " + scope.criticalCount : "") +
        (scope.warningCount ? " · warnings: " + scope.warningCount : "") +
        (scope.missingCount ? " · no data: " + scope.missingCount : "") +
        (scope.equipmentIssues
          ? " · equipment: " + scope.equipmentIssues
          : "") +
        (scope.equipmentMissing
          ? " · equip. no data: " + scope.equipmentMissing
          : "")
      : "");
  $("scene-status").style.color = COLORS[scope.state];
  $("empty").hidden = scope.serverCount > 0;
  const bc = $("breadcrumbs");
  bc.replaceChildren(button("All DCs", () => navigate("network")));
  for (const [level, id, label] of [
    ["site", state.siteId, m.sites.get(state.siteId)?.name],
    ["room", state.roomId, m.rooms.get(state.roomId)?.name.split(" · ")[0]],
    ["rack", state.rackId, m.racks.get(state.rackId)?.key],
    [
      "server",
      state.level === "server" ? state.serverId : 0,
      m.servers.get(state.serverId)?.key,
    ],
  ])
    if (id) {
      const b = button(displayLabel(label), () => navigate(level, id));
      b.title = label;
      b.setAttribute("aria-label", label);
      bc.append(el("span", "/"), b);
    }
  if (state.level !== "network") {
    const p = parentState(m, state);
    const back = button("← Back", () =>
      navigate(p.level, p.rackId || p.roomId || p.siteId),
    );
    bc.prepend(back);
  }
  const metrics = state.rackId
    ? [
        ["Rack occupancy", scope.occupiedU + " / " + scope.capacity + " U"],
        ["Filtered servers", scope.serverCount],
        ["Server power", format(scope.powerKw, "kW", 2)],
        ["Max. inlet temperature", format(scope.maxTemp, "°C", 1)],
        ["Incidents", scope.incidentCount],
      ]
    : [
        ["Racks in scope", scope.rackCount],
        ["Filtered servers", scope.serverCount],
        ["Server power", format(scope.powerKw, "kW", 2)],
        ["Max. inlet temperature", format(scope.maxTemp, "°C", 1)],
        ["Incidents", scope.incidentCount],
      ];
  if (isScope)
    metrics.splice(
      2,
      0,
      ["CPU · maximum", scope.cpuLoad],
      ["RAM · maximum", scope.ramLoad],
    );
  $("kpis").classList.toggle("scope-kpis", isScope);
  $("kpis").replaceChildren(
    ...metrics.map(([label, value]) => {
      const k = el("div", undefined, "kpi");
      if (typeof value === "object" && value !== null) {
        k.classList.add("load-kpi");
        k.append(loadIndicator(label, value));
        const note = el(
          "span",
          "Readings " + value.known + " / " + value.total,
          "coverage",
        );
        k.append(note);
      } else k.append(el("span", label), el("strong", String(value)));
      return k;
    }),
  );
  const panel = $("details");
  panel.replaceChildren();
  if (state.level === "switch") {
    const device = m.devices.get(state.deviceId),
      defs = m.data.metric_definitions || {};
    panel.append(
      switchSummary(device, defs),
      historyLink(device.id),
      button("← Rack", () => navigate("rack", state.rackId), "secondary"),
    );
    const health = networkHealth(device, defs);
    $("scene-status").textContent = "● " + STATUS[health];
    $("scene-status").style.color = COLORS[health];
    $("empty").hidden = true;
    const values = [
      ["Ports", (device.ports || []).length],
      ["Connected", (device.ports || []).filter((p) => p.linked).length],
      ["Port speed", "25 Gbps"],
      ["CPU", format(device.metrics?.cpu_pct, "%")],
      ["Temperature", format(device.metrics?.switch_c, "°C")],
    ];
    $("kpis").replaceChildren(
      ...values.map(([k, v]) => {
        const e = el("div", undefined, "kpi");
        e.append(el("span", k), el("strong", String(v)));
        return e;
      }),
    );
    return;
  }
  if (state.level === "rack" || state.level === "server") {
    if (state.serverId) serverDetails(state.serverId);
    else
      panel.append(
        el("h2", "No server"),
        el("p", "No servers in this rack match the selected filters.", "sub"),
      );
    if (state.level === "rack") {
      const bar = el("div", undefined, "capacity"),
        fill = el("i");
      fill.style.width = (100 * scope.occupiedU) / scope.capacity + "%";
      bar.append(fill);
      panel.append(
        el("h3", "Occupancy · all devices"),
        el("div", "Free " + scope.freeU + " U"),
        bar,
        el("p", "Free units are shown as dark panels.", "sub"),
      );
    } else
      panel.append(
        button(
          "← Back to rack",
          () => navigate("rack", state.rackId),
          "secondary",
        ),
      );
  } else {
    panel.append(
      el(
        "h2",
        state.level === "network"
          ? "Sites"
          : state.level === "site"
            ? "Data halls"
            : "Hall racks",
      ),
      el(
        "p",
        "CPU/RAM show the maximum across selected servers. ≥ indicates incomplete data. Equipment includes all devices in scope.",
        "sub",
      ),
    );
  }
  if (state.level !== "server") {
    const list = el("div", undefined, "object-list");
    if (state.level === "rack") panel.append(el("h3", "Rack servers"));
    for (const item of children(m, state)) {
      const s = item.excluded
        ? null
        : item.level === "server"
          ? stats(m, select(m, item.level, item.id))
          : aggregateScope(m, select(m, item.level, item.id));
      const b = button("", () => navigate(item.level, item.id), "object");
      b.disabled = !!item.excluded;
      b.style.setProperty("--status", COLORS[s?.state || "empty"]);
      const name = el("strong");
      name.append(
        el("span", "●", "dot"),
        document.createTextNode(
          item.key && item.level !== "site" && item.level !== "room"
            ? item.key
            : item.name,
        ),
      );
      let subtitle = item.excluded
        ? "Outside the selected filters"
        : item.level === "server"
          ? "U" +
            item.u_start +
            "–" +
            (item.u_start + item.u_height - 1) +
            " · " +
            STATUS[s.state]
          : "Servers: " + s.serverCount + " · " + format(s.powerKw, "kW", 2);
      b.append(name, el("span", subtitle, "object-subtitle"));
      if (s && item.level !== "server") {
        const loads = el("span", undefined, "object-loads");
        loads.append(
          loadIndicator("CPU max.", s.cpuLoad),
          loadIndicator("RAM max.", s.ramLoad),
        );
        b.append(loads, problemBadges(s));
      }
      list.append(b);
    }
    panel.append(list);
  }
  const switches = [...m.devices.values()].filter(
    (d) =>
      d.kind === "switch" &&
      (state.rackId
        ? d.rack_id === state.rackId
        : state.roomId
          ? d.room_id === state.roomId
          : state.siteId
            ? m.rooms.get(d.room_id).site_id === state.siteId
            : false),
  );
  if (switches.length) {
    panel.append(el("h3", "Switches · " + switches.length));
    const list = el("div", undefined, "object-list");
    for (const d of switches) {
      const health = networkHealth(d, m.data.metric_definitions || {}),
        b = button("", () => navigate("switch", d.id), "object");
      b.style.setProperty("--status", COLORS[health]);
      b.append(
        el("strong", "● " + d.key),
        el(
          "span",
          STATUS[health] +
            " · " +
            (d.ports || []).filter((p) => p.linked).length +
            " / " +
            (d.ports || []).length +
            " ports connected",
        ),
      );
      list.append(b);
    }
    panel.append(list);
  }
  const equipment = supportEquipment(m, state);
  if (state.focusDeviceId) {
    const d = m.devices.get(state.focusDeviceId),
      focus = el("div", undefined, "focused-equipment");
    focus.append(
      el("h3", "Selected equipment"),
      el("h2", d.key),
      statusNode(d.state),
      historyLink(d.id),
    );
    panel.prepend(focus);
  }
  if (equipment.length) {
    panel.append(
      el("h3", state.level === "room" ? "Hall equipment" : "Rack power"),
    );
    for (const d of equipment) {
      const row = el("div", undefined, "equipment-row");
      row.append(
        el("strong", d.key),
        el(
          "span",
          {
            crac: "Cooling",
            ups: "UPS",
            storage: "Storage array",
            pdu: "Power distribution",
            fire_sensor: "Fire sensor",
            access_controller: "Access control",
            chiller: "Chiller",
          }[d.kind] || d.kind,
        ),
      );
      row.append(statusNode(d.state));
      panel.append(row);
    }
  }
  if (isScope && state.level === "rack") {
    const h = el("div", undefined, "rack-health-note");
    h.append(
      el("h3", "Rack issues"),
      problemBadges(scope),
      el(
        "p",
        "Servers follow the filters. Equipment includes all physical devices in the rack.",
        "sub",
      ),
    );
    panel.prepend(h);
  }
  panel.append(
    el(
      "div",
      "Snapshot: 21 Oct 2026 · 14:32 MSK. Metrics cover selected servers; occupancy includes all installed devices.",
      "legend",
    ),
  );
  panel.scrollTop = 0;
}
/**
 * Render overview or full infrastructure mode. Release old observers before
 * replacing the illustration, show CPU/RAM trends only for server detail, and
 * update the contextual interaction help and heading.
 */
function draw() {
  if (overview) {
    $("scene-title").textContent = "Site network";
    $("empty").hidden = true;
    cleanup?.();
    cleanup = renderIllustration(
      $("viewport"),
      m,
      select(m, "network"),
      (level, id) => reportScene(id),
      { compact: true },
    );
    document
      .querySelector(".scene-help")
      .replaceChildren(
        statusLegend(),
        el(
          "div",
          "Hover over a site to highlight it · click to open the data center",
          "campus-help",
        ),
      );
    return;
  }
  drawUI();
  const charts = $("trends");
  charts.replaceChildren();
  charts.hidden = state.level !== "server";
  $("viewport")
    .closest(".stage")
    .classList.toggle("has-trends", state.level === "server");
  if (state.level === "server") {
    const s = m.servers.get(state.serverId),
      d = m.data.metric_definitions || {};
    charts.append(
      trend("CPU", s.history || [], "cpu", d.cpu_pct),
      trend("RAM", s.history || [], "memory", d.memory_pct),
    );
  }
  cleanup?.();
  cleanup = renderIllustration($("viewport"), m, state, navigate);
  document.querySelector(".scene-help").textContent =
    state.level === "server"
      ? "Demo · illustrative thresholds · CPU/RAM history: 5-minute intervals"
      : "Select an object in the image or in the list on the right";
  $("eyebrow").textContent = {
    network: "SITE NETWORK",
    site: "BUILDING CUTAWAY",
    room: "RACK LAYOUT",
    rack: "RACK ELEVATION",
    server: "SERVER AND STORAGE",
    switch: "NETWORK EQUIPMENT",
  }[state.level];
  if (state.level === "network")
    document
      .querySelector(".scene-help")
      .replaceChildren(
        statusLegend(),
        el(
          "div",
          "Hover over a site to highlight it · click to open the data center",
          "campus-help",
        ),
      );
}
/**
 * Remove only the known designer-generated iframe title tooltip while retaining
 * an accessible name. FineVIS and the deployed iframe share the same origin.
 */
function clearHostTooltip() {
  // FineVIS copies the designer widget name into the same-origin iframe title.
  // Keep an accessible name without a native tooltip covering the telemetry.
  const host = window.frameElement;
  if (
    ["Interactive DC Infrastructure", "Interactive DC Network"].includes(
      host?.getAttribute("title"),
    )
  ) {
    host.setAttribute("aria-label", "Interactive DC infrastructure");
    host.setAttribute("title", "");
  }
}
/**
 * On startup or hashchange, decode and validate the entire new payload, choose
 * its initial deep-link state and redraw. Any failure shows the retry UI.
 */
function load() {
  clearHostTooltip();
  try {
    m = createModel(decodePayload(location.hash));
    state = initialState(m);
    $("error").hidden = true;
    $("app").hidden = false;
    draw();
  } catch (e) {
    console.error(e);
    error(
      "Could not load data. Open Infrastructure from the DC dashboard and try again.",
    );
  }
}
window.addEventListener("hashchange", load);
window.addEventListener("pagehide", () => cleanup?.());
load();
