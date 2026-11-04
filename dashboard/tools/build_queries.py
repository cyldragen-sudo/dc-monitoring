"""Build the 22 read-only FineVIS dataset queries and their parameter manifest.

This file owns the shared SQL pipeline and the IT-page projections. The network,
scene and operations modules register additional projections through ``add``;
none of these builders opens a database connection or modifies report assets.
Run this script to write dashboard/sql/*.sql and dashboard/datasets.json.

The demo uses the fixed PostgreSQL instant 2026-10-21 14:32:00+03. Validity ranges
are half-open [valid_from, valid_to), and latest incident/state/metric readings
must never look beyond that instant. Server scope follows execution/compute paths
and active physical placement, not an independent device-name search. The common
pipeline intentionally retains full physical inventory only in specialized scene
and operations projections; its ``facts`` rows contain filtered servers only.

Parameters are integers; zero means unrestricted or automatic selection. p_env
is 0/all, 1/PROD, 2/TEST, 3/DEV, and p_page is clamped to at least one. Unknown
system/software identifiers and out-of-range environments produce empty scope.
Generated FineReport expressions normalize nullable identity parameters with NVL.
The placeholders are trusted numeric report parameters, not arbitrary SQL text.

Metric display values come from dcmon.metric_snapshot: unusable, invalid or stale
readings remain null. W are converted to kW only by explicit aggregates; memory
capacity stays GiB, CPU/RAM/disk utilization percent, temperatures degrees Celsius.
See docs/dataset-contract.md for the exact grain, output and empty semantics of
every projection. English localization changes display projections only, leaving
IDs, state codes, metric codes, labels and stored fixture data unchanged.
"""

from pathlib import Path
import json
import textwrap
from english_locale import english_sql

