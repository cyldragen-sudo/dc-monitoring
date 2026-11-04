/**
 * Infrastructure view composition and responsive physical layouts. Renderers
 * create DOM nodes with textContent, overlay inventory positions on illustrations,
 * and return cleanup callbacks for ResizeObservers. Host code must invoke the
 * previous callback before replacing a view. Illustrations are decorative context;
 * filtered object lists and details remain available if an image fails to load.
 */
import { renderServerMonitoring, renderSwitch } from "./hardware-widgets.mjs";
import { layout, rackSlots, displayLabel, labelPositions } from "./layout.mjs";
import { COLORS, STATUS, format, select } from "./core.mjs";
import { metricReading } from "./metrics.mjs";
import { aggregateScope } from "./scope.mjs";
import { loadIndicator, problemBadges } from "./metric-widgets.mjs";
import { renderCampuses } from "./campus.mjs";
const el = (tag, cls, text) => {
  const x = document.createElement(tag);
  if (cls) x.className = cls;
  if (text !== undefined) x.textContent = text;
  return x;
};
/**
 * Create non-draggable artwork with alternative text. On load failure remove
 * the broken image and append a live status note; independent navigation survives.
 */
function image(src, alt, container) {
  const img = el("img", "render-image");
  img.src = src;
  img.alt = alt;
  img.draggable = false;
  img.onerror = () => {
    img.hidden = true;
    container.classList.add("image-missing");
    const note = el(
      "div",
      "image-error",
      "Image unavailable. Navigation and details are available in the list on the right.",
    );
    note.setAttribute("role", "status");
    container.append(note);
  };
  return img;
}
/**
 * Create an accessible button dispatching the supplied local navigation action.
 */
function action(label, run, cls) {
  const b = el("button", cls);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.onclick = run;
  return b;
}
/**
 * Fit a fixed-ratio board inside the host’s content box, excluding padding.
 * ResizeObserver keeps overlays aligned; cleanup disconnects it when the view ends.
 */
function artboard(host, ratio) {
  const board = el("div", "artboard");
  host.append(board);
  const fit = () => {
    const rect = host.getBoundingClientRect(),
      style = getComputedStyle(host);
    const width =
        rect.width -
        parseFloat(style.paddingLeft) -
        parseFloat(style.paddingRight),
      height =
        rect.height -
        parseFloat(style.paddingTop) -
        parseFloat(style.paddingBottom);
    const w = Math.max(0, Math.min(width, height * ratio));
    board.style.width = w + "px";
    board.style.height = w / ratio + "px";
  };
  const obs = new ResizeObserver(fit);
  obs.observe(host);
  fit();
  return { board, cleanup: () => obs.disconnect() };
}
/**
 * Render an actual rack elevation, U scale, inventory slots, PDU legend and
 * external labels. Slots are percentages of the rack plane; responsive SVG leaders
 * translate their centers into host pixels. Excluded servers remain visible but
 * disabled. The returned cleanup releases the rack resize observer.
 */
