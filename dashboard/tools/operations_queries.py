"""Register the Issues queue, device lookup and bounded History JSON datasets.

All projections append SCOPE to the common path/snapshot pipeline. eligible keeps
actively placed devices in the requested site: servers must also belong to hosts,
while network/facility devices are independent of the application filters.
observed joins snapshot readings to metric metadata, treating null as unknown and
a down installed network link as critical. live_incidents chooses one eligible
representative device per incident, preferring cooling equipment then device ID.

QUEUE preserves one row per problematic metric series, plus a device-state row
only when no metric problem already represents that device, plus one row per
active incident. A device can therefore have multiple issues. Onset estimates
search two hours of samples; ongoing_before_window means no in-window last-good
sample was found and must not be presented as a precise onset. Missing stale
telemetry starts at observed_at + stale_after_sec; other missing-data causes keep
the last observation instant when known. No unbounded history is inferred.

History auto-selection ranks device status then server preference then ID. A
nonzero requested device outside eligible yields device=null and empty arrays;
it never silently switches devices. Each series has 25 five-minute points over
two hours, with latest-at-or-before samples validated by quality, range and its
own stale_after_sec. Invalid readings are JSON null, never zero/interpolated.
selected_series is a display focus hint, not a database series filter. Related
incidents include those detected in-window or still active, including dependency
incidents for a selected server. All payloads are one UTF-8/base64 row; see the
dataset contract for named JSON fields, units and empty-state details.
"""

SCOPE = """
, eligible AS MATERIALIZED (
 SELECT d.ci_id id,c.ci_key key,c.name,d.device_class kind,dp.room_id,dp.rack_id,
   r.site_id,sc.name site_name,rc.name room_name,kc.ci_key rack_key,
   coalesce(st.state,'unknown') state,st.reason,st.observed_at state_at
 FROM dcmon.device d JOIN dcmon.ci c ON c.ci_id=d.ci_id CROSS JOIN param p
 JOIN dcmon.device_placement dp ON dp.device_id=d.ci_id AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at
 JOIN dcmon.room r ON r.ci_id=dp.room_id JOIN dcmon.ci sc ON sc.ci_id=r.site_id
 JOIN dcmon.ci rc ON rc.ci_id=r.ci_id LEFT JOIN dcmon.ci kc ON kc.ci_id=dp.rack_id
 LEFT JOIN LATERAL (SELECT s.* FROM dcmon.status_snapshot(p.at) s WHERE s.ci_id=d.ci_id) st ON true
 WHERE (p.site_id=0 OR r.site_id=p.site_id)
 AND (d.device_class<>'server' OR EXISTS(SELECT 1 FROM hosts h WHERE h.server_id=d.ci_id))
), observed AS MATERIALIZED (
 SELECT m.*,md.name metric_name,md.warning_above,md.critical_above,md.valid_min,md.valid_max,ms.stale_after_sec,
   e.kind,e.key,e.site_id,e.site_name,e.room_name,e.rack_key,e.room_id,e.rack_id,
   CASE WHEN m.display_value IS NULL THEN 'unknown'
     WHEN m.metric_code='net_link_up' AND m.display_value=0 AND EXISTS(
       SELECT 1 FROM dcmon.network_link l CROSS JOIN p WHERE (l.port_a_id=(m.labels->>'port_id')::bigint OR l.port_b_id=(m.labels->>'port_id')::bigint) AND tstzrange(l.valid_from,l.valid_to,'[)') @> p.at) THEN 'critical'
     WHEN m.display_value>md.critical_above THEN 'critical'
     WHEN m.display_value>md.warning_above THEN 'warning' ELSE 'healthy' END severity
 FROM all_metrics m JOIN eligible e ON e.id=m.ci_id
 JOIN dcmon.metric_definition md ON md.code=m.metric_code JOIN dcmon.metric_series ms ON ms.series_id=m.series_id
), live_incidents AS MATERIALIZED (
 SELECT DISTINCT ON(i.id) i.id,i.incident_key,i.title,i.severity,i.detected_at,e.id device_id,e.key,e.kind,e.site_id,e.site_name,e.room_name,e.rack_key,e.room_id,e.rack_id
 FROM dcmon.incident i JOIN dcmon.incident_ci ic ON ic.incident_id=i.id
 JOIN eligible e ON e.id=ic.ci_id CROSS JOIN p
 JOIN LATERAL (SELECT ie.state FROM dcmon.incident_event ie WHERE ie.incident_id=i.id AND ie.occurred_at<=p.at ORDER BY ie.occurred_at DESC,ie.id DESC LIMIT 1) ev ON true
 WHERE i.detected_at<=p.at AND ic.linked_at<=p.at AND ev.state NOT IN ('resolved','closed')
 ORDER BY i.id,(e.kind='crac') DESC,e.id
)
"""

