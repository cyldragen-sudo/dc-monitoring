/**
 * Browser entry point shared by the Issues and History iframes. view=history
 * selects history; the default renders the operational queue. A base64 JSON fragment
 * provides a read-only snapshot, and hashchange replaces it. Local search/category/
 * severity and period/component controls operate only on that snapshot. SVG charts
 * show gaps for nulls, source thresholds, observed state changes and incident times;
 * they do not claim an exact incident onset from the bounded sample window.
 */
import { decodePayload, COLORS, STATUS, format } from "./core.mjs";
import {
  UNITS,
  CATEGORY,
  timeLabel,
  seriesState,
  periodPoints,
  transitions,
  filterProblems,
  targetUrl,
} from "./operations-core.mjs";
const el = (tag, cls, text) => {
  const x = document.createElement(tag);
  if (cls) x.className = cls;
  if (text !== undefined) x.textContent = text;
  return x;
};
const NS = "http://www.w3.org/2000/svg";
/**
 * Create SVG namespace elements with plain-text labels and supplied attributes.
 */
function svg(tag, attrs = {}, text) {
  const x = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) x.setAttribute(k, v);
  if (text !== undefined) x.textContent = text;
  return x;
}
const root = document.getElementById("ops");
let data,
  period = 60,
  part = "",
  filters = { severity: "all", category: "all", search: "" };
/**
 * Create an accessible native button for a local, read-only control.
 */
function button(text, run, cls = "") {
  const b = el("button", cls, text);
  b.type = "button";
  b.onclick = run;
  return b;
}
/**
 * Create a top-frame FineVIS report link retaining the payload’s scope filters.
 */
function link(text, target, page) {
  const a = el("a", "ops-link", text);
  a.href = targetUrl(data.filters, target, page, location.origin);
  a.target = "_top";
  return a;
}
/**
 * Render a textual operational state with the shared color convention.
 */
function status(state) {
  const n = el("span", "ops-status", "● " + (STATUS[state] || STATUS.unknown));
  n.style.color = COLORS[state];
  return n;
}
/**
 * Join available site, short room and rack labels without empty separators.
 */
function locationText(r) {
  return [r.site_name, r.room_name?.split(" · ")[0], r.rack_key]
    .filter(Boolean)
    .join(" / ");
}
/**
 * Map stored unit codes to readable English symbols and format unknowns safely.
 */
function value(v, unit) {
  return format(v, UNITS[unit] ?? unit, 1);
}
/**
 * Distinguish detected incidents, measured threshold onset and stale-data onset.
 * ongoing_before_window explicitly marks unknown onset before the bounded window.
 */
function problemSince(r) {
  return !r.since
    ? "Time unknown"
    : r.ongoing_before_window
      ? "Present by " + timeLabel(r.since) + " · onset unknown"
      : (r.category === "incident"
          ? "Detected "
          : r.severity === "unknown"
            ? "Data missing since "
            : "Observed since ") + timeLabel(r.since);
}
/**
 * Render issue counts, local severity/category/search controls and the queue.
 * Counts describe issue rows rather than unique devices; the result also shows
 * unique devices. Equipment/history links carry the row’s device/component IDs.
 */
