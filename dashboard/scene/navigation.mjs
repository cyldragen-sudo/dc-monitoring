/**
 * Deterministic local drilldown selection. Entering a rack retains a selected
 * server when possible; otherwise attention, load, physical unit and stable identity
 * break ties in that order. This changes iframe state only; report-page navigation
 * and server filtering remain the responsibility of app.mjs and the SQL payload.
 */
import { select, stats } from "./core.mjs";
import { serverAttention, loadScore } from "./metrics.mjs";
/**
 * Validate the requested destination, then choose a rack’s detail server.
 * A retained manual selection wins; otherwise sort by attention, descending valid
 * CPU/RAM load, ascending rack U, key, then ID. selectionReason explains this choice
 * to the user and is preserved when reopening the same selected server.
 */
export function nextView(m, current, level, id = 0) {
  const next = select(m, level, id);
  if (level === "rack") {
    const servers = stats(m, next).servers,
      defs = m.data.metric_definitions || {};
    const retained =
      current?.level === "server" &&
      servers.find((s) => s.id === current.serverId);
    const ranked = [...servers].sort(
      (a, b) =>
        serverAttention(a, defs) - serverAttention(b, defs) ||
        loadScore(b) - loadScore(a) ||
        (m.devices.get(a.id).u_start ?? Infinity) -
          (m.devices.get(b.id).u_start ?? Infinity) ||
        a.key.localeCompare(b.key) ||
        a.id - b.id,
    );
    const chosen = retained || ranked[0];
    next.serverId = chosen?.id || 0;
    next.selectionReason = retained
      ? "Your selection was preserved"
      : chosen
        ? [
            "Auto-selected: critical state",
            "Auto-selected: needs attention",
            "Auto-selected: missing recent data",
            "Auto-selected: maintenance",
            "Auto-selected: highest CPU/RAM utilization",
          ][serverAttention(chosen, defs)]
        : "No matches";
  } else if (level === "server")
    next.selectionReason =
      current?.serverId === id ? current.selectionReason : "Selected manually";
  return next;
}