QUEUE = """
, metric_problems AS (
 SELECT 'm:'||o.series_id id,o.ci_id device_id,o.series_id,o.key,o.kind,o.site_id,o.site_name,o.room_name,o.rack_key,
   o.room_id,o.rack_id,
   CASE WHEN o.labels ? 'disk' THEN 'disk' WHEN left(o.metric_code,4)='net_' THEN 'network' ELSE CASE WHEN o.kind='server' THEN 'server' ELSE 'equipment' END END category,
   coalesce(o.labels->>'disk',o.labels->>'port','') part,
   CASE WHEN o.labels ? 'disk' THEN CASE WHEN o.labels->>'disk'='sdb' THEN 2 ELSE 1 END WHEN o.labels ? 'port_id' THEN (o.labels->>'port_id')::bigint ELSE 0 END target_part,
   o.metric_name title,o.metric_code,o.severity,o.display_value value,o.unit,o.warning_above,o.critical_above,o.observed_at,
   CASE WHEN o.severity='unknown' THEN CASE WHEN o.freshness='stale' THEN o.observed_at+o.stale_after_sec*interval '1 second' ELSE o.observed_at END ELSE first_bad.at END since,
   o.severity<>'unknown' AND last_good.at IS NULL ongoing_before_window,
   CASE WHEN o.severity='unknown' THEN 'No valid recent reading' WHEN o.metric_code='net_link_up' THEN 'Connected port is down' ELSE 'Threshold exceeded' END reason
 FROM observed o CROSS JOIN p
 LEFT JOIN LATERAL (
  SELECT max(q.observed_at) at FROM dcmon.metric_sample q WHERE q.series_id=o.series_id AND q.observed_at BETWEEN p.at-interval '2 hours' AND p.at
  AND q.quality='ok' AND (o.valid_min IS NULL OR q.value>=o.valid_min) AND (o.valid_max IS NULL OR q.value<=o.valid_max)
  AND CASE WHEN o.metric_code='net_link_up' THEN q.value=1 ELSE q.value<=coalesce(o.warning_above,o.critical_above) END
 ) last_good ON o.severity<>'unknown'
 LEFT JOIN LATERAL (
  SELECT min(q.observed_at) at FROM dcmon.metric_sample q WHERE q.series_id=o.series_id AND q.observed_at BETWEEN p.at-interval '2 hours' AND p.at
  AND (last_good.at IS NULL OR q.observed_at>last_good.at) AND q.quality='ok'
  AND CASE WHEN o.metric_code='net_link_up' THEN q.value=0 ELSE q.value>coalesce(o.warning_above,o.critical_above) END
 ) first_bad ON o.severity<>'unknown'
 WHERE o.severity IN ('critical','warning','unknown')
), state_problems AS (
 SELECT 's:'||e.id id,e.id device_id,0::bigint series_id,e.key,e.kind,e.site_id,e.site_name,e.room_name,e.rack_key,e.room_id,e.rack_id,
   CASE WHEN e.kind='server' THEN 'server' WHEN e.kind='switch' THEN 'network' ELSE 'equipment' END category,
   '' part,0::bigint target_part,'Equipment status' title,'' metric_code,e.state severity,NULL::numeric value,'' unit,NULL::numeric warning_above,NULL::numeric critical_above,e.state_at observed_at,
   e.state_at since,false ongoing_before_window,e.reason
 FROM eligible e WHERE e.state IN ('critical','warning','unknown')
 AND NOT EXISTS(SELECT 1 FROM metric_problems mp WHERE mp.device_id=e.id)
), incident_problems AS (
 SELECT 'i:'||i.id id,i.device_id,0::bigint series_id,i.key,i.kind,i.site_id,i.site_name,i.room_name,i.rack_key,i.room_id,i.rack_id,'incident' category,
  i.incident_key part,0::bigint target_part,i.title,'' metric_code,
  CASE WHEN i.severity IN ('critical','P1','critical_high') THEN 'critical' ELSE 'warning' END severity,
  NULL::numeric value,'' unit,NULL::numeric warning_above,NULL::numeric critical_above,i.detected_at observed_at,i.detected_at since,false ongoing_before_window,'Active incident' reason
 FROM live_incidents i
), problems AS (SELECT * FROM metric_problems UNION ALL SELECT * FROM state_problems UNION ALL SELECT * FROM incident_problems)
"""


