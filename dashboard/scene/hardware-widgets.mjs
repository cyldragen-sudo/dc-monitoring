/**
 * DOM hardware views for filtered servers and physical switches. Disk arrays
 * and port maps are decoded by createModel before reaching this module. Capacity
 * uses GiB, latency ms, throughput MiB/s or Mbps, I/O IOPS and packet/error rates /s.
 * Selected disks use one-based payload part indices; selected ports use inventory
 * port IDs. No interaction here changes the dataset filters or writes telemetry.
 */
import { COLORS, STATUS, format } from "./core.mjs";
import { metricReading } from "./metrics.mjs";
import { diskHealth, portHealth, networkHealth } from "./hardware.mjs";
import { loadIndicator, signal } from "./metric-widgets.mjs";
const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};
const reading = (value, def) => ({
  ...metricReading(value, def),
  known: Number.isFinite(value) ? 1 : 0,
  total: 1,
  partial: false,
  tooltip: "Current value for this disk. Thresholds come from the data source.",
});
/**
 * Render one article per reported disk, including validated used/capacity/free
 * GiB, utilization bars, temperature and I/O. Free space is unknown if either
 * quantity is missing or used exceeds capacity. Missing inventory gets a message.
 */
export function diskCards(server, defs) {
  const grid = el("section", "disk-cards");
  grid.setAttribute("aria-label", "Disk monitoring");
  for (const d of server.disks || []) {
    const v = d.metrics || {},
      state = diskHealth(d, defs),
      card = el("article", "disk-card");
    card.style.setProperty("--status", COLORS[state]);
    const head = el("div", "disk-head");
    head.append(
      el("b", "", d.media + " · " + d.name),
      el("span", "", STATUS[state]),
    );
    card.append(head, el("div", "disk-mount", d.mount));
    const capacity = metricReading(
        v.disk_capacity_gib,
        defs.disk_capacity_gib,
      ).value,
      used = metricReading(v.disk_used_gib, defs.disk_used_gib).value;
    card.append(
      el(
        "p",
        "sub",
        "Used " +
          format(used, "GiB", 0) +
          " / " +
          format(capacity, "GiB", 0) +
          " · free " +
          format(
            capacity !== null && used !== null && used <= capacity
              ? capacity - used
              : null,
            "GiB",
            0,
          ),
      ),
    );
    const loads = el("div", "disk-loads");
    loads.append(
      loadIndicator("Used", reading(v.disk_used_pct, defs.disk_used_pct)),
      loadIndicator(
        "I/O utilization",
        reading(v.disk_busy_pct, defs.disk_busy_pct),
      ),
    );
    card.append(loads);
    const metrics = el("div", "disk-measures");
    for (const [label, code, unit] of [
      ["Temperature", "disk_c", "°C"],
      ["Latency", "disk_latency_ms", "ms"],
      ["Read", "disk_read_iops", "IOPS"],
      ["Write", "disk_write_iops", "IOPS"],
      ["Read", "disk_read_mib_s", "MiB/s"],
      ["Write", "disk_write_mib_s", "MiB/s"],
      ["SMART errors", "disk_smart_errors", ""],
    ]) {
      const metric = el("div", "disk-measure"),
        r = metricReading(v[code], defs[code]);
      metric.append(
        el("span", "", label),
        el("b", "", format(r.value, unit, 1)),
      );
      if (["disk_c", "disk_latency_ms", "disk_smart_errors"].includes(code))
        metric.style.color = COLORS[r.state];
      metrics.append(metric);
    }
    card.append(metrics);
    grid.append(card);
  }
  if (!server.disks?.length)
    grid.append(el("p", "sub", "No disk monitoring data"));
  return grid;
}
/**
 * Render the server face and disk cards, synchronize selected bays/cards, and
 * choose the requested one-based part target or the worst-health disk. Focusing
 * a bay can scroll its metric card into view without changing server selection.
 */
