-- p: normalize numeric parameters and pin the reproducible snapshot instant.
WITH RECURSIVE localized_ci AS MATERIALIZED (SELECT ci_id,ci_key,kind,CASE WHEN name LIKE 'Стойка %' THEN 'Rack '||substr(name,8) ELSE CASE name WHEN 'Автоматизированная банковская система' THEN 'Core Banking' WHEN 'Дистанционное банковское обслуживание' THEN 'Digital Banking' WHEN 'Кадровая система' THEN 'Human Resources' WHEN 'Мониторинг инфраструктуры' THEN 'Infrastructure Monitoring' WHEN 'Управление отношениями с клиентами' THEN 'Customer Relationship Management' WHEN 'Хранилище данных' THEN 'Data Warehouse' WHEN 'ЦОД «Север»' THEN 'DC North' WHEN 'ЦОД «Восток»' THEN 'DC East' WHEN 'ЦОД «Резерв»' THEN 'DC Reserve' WHEN 'Зал A · Север' THEN 'Hall A · North' WHEN 'Зал A · Восток' THEN 'Hall A · East' WHEN 'Зал A · Резерв' THEN 'Hall A · Reserve' WHEN 'Зал B · Север' THEN 'Hall B · North' WHEN 'Зал B · Восток' THEN 'Hall B · East' WHEN 'Зал B · Резерв' THEN 'Hall B · Reserve' ELSE name END END AS name,owner_team_id,lifecycle,retired_at,first_seen_at,last_seen_at FROM dcmon.ci),
localized_incident AS MATERIALIZED (SELECT id,incident_key,source_id,external_id,CASE title WHEN 'CRAC-02: снижена холодопроизводительность; температура R12 29,4 °C' THEN 'CRAC-02: reduced cooling capacity; R12 inlet temperature 29.4 °C' WHEN 'Кратковременная потеря связи' THEN 'Brief connectivity loss' ELSE title END AS title,severity,detected_at,owner_team_id,response_due_at FROM dcmon.incident),
localized_metric_definition AS MATERIALIZED (SELECT id,code,CASE name WHEN 'Загрузка CPU' THEN 'CPU utilization' WHEN 'Занятость IO' THEN 'I/O utilization' WHEN 'Температура диска' THEN 'Disk temperature' WHEN 'Ёмкость диска' THEN 'Disk capacity' WHEN 'Задержка диска' THEN 'Disk latency' WHEN 'Чтение: IOPS' THEN 'Read IOPS' WHEN 'Скорость чтения' THEN 'Read throughput' WHEN 'Ошибки SMART' THEN 'SMART errors' WHEN 'Занято на диске' THEN 'Disk used' WHEN 'Диск: занято' THEN 'Disk utilization' WHEN 'Запись: IOPS' THEN 'Write IOPS' WHEN 'Скорость записи' THEN 'Write throughput' WHEN 'Скорость вентилятора' THEN 'Fan speed' WHEN 'Влажность' THEN 'Humidity' WHEN 'Температура на входе' THEN 'Inlet temperature' WHEN 'Занято RAM' THEN 'RAM utilization' WHEN 'Потери в секунду' THEN 'Drops per second' WHEN 'Ошибки в секунду' THEN 'Errors per second' WHEN 'Состояние порта' THEN 'Port status' WHEN 'Приём' THEN 'Receive' WHEN 'Передача' THEN 'Transmit' WHEN 'Загрузка порта' THEN 'Port utilization' WHEN 'Принятые байты' THEN 'Received bytes' WHEN 'Активная мощность' THEN 'Active power' WHEN 'Занято дисковое пространство' THEN 'Storage utilization' WHEN 'Температура коммутатора' THEN 'Switch temperature' ELSE name END AS name,unit,metric_type,valid_min,valid_max,warning_above,critical_above FROM dcmon.metric_definition),
p AS (
 SELECT ${INT(p_system)}::bigint system_id,${INT(p_env)}::int env_id,
 ${INT(p_software)}::bigint software_id,${INT(NVL(p_server,0))}::bigint selected_id,
 ${INT(NVL(p_site,0))}::bigint site_id,
 greatest(1,${INT(p_page)}::int) requested_page,
 '2026-10-21 14:32:00+03'::timestamptz at
),
-- param: resolve external IDs and reject invalid system/software/environment filters.
param AS (
 SELECT p.*,sy.ci_key system_key,sp.code software_code,
 CASE env_id WHEN 1 THEN 'PROD' WHEN 2 THEN 'TEST' WHEN 3 THEN 'DEV' END environment
 FROM p LEFT JOIN dcmon.information_system s ON s.ci_id=p.system_id
 LEFT JOIN localized_ci sy ON sy.ci_id=s.ci_id
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
 JOIN localized_incident i ON i.id=ic.incident_id CROSS JOIN param p
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
 replace(dev.model,' диска',' drives') AS model,dev.cpu_cores,dev.memory_gib,
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
 FROM hosts h JOIN localized_ci c ON c.ci_id=h.server_id
 JOIN dcmon.device dev ON dev.ci_id=h.server_id CROSS JOIN param p
 LEFT JOIN states st ON st.ci_id=h.server_id
 LEFT JOIN dcmon.device_placement dp ON dp.device_id=h.server_id AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at
 LEFT JOIN localized_ci rack_ci ON rack_ci.ci_id=dp.rack_id
 LEFT JOIN dcmon.room room ON room.ci_id=dp.room_id LEFT JOIN localized_ci room_ci ON room_ci.ci_id=room.ci_id
 LEFT JOIN localized_ci site_ci ON site_ci.ci_id=room.site_id LEFT JOIN metrics m ON m.ci_id=h.server_id
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
 JOIN localized_ci ic ON ic.ci_id=si.ci_id JOIN localized_ci host ON host.ci_id=ip.host_id
 WHERE p.software_id=0 OR sp.id=p.software_id
)