def register(add):
    """Add this page's named queries through the shared registration callback.

    The callback prepends COMMON by default. Leading-comma statements extend its
    CTE chain; lookup-only statements explicitly opt out. No query executes here.
    """
    add(
        "filters_history_device",
        SCOPE
        + """
 SELECT 0::bigint id,'Auto-select device'::text label UNION ALL
 SELECT id,key||' · '||site_name label FROM eligible ORDER BY id
 """,
    )
    add(
        "problems_payload",
        SCOPE
        + QUEUE
        + """
 SELECT replace(encode(convert_to(jsonb_build_object(
 'as_of',p.at,'window_start',p.at-interval '2 hours',
 'filters',jsonb_build_object('p_system',p.system_id,'p_env',p.env_id,'p_software',p.software_id,'p_site',p.site_id),
 'problems',coalesce((SELECT jsonb_agg(to_jsonb(q) ORDER BY CASE severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END,key,part,title) FROM problems q),'[]'::jsonb)
 )::text,'UTF8'),'base64'),chr(10),'') payload_base64 FROM p
 """,
    )
    add(
        "history_payload",
        SCOPE
        + """
 , selected AS (
  SELECT e.* FROM eligible e CROSS JOIN p
  WHERE @@p_history_device@@=0 OR e.id=@@p_history_device@@
  ORDER BY CASE e.state WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END,(e.kind='server') DESC,e.id LIMIT 1
 ), selected_incidents AS (
  SELECT DISTINCT i.id,i.incident_key,i.title,i.severity,i.detected_at
  FROM dcmon.incident i JOIN dcmon.incident_ci ic ON ic.incident_id=i.id CROSS JOIN selected s CROSS JOIN p
  JOIN LATERAL (SELECT ie.state FROM dcmon.incident_event ie WHERE ie.incident_id=i.id AND ie.occurred_at<=p.at ORDER BY ie.occurred_at DESC,ie.id DESC LIMIT 1) ev ON true
  WHERE (ic.ci_id=s.id OR EXISTS(SELECT 1 FROM walk w WHERE w.server_id=s.id AND w.node_id=ic.ci_id))
  AND i.detected_at<=p.at AND ic.linked_at<=p.at
  AND (i.detected_at>=p.at-interval '2 hours' OR ev.state NOT IN ('resolved','closed'))
 ), history_series AS (
  SELECT ms.series_id,ms.ci_id,ms.labels,ms.stale_after_sec,md.*,
   CASE WHEN ms.labels ? 'port_id' THEN EXISTS(SELECT 1 FROM dcmon.network_link l CROSS JOIN p WHERE (l.port_a_id=(ms.labels->>'port_id')::bigint OR l.port_b_id=(ms.labels->>'port_id')::bigint) AND tstzrange(l.valid_from,l.valid_to,'[)') @> p.at) ELSE false END linked
  FROM dcmon.metric_series ms JOIN selected e ON e.id=ms.ci_id JOIN dcmon.metric_definition md ON md.id=ms.metric_id
 ), history_points AS (
  SELECT hs.series_id,t.at,
   CASE WHEN q.quality='ok' AND t.at-q.observed_at<=hs.stale_after_sec*interval '1 second'
   AND (hs.valid_min IS NULL OR q.value>=hs.valid_min) AND (hs.valid_max IS NULL OR q.value<=hs.valid_max) THEN q.value END value
  FROM history_series hs CROSS JOIN p CROSS JOIN LATERAL generate_series(p.at-interval '2 hours',p.at,interval '5 minutes') t(at)
  LEFT JOIN LATERAL (SELECT * FROM dcmon.metric_sample q WHERE q.series_id=hs.series_id AND q.observed_at<=t.at ORDER BY q.observed_at DESC LIMIT 1) q ON true
 ), history_rows AS (
  SELECT hs.series_id id,hs.code,hs.name,hs.unit,hs.labels,hs.warning_above,hs.critical_above,hs.valid_min,hs.valid_max,hs.linked,
   (SELECT jsonb_agg(round(hp.value,3) ORDER BY hp.at) FROM history_points hp WHERE hp.series_id=hs.series_id) values
  FROM history_series hs
 )
 SELECT replace(encode(convert_to(jsonb_build_object(
 'as_of',p.at,'window_start',p.at-interval '2 hours',
 'filters',jsonb_build_object('p_system',p.system_id,'p_env',p.env_id,'p_software',p.software_id,'p_site',p.site_id),
 'selected_series',@@p_history_series@@,'requested_device',@@p_history_device@@,
 'device',(SELECT to_jsonb(e) FROM selected e),
 'times',(SELECT jsonb_agg(t ORDER BY t) FROM generate_series(p.at-interval '2 hours',p.at,interval '5 minutes') t),
 'series',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM history_rows h),'[]'::jsonb),
 'incidents',coalesce((SELECT jsonb_agg(to_jsonb(i)) FROM selected_incidents i),'[]'::jsonb)
 )::text,'UTF8'),'base64'),chr(10),'') payload_base64 FROM p
 """,
    )
