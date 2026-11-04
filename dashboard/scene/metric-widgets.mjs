/**
 * Reusable DOM/SVG metric cards. SVG coordinates are local viewBox units and
 * scale with CSS; percent gauges/trends use a fixed 0–100 visual domain. All values
 * pass through metricReading, and missing history breaks lines rather than bridging
 * a gap. Labels, accessible names and tooltips explain units, thresholds and partial
 * coverage without changing the underlying source values.
 */
import { metricReading, historySeries } from "./metrics.mjs";
import { COLORS, format } from "./core.mjs";
const NS = "http://www.w3.org/2000/svg",
  labels = {
    healthy: "Normal",
    warning: "High",
    critical: "Critical",
    unknown: "No data",
  };
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
};
/**
 * Create SVG namespace elements; attributes are stringified and text is assigned
 * through textContent so labels are never interpreted as markup.
 */
function svg(tag, attrs = {}, text) {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
  if (text !== undefined) n.textContent = text;
  return n;
}
const point = (t) => [
  65 - 50 * Math.cos(Math.PI * t),
  65 - 50 * Math.sin(Math.PI * t),
];
/**
 * Describe a 50-unit-radius semicircle segment between normalized fractions.
 * The coordinate system is shared with the gauge marker and backdrop.
 */
function arc(a, b) {
  const p = point(a),
    q = point(b);
  return `M${p[0]} ${p[1]} A50 50 0 0 1 ${q[0]} ${q[1]}`;
}
/**
 * Render a percent semicircle in a 130×85 viewBox. Source thresholds color the
 * background ranges; a known normalized reading controls the arc and marker.
 * Unknown values show a dash with no fabricated arc.
 */
export function gauge(name, value, definition) {
  const reading = metricReading(value, definition),
    color = COLORS[reading.state];
  const card = el("div", "gauge-card");
  card.style.setProperty("--metric-color", color);
  const head = el("div", "gauge-heading");
  head.append(el("b", "", name), el("span", "", labels[reading.state]));
  card.append(head);
  const chart = svg("svg", {
    viewBox: "0 0 130 85",
    role: "img",
    "aria-label":
      name +
      ": " +
      format(reading.value, "%", 1) +
      " · " +
      labels[reading.state],
  });
  chart.append(
    svg("path", {
      d: arc(0, 1),
      fill: "none",
      stroke: "#4b4451",
      "stroke-width": 9,
    }),
  );
  if (reading.value !== null && reading.fraction !== null) {
    const a = Number.isFinite(definition?.warning_above)
        ? definition.warning_above / 100
        : 1,
      b = Number.isFinite(definition?.critical_above)
        ? definition.critical_above / 100
        : 1;
    for (const [start, end, c] of [
      [0, a, COLORS.healthy],
      [a, b, COLORS.warning],
      [b, 1, COLORS.critical],
    ])
      if (end > start)
        chart.append(
          svg("path", {
            d: arc(start, end),
            fill: "none",
            stroke: c,
            "stroke-width": 9,
            opacity: 0.28,
          }),
        );
    if (reading.fraction > 0)
      chart.append(
        svg("path", {
          d: arc(0, reading.fraction),
          fill: "none",
          stroke: color,
          "stroke-width": 9,
        }),
      );
    const p = point(reading.fraction);
    chart.append(
      svg("circle", {
        cx: p[0],
        cy: p[1],
        r: 4,
        fill: color,
        stroke: "#f2eff3",
        "stroke-width": 1,
      }),
    );
  }
  chart.append(
    svg(
      "text",
      {
        x: 65,
        y: 62,
        "text-anchor": "middle",
        fill: color,
        "font-size": 21,
        "font-weight": 700,
      },
      reading.value === null ? "—" : format(reading.value, "%", 1),
    ),
  );
  chart.append(
    svg("text", { x: 11, y: 82, fill: "#aaa3af", "font-size": 8 }, "0"),
    svg(
      "text",
      { x: 119, y: 82, "text-anchor": "end", fill: "#aaa3af", "font-size": 8 },
      "100%",
    ),
  );
  card.append(chart);
  const limits = Number.isFinite(definition?.warning_above)
    ? "Thresholds: >" +
      definition.warning_above +
      "% / >" +
      definition.critical_above +
      "%"
    : "No thresholds set";
  card.append(el("div", "gauge-limits", limits));
  return card;
}
/**
 * Render a scalar with its supplied source unit and optional threshold status.
 * Definitions without warning thresholds keep neutral text while preserving value.
 */