function problems() {
  root.replaceChildren();
  root.className = "problems-page";
  const rows = data.problems || [],
    counts = el("section", "problem-counts");
  counts.setAttribute("aria-label", "Issue summary");
  for (const [key, label] of [
    ["all", "All issues"],
    ["critical", "Critical"],
    ["warning", "Warnings"],
    ["unknown", "No data"],
  ]) {
    const b = button(
      "",
      () => {
        filters.severity = key;
        problems();
      },
      "problem-count",
    );
    b.classList.toggle("active", filters.severity === key);
    b.setAttribute("aria-pressed", String(filters.severity === key));
    b.append(
      el("span", "", label),
      el(
        "strong",
        "",
        String(
          key === "all"
            ? rows.length
            : rows.filter((x) => x.severity === key).length,
        ),
      ),
    );
    if (key !== "all") b.style.setProperty("--status", COLORS[key]);
    counts.append(b);
  }
  root.append(counts);
  const controls = el("div", "ops-controls"),
    search = el("input", "ops-search");
  search.type = "search";
  search.placeholder = "Find a server, disk, port or incident";
  search.setAttribute("aria-label", "Search issues");
  search.value = filters.search;
  const category = el("select");
  category.setAttribute("aria-label", "Issue type");
  for (const [key, name] of [
    ["all", "All types"],
    ...Object.entries(CATEGORY),
  ]) {
    const o = el("option", "", name);
    o.value = key;
    category.append(o);
  }
  category.value = filters.category;
  controls.append(
    search,
    category,
    el("span", "ops-muted", "Snapshot " + timeLabel(data.as_of) + " MSK"),
  );
  root.append(controls);
  const info = el(
    "p",
    "ops-note",
    "Servers and disks follow the system, environment and software filters. Network and facility equipment cover the selected site. Counts represent issues; a device can have more than one.",
  );
  root.append(info);
  const result = el("section", "problem-results");
  result.setAttribute("aria-label", "Issue list");
  root.append(result);
  const draw = () => {
    const list = filterProblems(rows, filters);
    result.replaceChildren(
      el(
        "div",
        "result-count",
        "Showing " +
          list.length +
          " of " +
          rows.length +
          " · devices " +
          new Set(list.map((r) => r.device_id)).size,
      ),
    );
    if (!list.length) {
      result.append(
        el(
          "div",
          "ops-empty",
          rows.length
            ? "No issues match these conditions."
            : "No issues found within the current filters.",
        ),
      );
      return;
    }
    const wrap = el("div", "table-wrap"),
      table = el("table", "problems-table"),
      thead = el("thead"),
      hr = el("tr");
    for (const name of [
      "Severity",
      "Equipment / location",
      "Issue",
      "Value / threshold",
      "Time · MSK",
      "Open",
    ])
      hr.append(el("th", "", name));
    thead.append(hr);
    table.append(thead);
    const body = el("tbody");
    for (const r of list) {
      const tr = el("tr");
      tr.dataset.problemId = r.id;
      const sev = el("td");
      sev.append(status(r.severity), el("small", "", CATEGORY[r.category]));
      const device = el("td");
      device.append(
        el("b", "", r.key + (r.part ? " · " + r.part : "")),
        el("small", "", locationText(r)),
      );
      const problem = el("td");
      problem.append(el("b", "", r.title), el("small", "", r.reason || ""));
      const measure = el("td");
      measure.append(el("b", "", r.metric_code ? value(r.value, r.unit) : "—"));
      let limit =
        r.severity === "critical" ? r.critical_above : r.warning_above;
      measure.append(
        el(
          "small",
          "",
          r.metric_code === "net_link_up"
            ? "Expected: link up"
            : limit != null
              ? "Threshold > " + value(limit, r.unit)
              : r.severity === "unknown"
                ? "No recent reading"
                : "Status from source",
        ),
      );
      const when = el("td");
      when.append(
        el("span", "", problemSince(r)),
        el(
          "small",
          "",
          r.observed_at
            ? (r.category === "incident"
                ? "Registered "
                : r.metric_code
                  ? "Measured "
                  : "Observed ") + timeLabel(r.observed_at)
            : "No measurements",
        ),
      );
      const actions = el("td", "row-actions");
      actions.append(link("Equipment →", r, 3), link("History →", r, 5));
      tr.append(sev, device, problem, measure, when, actions);
      body.append(tr);
    }
    table.append(body);
    wrap.append(table);
    result.append(wrap);
  };
  search.oninput = () => {
    filters.search = search.value;
    draw();
  };
  category.onchange = () => {
    filters.category = category.value;
    draw();
  };
  draw();
}
/**
 * Group history series by disk label, port label or whole-device telemetry.
 * This UI grouping leaves numeric series IDs and source labels unchanged.
 */
function partKey(s) {
  return s.labels?.disk
    ? "disk:" + s.labels.disk
    : s.labels?.port
      ? "port:" + s.labels.port
      : "device";
}
/**
 * Render one unit-compatible group in a 560×180 SVG. Percent/boolean scales are
 * fixed; other units use a rounded scale that includes thresholds. Draw nulls as
 * gaps, booleans as steps, threshold/state markers as dashed lines and incidents
 * at their actual instants. Statistics use only known points in the chosen period.
 */
