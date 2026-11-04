"""Register the compact base64 JSON scene payload for Infrastructure/overview.

The common facts/metrics/events restrict server telemetry to the report scope;
placements and inventory_states retain all physical objects at the fixed instant.
This distinction makes rack occupancy and support equipment truthful even when
system/environment/software filters exclude some servers. Switch device/port
telemetry uses all_metrics, so it is not restricted to selected servers.

sites, rooms, racks, devices and servers serialize as rows with alphabetically
sorted *_columns arrays. disk_metric_codes and port_metric_codes describe sorted
metric arrays. history_times is shared by every server; history contains 13
[cpu,memory,temperature] triples at five-minute ticks over one hour. The latest
sample at or before each tick is accepted only when quality, validity bounds and
its metric_series.stale_after_sec all pass; rejected readings remain JSON null.

Output grain is exactly one payload_base64 row. Base64 wraps UTF-8 JSON with no
line breaks and is intended for the iframe URL fragment. Inventory arrays become
[] when empty; column metadata can be null when its source entity table is empty.
The browser decodes/validates references before drawing. Component targets retain
numeric inventory IDs and one-based disk indices; no credentials enter payloads.
"""


def register(add):
    """Add this page's named queries through the shared registration callback.

    The callback prepends COMMON by default. Leading-comma statements extend its
    CTE chain; lookup-only statements explicitly opt out. No query executes here.
    """
    add(
        "scene_payload",
        """
      , placements AS MATERIALIZED (
        SELECT dp.* FROM dcmon.device_placement dp CROSS JOIN p
        WHERE tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at
      ), inventory_states AS MATERIALIZED (
        SELECT s.* FROM p CROSS JOIN LATERAL dcmon.status_snapshot(p.at) s
      ), scene_sites AS (
        SELECT st.ci_id id,c.ci_key key,c.name FROM dcmon.site st JOIN dcmon.ci c ON c.ci_id=st.ci_id
      ), scene_rooms AS (
        SELECT r.ci_id id,c.ci_key key,c.name,r.site_id,r.area_m2
        FROM dcmon.room r JOIN dcmon.ci c ON c.ci_id=r.ci_id
      ), scene_racks AS (
        SELECT r.ci_id id,c.ci_key key,c.name,r.room_id,r.height_u,r.power_limit_kw,r.x_m,r.y_m,
          coalesce((SELECT sum(dp.u_height) FROM placements dp WHERE dp.rack_id=r.ci_id AND dp.u_start IS NOT NULL),0)::int occupied_u
        FROM dcmon.rack r JOIN dcmon.ci c ON c.ci_id=r.ci_id
      ), disk_values AS (
        SELECT m.ci_id,m.labels->>'disk' name,m.labels->>'media' media,m.labels->>'mount' mount,
          jsonb_agg(m.display_value ORDER BY m.metric_code) metrics
        FROM metrics m WHERE m.labels ? 'disk' GROUP BY m.ci_id,m.labels->>'disk',m.labels->>'media',m.labels->>'mount'
      ), scene_disks AS (
        SELECT ci_id,jsonb_agg(jsonb_build_object('name',name,'media',media,'mount',mount,'metrics',metrics) ORDER BY name) disks FROM disk_values GROUP BY ci_id
      ), port_values AS (
        SELECT m.ci_id,(m.labels->>'port_id')::bigint port_id,jsonb_agg(m.display_value ORDER BY m.metric_code) metrics
        FROM all_metrics m WHERE m.labels ? 'port_id' GROUP BY m.ci_id,m.labels->>'port_id'
      ), scene_ports AS (
        SELECT p.device_id,jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'speed_mbps',p.speed_mbps,'metrics',v.metrics,
          'linked',l.id IS NOT NULL,'peer_id',peer.device_id,'peer',pc.ci_key||' · '||peer.name) ORDER BY p.id) ports
        FROM dcmon.network_port p JOIN dcmon.device d ON d.ci_id=p.device_id AND d.device_class='switch'
        LEFT JOIN port_values v ON v.port_id=p.id CROSS JOIN param
        LEFT JOIN dcmon.network_link l ON (l.port_a_id=p.id OR l.port_b_id=p.id) AND tstzrange(l.valid_from,l.valid_to,'[)') @> param.at
        LEFT JOIN dcmon.network_port peer ON peer.id=CASE WHEN l.port_a_id=p.id THEN l.port_b_id ELSE l.port_a_id END
        LEFT JOIN dcmon.ci pc ON pc.ci_id=peer.device_id GROUP BY p.device_id
      ), switch_values AS (
        SELECT m.ci_id,jsonb_object_agg(m.metric_code,m.display_value) metrics FROM all_metrics m
        JOIN dcmon.device d ON d.ci_id=m.ci_id AND d.device_class='switch' WHERE m.labels='{}'::jsonb GROUP BY m.ci_id
      ), scene_devices AS (
        SELECT d.ci_id id,c.ci_key key,c.name,d.device_class kind,dp.room_id,dp.rack_id,dp.u_start,dp.u_height,
          coalesce(s.state,'unknown') state,sv.metrics,sp.ports
        FROM dcmon.device d JOIN dcmon.ci c ON c.ci_id=d.ci_id JOIN placements dp ON dp.device_id=d.ci_id
        LEFT JOIN inventory_states s ON s.ci_id=d.ci_id
        LEFT JOIN switch_values sv ON sv.ci_id=d.ci_id LEFT JOIN scene_ports sp ON sp.device_id=d.ci_id
      ), history_points AS (
        SELECT f.server_id,t.at,
          max(CASE WHEN z.quality='ok' AND t.at-z.observed_at<=ms.stale_after_sec*interval '1 second'
            AND (md.valid_min IS NULL OR z.value>=md.valid_min) AND (md.valid_max IS NULL OR z.value<=md.valid_max)
            THEN z.value END) FILTER(WHERE md.code='cpu_pct') cpu,
          max(CASE WHEN z.quality='ok' AND t.at-z.observed_at<=ms.stale_after_sec*interval '1 second'
            AND (md.valid_min IS NULL OR z.value>=md.valid_min) AND (md.valid_max IS NULL OR z.value<=md.valid_max)
            THEN z.value END) FILTER(WHERE md.code='memory_pct') memory,
          max(CASE WHEN z.quality='ok' AND t.at-z.observed_at<=ms.stale_after_sec*interval '1 second'
            AND (md.valid_min IS NULL OR z.value>=md.valid_min) AND (md.valid_max IS NULL OR z.value<=md.valid_max)
            THEN z.value END) FILTER(WHERE md.code='inlet_c') temperature
        FROM facts f CROSS JOIN p CROSS JOIN LATERAL generate_series(p.at-interval '60 minutes',p.at,interval '5 minutes') t(at)
        LEFT JOIN dcmon.metric_series ms ON ms.ci_id=f.server_id AND ms.metric_id IN (SELECT id FROM dcmon.metric_definition WHERE code IN ('cpu_pct','memory_pct','inlet_c'))
        LEFT JOIN dcmon.metric_definition md ON md.id=ms.metric_id AND md.code IN ('cpu_pct','memory_pct','inlet_c')
        LEFT JOIN LATERAL (SELECT q.value,q.quality,q.observed_at FROM dcmon.metric_sample q
          WHERE q.series_id=ms.series_id AND md.id IS NOT NULL AND q.observed_at<=t.at ORDER BY q.observed_at DESC LIMIT 1) z ON true
        GROUP BY f.server_id,t.at
      ), scene_history AS (
        SELECT server_id,jsonb_agg(jsonb_build_array(cpu,memory,temperature) ORDER BY at) history
        FROM history_points GROUP BY server_id
      ), scene_servers AS (
        SELECT f.server_id id,f.server_key key,f.state,f.cpu,f.memory,f.temperature,f.power_w,
          f.disk_used_pct,f.disk_c,f.disk_busy_pct,sd.disks,f.unavailable_metrics,f.incident_count,f.model,f.cpu_cores,f.memory_gib,f.site_id,f.rack_id,
          coalesce((SELECT jsonb_agg(jsonb_build_object('key',e.incident_key,'title',e.title) ORDER BY e.incident_key)
            FROM events e WHERE e.server_id=f.server_id),'[]'::jsonb) incidents,coalesce(sh.history,'[]'::jsonb) history
        FROM facts f LEFT JOIN scene_history sh ON sh.server_id=f.server_id LEFT JOIN scene_disks sd ON sd.ci_id=f.server_id
      ), payload AS (
        SELECT jsonb_build_object(
          'as_of','2026-10-21T14:32:00+03:00',
          'history_times',(SELECT jsonb_agg(jsonb_build_object('at',t,'time_label',to_char(t AT TIME ZONE 'Europe/Moscow','HH24:MI')) ORDER BY t) FROM generate_series(p.at-interval '60 minutes',p.at,interval '5 minutes') t),
          'disk_metric_codes',(SELECT jsonb_agg(code ORDER BY code) FROM dcmon.metric_definition WHERE left(code,5)='disk_'),
          'port_metric_codes',(SELECT jsonb_agg(code ORDER BY code) FROM dcmon.metric_definition WHERE left(code,4)='net_'),
          'metric_definitions',(SELECT jsonb_object_agg(code,jsonb_build_object('valid_min',valid_min,'valid_max',valid_max,'warning_above',warning_above,'critical_above',critical_above)) FROM dcmon.metric_definition ),
          'filters',jsonb_build_object('p_system',p.system_id,'p_env',p.env_id,'p_software',p.software_id,
            'p_site',p.site_id,'p_scene_server',@@p_scene_server@@::bigint,'p_scene_target',@@p_scene_target@@::bigint,'p_scene_part',@@p_scene_part@@::bigint),
          'sites_columns',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_each((SELECT to_jsonb(s) FROM scene_sites s LIMIT 1))),
          'sites',coalesce((SELECT jsonb_agg((SELECT jsonb_agg(value ORDER BY key) FROM jsonb_each(to_jsonb(s))) ORDER BY id) FROM scene_sites s),'[]'::jsonb),
          'rooms_columns',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_each((SELECT to_jsonb(s) FROM scene_rooms s LIMIT 1))),
          'rooms',coalesce((SELECT jsonb_agg((SELECT jsonb_agg(value ORDER BY key) FROM jsonb_each(to_jsonb(s))) ORDER BY id) FROM scene_rooms s),'[]'::jsonb),
          'racks_columns',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_each((SELECT to_jsonb(s) FROM scene_racks s LIMIT 1))),
          'racks',coalesce((SELECT jsonb_agg((SELECT jsonb_agg(value ORDER BY key) FROM jsonb_each(to_jsonb(s))) ORDER BY id) FROM scene_racks s),'[]'::jsonb),
          'devices_columns',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_each((SELECT to_jsonb(s) FROM scene_devices s LIMIT 1))),
          'devices',coalesce((SELECT jsonb_agg((SELECT jsonb_agg(value ORDER BY key) FROM jsonb_each(to_jsonb(s))) ORDER BY id) FROM scene_devices s),'[]'::jsonb),
          'servers_columns',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_each((SELECT to_jsonb(s) FROM scene_servers s LIMIT 1))),
          'servers',coalesce((SELECT jsonb_agg((SELECT jsonb_agg(value ORDER BY key) FROM jsonb_each(to_jsonb(s))) ORDER BY id) FROM scene_servers s),'[]'::jsonb)
        ) data FROM p
      )
      SELECT replace(encode(convert_to(data::text,'UTF8'),'base64'),chr(10),'') payload_base64 FROM payload
    """,
    )