export function renderServerMonitoring(host, m, state) {
  const server = m.servers.get(state.serverId),
    device = m.devices.get(state.serverId),
    defs = m.data.metric_definitions || {},
    box = el("div", "server-monitor");
  const cards = diskCards(server, defs),
    face = el("section", "server-face");
  face.setAttribute("aria-label", "Server layout " + server.key);
  face.style.setProperty("--status", COLORS[server.state]);
  const brand = el("div", "server-brand");
  brand.append(
    el("b", "", server.key),
    el(
      "span",
      "",
      device.u_height +
        "U · " +
        format(server.cpu_cores, "cores", 0) +
        " · " +
        format(server.memory_gib, "GiB", 0),
    ),
  );
  const stateLabel = el(
    "span",
    "server-face-status",
    "● " + STATUS[server.state],
  );
  brand.append(stateLabel);
  face.append(brand);
  const bays = el("div", "server-bays");
  function selectDisk(index, scroll = false) {
    for (const [i, bay] of [...bays.children].entries()) {
      bay.classList.toggle("selected", i === index);
      bay.setAttribute("aria-pressed", String(i === index));
    }
    for (const [i, card] of [...cards.children].entries())
      card.classList.toggle("selected", i === index);
    if (scroll) {
      const card = cards.children[index];
      card.focus({ preventScroll: true });
      card.scrollIntoView({ block: "nearest", behavior: "auto" });
    }
  }
  for (const [index, d] of (server.disks || []).entries()) {
    const health = diskHealth(d, defs),
      bay = el("button", "server-bay");
    bay.type = "button";
    bay.style.setProperty("--status", COLORS[health]);
    bay.setAttribute(
      "aria-label",
      d.media + " " + d.name + " · " + STATUS[health] + " · Show metrics",
    );
    const label = el("span", "bay-label");
    label.append(
      el("b", "", d.media + " · " + d.name),
      el(
        "small",
        "",
        format(
          metricReading(d.metrics?.disk_capacity_gib, defs.disk_capacity_gib)
            .value,
          "GiB",
          0,
        ),
      ),
    );
    bay.append(
      el("i", "bay-grille"),
      label,
      el("span", "bay-status", "● " + STATUS[health]),
    );
    bay.onclick = () => selectDisk(index, true);
    bays.append(bay);
    cards.children[index].tabIndex = -1;
  }
  if (!server.disks?.length)
    bays.append(el("span", "sub", "No drive inventory data"));
  face.append(bays);
  box.append(
    face,
    el("h2", "", "Disks · capacity, temperature and I/O"),
    cards,
  );
  host.append(box);
  const priority = ["critical", "warning", "unknown", "maintenance", "healthy"];
  const first = (server.disks || [])
    .map((d, i) => ({ i, rank: priority.indexOf(diskHealth(d, defs)) }))
    .sort((a, b) => a.rank - b.rank)[0];
  if (first)
    selectDisk(
      state.partTarget && server.disks[state.partTarget - 1]
        ? state.partTarget - 1
        : first.i,
    );
  return () => {};
}
/**
 * Render inventory port buttons, the selected port detail and a full metric
 * table. A requested port ID wins; otherwise choose the worst-health port. Peer
 * server links are enabled only when the peer belongs to the filtered server map.
 */