function chart(title, series, points) {
  const card = el("section", "history-chart");
  card.setAttribute("aria-label", title);
  card.classList.toggle(
    "selected",
    series.some((s) => s.id === data.selected_series),
  );
  card.append(el("h2", "", title));
  const colors = ["#7bcb9b", "#76b5e4", "#c58ad5"],
    unit = series[0].unit;
  const all = points.flatMap((p) =>
    p.filter((x) => Number.isFinite(x.value)).map((x) => x.value),
  );
  const pct = unit === "percent",
    min = Math.min(0, ...all),
    thresholds = series
      .flatMap((s) => [s.warning_above, s.critical_above])
      .filter(Number.isFinite),
    rawMax = Math.max(1, ...all, ...thresholds),
    power = 10 ** Math.floor(Math.log10(rawMax / 4)),
    step = [1, 2, 5, 10].find((n) => n * power >= rawMax / 4) * power,
    max = pct ? 100 : unit === "boolean" ? 1 : Math.ceil(rawMax / step) * step;
  const current = el("div", "chart-current");
  series.forEach((s, j) => {
    const latest = points[j].at(-1)?.value,
      n = el("strong", "", value(latest, unit));
    n.style.color = COLORS[seriesState(s, latest)];
    current.append(n);
  });
  card.append(current);
  const left = 49,
    right = 512,
    top = 18,
    bottom = 146,
    w = 560,
    h = 180,
    x = (i) => left + (i * (right - left)) / Math.max(points[0].length - 1, 1),
    y = (v) => bottom - ((v - min) / (max - min)) * (bottom - top);
  const plot = svg("svg", {
    viewBox: `0 0 ${w} ${h}`,
    role: "img",
    "aria-label":
      title + " · " + period + " minutes. Missing readings are shown as gaps.",
  });
  for (let i = 0; i <= 4; i++) {
    const v = min + ((max - min) * i) / 4;
    plot.append(
      svg("line", {
        x1: left,
        x2: right,
        y1: y(v),
        y2: y(v),
        stroke: "#49414d",
        "stroke-width": 0.6,
      }),
      svg(
        "text",
        {
          x: left - 7,
          y: y(v) + 3,
          "text-anchor": "end",
          fill: "#aaa3af",
          "font-size": 10,
        },
        Number(v.toFixed(1)),
      ),
    );
  }
  if (series.length === 1)
    for (const [limit, color] of [
      [series[0].warning_above, COLORS.warning],
      [series[0].critical_above, COLORS.critical],
    ])
      if (Number.isFinite(limit)) {
        plot.append(
          svg("line", {
            x1: left,
            x2: right,
            y1: y(limit),
            y2: y(limit),
            stroke: color,
            "stroke-width": 1,
            "stroke-dasharray": "5 4",
          }),
          svg(
            "text",
            { x: right + 5, y: y(limit) + 3, fill: color, "font-size": 9 },
            limit,
          ),
        );
      }
  series.forEach((s, j) => {
    let segment = [];
    const flush = () => {
      if (segment.length > 1) {
        let d =
          "M" +
          segment
            .map((p, i) =>
              i && s.unit === "boolean"
                ? `${x(p.i)} ${y(segment[i - 1].value)} L${x(p.i)} ${y(p.value)}`
                : `${x(p.i)} ${y(p.value)}`,
            )
            .join(" L");
        plot.append(
          svg("path", {
            d,
            fill: "none",
            stroke: colors[j % 3],
            "stroke-width": 2,
          }),
        );
      }
      segment = [];
    };
    points[j].forEach((p, i) => {
      if (p.value === null) {
        flush();
        return;
      }
      segment.push({ ...p, i });
      const state = seriesState(s, p.value),
        dot = svg("circle", {
          cx: x(i),
          cy: y(p.value),
          r: 2.5,
          fill: state === "healthy" ? colors[j % 3] : COLORS[state],
        });
      dot.append(
        svg(
          "title",
          {},
          timeLabel(p.at) + " · " + s.name + ": " + value(p.value, unit),
        ),
      );
      plot.append(dot);
    });
    flush();
    for (const event of transitions(s, points[j])) {
      const i = points[j].findIndex((p) => p.at === event.at),
        color = COLORS[event.severity];
      const line = svg("line", {
        x1: x(i),
        x2: x(i),
        y1: top,
        y2: bottom,
        stroke: color,
        "stroke-width": 1,
        "stroke-dasharray": "2 4",
        opacity: 0.7,
      });
      line.append(
        svg(
          "title",
          {},
          timeLabel(event.at) +
            " · " +
            STATUS[event.severity] +
            (event.initial ? " already present at period start" : ""),
        ),
      );
      plot.append(line);
    }
  });
  for (const inc of data.incidents || []) {
    const at = Date.parse(inc.detected_at),
      start = Date.parse(points[0][0]?.at),
      end = Date.parse(points[0].at(-1)?.at);
    if (at >= start && at <= end) {
      const pos = left + ((at - start) / (end - start)) * (right - left);
      const marker = svg("line", {
        x1: pos,
        x2: pos,
        y1: top,
        y2: bottom,
        stroke: "#d08aa0",
        "stroke-width": 1.5,
        "stroke-dasharray": "4 3",
      });
      marker.append(
        svg(
          "title",
          {},
          inc.incident_key +
            " · " +
            timeLabel(inc.detected_at) +
            " · " +
            inc.title,
        ),
      );
      plot.append(marker);
    }
  }
  if (!all.length)
    plot.append(
      svg(
        "text",
        {
          x: (left + right) / 2,
          y: 85,
          "text-anchor": "middle",
          fill: "#aaa3af",
          "font-size": 15,
        },
        "No valid readings",
      ),
    );
  const p = points[0];
  for (const i of [
    ...new Set([0, Math.floor((p.length - 1) / 2), p.length - 1]),
  ])
    if (p[i])
      plot.append(
        svg(
          "text",
          {
            x: x(i),
            y: 170,
            "text-anchor":
              i === 0 ? "start" : i === p.length - 1 ? "end" : "middle",
            fill: "#aaa3af",
            "font-size": 10,
          },
          timeLabel(p[i].at),
        ),
      );
  card.append(plot);
  const stat = el("div", "history-stats");
  series.forEach((s, j) => {
    const known = points[j]
        .filter((p) => Number.isFinite(p.value))
        .map((p) => p.value),
      row = el("div");
    row.style.setProperty("--series-color", colors[j % 3]);
    row.append(
      el("b", "", s.name),
      el("span", "", value(points[j].at(-1)?.value, unit)),
      el(
        "small",
        "",
        known.length
          ? "min " +
              value(Math.min(...known), unit) +
              " · avg " +
              value(known.reduce((a, b) => a + b, 0) / known.length, unit) +
              " · max " +
              value(Math.max(...known), unit)
          : "No data",
      ),
    );
    stat.append(row);
  });
  card.append(stat);
  return card;
}
/**
 * Render the chosen device’s component and 30/60/120-minute controls. Preserve
 * a requested series by selecting its part and moving its chart first. Group
 * related metrics by units, retain unrecognized series as individual charts, and
 * show state transitions/incident context with bounded-onset wording.
 */