export function signal(name, value, unit, definition) {
  const r = metricReading(value, definition),
    card = el("div", "metric signal-metric");
  card.style.setProperty(
    "--metric-color",
    definition?.warning_above != null ? COLORS[r.state] : "#f2eff3",
  );
  card.append(el("span", "", name), el("b", "", format(r.value, unit, 1)));
  if (definition?.warning_above != null) {
    card.append(
      el(
        "small",
        "",
        r.state === "healthy"
          ? "Normal"
          : r.state === "unknown"
            ? "No data"
            : r.state === "critical"
              ? "Critical"
              : "Above normal",
      ),
    );
    card.title =
      "Thresholds: >" +
      definition.warning_above +
      " / >" +
      definition.critical_above +
      " " +
      unit;
  }
  return card;
}
/**
 * Render the one-hour percent trend in a 320×104 viewBox. Original sample indices
 * keep missing slots in time; separate segments prevent lines crossing gaps.
 * Thresholds, end/midpoint times and known-sample statistics share the same axis.
 */
export function trend(name, history, key, definition) {
  const series = historySeries(history, key, definition),
    r = metricReading(history.at(-1)?.[key], definition),
    color = COLORS[r.state];
  const card = el("section", "trend-card");
  const head = el("div", "trend-heading");
  head.append(
    el("b", "", name + " · 60 min"),
    el("span", "", format(r.value, "%", 1)),
  );
  head.lastChild.style.color = color;
  card.append(head);
  const plot = svg("svg", {
    viewBox: "0 0 320 104",
    role: "img",
    "aria-label":
      name +
      " over the last hour. " +
      (series.mean === null
        ? "No data"
        : "Minimum " +
          format(series.min, "%", 1) +
          ", mean " +
          format(series.mean, "%", 1) +
          ", maximum " +
          format(series.max, "%", 1)),
  });
  const y = (v) => 78 - v * 0.6,
    x = (i) => 29 + (i * 278) / Math.max(history.length - 1, 1);
  for (const v of [0, 50, 100]) {
    plot.append(
      svg("line", {
        x1: 29,
        x2: 307,
        y1: y(v),
        y2: y(v),
        stroke: "#514951",
        "stroke-width": 0.6,
      }),
      svg(
        "text",
        {
          x: 23,
          y: y(v) + 3,
          "text-anchor": "end",
          fill: "#a6a0ad",
          "font-size": 8,
        },
        v + "%",
      ),
    );
  }
  for (const [threshold, c] of [
    [definition?.warning_above, COLORS.warning],
    [definition?.critical_above, COLORS.critical],
  ])
    if (Number.isFinite(threshold))
      plot.append(
        svg("line", {
          x1: 29,
          x2: 307,
          y1: y(threshold),
          y2: y(threshold),
          stroke: c,
          "stroke-width": 0.7,
          "stroke-dasharray": "3 4",
          opacity: 0.65,
        }),
      );
  const lineColor = key === "cpu" ? "#7bcb9b" : "#76b5e4";
  for (const segment of series.segments) {
    const points = segment.map((p) => `${x(p.index)},${y(p.value)}`).join(" ");
    if (segment.length > 1)
      plot.append(
        svg("polygon", {
          points: `${x(segment[0].index)},78 ${points} ${x(segment.at(-1).index)},78`,
          fill: lineColor,
          opacity: 0.1,
        }),
        svg("polyline", {
          points,
          fill: "none",
          stroke: lineColor,
          "stroke-width": 1.8,
        }),
      );
    for (const p of segment) {
      const dot = svg("circle", {
        cx: x(p.index),
        cy: y(p.value),
        r: 2.3,
        fill: lineColor,
      });
      dot.append(
        svg(
          "title",
          {},
          history[p.index].time_label + " · " + format(p.value, "%", 1),
        ),
      );
      plot.append(dot);
    }
  }
  if (series.mean === null)
    plot.append(
      svg(
        "text",
        {
          x: 168,
          y: 50,
          "text-anchor": "middle",
          fill: "#aaa3af",
          "font-size": 12,
        },
        "No data",
      ),
    );
  for (const i of [
    ...new Set([0, Math.floor((history.length - 1) / 2), history.length - 1]),
  ])
    if (history[i])
      plot.append(
        svg(
          "text",
          {
            x: x(i),
            y: 96,
            "text-anchor":
              i === 0 ? "start" : i === history.length - 1 ? "end" : "middle",
            fill: "#aaa3af",
            "font-size": 8,
          },
          history[i].time_label,
        ),
      );
  card.append(
    plot,
    el(
      "div",
      "trend-stats",
      "min " +
        format(series.min, "%", 1) +
        "  ·  avg " +
        format(series.mean, "%", 1) +
        "  ·  max " +
        format(series.max, "%", 1),
    ),
  );
  return card;
}

