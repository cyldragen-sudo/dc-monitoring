# Dataset contract

The authoritative list is [dashboard/datasets.json](../dashboard/datasets.json); the exact query text is in [dashboard/sql](../dashboard/sql). All 22 datasets use the FineReport named connection `DC_MONITORING` and return read-only results. Generated SQL contains FineReport `${INT(...)}` expressions; execute through FineReport or the repository verifier, not by sending the raw placeholders to `psql`.

## Parameters and shared scope

Every scoped dataset declares the common set **C**: `p_system=0`, `p_env=0`, `p_software=0`, `p_server=0`, `p_page=1`, `p_site=0`. Declaration does not mean every projection uses every value directly: the shared CTE pipeline exposes the complete set.

| Parameter | Meaning |
|---|---|
| `p_system` | `information_system.ci_id`; 0 means all systems |
| `p_env` | 0=all, 1=PROD, 2=TEST, 3=DEV |
| `p_software` | `software_product.id`; 0 means all products |
| `p_site` | Site CI ID; 0 means all sites |
| `p_server` | Preferred IT-page server CI ID; 0 selects automatically |
| `p_page` | IT table page request; clamped to at least 1 and at most the page count |
| `p_scene_server` | Return-to-rack server ID used by the IT-to-Infrastructure link |
| `p_scene_target` | Explicit Infrastructure device CI ID; takes priority over the return server |
| `p_scene_part` | Component target: one-based disk index, or network port ID |
| `p_history_device` | History device CI ID; 0 selects automatically |
| `p_history_series` | History metric-series focus hint; 0 means no explicit focus |

All parameters are integers, never arbitrary SQL fragments. Selection/identity controls for server, site, scene and history use `INT(NVL(parameter,0))`; system, environment, software and page use `INT(parameter)` and must receive their declared defaults. An invalid nonzero system/software ID or an environment outside 0–3 produces empty server scope. An unknown site has no matching servers or eligible equipment.

The fixed reference **T** is `2026-10-21 14:32:00+03`. All relationship validity tests are half-open `[valid_from, valid_to)`. Server scope uses execution paths, plus compute paths only when system and environment are both unrestricted; software must match an installation on that path or its host nodes. Site is an intersection with effective physical placement. `hosts` deduplicates physical server IDs; `facts` is one row per selected server. Related incidents propagate from the selected paths through active power/cooling/network/storage dependencies and deduplicate by incident ID where counted.

The chosen IT server is the requested in-scope `p_server`, otherwise the first server sorted by reported-state priority then server key. That choice is independent of which ten-row table page is visible. Empty scope selects no server. The [data model](data-model.md) describes observation-time history and the lifecycle caveats of the underlying functions.

## Lookups and IT datasets

All dates below are bounded by T; display clock labels use Europe/Moscow. `No data`, em dash and fallback strings are display values only, not numeric zeros.

| Dataset | Parameters | Grain and outputs | Empty, NULL and time behavior |
|---|---|---|---|
| `filters_system` | None | One `(id,label)` per catalog system plus ID 0, All systems; sorted by ID | Global lookup, independent of scope and T; sentinel remains with an empty catalog |
| `filters_environment` | None | Four `(id,label)` rows for All, PROD, TEST, DEV | Fixed enumeration, never empty |
| `filters_software` | None | One `(id,label)` per software product plus ID 0; label combines name/category | Global current catalog, no historical version reconstruction |
| `filters_server` | C | One `(id,label)` per selected physical server plus ID 0, Auto-select server; label includes reported state | Empty scope returns the sentinel only; ID order differs from attention-ranked table order |
| `summary` | C | Exactly one row: `server_count`, `healthy_count`, `attention_count`, `unavailable_count`, `incident_count`, `page_no`, `page_count`, `list_title` | Counts are zero for empty facts; page 1 of 1. Healthy is reported healthy status; attention is reported warning/critical; unavailable is unknown state OR any unavailable series. These counts may overlap. Incidents are distinct IDs, not affected-server links |
| `servers_page` | C | Up to 10 server rows: identity, reported state, location, CPU/RAM/temperature labels and related-incident count | No rows for empty scope. Numeric missing readings become No data labels. Stable order: critical, warning, unknown, other, then server key. Page request clamps to available range |
| `server_card` | C | Exactly one chosen-server detail row: hardware/capacity, location/U interval, current labels, freshness, all associated systems, disk labels/states | Empty scope returns a fallback row with NULL server ID, No server and unknown state. Missing labels remain No data. Disk labels pivot the maximum available per-disk percentage/temperature/I/O reading, not disk totals. Disk state thresholds here are >80/>95% for usage/busy and >45/>55°C for temperature |
| `server_software` | C | One distinct active installation/path-host tuple: `installation_key`, `software_name`, `version`, `category`, `host_key`; ordered by product/name key | Empty selection returns no rows. Active placement is evaluated at T; version/name are current catalog attributes |
| `software_summary` | C | Exactly one row: wrapped `software_text`, `software_count`; distinct product-name/version pairs for chosen server | Empty selection gives count 0 and No software matches the filters. Count is distinct name/version labels, not installation IDs |
| `incidents` | C | One active related incident row: key, title, severity, latest state, distinct `matching_servers` | No rows if none. Latest event must be <=T; detected/link times must be <=T; resolved/closed excluded. Multiple dependent devices do not duplicate the incident |
| `server_incidents` | C | Exactly one `incident_text` row for the chosen server, ordered by incident key | No active related incidents fallback if none; same as-of event rules as `incidents` |
| `cpu_history` | C | One row per five-minute tick over [T−30m,T], normally 7: `time_label`, `cpu_pct` for chosen server's CPU series | No chosen server/CPU series yields no rows. At each tick accepts latest quality=ok observation strictly after tick−60s and <=tick. No eligible sample yields NULL, not zero. This short-window rule differs from general History |