export function renderSwitch(host, m, state, onNavigate) {
  const d = m.devices.get(state.deviceId),
    defs = m.data.metric_definitions || {},
    box = el("div", "switch-monitor");
  const face = el("div", "switch-face"),
    name = el("div", "switch-brand");
  name.append(el("b", "", d.key), el("span", "", "24 × 25GbE · ToR"));
  face.append(name);
  const ports = el("div", "switch-ports"),
    focus = el("div", "port-focus");
  function selectPort(p) {
    const v = p.metrics || {},
      health = portHealth(p, defs);
    focus.replaceChildren(
      el(
        "h2",
        "",
        p.name +
          " · " +
          (health === "free"
            ? "Unused"
            : health === "unknown"
              ? "No data"
              : v.net_link_up === 1
                ? "Link up"
                : "Link down"),
      ),
    );
    const peer = el("p", "sub", p.peer || "No cable connected");
    if (p.peer_id && m.servers.has(p.peer_id)) {
      const b = el("button", "peer-link", p.peer + " →");
      b.onclick = () => onNavigate("server", p.peer_id);
      peer.replaceChildren(b);
    }
    focus.append(peer);
    const grid = el("div", "port-metrics");
    for (const [label, code, unit] of [
      ["RX", "net_rx_mbps", "Mbps"],
      ["TX", "net_tx_mbps", "Mbps"],
      ["Errors", "net_errors_s", "/s"],
      ["Drops", "net_discards_s", "pkt/s"],
    ])
      grid.append(signal(label, v[code], unit, defs[code]));
    focus.append(grid);
    for (const b of ports.children)
      b.classList.toggle("selected", Number(b.dataset.portId) === p.id);
  }
  for (const p of d.ports || []) {
    const status = portHealth(p, defs),
      b = el("button", "network-port", p.name.replace("port-", ""));
    b.type = "button";
    b.dataset.portId = p.id;
    b.style.setProperty("--status", COLORS[status]);
    b.title = p.name + " · " + STATUS[status] + (p.peer ? " · " + p.peer : "");
    b.setAttribute("aria-label", b.title);
    b.onclick = () => selectPort(p);
    ports.append(b);
  }
  face.append(ports);
  box.append(
    face,
    el(
      "p",
      "sub",
      "Port colors indicate status. Select a port to view its connection, traffic and errors.",
    ),
    focus,
  );
  const table = el("table", "port-table"),
    head = el("tr");
  for (const label of [
    "Port / connection",
    "Status",
    "Utilization",
    "RX / TX, Mbps",
    "Errors / drops per second",
  ])
    head.append(el("th", "", label));
  const th = el("thead");
  th.append(head);
  table.append(th);
  const body = el("tbody");
  for (const p of d.ports || []) {
    const v = p.metrics || {},
      status = portHealth(p, defs),
      row = el("tr");
    row.style.setProperty("--status", COLORS[status]);
    const peer = el("td");
    const b = el("button", "port-link", p.name);
    b.onclick = () => selectPort(p);
    peer.append(b, el("small", "", p.peer || "Not connected"));
    row.append(
      peer,
      el("td", "port-status", STATUS[status]),
      el("td", "", format(v.net_util_pct, "%", 1)),
      el(
        "td",
        "",
        format(v.net_rx_mbps, "", 0) + " / " + format(v.net_tx_mbps, "", 0),
      ),
      el(
        "td",
        "",
        format(v.net_errors_s, "", 1) + " / " + format(v.net_discards_s, "", 1),
      ),
    );
    body.append(row);
  }
  table.append(body);
  box.append(table);
  host.append(box);
  const candidates = [...(d.ports || [])].sort(
    (a, b) =>
      ["critical", "warning", "unknown", "healthy", "free"].indexOf(
        portHealth(a, defs),
      ) -
      ["critical", "warning", "unknown", "healthy", "free"].indexOf(
        portHealth(b, defs),
      ),
  );
  if (candidates[0])
    selectPort(
      candidates.find((p) => p.id === state.partTarget) || candidates[0],
    );
  return () => {};
}
/**
 * Render whole-device switch metrics and explain that server scope filters
 * restrict server navigation while switch telemetry covers the physical device.
 */
export function switchSummary(d, defs) {
  const box = el("div", "switch-summary");
  box.append(
    el("h3", "", "Network equipment"),
    el("h2", "", d.key),
    el("p", "", STATUS[networkHealth(d, defs)]),
  );
  const grid = el("div", "metric-grid");
  for (const [label, code, unit] of [
    ["CPU", "cpu_pct", "%"],
    ["RAM", "memory_pct", "%"],
    ["Temperature", "switch_c", "°C"],
  ])
    grid.append(signal(label, d.metrics?.[code], unit, defs[code]));
  box.append(
    grid,
    el(
      "p",
      "sub",
      "Switch metrics cover the whole device. System, environment and software filters determine which servers can be opened.",
    ),
  );
  return box;
}