# Resolve outputs relative to this source file, independent of the caller's directory.
ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = {
    "p_system": 0,
    "p_env": 0,
    "p_software": 0,
    "p_server": 0,
    "p_page": 1,
    "p_site": 0,
    "p_scene_server": 0,
    "p_history_device": 0,
    "p_history_series": 0,
    "p_scene_target": 0,
    "p_scene_part": 0,
}
# Shared CTEs are reused verbatim so every page applies the same path filters,
# snapshot instant, incident propagation, metric nulls and deterministic ordering.
COMMON = """
-- p: normalize numeric parameters and pin the reproducible snapshot instant.
WITH RECURSIVE p AS (
 SELECT @@p_system@@::bigint system_id,@@p_env@@::int env_id,
 @@p_software@@::bigint software_id,@@p_server@@::bigint selected_id,
 @@p_site@@::bigint site_id,
 greatest(1,@@p_page@@::int) requested_page,
 '2026-10-21 14:32:00+03'::timestamptz at
),
-- param: resolve external IDs and reject invalid system/software/environment filters.
param AS (
 SELECT p.*,sy.ci_key system_key,sp.code software_code,
 CASE env_id WHEN 1 THEN 'PROD' WHEN 2 THEN 'TEST' WHEN 3 THEN 'DEV' END environment
 FROM p LEFT JOIN dcmon.information_system s ON s.ci_id=p.system_id
 LEFT JOIN dcmon.ci sy ON sy.ci_id=s.ci_id
 LEFT JOIN dcmon.software_product sp ON sp.id=p.software_id
 WHERE (p.system_id=0 OR s.ci_id IS NOT NULL)
 AND (p.software_id=0 OR sp.id IS NOT NULL) AND env_id BETWEEN 0 AND 3
),
-- all_paths: union application execution paths with compute inventory only for all systems/environments.
all_paths AS (
 SELECT e.server_id,e.node_ids FROM param p
 CROSS JOIN LATERAL dcmon.execution_paths(p.at) e
 WHERE (p.system_id=0 OR e.system_key=p.system_key)
 AND (p.env_id=0 OR e.environment=p.environment)
 UNION
 SELECT cp.server_id,cp.node_ids FROM param p
 CROSS JOIN LATERAL dcmon.compute_paths(p.at) cp WHERE p.system_id=0 AND p.env_id=0
),
-- paths: intersect path members with the active site placement and software installation scope.
paths AS MATERIALIZED (
 SELECT a.* FROM all_paths a CROSS JOIN param p
 WHERE (p.site_id=0 OR EXISTS (
 SELECT 1 FROM dcmon.device_placement placement JOIN dcmon.room room ON room.ci_id=placement.room_id
 WHERE placement.device_id=a.server_id AND room.site_id=p.site_id
 AND tstzrange(placement.valid_from,placement.valid_to,'[)') @> p.at))
 AND (p.software_id=0 OR EXISTS (
 SELECT 1 FROM dcmon.software_installation si
 JOIN dcmon.installation_placement ip ON ip.installation_id=si.ci_id
 AND tstzrange(ip.valid_from,ip.valid_to,'[)') @> p.at
 WHERE si.product_id=p.software_id
 AND (si.ci_id=ANY(a.node_ids) OR ip.host_id=ANY(a.node_ids))))
),
-- hosts: the distinct physical server IDs define the selected telemetry population.
hosts AS MATERIALIZED (
 SELECT DISTINCT server_id FROM paths
),
-- seeds: expand each path into starting nodes for infrastructure dependency traversal.
seeds AS (
 SELECT DISTINCT server_id,unnest(node_ids) node_id FROM paths
),
-- walk: traverse active power/cooling/network/storage providers; prevent cycles and cap paths at 32 nodes.
walk AS (
 SELECT s.server_id,s.node_id,ARRAY[s.node_id] visited FROM seeds s
 UNION ALL
 SELECT w.server_id,d.provider_id,w.visited||d.provider_id
 FROM walk w JOIN dcmon.dependency d ON d.dependent_id=w.node_id CROSS JOIN param p
 WHERE d.dependency_type IN ('power','cooling','network','storage')
 AND tstzrange(d.valid_from,d.valid_to,'[)') @> p.at
 AND NOT d.provider_id=ANY(w.visited) AND cardinality(w.visited)<32
),
-- events: propagate active incidents to selected servers using their latest event at or before the snapshot.
events AS MATERIALIZED (
 SELECT DISTINCT w.server_id,i.id incident_id,i.incident_key,i.title,i.severity,e.state,i.detected_at
 FROM walk w JOIN dcmon.incident_ci ic ON ic.ci_id=w.node_id
 JOIN dcmon.incident i ON i.id=ic.incident_id CROSS JOIN param p
 JOIN LATERAL (
 SELECT ev.state FROM dcmon.incident_event ev
 WHERE ev.incident_id=i.id AND ev.occurred_at<=p.at
 ORDER BY ev.occurred_at DESC,ev.id DESC LIMIT 1) e ON true
 WHERE i.detected_at<=p.at AND ic.linked_at<=p.at AND e.state NOT IN ('resolved','closed')
),
-- all_metrics: keep a single whole-inventory snapshot for equipment-aware projections.
all_metrics AS MATERIALIZED (
 SELECT m.* FROM param p CROSS JOIN LATERAL dcmon.metric_snapshot(p.at) m
),
-- metrics: restrict the same snapshot to selected physical servers.
metrics AS MATERIALIZED (
 SELECT m.* FROM all_metrics m JOIN hosts h ON h.server_id=m.ci_id
),
-- states: resolve as-of server status independently of measurements.
states AS MATERIALIZED (
 SELECT s.* FROM param p CROSS JOIN LATERAL dcmon.status_snapshot(p.at) s
 JOIN hosts h ON h.server_id=s.ci_id
),
-- facts: one row per selected server with active location, null-preserving metric pivots and incident count.
facts AS MATERIALIZED (
 SELECT h.server_id,c.ci_key server_key,c.name server_name,
 coalesce(st.state,'unknown') state,
 CASE coalesce(st.state,'unknown') WHEN 'healthy' THEN 'Healthy'
 WHEN 'warning' THEN 'Warning' WHEN 'critical' THEN 'Critical'
 WHEN 'maintenance' THEN 'Maintenance' ELSE 'No data' END state_label,
 room.site_id,dp.rack_id,coalesce(site_ci.name,'No location') site_name,
 coalesce(room_ci.ci_key,'—') room_key,coalesce(rack_ci.ci_key,'—') rack_key,
 coalesce(dp.u_start::text||'–'||(dp.u_start+dp.u_height-1)::text,'—') units,
 dev.model,dev.cpu_cores,dev.memory_gib,
 max(m.display_value) FILTER(WHERE m.metric_code='power_w') power_w,
 max(m.display_value) FILTER(WHERE m.metric_code='cpu_pct') cpu,
 max(m.display_value) FILTER(WHERE m.metric_code='memory_pct') memory,
 max(m.display_value) FILTER(WHERE m.metric_code='inlet_c') temperature,
 max(m.display_value) FILTER(WHERE m.metric_code='disk_used_pct') disk_used_pct,
 max(m.display_value) FILTER(WHERE m.metric_code='disk_c') disk_c,
 max(m.display_value) FILTER(WHERE m.metric_code='disk_busy_pct') disk_busy_pct,
 count(m.series_id) FILTER(WHERE m.freshness<>'fresh') unavailable_metrics,
 (SELECT count(DISTINCT e.incident_id) FROM events e WHERE e.server_id=h.server_id) incident_count,
 CASE coalesce(st.state,'unknown') WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END priority
 FROM hosts h JOIN dcmon.ci c ON c.ci_id=h.server_id
 JOIN dcmon.device dev ON dev.ci_id=h.server_id CROSS JOIN param p
 LEFT JOIN states st ON st.ci_id=h.server_id
 LEFT JOIN dcmon.device_placement dp ON dp.device_id=h.server_id AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at
 LEFT JOIN dcmon.ci rack_ci ON rack_ci.ci_id=dp.rack_id
 LEFT JOIN dcmon.room room ON room.ci_id=dp.room_id LEFT JOIN dcmon.ci room_ci ON room_ci.ci_id=room.ci_id
 LEFT JOIN dcmon.ci site_ci ON site_ci.ci_id=room.site_id LEFT JOIN metrics m ON m.ci_id=h.server_id
 GROUP BY h.server_id,c.ci_key,c.name,st.state,room.site_id,dp.rack_id,site_ci.name,room_ci.ci_key,rack_ci.ci_key,
 dp.u_start,dp.u_height,dev.model,dev.cpu_cores,dev.memory_gib
),
-- ranked: stable attention-first ordering, then server key, supplies ten-row pagination.
ranked AS (
 SELECT f.*,row_number() OVER(ORDER BY priority,server_key)::int row_no FROM facts f
),
-- paging: even empty results have page 1 of 1; requests beyond the end clamp to the last page.
paging AS (
 SELECT greatest(1,ceil(count(*)/10.0)::int) page_count,
 least((SELECT requested_page FROM p),greatest(1,ceil(count(*)/10.0)::int)) page_no FROM ranked
),
-- chosen: prefer the requested in-scope server, otherwise the first ranked server; empty facts selects none.
chosen AS (
 SELECT r.* FROM ranked r ORDER BY CASE WHEN r.server_id=(SELECT selected_id FROM p) THEN 0 ELSE 1 END,r.row_no LIMIT 1
),
-- chosen_software: distinct active installations on the chosen server execution path, respecting product filter.
chosen_software AS (
 SELECT DISTINCT ic.ci_key installation_key,sp.name software_name,si.version,sp.category,host.ci_key host_key
 FROM chosen c JOIN paths a ON a.server_id=c.server_id CROSS JOIN param p
 JOIN dcmon.installation_placement ip ON (ip.host_id=ANY(a.node_ids) OR ip.installation_id=ANY(a.node_ids))
 AND tstzrange(ip.valid_from,ip.valid_to,'[)') @> p.at
 JOIN dcmon.software_installation si ON si.ci_id=ip.installation_id
 JOIN dcmon.software_product sp ON sp.id=si.product_id
 JOIN dcmon.ci ic ON ic.ci_id=si.ci_id JOIN dcmon.ci host ON host.ci_id=ip.host_id
 WHERE p.software_id=0 OR sp.id=p.software_id
)
"""
# Insertion order is the public manifest order; duplicate names would overwrite a query.
Q = {}