function renderRack(host, m, state, onNavigate) {
  const container = el("div", "rack-layout"),
    board = el("div", "artboard rack-board");
  container.append(board);
  host.append(container);
  board.append(
    image(
      "assets/rack.png",
      "Front view of the cabinet with equipment positioned from inventory data",
      board,
    ),
  );
  const rack = m.racks.get(state.rackId),
    slots = rackSlots(m, state.rackId),
    plane = el("div", "rack-slots");
  plane.style.setProperty("--unit", 100 / rack.height_u + "%");
  board.append(plane);
  // Rail numbers and free panels follow the actual capacity, not marks in the image.
  for (let u = 1; u <= rack.height_u; u++) {
    if (u === 1 || u % 2 === 0) {
      const tick = el("span", "unit-tick", String(u));
      tick.style.top = (100 * (rack.height_u - u + 0.5)) / rack.height_u + "%";
      plane.append(tick);
    }
  }
  for (const d of slots) {
    const isServer = d.kind === "server",
      s = m.servers.get(d.id),
      color = COLORS[d.excluded ? "empty" : s?.state || d.state || "unknown"];
    const label =
      d.key +
      " · U" +
      d.u_start +
      "–" +
      (d.u_start + d.u_height - 1) +
      (d.excluded ? " · outside the selected filters" : "");
    const slot = action(
      "Open " + label,
      () => onNavigate(isServer ? "server" : "switch", d.id),
      "rack-device " + (isServer ? "server-device" : d.kind + "-device"),
    );
    slot.style.top = d.top + "%";
    slot.style.height = d.height + "%";
    slot.style.setProperty("--status", color);
    slot.title = label;
    slot.dataset.deviceId = String(d.id);
    if (isServer) {
      slot.disabled = d.excluded;
      slot.classList.toggle("selected", d.id === state.serverId);
      const face = el("span", "unit-face"),
        vent = el("i", "unit-vent"),
        drives = el("span", "unit-drives");
      face.setAttribute("aria-hidden", "true");
      for (const disk of s?.disks || []) drives.append(el("i", "unit-drive"));
      face.append(vent, drives, el("span", "device-indicator"));
      slot.append(face);
    } else {
      slot.setAttribute("aria-label", label);
      const ports = el("div", "port-row");
      for (let i = 0; i < 16; i++) ports.append(el("i"));
      slot.append(ports);
    }
    plane.append(slot);
  }
  const pdus = [...m.devices.values()].filter(
    (d) => d.rack_id === state.rackId && d.kind === "pdu",
  );
  if (pdus.length) {
    const panel = el("div", "pdu-legend");
    panel.append(el("span", "caption", "RACK POWER"));
    for (const d of pdus) {
      const row = el("div", "pdu-row");
      row.style.setProperty("--status", COLORS[d.state] || COLORS.unknown);
      row.append(el("i", "dot", "●"), el("span", "", d.key));
      panel.append(row);
    }
    container.append(panel);
  }
  const NS = "http://www.w3.org/2000/svg",
    leaders = document.createElementNS(NS, "svg");
  leaders.classList.add("rack-leaders");
  leaders.setAttribute("aria-hidden", "true");
  container.append(leaders);
  const labels = slots
    .filter((d) => ["server", "switch"].includes(d.kind))
    .map((d) => {
      const s = m.servers.get(d.id),
        color = COLORS[d.excluded ? "empty" : s?.state || d.state || "unknown"];
      const range = "U" + d.u_start + "–" + (d.u_start + d.u_height - 1),
        label =
          d.key +
          " · " +
          range +
          (d.excluded ? " · outside the selected filters" : "");
      const button = action(
        "Open " + label,
        () => onNavigate(d.kind === "switch" ? "switch" : "server", d.id),
        "rack-label",
      );
      button.disabled = d.excluded;
      button.title = label;
      button.dataset.deviceId = String(d.id);
      button.classList.toggle("selected", d.id === state.serverId);
      button.style.setProperty("--status", color);
      const name = el("b", "", d.key),
        meta = el(
          "span",
          "",
          range +
            (d.excluded
              ? " · outside filter"
              : " · " + STATUS[s?.state || d.state || "unknown"]),
        );
      button.append(name, meta);
      container.append(button);
      const path = document.createElementNS(NS, "path");
      path.setAttribute("stroke", d.id === state.serverId ? "#cf7591" : color);
      path.setAttribute("opacity", d.excluded ? ".3" : ".7");
      leaders.append(path);
      return { ...d, button, path };
    });
  const fit = () => {
    const rect = host.getBoundingClientRect(),
      w = rect.width,
      h = Math.max(rect.height, labels.length * 30 + 100),
      wide = w > 620;
    container.style.height = h + "px";
    leaders.setAttribute("viewBox", `0 0 ${w} ${h}`);
    const fw = Math.min(((h - 40) * 2) / 3, w * 0.57),
      fh = fw * 1.5,
      left = wide ? w * 0.18 : 0,
      top = (h - fh) / 2;
    Object.assign(board.style, {
      width: fw + "px",
      height: fh + "px",
      left: left + "px",
      top: top + "px",
    });
    const labelLeft = Math.max(w * 0.56, left + fw * 0.76 + 24),
      labelWidth = w - labelLeft - 16;
    const labelTop = 48,
      labelHeight = h - 98;
    const positions = labelPositions(
      labels.map((d) => ({
        ...d,
        top:
          (100 *
            (top +
              fh * (0.082 + (0.83 * (d.top + d.height / 2)) / 100) -
              labelTop)) /
          labelHeight,
        height: 0,
      })),
      labelHeight,
      30,
    );
    for (const d of positions.labels) {
      d.y += labelTop;
      d.anchor += labelTop;
    }
    for (const d of positions.labels) {
      Object.assign(d.button.style, {
        left: labelLeft + "px",
        top: d.y + "px",
        width: labelWidth + "px",
      });
      const x = left + fw * 0.74,
        bend = x + Math.max(12, (labelLeft - x) * 0.55);
      d.path.setAttribute(
        "d",
        `M${x} ${d.anchor} H${bend - 9} L${bend + 9} ${d.y} H${labelLeft}`,
      );
    }
  };
  const observer = new ResizeObserver(fit);
  observer.observe(host);
  fit();
  const cleanup = () => observer.disconnect();
  return cleanup;
}
/**
 * Replace the previous DOM and dispatch by level to the appropriate renderer.
 * Return its cleanup callback. Compatible artboards get percent-positioned buttons;
 * changed inventory gets a schematic list rather than guessed image coordinates.
 */
