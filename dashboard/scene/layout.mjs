/**
 * Inventory-driven geometry without DOM access. Illustration anchors are
 * percentages of each source artboard. Fixed campus/hall artwork is used only when
 * the inventory cardinality matches; otherwise the renderer uses a schematic.
 * Rack positions derive from actual U capacity and reject overlaps or invalid
 * placement ranges instead of drawing misleading hardware.
 */
import { children, select } from "./core.mjs";
import { aggregateScope } from "./scope.mjs";

// Coordinates are normalized to the illustration, never the outer viewport.
const PLACES = {
  network: [
    { x: 27, y: 42 },
    { x: 70, y: 24 },
    { x: 79, y: 69 },
  ],
  site: [
    { x: 38, y: 36 },
    { x: 62, y: 30 },
  ],
  room: [
    { x: 34, y: 43 },
    { x: 64, y: 54 },
  ],
};
/**
 * Select compatible artwork and child hotspots. Health comes from aggregateScope;
 * percent anchors are attached only when a fixed illustration matches inventory.
 * The server image specification has no hotspots because component views own it.
 */
export function layout(m, state) {
  const items = children(m, state);
  let compatible = false,
    image = null,
    ratio = 1.5;
  if (state.level === "network") {
    compatible = items.length === 3;
    image = "assets/network-scene.png";
    ratio = 2;
  }
  if (state.level === "site") {
    compatible = items.length === 2;
    image = "assets/campus.png";
  }
  if (state.level === "room") {
    compatible = items.length === 2;
    image = "assets/hall.png";
  }
  if (state.level === "server")
    return { image: "assets/server.png", ratio: 1.5, hotspots: [] };
  return {
    image: compatible ? image : null,
    ratio,
    hotspots: items.map((item, i) => ({
      ...item,
      state: aggregateScope(m, select(m, item.level, item.id)).state,
      ...(compatible ? PLACES[state.level][i] : {}),
    })),
  };
}
/**
 * Convert inclusive bottom-up rack U ranges into top-down percentage rectangles.
 * Reject invalid capacity/ranges and overlapping occupied units across all device
 * kinds. Unplaced vertical equipment has null u_start and no horizontal slot.
 */
export function rackSlots(m, rackId) {
  const rack = m.racks.get(rackId);
  if (!rack || !Number.isInteger(rack.height_u) || rack.height_u < 1)
    throw Error("Invalid rack unit capacity");
  const used = new Set();
  return [...m.devices.values()]
    .filter((d) => d.rack_id === rackId && d.u_start !== null)
    .map((d) => {
      if (
        !Number.isInteger(d.u_start) ||
        !Number.isInteger(d.u_height) ||
        d.u_start < 1 ||
        d.u_height < 1 ||
        d.u_start + d.u_height - 1 > rack.height_u
      )
        throw Error("Invalid device unit range");
      for (let u = d.u_start; u < d.u_start + d.u_height; u++) {
        if (used.has(u)) throw Error("Overlapping unit range");
        used.add(u);
      }
      return {
        ...d,
        top:
          (100 * (rack.height_u - d.u_start - d.u_height + 1)) / rack.height_u,
        height: (100 * d.u_height) / rack.height_u,
        excluded: d.kind === "server" && !m.servers.has(d.id),
      };
    });
}
/**
 * Return floor equipment at room level and unnumbered rack equipment at rack
 * level. These objects are physical inventory and independent of server filters.
 */
export function supportEquipment(m, state) {
  const devices = [...m.devices.values()];
  if (state.level === "room")
    return devices.filter(
      (d) => d.room_id === state.roomId && d.rack_id === null,
    );
  if (state.level === "rack")
    return devices.filter(
      (d) => d.rack_id === state.rackId && d.u_start === null,
    );
  return [];
}
/**
 * Shorten long labels by Unicode code points while retaining their beginning
 * and ending. Callers keep full text in title/aria-label for accessibility.
 */
export function displayLabel(value) {
  const chars = Array.from(value);
  return chars.length <= 26
    ? value
    : chars.slice(0, 17).join("") + "…" + chars.slice(-8).join("");
}
/**
 * Lay out leader labels in vertical pixels with a minimum gap. Expand available
 * height when necessary, sort by physical center then ID, and use forward/backward
 * passes to keep labels ordered and inside the available height.
 */
export function labelPositions(items, height, gap = 36) {
  height = Math.max(height, items.length * gap);
  const labels = items
    .map((x) => ({ ...x, anchor: ((x.top + x.height / 2) * height) / 100 }))
    .sort((a, b) => a.anchor - b.anchor || a.id - b.id);
  for (let i = 0; i < labels.length; i++)
    labels[i].y = Math.max(
      labels[i].anchor,
      i ? labels[i - 1].y + gap : gap / 2,
    );
  for (let i = labels.length - 1; i >= 0; i--)
    labels[i].y = Math.min(
      labels[i].y,
      i < labels.length - 1 ? labels[i + 1].y - gap : height - gap / 2,
    );
  return { height, labels };
}