def add(name, sql, common=True):
    """Register one projection, optionally appending it to the common WITH clause.

    Extension queries may begin with a comma to add CTEs after chosen_software.
    Lookup datasets pass common=False because they intentionally ignore scope.
    SQL stays templated until build(), so dependency modules share one parameter
    replacement policy and the English localization sees the full statement.
    """
    Q[name] = (COMMON if common else "") + textwrap.dedent(sql)


add(
    "filters_system",
    """SELECT 0::bigint id,'All systems'::text label UNION ALL
 SELECT s.ci_id,c.name FROM dcmon.information_system s JOIN dcmon.ci c ON c.ci_id=s.ci_id ORDER BY id""",
    False,
)
add(
    "filters_environment",
    """SELECT * FROM (VALUES(0,'All environments'),(1,'PROD'),(2,'TEST'),(3,'DEV')) x(id,label) ORDER BY id""",
    False,
)
add(
    "filters_software",
    """SELECT 0::bigint id,'All software'::text label UNION ALL
 SELECT id,name||' · '||upper(category) FROM dcmon.software_product ORDER BY id""",
    False,
)
add(
    "filters_server",
    """SELECT 0::bigint id,'Auto-select server'::text label UNION ALL
 SELECT server_id,server_key||' · '||state_label FROM facts ORDER BY id""",
)
add(
    "summary",
    """
 SELECT count(*)::int server_count,
 count(*) FILTER(WHERE state='healthy')::int healthy_count,
 count(*) FILTER(WHERE state IN ('warning','critical'))::int attention_count,
 count(*) FILTER(WHERE state='unknown' OR unavailable_metrics>0)::int unavailable_count,
 (SELECT count(DISTINCT incident_id)::int FROM events) incident_count,
 (SELECT page_no FROM paging) page_no,(SELECT page_count FROM paging) page_count,
 CASE WHEN count(*)=0 THEN 'No servers match these filters'
 ELSE 'Linked physical servers · '||count(*)::text END list_title FROM facts
""",
)
add(
    "servers_page",
    """
 SELECT server_id,server_key,state_label,site_name,rack_key,
 coalesce(round(cpu,1)::text||' %','No data') cpu_label,
 coalesce(round(memory,1)::text||' %','No data') memory_label,
 coalesce(round(temperature,1)::text||' °C','No data') temp_label,
 incident_count::text incidents_label,state
 FROM ranked CROSS JOIN paging
 WHERE row_no BETWEEN (page_no-1)*10+1 AND page_no*10 ORDER BY row_no
""",
)
add(
    "server_card",
    """
 SELECT c.server_id,coalesce(c.server_key,'No server') server_key,
 coalesce(c.state_label,'No matching data') state_label,coalesce(c.site_name,'—') site_name,
 coalesce(c.room_key,'—') room_key,coalesce(c.rack_key,'—') rack_key,coalesce(c.units,'—') units,
 coalesce(c.model,'—') model,coalesce(c.cpu_cores::text,'—') cpu_cores,
 coalesce(c.memory_gib::text||' GiB','—') memory_capacity,
 coalesce(round(c.cpu,1)::text||' %','No data') cpu_label,
 coalesce(round(c.memory,1)::text||' %','No data') memory_label,
 coalesce(round(c.temperature,1)::text||' °C','No data') temp_label,
 CASE WHEN c.server_id IS NULL THEN '—' WHEN c.unavailable_metrics>0
 THEN c.unavailable_metrics::text||' metrics without recent readings'
 ELSE 'All readings are current for this snapshot' END freshness_label,
 coalesce(c.incident_count::text,'0') incident_count,
 coalesce((SELECT string_agg(DISTINCT replace(e.system_key,'SYS-','')||' / '||e.environment,', ')
 FROM dcmon.execution_paths((SELECT at FROM p)) e WHERE e.server_id=c.server_id),'No system association') all_systems,
 coalesce(c.state,'unknown') state,
 coalesce(round(c.disk_used_pct,1)::text||' %','No data') disk_label,
 coalesce(round(c.disk_c,1)::text||' °C','No data') disk_temp_label,
 coalesce(round(c.disk_busy_pct,1)::text||' %','No data') disk_io_label,
 CASE WHEN c.disk_used_pct IS NULL THEN 'unknown' WHEN c.disk_used_pct>95 THEN 'critical' WHEN c.disk_used_pct>80 THEN 'warning' ELSE 'healthy' END disk_label_state,
 CASE WHEN c.disk_c IS NULL THEN 'unknown' WHEN c.disk_c>55 THEN 'critical' WHEN c.disk_c>45 THEN 'warning' ELSE 'healthy' END disk_temp_label_state,
 CASE WHEN c.disk_busy_pct IS NULL THEN 'unknown' WHEN c.disk_busy_pct>95 THEN 'critical' WHEN c.disk_busy_pct>80 THEN 'warning' ELSE 'healthy' END disk_io_label_state
 FROM (SELECT 1) anchor LEFT JOIN chosen c ON true
""",
)
add(
    "server_software",
    "SELECT * FROM chosen_software ORDER BY software_name,installation_key",
)
add(
    "software_summary",
    """
 SELECT regexp_replace(coalesce(string_agg(label,', ' ORDER BY label),'No software matches the filters'),'(.{1,50})([[:space:]]+|$)',chr(92)||'1'||chr(10),'g') software_text,
 count(*)::int software_count FROM (SELECT DISTINCT software_name||' '||version label FROM chosen_software) products
""",
)
add(
    "incidents",
    """
 SELECT incident_key,title,severity,state,count(DISTINCT server_id)::int matching_servers
 FROM events GROUP BY incident_key,title,severity,state ORDER BY incident_key
""",
)
add(
    "server_incidents",
    """
 SELECT coalesce(string_agg(e.incident_key||' · '||e.title,E'\\n' ORDER BY e.incident_key),'No active related incidents') incident_text
 FROM events e JOIN chosen c ON c.server_id=e.server_id
""",
)
add(
    "cpu_history",
    """
 SELECT to_char(t.at AT TIME ZONE 'Europe/Moscow','HH24:MI') AS time_label,m.value AS cpu_pct
 FROM chosen c CROSS JOIN param p
 CROSS JOIN LATERAL generate_series(p.at-interval '30 minutes',p.at,interval '5 minutes') t(at)
 JOIN dcmon.metric_series s ON s.ci_id=c.server_id
 JOIN dcmon.metric_definition d ON d.id=s.metric_id AND d.code='cpu_pct'
 LEFT JOIN LATERAL (SELECT z.value FROM dcmon.metric_sample z WHERE z.series_id=s.series_id
  AND z.observed_at>t.at-interval '60 seconds' AND z.observed_at<=t.at AND z.quality='ok'
  ORDER BY z.observed_at DESC LIMIT 1) m ON true
 ORDER BY t.at
""",
)

