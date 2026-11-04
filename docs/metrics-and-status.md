# Metrics and status

Every value in this demonstration is synthetic. Thresholds illustrate monitoring behavior and are not equipment operating recommendations or production service objectives. The fixed comparison time is **2026-10-21 14:32 MSK**. Source definitions live in `dcmon.metric_definition`; series identity, labels and freshness budgets live in `dcmon.metric_series`.

## Units and threshold definitions

Validity limits are inclusive. Warning and critical comparisons are **strictly greater than** the bound: CPU=95 is warning, CPU>95 is critical. A dash below means no bound is configured, not zero.

| Metric code | Unit | Valid range | Warning above | Critical above |
|---|---|---|---|---|
| `cpu_pct` | percent | 0–100 | 80 | 95 |
| `memory_pct` | percent | 0–100 | 85 | 95 |
| `storage_pct` | percent | 0–100 | 80 | 95 |
| `power_w` | W | >=0 | — | — |
| `inlet_c` | celsius | −40–100 | 28 | 32 |
| `humidity_pct` | percent | 0–100 | 65 | 75 |
| `fan_rpm` | rpm | 0–50,000 | — | — |
| `network_rx_bytes` | bytes, cumulative counter | >=0 | — | — |
| `disk_capacity_gib` | GiB | >=0 | — | — |
| `disk_used_gib` | GiB | >=0 | — | — |
| `disk_used_pct` | percent | 0–100 | 80 | 95 |
| `disk_c` | C | −20–100 | 45 | 55 |
| `disk_read_iops` | IOPS | >=0 | — | — |
| `disk_write_iops` | IOPS | >=0 | — | — |
| `disk_read_mib_s` | MiB/s | >=0 | — | — |
| `disk_write_mib_s` | MiB/s | >=0 | — | — |
| `disk_latency_ms` | ms | >=0 | 20 | 40 |
| `disk_busy_pct` | percent | 0–100 | 80 | 95 |
| `disk_smart_errors` | count | >=0 | 0 | 5 |
| `net_rx_mbps` | Mbps | >=0 | — | — |
| `net_tx_mbps` | Mbps | >=0 | — | — |
| `net_util_pct` | percent | 0–100 | 80 | 95 |
| `net_errors_s` | errors/s | >=0 | 0 | 10 |
| `net_discards_s` | packets/s | >=0 | 0 | 20 |
| `net_link_up` | boolean, 0/1 | 0–1 | — | — |
| `switch_c` | C | −20–100 | 65 | 80 |

Percent means 0–100, not 0–1. GiB and MiB are binary units; Mbps is megabits per second. Site/server-population power converts W to kW by dividing by 1,000. `network_rx_bytes` is a cumulative counter: a rate requires reset-aware differentiation. The `net_*_mbps`, IOPS, throughput and per-second error/discard series are already rate gauges; do not differentiate them again. Disk and switch source unit `C` and inlet unit `celsius` both render as °C.

Disk labels preserve disk name (`sda`/`sdb`), media and mount. Network labels preserve port name and inventory port ID. Do not average both disks into a fictitious disk or add receive/transmit Mbps to utilization percent. Device-card disk summaries use maxima across available disks. Component views retain the individual series.

## Quality and freshness

Samples distinguish observation time from ingestion time. Snapshot selection finds the latest observation at or before the requested time; it does not reconstruct what the warehouse knew at that time using ingestion timestamps. It never selects future observations.

| Condition for the latest sample | Classification | Display |
|---|---|---|
| No sample <=snapshot | missing | NULL |
| Age > series `stale_after_sec` | stale | NULL |
| Within budget, quality missing/error | missing/error | NULL |
| Within budget, quality ok and valid numeric value | fresh | Value |

At exactly the budget a sample remains fresh. A newer missing/error sample suppresses an older valid one. A stale missing/error sample is classified stale first. NULL is not zero, healthy, or an invitation to interpolate. Database `raw_value` and observation time remain diagnostic context even when `display_value` is NULL.

Scene and full History use each series' freshness budget at each tick and reject invalid values. Their axes are one hour/13 points and two hours/25 points respectively. IT CPU and network power charts preserve a narrower rule: latest quality=ok point in `(tick−60 seconds,tick]`, at five-minute ticks. These query contracts are deliberately different; see [dataset details](dataset-contract.md).

## Different health dimensions

Reported technical status comes from `status_observation` and `status_snapshot`: healthy, warning, critical, unknown or maintenance. An absent/expired latest status becomes unknown. It is not automatically recomputed from metric thresholds. Inventory lifecycle (planned/active/retired), incident priority and application criticality are separate concepts.

UI rollups can worsen attention based on known thresholds, incidents or unavailable readings. They never turn a missing value into healthy. Site aggregation first handles no selected servers as empty, then applies critical → warning → unknown → maintenance → healthy precedence. A partial maximum is labeled as a lower bound; a partial power sum is withheld entirely. IT summary counters retain their specific reported-state semantics, so a threshold issue can exist on a device whose reported state is healthy.

A port with an active physical network link and `net_link_up=0` is critical. An unconnected unused port at zero is not automatically a fault. A NULL link reading is unknown in both cases. Hardware and History views use the same link-aware distinction.

## Counts and incident meaning

The initial queue has 13 rows: 4 critical, 7 warning and 2 unknown, across five devices, including one incident. Metric rows are per series; device-state fallback appears only when no metric issue represents the device; active incidents appear once. Thus issue count, affected-device count, selected-server count and incident count answer different questions.

Related-incident propagation follows directed consumer → provider dependencies. Several affected server paths can refer to one incident. Neither an infrastructure dependency, an `at_risk` link nor a stale sensor proves a business-system outage. Incident state is the latest event at or before the snapshot; resolved/closed incidents are excluded from the active queue. History retains relevant incidents detected during its window or still active.

Observed threshold transitions and bounded onset estimates describe samples, not precise failure onset. If the two-hour search has no last-good point, the UI says onset unknown. Missing-data onset can be the last observation plus its freshness budget. This demonstration does not calculate availability, SLA/SLO compliance, MTTR or root-cause certainty.

RTO/RPO values in the model are illustrative recovery targets. A successful backup job does not establish recoverability or achievement of those targets; recovery-point age and recorded restore tests need separate interpretation. See [the data model](data-model.md).