export function renderIllustration(host, m, state, onNavigate, options = {}) {
  host.replaceChildren();
  host.className = "view-" + state.level;
  if (state.level === "rack") return renderRack(host, m, state, onNavigate);
  if (state.level === "server") return renderServerMonitoring(host, m, state);
  if (state.level === "switch") return renderSwitch(host, m, state, onNavigate);
  if (state.level === "room") return renderHall(host, m, state, onNavigate);
  const spec = layout(m, state),
    { board, cleanup } = artboard(host, spec.ratio);
  if (spec.image)
    board.append(
      image(
        spec.image,
        state.level === "server"
          ? "Server chassis illustration"
          : state.level === "site"
            ? "Illustrative building cutaway with two halls"
            : state.level === "room"
              ? "Illustrative hall view with two racks"
              : "Data center sites",
        board,
      ),
    );
  else {
    board.classList.add("schematic-fallback");
    board.append(
      el(
        "p",
        "fallback-note",
        "Inventory has changed. Select an object from the current list.",
      ),
    );
  }
  if (state.level === "network" && spec.image) {
    renderCampuses(board, m, spec.hotspots, onNavigate, options);
    return cleanup;
  }
  for (const item of spec.hotspots) {
    const label =
      item.level === "room"
        ? item.name.split(" · ")[0]
        : item.key && item.level !== "site"
          ? item.key
          : item.name;
    const b = action(
      "Open " + label,
      () => onNavigate(item.level, item.id),
      "hotspot " + item.level + "-hotspot",
    );
    b.style.setProperty("--status", COLORS[item.state]);
    if (spec.image) {
      b.style.left = item.x + "%";
      b.style.top = item.y + "%";
    }
    const scope = aggregateScope(m, select(m, item.level, item.id));
    const tag = el("span", "hotspot-label"),
      heading = el("span", "hotspot-heading");
    heading.append(
      el("i", "dot", "●"),
      el("b", "", displayLabel(label)),
      el("span", "chevron", "→"),
    );
    const loads = el("span", "hotspot-loads");
    loads.append(
      loadIndicator("CPU", scope.cpuLoad),
      loadIndicator("RAM", scope.ramLoad),
    );
    tag.append(heading, loads, problemBadges(scope, true));
    b.append(tag, el("span", "hotspot-target"));
    b.title =
      label +
      " · " +
      STATUS[item.state] +
      " · CPU/RAM: maximum across selected servers";
    board.append(b);
  }
  if (state.level === "server") {
    const s = m.servers.get(state.serverId),
      device = m.devices.get(state.serverId);
    const strip = el("div", "server-caption");
    strip.append(
      el("b", "", s.model || "Server"),
      el(
        "span",
        "",
        "U" +
          device.u_start +
          "–" +
          (device.u_start + device.u_height - 1) +
          " · " +
          format(s.cpu_cores, "cores", 0) +
          " · " +
          format(s.memory_gib, "GiB", 0),
      ),
    );
    board.append(strip);
    const thermal = el("div", "thermal-label");
    thermal.style.setProperty(
      "--status",
      COLORS[
        metricReading(s.temperature, m.data.metric_definitions?.inlet_c).state
      ],
    );
    thermal.append(
      el("span", "", "Inlet air"),
      el("b", "", format(s.temperature, "°C", 1)),
    );
    board.append(thermal);
  }
  return cleanup;
}

/**
 * Render a card for every inventory rack in the selected room, including a
 * miniature physical elevation and filtered CPU/RAM coverage. It needs no resize
 * observer, so the cleanup contract returns a no-op.
 */
function renderHall(host, m, state, onNavigate) {
  const grid = el("div", "hall-grid");
  host.append(grid);
  for (const r of [...m.racks.values()].filter(
    (r) => r.room_id === state.roomId,
  )) {
    const scope = aggregateScope(m, select(m, "rack", r.id)),
      card = action(
        "Open " + r.key,
        () => onNavigate("rack", r.id),
        "hall-rack",
      );
    card.style.setProperty("--status", COLORS[scope.state]);
    const head = el("div", "hall-rack-head");
    head.append(el("i", "dot", "●"), el("b", "", r.key), el("span", "", "→"));
    card.append(head);
    const mini = el("div", "mini-rack");
    mini.append(image("assets/rack.png", "Rack " + r.key, mini));
    const plane = el("div", "mini-slots");
    for (const d of rackSlots(m, r.id)) {
      const slot = el("i", d.kind === "server" ? "mini-server" : "mini-switch");
      slot.style.top = d.top + "%";
      slot.style.height = d.height + "%";
      slot.style.setProperty(
        "--status",
        COLORS[d.excluded ? "empty" : m.servers.get(d.id)?.state || d.state],
      );
      if (d.excluded) slot.classList.add("excluded");
      plane.append(slot);
    }
    mini.append(plane);
    card.append(mini);
    const loads = el("div", "hall-loads");
    loads.append(
      loadIndicator("CPU", scope.cpuLoad),
      loadIndicator("RAM", scope.ramLoad),
    );
    card.append(
      el(
        "small",
        "",
        scope.serverCount +
          " servers · " +
          r.occupied_u +
          "/" +
          r.height_u +
          " U",
      ),
      loads,
      problemBadges(scope, true),
    );
    grid.append(card);
  }
  return () => {};
}