function history() {
  root.replaceChildren();
  root.className = "history-page";
  if (!data.device) {
    root.append(
      el(
        "div",
        "ops-empty",
        "This device is outside the selected filters. Choose another device or Auto-select device, then click Show.",
      ),
    );
    return;
  }
  const d = data.device,
    head = el("section", "history-context");
  const name = el("div");
  name.append(el("h1", "", d.key), el("p", "ops-muted", locationText(d)));
  head.append(
    name,
    link("Back to equipment →", d, 3),
    link("All issues →", {}, 4),
  );
  root.append(head);
  const parts = [...new Set(data.series.map(partKey))];
  if (!parts.includes(part))
    part = partKey(
      data.series.find((s) => s.id === data.selected_series) ||
        data.series[0] ||
        {},
    );
  const selectedPart = data.series.find((s) => partKey(s) === part);
  head.querySelector("a").href = targetUrl(
    data.filters,
    {
      ...d,
      target_part: part.startsWith("disk:")
        ? selectedPart.labels.disk === "sdb"
          ? 2
          : 1
        : Number(selectedPart?.labels?.port_id) || 0,
    },
    3,
    location.origin,
  );
  const controls = el("div", "ops-controls");
  const label = el("label", "", "Component "),
    picker = el("select");
  picker.setAttribute("aria-label", "Device component");
  for (const key of parts) {
    const sample = data.series.find((s) => partKey(s) === key);
    const o = el(
      "option",
      "",
      key === "device"
        ? "Device"
        : key.startsWith("disk:")
          ? (sample.labels.media || "Disk") +
            " · " +
            sample.labels.disk +
            " · " +
            (sample.labels.mount || "")
          : sample.labels.port,
    );
    o.value = key;
    picker.append(o);
  }
  picker.value = part;
  picker.onchange = () => {
    part = picker.value;
    history();
  };
  label.append(picker);
  controls.append(label);
  const periods = el("div", "period-buttons");
  periods.setAttribute("aria-label", "History period");
  for (const [minutes, text] of [
    [30, "30 min"],
    [60, "1 hour"],
    [120, "2 hours"],
  ]) {
    const b = button(text, () => {
      period = minutes;
      history();
    });
    b.setAttribute("aria-pressed", String(period === minutes));
    periods.append(b);
  }
  controls.append(
    periods,
    el(
      "span",
      "ops-muted",
      new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Moscow",
        day: "numeric",
        month: "short",
        year: "numeric",
      }).format(new Date(data.as_of)) +
        " · " +
        timeLabel(new Date(Date.parse(data.as_of) - period * 60000)) +
        "–" +
        timeLabel(data.as_of) +
        " MSK",
    ),
  );
  root.append(controls);
  root.append(
    el(
      "p",
      "ops-note",
      "Demo · PostgreSQL measurements at 5-minute intervals. Dashed lines mark thresholds and state changes; pink marks incidents. Gaps indicate missing or invalid readings.",
    ),
  );
  const selected = data.series.filter((s) => partKey(s) === part),
    available = (code) => selected.find((s) => s.code === code),
    groups = part.startsWith("disk:")
      ? [
          ["Disk usage", ["disk_used_pct"]],
          ["Disk temperature", ["disk_c"]],
          ["I/O utilization", ["disk_busy_pct"]],
          ["Disk latency", ["disk_latency_ms"]],
          ["Read / write operations", ["disk_read_iops", "disk_write_iops"]],
          ["Read / write throughput", ["disk_read_mib_s", "disk_write_mib_s"]],
          ["Used / capacity", ["disk_used_gib", "disk_capacity_gib"]],
          ["SMART errors", ["disk_smart_errors"]],
        ]
      : part.startsWith("port:")
        ? [
            ["Port utilization", ["net_util_pct"]],
            ["Receive / transmit", ["net_rx_mbps", "net_tx_mbps"]],
            ["Errors", ["net_errors_s"]],
            ["Packet drops", ["net_discards_s"]],
            ["Link status · 1 = up, 0 = down", ["net_link_up"]],
          ]
        : [
            ["CPU", ["cpu_pct"]],
            ["RAM", ["memory_pct"]],
            ["Temperature", ["inlet_c", "switch_c"].filter(available)],
            ["Power", ["power_w"]],
          ];
  const focusCode = selected.find((s) => s.id === data.selected_series)?.code;
  if (focusCode)
    groups.sort(
      (a, b) =>
        Number(b[1].includes(focusCode)) - Number(a[1].includes(focusCode)),
    );
  const charts = el("section", "history-grid");
  charts.setAttribute("aria-label", "Metric charts");
  const used = new Set();
  for (const [name, codes] of groups) {
    const series = codes.map(available).filter(Boolean);
    if (!series.length) continue;
    series.forEach((s) => used.add(s.id));
    charts.append(
      chart(
        name,
        series,
        series.map((s) =>
          periodPoints(data.times, s.values, data.as_of, period),
        ),
      ),
    );
  }
  for (const s of selected.filter((s) => !used.has(s.id)))
    charts.append(
      chart(
        s.name,
        [s],
        [periodPoints(data.times, s.values, data.as_of, period)],
      ),
    );
  root.append(charts);
  const events = selected
    .flatMap((s) =>
      transitions(s, periodPoints(data.times, s.values, data.as_of, period)),
    )
    .sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
  const list = el("section", "history-events");
  list.setAttribute("aria-label", "Chart events");
  list.append(el("h2", "", "Events in the selected period"));
  for (const e of events) {
    const row = el("div", "history-event");
    row.append(
      el("time", "", timeLabel(e.at)),
      status(e.severity),
      el(
        "span",
        "",
        e.name +
          (e.initial
            ? " · already present at period start; onset unknown"
            : ""),
      ),
    );
    list.append(row);
  }
  for (const inc of data.incidents || []) {
    const visible =
      Date.parse(inc.detected_at) >= Date.parse(data.as_of) - period * 60000;
    list.append(
      el(
        "div",
        "incident-event",
        inc.incident_key +
          " · " +
          timeLabel(inc.detected_at) +
          (visible ? "" : " · started before this period") +
          " · " +
          inc.title,
      ),
    );
  }
  if (!events.length && !data.incidents?.length)
    list.append(
      el(
        "p",
        "ops-muted",
        "No state changes or related incidents in this period.",
      ),
    );
  root.append(list);
}
/**
 * Decode a fresh fragment and route by view=history. The surrounding report
 * performs device/scope filtering; a missing selected device gets an empty state.
 * A malformed payload is caught and replaced with a refresh instruction.
 */
function load() {
  try {
    const host = window.frameElement;
    if (host) {
      host.setAttribute("title", "");
      host.setAttribute("aria-label", "DC issues and history");
    }
    data = decodePayload(location.hash);
    new URLSearchParams(location.search).get("view") === "history"
      ? history()
      : problems();
  } catch (e) {
    console.error(e);
    root.replaceChildren(
      el(
        "div",
        "ops-empty",
        "Could not load data. Refresh the page or apply the filters again.",
      ),
    );
  }
}
window.addEventListener("hashchange", load);
load();