`server_card.all_systems` reports all execution-path associations for the chosen server at T; it is informative context rather than a repetition of the selected system filter.

## Network datasets

| Dataset | Parameters | Grain and outputs | Empty, NULL and time behavior |
|---|---|---|---|
| `filters_site` | None | One `(id,label)` per configured site plus ID 0, All DCs | Global catalog lookup, independent of selected server population |
| `network_summary` | C | Exactly one row: distinct selected `site_count`, `rack_count`, physical `server_count`, distinct active `incident_count`, `unavailable_count` | Zero counts for empty server scope. NULL/unplaced site and rack IDs do not count as distinct locations |
| `network_sites` | C | One row per configured site, including empty sites: selected server/rack counts, power, maximum inlet/CPU/RAM, known-value coverage, state and formatted labels, server/equipment issue counts | Empty sites remain `empty`/No matches. Site power is NULL unless all selected servers have power. CPU/RAM/temperature maxima use valid known values; `≥` marks partial CPU/RAM coverage. Equipment status includes actively placed non-server devices at T. Severity after empty handling is critical, warning, unknown, maintenance, healthy |
| `network_power_history` | C | Exactly 25 five-minute ticks [T−2h,T]: `time_label`, `power_kw`, `server_count`, `measured_count` | Cohort is the selected hosts at T, not reselected at each tick. Uses latest quality=ok power point in (tick−60s,tick]. Sum W/1000 is NULL for empty/incomplete coverage; explicit counts explain gaps |
| `network_incident` | C | Exactly one representative incident key/title plus distinct active incident count | Picks latest detected related incident, tie by key. No active incidents fallback and count 0 when none; not one row per incident |
| `it_context` | C | Exactly one `site_label` | All DCs for ID 0; current CI name for selected ID, otherwise Unknown data center. Does not itself return server counts |

## Encoded iframe datasets

Each payload dataset returns exactly one text column, **`payload_base64`**, containing UTF-8 JSON encoded as base64 without line breaks. Decode as bytes then UTF-8; decoding base64 directly as browser Latin-1 corrupts non-ASCII symbols. Payloads have no database credentials. Encoding is not an access-control mechanism.

### `scene_payload`

Parameters: **C** plus `p_scene_server=0`, `p_scene_target=0`, `p_scene_part=0`. Grain: one complete physical scene and filtered server-telemetry snapshot at T.

- `as_of` is the fixed snapshot instant; `filters` retains scope and deep-link targets.
- `sites`, `rooms`, `racks`, `devices`, `servers` are compact arrays of row arrays. For each entity, the matching `*_columns` lists the alphabetical column order. Zip columns to values rather than hardcoding array offsets. Arrays are `[]` when empty; column metadata can be NULL when the source entity table is empty.
- Sites, rooms, racks and placed devices preserve the full physical inventory independently of selected server scope. Rack `occupied_u` sums physical occupied intervals. Devices include reported state and switch/port telemetry. Servers contain only selected facts, their component disks, model/capacity, location, current readings and related incidents.
- `disk_metric_codes` and `port_metric_codes` define sorted positions in compact per-disk/per-port `metrics` arrays. Disk labels retain name/media/mount; port identity retains inventory port IDs and link context.
- `metric_definitions` carries validity bounds and warning/critical thresholds by stable code. Missing/stale/error current values are JSON NULL.
- `history_times` is a shared 13-tick axis [T−1h,T], five minutes apart. Each selected server's `history` has aligned `[cpu,memory,temperature]` triples. Each tick uses the latest sample <=tick, checks quality, inclusive valid range and the series-specific stale budget. Invalid values remain NULL.

