/**
 * Pure hardware severity rules for disks, ports and switches. Component health
 * uses source metric definitions and the same severity order as scope summaries.
 * A cable-free port that reports down is unused; an installed link that reports
 * down is critical. Missing link telemetry remains unknown in either case.
 */
import { metricReading } from "./metrics.mjs";
/**
 * Resolve the first present state using the shared severity precedence.
 * Unknown is the fallback when there are no recognized states.
 */
export function worst(states) {
  return (
    ["critical", "warning", "unknown", "maintenance", "healthy", "free"].find(
      (s) => states.includes(s),
    ) || "unknown"
  );
}
/**
 * Use capacity utilization, temperature, latency, I/O busy and SMART error
 * readings to compute disk health; informational throughput is not a health input.
 */
export function diskHealth(d, defs) {
  return worst(
    [
      "disk_used_pct",
      "disk_c",
      "disk_latency_ms",
      "disk_busy_pct",
      "disk_smart_errors",
    ].map((k) => metricReading(d.metrics?.[k], defs[k]).state),
  );
}
/**
 * Interpret link presence before utilization/error/drop thresholds. A missing
 * link value is unknown, an uncabled down port is free, and a cabled down port is
 * critical. Remaining ports inherit their worst quality/performance state.
 */
export function portHealth(p, defs) {
  const link = metricReading(p.metrics?.net_link_up, defs.net_link_up);
  if (link.value === null) return "unknown";
  if (!p.linked && link.value === 0) return "free";
  if (p.linked && link.value === 0) return "critical";
  return worst(
    ["net_util_pct", "net_errors_s", "net_discards_s"].map(
      (k) => metricReading(p.metrics?.[k], defs[k]).state,
    ),
  );
}
/**
 * Combine device status, every port and defined switch CPU/RAM/temperature
 * metrics. Missing optional metric definitions do not add synthetic measurements.
 */
export function networkHealth(d, defs) {
  return worst([
    d.state || "unknown",
    ...(d.ports || []).map((p) => portHealth(p, defs)),
    ...["cpu_pct", "memory_pct", "switch_c"]
      .filter((k) => defs[k])
      .map((k) => metricReading(d.metrics?.[k], defs[k]).state),
  ]);
}