from network_queries import register

register(add)
from scene_queries import register as register_scene

register_scene(add)
from operations_queries import register as register_operations

register_operations(add)


def build():
    """Regenerate UTF-8 SQL and the machine-readable dataset/parameter manifest.

    Parameters are discovered from each full query, including its shared CTEs;
    therefore a dataset can expose a common parameter it does not directly project.
    Only declared DEFAULTS are substituted. Identity/selection parameters tolerate
    nullable report controls through INT(NVL(...,0)); others use INT(...). Output
    files are deterministic and terminated with one SQL semicolon/newline. This
    function writes source artifacts only and never deploys them or runs SQL.
    """
    folder = ROOT / "sql"
    folder.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, sql in Q.items():
        # Localize before replacing numeric placeholders; do not translate identifiers.
        sql = english_sql(sql)
        params = {k: v for k, v in DEFAULTS.items() if "@@" + k + "@@" in sql}
        for key in params:
            formula = (
                "INT(NVL(" + key + ",0))"
                if key
                in (
                    "p_server",
                    "p_site",
                    "p_scene_server",
                    "p_history_device",
                    "p_history_series",
                    "p_scene_target",
                    "p_scene_part",
                )
                else "INT(" + key + ")"
            )
            sql = sql.replace("@@" + key + "@@", "$" + "{" + formula + "}")
        (folder / (name + ".sql")).write_text(sql.strip() + ";\n")
        manifest.append(
            {"name": name, "file": "sql/" + name + ".sql", "parameters": params}
        )
    (ROOT / "datasets.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )
    print("SQL datasets:", len(manifest))


if __name__ == "__main__":
    build()
