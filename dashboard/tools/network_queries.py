"""Register the network overview datasets against build_queries.COMMON.

Dependencies: facts/hosts/events carry the selected server population; p/param
carry the fixed snapshot and site filter; metric_definition supplies validity and
threshold metadata. filters_site is a global lookup, while network_sites keeps
one row per configured site even when its selected-server count is zero.
Equipment health covers all actively placed non-server devices in a site.

network_summary counts selected servers/racks/sites and unique active incidents.
network_sites computes valid CPU/RAM/temperature maxima with coverage, includes
physical equipment health, and sums W to kW only if every selected server has a
power value. A partial maximum is labelled with a lower-bound marker; an empty
site is empty rather than healthy. Severity precedence is critical, warning,
unknown, maintenance, healthy, after handling zero-server sites.

network_power_history uses 25 five-minute ticks over two hours; the historical
server cohort is the snapshot's selected hosts. Each tick accepts only the latest
quality=ok sample in (tick-60 seconds, tick]. Missing coverage nulls total power,
while server_count and measured_count explain why. This intentionally differs
from the series-specific staleness used by scene/history JSON payloads.
network_incident returns one fallback row; it_context reports the selected site.
"""


def register(add):
    """Add this page's named queries through the shared registration callback.

    The callback prepends COMMON by default. Leading-comma statements extend its
    CTE chain; lookup-only statements explicitly opt out. No query executes here.
    """
    add(
        "filters_site",
        """SELECT 0::bigint id,'All DCs'::text label UNION ALL
        SELECT s.ci_id,c.name FROM dcmon.site s JOIN dcmon.ci c ON c.ci_id=s.ci_id ORDER BY id""",
        False,
    )
    add(
        "network_summary",
        """
        SELECT count(DISTINCT site_id)::int site_count,count(DISTINCT rack_id)::int rack_count,
        count(*)::int server_count,(SELECT count(DISTINCT incident_id)::int FROM events) incident_count,
        count(*) FILTER(WHERE state='unknown' OR unavailable_metrics>0)::int unavailable_count
        FROM facts
    """,
    )
    add(
        "network_sites",
        """
        , thresholds AS (SELECT
          max(valid_min) FILTER(WHERE code='cpu_pct') cpu_min,
          max(valid_max) FILTER(WHERE code='cpu_pct') cpu_max,
          max(warning_above) FILTER(WHERE code='cpu_pct') cpu_warning,
          max(critical_above) FILTER(WHERE code='cpu_pct') cpu_critical,
          max(valid_min) FILTER(WHERE code='memory_pct') mem_min,
          max(valid_max) FILTER(WHERE code='memory_pct') mem_max,
          max(warning_above) FILTER(WHERE code='memory_pct') mem_warning,
          max(critical_above) FILTER(WHERE code='memory_pct') mem_critical,
          max(valid_min) FILTER(WHERE code='inlet_c') temp_min,
          max(valid_max) FILTER(WHERE code='inlet_c') temp_max,
          max(warning_above) FILTER(WHERE code='inlet_c') temp_warning,
          max(critical_above) FILTER(WHERE code='inlet_c') temp_critical
          FROM dcmon.metric_definition),
        clean_facts AS (SELECT f.*,
          CASE WHEN (t.cpu_min IS NULL OR f.cpu>=t.cpu_min) AND (t.cpu_max IS NULL OR f.cpu<=t.cpu_max) THEN f.cpu END valid_cpu,
          CASE WHEN (t.mem_min IS NULL OR f.memory>=t.mem_min) AND (t.mem_max IS NULL OR f.memory<=t.mem_max) THEN f.memory END valid_memory,
          CASE WHEN (t.temp_min IS NULL OR f.temperature>=t.temp_min) AND (t.temp_max IS NULL OR f.temperature<=t.temp_max) THEN f.temperature END valid_temperature
          FROM facts f CROSS JOIN thresholds t),
        health_facts AS (SELECT f.*,
          CASE WHEN f.state='critical' OR f.valid_cpu>t.cpu_critical OR f.valid_memory>t.mem_critical OR f.valid_temperature>t.temp_critical THEN 'critical'
               WHEN f.state='warning' OR f.incident_count>0 OR f.valid_cpu>t.cpu_warning OR f.valid_memory>t.mem_warning OR f.valid_temperature>t.temp_warning THEN 'warning'
               WHEN f.state='unknown' OR f.unavailable_metrics>0 OR f.valid_cpu IS NULL OR f.valid_memory IS NULL OR f.valid_temperature IS NULL THEN 'unknown'
               WHEN f.state='maintenance' THEN 'maintenance' ELSE 'healthy' END severity,
          (f.state='unknown' OR f.unavailable_metrics>0 OR f.valid_cpu IS NULL OR f.valid_memory IS NULL OR f.valid_temperature IS NULL) missing
          FROM clean_facts f CROSS JOIN thresholds t),
        equipment_status AS MATERIALIZED (SELECT x.* FROM p CROSS JOIN LATERAL dcmon.status_snapshot(p.at) x),
        equipment AS (SELECT r.site_id,
          count(DISTINCT d.ci_id) FILTER(WHERE es.state IN ('critical','warning'))::int issues,
          count(DISTINCT d.ci_id) FILTER(WHERE coalesce(es.state,'unknown')='unknown')::int missing,
          bool_or(es.state='critical') critical,bool_or(es.state='warning') warning,bool_or(es.state='maintenance') maintenance
          FROM dcmon.device d JOIN dcmon.device_placement dp ON dp.device_id=d.ci_id CROSS JOIN p
          JOIN dcmon.room r ON r.ci_id=dp.room_id LEFT JOIN equipment_status es ON es.ci_id=d.ci_id
          WHERE d.device_class<>'server' AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at GROUP BY r.site_id),
        totals AS (
          SELECT c.ci_id site_id,c.ci_key site_key,c.name site_name,
          count(f.server_id)::int server_count,count(DISTINCT f.rack_id)::int rack_count,
          CASE WHEN count(f.server_id)>0 AND count(f.power_w)=count(f.server_id) THEN round(sum(f.power_w)/1000,2) END power_kw,
          CASE WHEN count(f.server_id)=0 THEN 'empty'
               WHEN bool_or(f.severity='critical') OR coalesce(e.critical,false) THEN 'critical'
               WHEN bool_or(f.severity='warning') OR coalesce(e.warning,false) THEN 'warning'
               WHEN bool_or(f.missing) OR coalesce(e.missing,0)>0 THEN 'unknown'
               WHEN bool_or(f.severity='maintenance') OR coalesce(e.maintenance,false) THEN 'maintenance' ELSE 'healthy' END state,
          (SELECT count(DISTINCT ev.incident_id)::int FROM events ev JOIN facts sf ON sf.server_id=ev.server_id WHERE sf.site_id=c.ci_id) incident_count,
          max(f.valid_temperature) max_temperature,max(f.valid_cpu) max_cpu,max(f.valid_memory) max_memory,
          count(f.valid_cpu)::int cpu_known,count(f.valid_memory)::int memory_known,
          count(f.server_id) FILTER(WHERE f.severity='critical')::int critical_count,
          count(f.server_id) FILTER(WHERE f.severity='warning')::int warning_count,
          count(f.server_id) FILTER(WHERE f.missing)::int missing_count,
          coalesce(e.issues,0) equipment_issue_count,coalesce(e.missing,0) equipment_missing_count
          FROM dcmon.site st JOIN dcmon.ci c ON c.ci_id=st.ci_id
          LEFT JOIN health_facts f ON f.site_id=c.ci_id LEFT JOIN equipment e ON e.site_id=c.ci_id
          GROUP BY c.ci_id,c.ci_key,c.name,e.critical,e.warning,e.missing,e.maintenance,e.issues
        )
        SELECT totals.*,coalesce(power_kw::text||' kW','No data') power_label,
          CASE state WHEN 'empty' THEN 'No matches' WHEN 'critical' THEN 'Critical'
          WHEN 'warning' THEN 'Warning' WHEN 'unknown' THEN 'No recent data'
          WHEN 'maintenance' THEN 'Maintenance' ELSE 'Healthy' END state_label,
          coalesce(round(max_temperature,1)::text||' °C','No data') temp_label,
          CASE WHEN max_cpu IS NULL THEN 'unknown' WHEN max_cpu>t.cpu_critical THEN 'critical' WHEN max_cpu>t.cpu_warning THEN 'warning' ELSE 'healthy' END cpu_load_state,
          CASE WHEN max_cpu IS NULL THEN '—' ELSE CASE WHEN cpu_known<server_count THEN '≥' ELSE '' END||trim(trailing '.' from trim(trailing '0' from round(max_cpu,1)::text))||'%' END cpu_load_label,
          CASE WHEN max_cpu IS NULL THEN '' ELSE repeat('■',least(10,greatest(0,ceil(max_cpu/10)::int))) END cpu_bar,
          CASE WHEN max_memory IS NULL THEN 'unknown' WHEN max_memory>t.mem_critical THEN 'critical' WHEN max_memory>t.mem_warning THEN 'warning' ELSE 'healthy' END memory_load_state,
          CASE WHEN max_memory IS NULL THEN '—' ELSE CASE WHEN memory_known<server_count THEN '≥' ELSE '' END||trim(trailing '.' from trim(trailing '0' from round(max_memory,1)::text))||'%' END memory_load_label,
          CASE WHEN max_memory IS NULL THEN '' ELSE repeat('■',least(10,greatest(0,ceil(max_memory/10)::int))) END memory_bar,
          'Crit. '||critical_count||' · Warn. '||warning_count||' · No data '||missing_count problem_label,
          'Equipment: '||equipment_issue_count||' · no data: '||equipment_missing_count||' · Inc.: '||incident_count equipment_label
        FROM totals CROSS JOIN thresholds t ORDER BY CASE site_key WHEN 'DC-N' THEN 1 WHEN 'DC-E' THEN 2 ELSE 3 END,site_key
    """,
    )
    add(
        "network_power_history",
        """
        , ticks AS (SELECT generate_series(p.at-interval '2 hours',p.at,interval '5 minutes') at FROM p),
        measures AS (
          SELECT t.at,h.server_id,m.value
          FROM ticks t CROSS JOIN hosts h
          LEFT JOIN dcmon.metric_series s ON s.ci_id=h.server_id
             AND s.metric_id=(SELECT id FROM dcmon.metric_definition WHERE code='power_w')
          LEFT JOIN LATERAL (SELECT z.value FROM dcmon.metric_sample z
             WHERE z.series_id=s.series_id AND z.observed_at<=t.at
             AND z.observed_at>t.at-interval '60 seconds' AND z.quality='ok'
             ORDER BY z.observed_at DESC LIMIT 1) m ON true
        )
        SELECT to_char(t.at AT TIME ZONE 'Europe/Moscow','HH24:MI') time_label,
          CASE WHEN count(m.server_id)>0 AND count(m.value)=count(m.server_id)
            THEN round(sum(m.value)/1000,2) END power_kw,
          count(m.server_id)::int server_count,count(m.value)::int measured_count
        FROM ticks t LEFT JOIN measures m ON m.at=t.at GROUP BY t.at ORDER BY t.at
    """,
    )
    add(
        "network_incident",
        """
        SELECT coalesce((SELECT incident_key FROM events ORDER BY detected_at DESC,incident_key LIMIT 1),'No active incidents') incident_key,
          coalesce((SELECT title FROM events ORDER BY detected_at DESC,incident_key LIMIT 1),'No related incidents within the selected filters') title,
          (SELECT count(DISTINCT incident_id)::int FROM events) incident_count
    """,
    )
    add(
        "it_context",
        """
        SELECT CASE WHEN p.site_id=0 THEN 'All DCs' ELSE coalesce((SELECT name FROM dcmon.ci WHERE ci_id=p.site_id),'Unknown data center') END site_label
        FROM p
    """,
    )