/**
 * Render a percent maximum bar with explicit coverage. A partial maximum uses
 * ≥ in text and at least in its accessible name. A null fraction fills no bar;
 * the displayed null value remains an em dash rather than zero.
 */
export function loadIndicator(name, reading) {
  const wrap = el("span", "load-indicator");
  wrap.style.setProperty("--metric-color", COLORS[reading.state]);
  const header = el("span", "load-heading");
  header.append(
    el("span", "", name),
    el(
      "b",
      "",
      reading.value === null
        ? "—"
        : (reading.partial ? "≥ " : "") + format(reading.value, "%", 1),
    ),
  );
  const rail = el("span", "load-rail"),
    fill = el("i");
  fill.style.width =
    (reading.fraction === null ? 0 : 100 * reading.fraction) + "%";
  rail.append(fill);
  wrap.append(header, rail);
  wrap.title =
    reading.tooltip ||
    "Maximum current utilization across selected servers. Readings: " +
      reading.known +
      " of " +
      reading.total +
      (reading.partial
        ? " · Some readings are missing: the actual maximum may be higher."
        : "");
  wrap.setAttribute(
    "aria-label",
    name +
      ": " +
      (reading.value === null
        ? "no data"
        : (reading.partial ? "at least " : "") +
          format(reading.value, "%", 1)) +
      ". Readings " +
      reading.known +
      " of " +
      reading.total,
  );
  return wrap;
}
/**
 * Render nonzero issue counts, which may overlap (for example warning and missing
 * data). Equipment and incident counts have distinct meanings. Compact hotspots
 * omit incident chips; an empty set is described as No issues or No servers.
 */
export function problemBadges(scope, compact = false) {
  const row = el("span", "problem-badges");
  const entries = [
    ["Crit.", scope.criticalCount, "critical"],
    ["Warn.", scope.warningCount, "warning"],
    ["No data", scope.missingCount, "unknown"],
    ["Equipment", scope.equipmentIssues, scope.equipmentState],
    ["Equip. no data", scope.equipmentMissing, "unknown"],
  ];
  if (!compact) entries.push(["Inc.", scope.incidentCount, "warning"]);
  for (const [name, count, state] of entries)
    if (count) {
      const item = el("span", "problem-chip", name + " " + count);
      item.style.setProperty("--chip-color", COLORS[state]);
      item.title = name.startsWith("Equip")
        ? "All physical devices in scope except servers; independent of system / environment / software filters"
        : name === "No data"
          ? "Servers with missing, invalid or stale readings; warnings may also apply"
          : name === "Inc."
            ? "Unique active incidents affecting the selected servers"
            : "Number of selected servers";
      row.append(item);
    }
  if (!row.children.length) {
    const item = el(
      "span",
      "problem-chip",
      scope.serverCount ? "No issues" : "No servers",
    );
    item.style.setProperty(
      "--chip-color",
      COLORS[scope.serverCount ? "healthy" : "empty"],
    );
    row.append(item);
  }
  return row;
}