An empty server scope does not erase physical occupancy. Consumers validate references before drawing; the model must not infer that a physically installed but filtered-out device is absent.

### `filters_history_device`

Parameters: **C**. Grain: one `(id,label)` per eligible placed device, plus ID 0, Auto-select device. Servers must belong to selected `hosts`; non-server devices are independent of system/environment/software and limited by site. Empty eligible scope returns the sentinel only. Eligibility uses placement/state at T. This is a regular row dataset, not an encoded payload.

### `problems_payload`

Parameters: **C**. Grain: one queue snapshot. Top-level JSON fields are `as_of`, `window_start` (T−2h), `filters` (system/environment/software/site), and `problems` (an ordered array, `[]` when empty).

Each issue includes stable `id`, `device_id`, `series_id`, device `key`/`kind`, site/room/rack IDs and labels, `category`, component `part` and `target_part`, `title`, `metric_code`, `severity`, numeric `value`/`unit`, warning/critical bounds, `observed_at`, `since`, `ongoing_before_window` and `reason`.

Issue identities and count rules are:

1. `m:<series_id>`: one problematic metric series (critical/warning/unknown); disk and port labels distinguish components. NULL `display_value` is unknown. A zero link value is critical only for a port with an active physical link.
2. `s:<device_id>`: one warning/critical/unknown device-state fallback, **only if no metric problem already represents that device**. Its measurement is NULL and series ID 0.
3. `i:<incident_id>`: one active incident, represented by one directly eligible linked device, preferring a CRAC then the smallest device ID. Its measurement is NULL and series ID 0. Critical/P1/critical_high incident severity maps to critical; other active incident severity maps to warning.

Queue ordering is severity (critical, warning, unknown), device key, component and title. The full fixture has 13 unique rows, 4/7/2 by severity, on five devices and includes one incident row. It does not emit one row for every dependency-affected server.

For threshold problems, onset estimation searches only [T−2h,T], finds the latest good point and first bad point after it. If no last-good point exists, `ongoing_before_window=true`; `since` is not an exact onset. For stale unknown readings `since=observed_at+stale_after_sec`; other unknown causes retain the observation time when known. A missing observation can leave timestamps NULL.

### `history_payload`

Parameters: **C** plus `p_history_device=0`, `p_history_series=0`. Grain: one eligible chosen device with all its defined series and a shared two-hour axis.

Top-level fields are `as_of`, `window_start`, `filters`, `requested_device`, `selected_series`, `device`, `times`, `series` and `incidents`. Automatic selection ranks critical, warning, unknown, other reported states, then servers before non-servers, then ID. A nonzero request outside eligibility returns **`device:null`, `series:[]`, `incidents:[]`**; the 25-tick `times` axis remains. It never silently selects a different device.

Each series exposes `id`, stable `code`, display `name`, source `unit`, `labels`, validity and warning/critical bounds, `linked`, and exactly 25 ordered `values`, rounded to three decimals. Ticks span [T−2h,T] every five minutes. The latest observation <=tick is accepted only if quality=ok, age <=that series' stale budget and inside the inclusive valid range. A later missing/error point prevents falling back to an older good sample. Rejected or absent readings remain JSON NULL.

`selected_series` is a focus hint; it does not filter the database series collection. The browser crops the aligned payload to inclusive 30/60/120-minute periods (7/13/25 points). Incidents include direct links and dependency-related incidents for a server, detected by T and either detected in-window or still active. Latest incident state is evaluated at T. These overlays are contextual, not an availability/SLA calculation.

## Verification and changes

`python3 scripts/verify_database.py` binds only declared integer parameters, executes all 22 contracts in read-only transactions with the proper path/timezone, and checks default and selected edge cases. A renamed dataset, changed parameter, changed grain or new default is a contract change: update builders, tests, this document and the FVS together. See [development](development.md) for the build order and [metrics/status](metrics-and-status.md) for units and health distinctions.
