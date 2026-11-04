/**
 * DOM/SVG rendering for the three-campus network illustration. The SVG viewBox
 * is the original 1774 by 887 artwork coordinate space; silhouettes clip lighting
 * and define pointer targets so surrounding roads never become clickable. Labels
 * use relative percentages and source-backed scope health. Compact mode suppresses
 * metric badges for the report overview while preserving navigation and status.
 */
import { COLORS, STATUS, select } from "./core.mjs";
import { aggregateScope } from "./scope.mjs";
import { loadIndicator, problemBadges } from "./metric-widgets.mjs";

// Silhouettes of the three illustrated campuses, in the source image's coordinates.
// The same shape controls both the lighting and the pointer target; roads stay inert.
const CAMPUSES = [
  {
    left: 6,
    top: 20,
    width: 27,
    path: "M63 398 Q62 385 80 378 L241 314 L246 298 L432 225 L523 254 L554 247 L571 232 L606 240 L610 275 L646 294 L689 315 L718 313 L764 329 L770 360 L854 392 L943 421 Q960 426 957 442 L956 461 Q956 470 943 476 L506 677 L436 674 L66 428 Z",
  },
  {
    left: 65,
    top: 9,
    width: 29,
    path: "M883 222 Q886 213 912 204 L1034 157 L1078 140 L1181 109 L1215 120 L1245 106 L1301 125 L1315 141 L1345 137 L1391 158 L1403 192 L1469 217 L1560 254 L1617 279 Q1640 286 1636 309 L1631 326 L1312 439 L1265 437 L888 255 Q879 249 883 222 Z",
  },
  {
    left: 70,
    top: 62,
    width: 27,
    path: "M1061 582 L1095 566 L1148 525 L1213 502 L1260 486 L1310 453 L1354 462 L1410 468 L1467 495 L1520 522 L1521 549 L1565 568 L1610 585 L1644 605 L1714 626 Q1734 632 1727 650 L1719 672 L1424 809 L1372 807 L1066 619 Q1053 610 1061 582 Z",
  },
];
const el = (tag, cls, text) => {
  const x = document.createElement(tag);
  x.className = cls;
  if (text !== undefined) x.textContent = text;
  return x;
};
const svg = (tag, attrs = {}) => {
  const x = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [k, v] of Object.entries(attrs)) x.setAttribute(k, v);
  return x;
};

/**
 * Overlay each compatible site on the matching campus silhouette. Site order
 * comes from the payload, and each click/label dispatches the same site ID. Clips
 * use unique inventory IDs so SVG lighting stays isolated between objects.
 */
export function renderCampuses(
  board,
  m,
  items,
  onNavigate,
  { compact = false } = {},
) {
  board.classList.add("campus-board");
  items.forEach((item, i) => {
    const shape = CAMPUSES[i],
      scope = aggregateScope(m, select(m, "site", item.id));
    const group = el("div", "campus-object");
    group.dataset.siteId = item.id;
    group.style.setProperty("--status", COLORS[scope.state]);
    const layer = svg("svg", {
      viewBox: "0 0 1774 887",
      preserveAspectRatio: "none",
      "aria-hidden": "true",
      class: "campus-layer",
    });
    const defs = svg("defs"),
      clip = svg("clipPath", { id: "campus-clip-" + item.id });
    clip.append(svg("path", { d: shape.path }));
    defs.append(clip);
    layer.append(defs);
    const light = svg("g", { class: "campus-light" });
    light.append(
      svg("path", { d: shape.path, class: "campus-halo" }),
      svg("image", {
        href: "assets/network-scene.png",
        width: 1774,
        height: 887,
        "clip-path": "url(#campus-clip-" + item.id + ")",
        class: "campus-lit-image",
      }),
      svg("path", { d: shape.path, class: "campus-tint" }),
    );
    const hit = svg("path", { d: shape.path, class: "campus-hit" });
    hit.onclick = () => onNavigate("site", item.id);
    layer.append(light, hit);
    group.append(layer);
    const card = el("button", "campus-label");
    card.type = "button";
    card.setAttribute("aria-label", "Open " + item.name);
    card.onclick = () => onNavigate("site", item.id);
    Object.assign(card.style, {
      left: shape.left + "%",
      top: shape.top + "%",
      width: shape.width + "%",
    });
    const heading = el("span", "campus-heading");
    heading.append(
      el("i", "dot", "●"),
      el("b", "", item.name),
      el("span", "chevron", "→"),
    );
    card.append(heading, el("span", "campus-status", STATUS[scope.state]));
    if (!compact) {
      const loads = el("span", "hotspot-loads");
      loads.append(
        loadIndicator("CPU", scope.cpuLoad),
        loadIndicator("RAM", scope.ramLoad),
      );
      card.append(loads, problemBadges(scope, true));
    }
    group.append(card);
    board.append(group);
  });
}

/**
 * Create the four common operational status keys with text as well as color;
 * maintenance/empty states are still described by their individual object labels.
 */
export function statusLegend() {
  const legend = el("div", "status-legend");
  legend.setAttribute("aria-label", "Status legend");
  for (const [state, text] of [
    ["healthy", "Normal"],
    ["warning", "Warning"],
    ["critical", "Critical"],
    ["unknown", "No recent data"],
  ]) {
    const item = el("span", "");
    item.style.color = COLORS[state];
    item.append(el("i", "", "●"), document.createTextNode(text));
    legend.append(item);
  }
  return legend;
}