, eligible AS MATERIALIZED (
 SELECT d.ci_id id,c.ci_key key,c.name,d.device_class kind,dp.room_id,dp.rack_id,
   r.site_id,sc.name site_name,rc.name room_name,kc.ci_key rack_key,
   coalesce(st.state,'unknown') state,CASE st.reason WHEN 'Демо: HDD /data — 97%, 58 °C, задержка 42 мс' THEN 'Demo: HDD /data at 97%, 58 °C, 42 ms latency' WHEN 'Демонстрационное штатное состояние' THEN 'Demo: normal operation' WHEN 'Нет наблюдения' THEN 'No observation' WHEN 'Демо: port-1 — 92%, ошибки и потери пакетов' THEN 'Demo: port-1 at 92%, packet errors and drops' WHEN 'Нет телеметрии' THEN 'No telemetry' WHEN 'Высокая температура / снижена холодопроизводительность' THEN 'High temperature / reduced cooling capacity' ELSE st.reason END AS reason,st.observed_at state_at
 FROM dcmon.device d JOIN localized_ci c ON c.ci_id=d.ci_id CROSS JOIN param p
 JOIN dcmon.device_placement dp ON dp.device_id=d.ci_id AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p.at
 JOIN dcmon.room r ON r.ci_id=dp.room_id JOIN localized_ci sc ON sc.ci_id=r.site_id
 JOIN localized_ci rc ON rc.ci_id=r.ci_id LEFT JOIN localized_ci kc ON kc.ci_id=dp.rack_id
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
 JOIN localized_metric_definition md ON md.code=m.metric_code JOIN dcmon.metric_series ms ON ms.series_id=m.series_id
), live_incidents AS MATERIALIZED (
 SELECT DISTINCT ON(i.id) i.id,i.incident_key,i.title,i.severity,i.detected_at,e.id device_id,e.key,e.kind,e.site_id,e.site_name,e.room_name,e.rack_key,e.room_id,e.rack_id
 FROM localized_incident i JOIN dcmon.incident_ci ic ON ic.incident_id=i.id
 JOIN eligible e ON e.id=ic.ci_id CROSS JOIN p
 JOIN LATERAL (SELECT ie.state FROM dcmon.incident_event ie WHERE ie.incident_id=i.id AND ie.occurred_at<=p.at ORDER BY ie.occurred_at DESC,ie.id DESC LIMIT 1) ev ON true
 WHERE i.detected_at<=p.at AND ic.linked_at<=p.at AND ev.state NOT IN ('resolved','closed')
 ORDER BY i.id,(e.kind='crac') DESC,e.id
)

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

 SELECT replace(encode(convert_to(jsonb_build_object(
 'as_of',p.at,'window_start',p.at-interval '2 hours',
 'filters',jsonb_build_object('p_system',p.system_id,'p_env',p.env_id,'p_software',p.software_id,'p_site',p.site_id),
 'problems',coalesce((SELECT jsonb_agg(to_jsonb(q) ORDER BY CASE severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END,key,part,title) FROM problems q),'[]'::jsonb)
 )::text,'UTF8'),'base64'),chr(10),'') payload_base64 FROM p;
