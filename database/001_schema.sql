-- Authoritative dcmon definitions captured read-only from the synthetic demo.
-- PostgreSQL 16 is required (range/multirange exclusion constraints and JSONB).
-- No owners, grants, roles, connection configuration or data are included.
-- Restore this file before 002_demo_data.sql.gz, then apply 003_comments.sql.
-- Definitions intentionally preserve deployed constraints, indexes and traversal
-- rules. Only human-readable status/interpretation strings are translated.
-- Objects are emitted in dependency order by pg_dump. Function body validation
-- is postponed because traversal functions refer to tables created later.
-- Inventory subtype triggers enforce CI kind; typed graph triggers validate
-- endpoint classes. Foreign keys alone cannot express those semantic rules.
-- All validity intervals are half-open [valid_from, valid_to); NULL is infinity.

--
-- PostgreSQL database dump
--

-- Dumped from database version 16.2
-- Dumped by pg_dump version 16.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: dcmon; Type: SCHEMA; Schema: -; Owner: -
--

-- A pre-existing dcmon schema must be rejected by the installer. No DROP is used.
CREATE SCHEMA dcmon;

-- GiST equality support combines entity IDs with validity ranges in exclusion
-- constraints, preventing simultaneous placements, hosts and network cables.
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: check_compute_reference(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment.
-- A compute target is a physical server or any runtime; only deployment may additionally target
-- software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately
-- require existence. Uses the caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_compute_reference() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE target bigint;
BEGIN
 IF TG_TABLE_NAME='deployment' THEN target:=NEW.target_id; ELSE target:=NEW.host_id; END IF;
 IF NOT is_compute(target) AND NOT (TG_TABLE_NAME='deployment' AND EXISTS(SELECT 1 FROM software_installation WHERE ci_id=target)) THEN
 RAISE EXCEPTION 'Target must be compute or a deployment installation' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;


--
-- Name: check_dependency(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Checks directed consumer/provider types on dependency INSERT/UPDATE. Application: component to
-- component/installation; power: device/rack to PDU/UPS/generator; cooling: room/rack/device to
-- CRAC/chiller; network: device/runtime to switch; storage: device/runtime to storage. Rejects
-- unknown/missing endpoint types with SQLSTATE 23514; does not infer availability, redundancy or
-- traversal in the reverse direction. Uses caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_dependency() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE dk text; pk text; pc text;
BEGIN
 SELECT kind INTO dk FROM ci WHERE ci_id=NEW.dependent_id;
 SELECT kind INTO pk FROM ci WHERE ci_id=NEW.provider_id;
 SELECT device_class INTO pc FROM device WHERE ci_id=NEW.provider_id;
 IF NOT (CASE NEW.dependency_type
 WHEN 'application' THEN dk='component' AND pk IN ('component','installation')
 WHEN 'power' THEN dk IN ('device','rack') AND pc IN ('pdu','ups','generator')
 WHEN 'cooling' THEN dk IN ('room','rack','device') AND pc IN ('crac','chiller')
 WHEN 'network' THEN dk IN ('device','runtime') AND pc='switch'
 WHEN 'storage' THEN dk IN ('device','runtime') AND pc='storage'
 ELSE false END) IS TRUE THEN RAISE EXCEPTION 'Invalid dependency endpoint types' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;


--
-- Name: check_hosting(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Checks hosting INSERT/UPDATE hierarchy: VM to physical server, pod to VM/server, container to
-- pod. Rejects invalid or missing endpoint types with SQLSTATE 23514. Effective-dated overlap
-- constraints separately prevent simultaneous hosts. Uses caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_hosting() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE g text; h text;
BEGIN
 SELECT runtime_kind INTO g FROM runtime WHERE ci_id=NEW.guest_id;
 SELECT runtime_kind INTO h FROM runtime WHERE ci_id=NEW.host_id;
 IF NOT ((g='vm' AND EXISTS(SELECT 1 FROM device WHERE ci_id=NEW.host_id AND device_class='server'))
 OR (g='pod' AND (h='vm' OR EXISTS(SELECT 1 FROM device WHERE ci_id=NEW.host_id AND device_class='server')))
 OR (g='container' AND h='pod')) IS TRUE THEN RAISE EXCEPTION 'Invalid hosting types' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;


--
-- Name: check_metric_value(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- On metric_sample INSERT/UPDATE, validates only quality=ok against its definition
-- valid_min/valid_max. NULL bounds leave that side unrestricted. Table checks independently
-- require finite values for ok and NULL for missing/error. Warning and critical thresholds are
-- presentation guidance, never validity limits. Raises SQLSTATE 23514 for a range breach. Uses
-- caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_metric_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE lo numeric; hi numeric;
BEGIN
 IF NEW.quality='ok' THEN
 SELECT d.valid_min,d.valid_max INTO lo,hi FROM metric_definition d JOIN metric_series s ON s.metric_id=d.id WHERE s.series_id=NEW.series_id;
 IF NEW.value<lo OR NEW.value>hi THEN RAISE EXCEPTION 'Metric outside valid range' USING ERRCODE='23514'; END IF;
 END IF; RETURN NEW;
END $$;


--
-- Name: check_rack_space(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- On device_placement INSERT/UPDATE with a U interval, acquires a shared lock on the target rack
-- and checks inclusive top U (u_start+u_height-1) against height_u. NULL U denotes floor/0U
-- placement and bypasses the capacity test; table checks and exclusions enforce other
-- shape/overlap rules. Raises SQLSTATE 23514 on overflow. Uses caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_rack_space() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE max_u integer;
BEGIN
 IF NEW.u_start IS NOT NULL THEN
 SELECT height_u INTO max_u FROM rack WHERE ci_id=NEW.rack_id FOR SHARE;
 IF NEW.u_start+NEW.u_height-1>max_u THEN RAISE EXCEPTION 'Device exceeds rack U capacity' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;


--
-- Name: check_storage_device(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- On storage_volume INSERT/UPDATE, requires storage_device_id to identify a device of class
-- storage. Rejects absent or other-class devices with SQLSTATE 23514. A foreign key alone cannot
-- express the device-class requirement. Uses caller search_path dcmon,public.
CREATE FUNCTION dcmon.check_storage_device() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM device WHERE ci_id=NEW.storage_device_id AND device_class='storage') THEN RAISE EXCEPTION 'Volume requires storage device' USING ERRCODE='23514'; END IF; RETURN NEW;
END $$;


--
-- Name: compute_paths(timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns origin_id, terminal physical server_id and ordered node_ids for
-- server/runtime/installation origins visible at p_at. Follows hosting and
-- installation_placement intervals [valid_from,valid_to), excludes planned origins, respects
-- origin first_seen_at/retired_at, and includes a physical server own one-node path. Rejects
-- revisiting a path node and caps node count at 64. Multiple legitimate paths remain separate;
-- downstream selection deduplicates hosts. Does not reconstruct historical software versions.
CREATE FUNCTION dcmon.compute_paths(p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(origin_id bigint, server_id bigint, node_ids bigint[])
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 WITH RECURSIVE edges AS (
 SELECT guest_id a,host_id b FROM hosting WHERE tstzrange(valid_from,valid_to,'[)') @> p_at
 UNION SELECT installation_id,host_id FROM installation_placement WHERE tstzrange(valid_from,valid_to,'[)') @> p_at
 ), walk AS (
 SELECT c.ci_id origin,c.ci_id node,ARRAY[c.ci_id] path FROM ci c WHERE (is_compute(c.ci_id) OR c.kind='installation') AND c.lifecycle<>'planned' AND c.first_seen_at<=p_at AND (c.retired_at IS NULL OR c.retired_at>p_at)
 UNION ALL SELECT w.origin,e.b,w.path||e.b FROM walk w JOIN edges e ON e.a=w.node WHERE NOT e.b=ANY(w.path) AND cardinality(w.path)<64
 ) SELECT w.origin,w.node,w.path FROM walk w JOIN device d ON d.ci_id=w.node AND d.device_class='server'
$$;


--
-- Application traversal follows directed dependencies and contains cycle guards.
-- Name: execution_paths(timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns application-to-server execution paths at p_at: component root, first target, ordered
-- node_ids and system/environment keys. Traverses effective deployment, directed application
-- dependencies, installation placement and guest-to-host hosting using half-open intervals. The
-- visited-node guard prevents cycles and the 64-node cap bounds recursion. Emits each path
-- ending at a physical server; does not deduplicate paths or apply CI lifecycle visibility
-- independently of relationship intervals.
CREATE FUNCTION dcmon.execution_paths(p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(system_key text, environment text, component_key text, target_key text, server_key text, server_id bigint, node_ids bigint[])
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 WITH RECURSIVE edges AS (
 SELECT component_id a,target_id b FROM deployment WHERE tstzrange(valid_from,valid_to,'[)') @> p_at
 UNION
 SELECT dependent_id,provider_id FROM dependency WHERE dependency_type='application' AND tstzrange(valid_from,valid_to,'[)') @> p_at
 UNION
 SELECT installation_id,host_id FROM installation_placement WHERE tstzrange(valid_from,valid_to,'[)') @> p_at
 UNION
 SELECT guest_id,host_id FROM hosting WHERE tstzrange(valid_from,valid_to,'[)') @> p_at
 ), walk AS (
 SELECT c.ci_id root,c.ci_id node,NULL::bigint target,ARRAY[c.ci_id] path FROM component c
 UNION ALL
 SELECT w.root,e.b,coalesce(w.target,e.b),w.path||e.b FROM walk w JOIN edges e ON e.a=w.node
 WHERE NOT e.b=ANY(w.path) AND cardinality(w.path)<64
 )
 SELECT sy.ci_key,se.environment,cc.ci_key,tc.ci_key,sc.ci_key,sc.ci_id,w.path
 FROM walk w JOIN device d ON d.ci_id=w.node AND d.device_class='server'
 JOIN ci sc ON sc.ci_id=d.ci_id JOIN ci cc ON cc.ci_id=w.root JOIN ci tc ON tc.ci_id=w.target
 JOIN component c ON c.ci_id=w.root JOIN system_environment se ON se.id=c.environment_id JOIN ci sy ON sy.ci_id=se.system_id
$$;


--
-- Name: immutable_ci_kind(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Before ci kind updates, rejects a different subtype with SQLSTATE 23514 so existing subtype,
-- topology and telemetry references retain their interpretation. Other inventory attributes may
-- change. Retiring/replacing a CI preserves identity history instead of retyping it.
CREATE FUNCTION dcmon.immutable_ci_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 IF NEW.kind<>OLD.kind THEN RAISE EXCEPTION 'CI kind is immutable' USING ERRCODE='23514'; END IF; RETURN NEW;
END $$;


--
-- Name: immutable_device_class(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Before device_class updates, rejects a different class with SQLSTATE 23514 because dependency
-- and hosting rules rely on that class. Replace or retire an incorrectly classified device
-- through an explicit migration rather than silently reinterpreting relationships.
CREATE FUNCTION dcmon.immutable_device_class() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 IF NEW.device_class<>OLD.device_class THEN RAISE EXCEPTION 'Device class is immutable' USING ERRCODE='23514'; END IF; RETURN NEW;
END $$;


--
-- Name: immutable_runtime_kind(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Before runtime_kind updates, rejects changing VM/pod/container type with SQLSTATE 23514
-- because hosting rules depend on the subtype. A newly created workload instance requires its
-- own identity.
CREATE FUNCTION dcmon.immutable_runtime_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 IF NEW.runtime_kind<>OLD.runtime_kind THEN RAISE EXCEPTION 'Runtime kind is immutable' USING ERRCODE='23514'; END IF; RETURN NEW;
END $$;


--
-- Name: is_compute(bigint); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns true if p_id is a physical device of class server or a runtime; false for missing IDs
-- and other physical equipment. It is a type predicate, not a lifecycle, health, placement or
-- capacity test. Uses caller search_path dcmon,public.
CREATE FUNCTION dcmon.is_compute(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
 SELECT EXISTS(SELECT 1 FROM device WHERE ci_id=p_id AND device_class='server') OR EXISTS(SELECT 1 FROM runtime WHERE ci_id=p_id)
$$;


--
-- Name: metric_snapshot(timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- For every metric_series, selects the latest sample with observed_at<=p_at, independent of
-- ingestion time. Returns raw_value for diagnosis and display_value only when quality=ok and
-- observation age is <=stale_after_sec. No point yields missing; age strictly above the budget
-- yields stale before checking point quality; otherwise quality missing/error propagates, or ok
-- becomes fresh. Age is in seconds and no value or timestamp is fabricated. Does not filter
-- series by CI lifecycle or first_seen_at; labels/definitions are current inventory attributes.
CREATE FUNCTION dcmon.metric_snapshot(p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(series_id bigint, ci_id bigint, object_key text, metric_code text, unit text, labels jsonb, observed_at timestamp with time zone, raw_value numeric, display_value numeric, freshness text, age_seconds numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 SELECT s.series_id,s.ci_id,c.ci_key,d.code,d.unit,s.labels,m.observed_at,m.value,
 CASE WHEN m.quality='ok' AND p_at-m.observed_at<=s.stale_after_sec*interval '1 second' THEN m.value END,
 CASE WHEN m.observed_at IS NULL THEN 'missing'
 WHEN p_at-m.observed_at>s.stale_after_sec*interval '1 second' THEN 'stale'
 WHEN m.quality<>'ok' THEN m.quality ELSE 'fresh' END,
 extract(epoch FROM p_at-m.observed_at)
 FROM metric_series s JOIN ci c ON c.ci_id=s.ci_id JOIN metric_definition d ON d.id=s.metric_id
 LEFT JOIN LATERAL (SELECT ms.observed_at,ms.value,ms.quality FROM metric_sample ms WHERE ms.series_id=s.series_id AND ms.observed_at<=p_at ORDER BY ms.observed_at DESC LIMIT 1) m ON true
$$;


--
-- Name: prevent_rack_shrink(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Before rack height updates, rejects any height below the inclusive top U of an existing
-- placement, including historical/closed intervals. Preserves historical physical validity; it
-- is intentionally stricter than checking only current placements. Raises SQLSTATE 23514. Uses
-- caller search_path dcmon,public.
CREATE FUNCTION dcmon.prevent_rack_shrink() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM device_placement WHERE rack_id=NEW.ci_id AND u_start+u_height-1>NEW.height_u) THEN RAISE EXCEPTION 'Rack height conflicts with placement history' USING ERRCODE='23514'; END IF; RETURN NEW;
END $$;


--
-- Name: require_ci_kind(); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the
-- trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys
-- separately maintain ownership. Does not require every CI to have a subtype row. Uses caller
-- search_path dcmon,public.
CREATE FUNCTION dcmon.require_ci_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE actual text; expected text:=TG_ARGV[0];
BEGIN
 SELECT kind INTO actual FROM ci WHERE ci_id=NEW.ci_id;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'CI % must be %, got %',NEW.ci_id,expected,actual USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;


--
-- As-of status never turns absent or expired observations into healthy values.
-- Name: status_snapshot(timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- For each CI with first_seen_at<=p_at and no retirement at/before p_at, selects its latest
-- status_observation with observed_at<=p_at. No observation or age strictly greater than
-- valid_for_sec becomes unknown, with an English reason; equality remains fresh. Preserves the
-- source timestamp for stale diagnostics. Does not exclude planned lifecycle CIs or infer status
-- from incidents/metrics.
CREATE FUNCTION dcmon.status_snapshot(p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(ci_id bigint, object_key text, state text, reason text, observed_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 SELECT c.ci_id,c.ci_key,CASE WHEN o.observed_at IS NULL OR p_at-o.observed_at>o.valid_for_sec*interval '1 second' THEN 'unknown' ELSE o.state END,
 CASE WHEN o.observed_at IS NULL THEN 'No observation' WHEN p_at-o.observed_at>o.valid_for_sec*interval '1 second' THEN 'Stale status' ELSE o.reason END,o.observed_at
 FROM ci c LEFT JOIN LATERAL (SELECT * FROM status_observation s WHERE s.ci_id=c.ci_id AND s.observed_at<=p_at ORDER BY s.observed_at DESC LIMIT 1) o ON true
 WHERE c.first_seen_at<=p_at AND (c.retired_at IS NULL OR c.retired_at>p_at)
$$;


--
-- Software filters apply to the selected execution path, avoiding sibling VM leakage.
-- Name: system_hosts(text, text, text, timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns distinct physical servers selected by optional system key, environment and software
-- product code at p_at; NULL means no restriction. Uses execution_paths and, only with both
-- system/environment NULL, compute_paths to retain unmapped hosts. Software must be on the
-- selected path or installed on a node of that path, avoiding sibling VM leakage. Current
-- effective device placement supplies optional rack/room/site keys; unplaced hosts remain with
-- NULL location. Does not test historical software version.
CREATE FUNCTION dcmon.system_hosts(p_system_key text DEFAULT NULL::text, p_environment text DEFAULT NULL::text, p_software_code text DEFAULT NULL::text, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(server_id bigint, server_key text, server_name text, rack_key text, room_key text, site_key text)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 WITH paths AS (
 SELECT e.server_id,e.node_ids FROM execution_paths(p_at) e WHERE (p_system_key IS NULL OR e.system_key=p_system_key) AND (p_environment IS NULL OR e.environment=p_environment)
 UNION SELECT cp.server_id,cp.node_ids FROM compute_paths(p_at) cp WHERE p_system_key IS NULL AND p_environment IS NULL
 ), selected AS (
 SELECT DISTINCT p.server_id FROM paths p
 WHERE p_software_code IS NULL OR EXISTS (
 SELECT 1 FROM software_installation si JOIN software_product sp ON sp.id=si.product_id
 JOIN installation_placement ip ON ip.installation_id=si.ci_id AND tstzrange(ip.valid_from,ip.valid_to,'[)') @> p_at
 WHERE sp.code=p_software_code AND (si.ci_id=ANY(p.node_ids) OR ip.host_id=ANY(p.node_ids)))
 )
 SELECT s.server_id,c.ci_key,c.name,rc.ci_key,rmc.ci_key,sc.ci_key FROM selected s JOIN ci c ON c.ci_id=s.server_id
 LEFT JOIN device_placement dp ON dp.device_id=s.server_id AND tstzrange(dp.valid_from,dp.valid_to,'[)') @> p_at
 LEFT JOIN ci rc ON rc.ci_id=dp.rack_id LEFT JOIN room rm ON rm.ci_id=dp.room_id LEFT JOIN ci rmc ON rmc.ci_id=rm.ci_id LEFT JOIN ci sc ON sc.ci_id=rm.site_id
$$;


--
-- Name: system_incidents(text, text, timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns one row per incident in system_scope at p_at with detection and incident-CI link times
-- not after p_at. Latest workflow event determines state; resolved/closed incidents are
-- excluded. matched_objects counts distinct in-scope linked CIs and all impact_role values may
-- match, so potential risk is not a confirmed application outage. Multiple links do not multiply
-- incidents. Interpretation remains explicitly advisory.
CREATE FUNCTION dcmon.system_incidents(p_system_key text, p_environment text, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(incident_key text, title text, severity text, state text, detected_at timestamp with time zone, matched_objects bigint, interpretation text)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 WITH scope AS (SELECT ci_id FROM system_scope(p_system_key,p_environment,p_at))
 SELECT i.incident_key,i.title,i.severity,e.state,i.detected_at,count(DISTINCT ic.ci_id),
 'Related infrastructure; application availability impact requires confirmation'::text
 FROM incident i JOIN incident_ci ic ON ic.incident_id=i.id AND ic.linked_at<=p_at JOIN scope s ON s.ci_id=ic.ci_id
 JOIN LATERAL (SELECT state FROM incident_event ev WHERE ev.incident_id=i.id AND ev.occurred_at<=p_at ORDER BY ev.occurred_at DESC LIMIT 1) e ON true
 WHERE i.detected_at<=p_at AND e.state NOT IN ('resolved','closed') GROUP BY i.id,e.state
$$;


--
-- Name: system_scope(text, text, timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Builds CI scope for optional system/environment at p_at from execution-path nodes, matching
-- components and systems, effective physical locations, software installed on core nodes,
-- attached volumes and containing clusters. With both filters NULL it also seeds historically
-- visible CIs. Recurses only consumer-to-provider through non-application infrastructure
-- dependencies; UNION deduplicates nodes and terminates cycles. Never traverses reverse hosting
-- to sibling VMs. Location/attachment expansion uses the core set, not every later
-- infrastructure node; the function does not infer transitive impact severity.
CREATE FUNCTION dcmon.system_scope(p_system_key text, p_environment text, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(ci_id bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 WITH RECURSIVE core AS (
 SELECT DISTINCT unnest(node_ids) ci_id FROM execution_paths(p_at) e WHERE (p_system_key IS NULL OR e.system_key=p_system_key) AND (p_environment IS NULL OR e.environment=p_environment)
 UNION SELECT c.ci_id FROM component c JOIN system_environment se ON se.id=c.environment_id JOIN ci sy ON sy.ci_id=se.system_id WHERE (p_system_key IS NULL OR sy.ci_key=p_system_key) AND (p_environment IS NULL OR se.environment=p_environment)
 UNION SELECT sy.ci_id FROM information_system sy JOIN ci c ON c.ci_id=sy.ci_id WHERE p_system_key IS NULL OR c.ci_key=p_system_key
 ), locations AS (
 SELECT dp.room_id,dp.rack_id,r.site_id FROM device_placement dp JOIN core c ON c.ci_id=dp.device_id JOIN room r ON r.ci_id=dp.room_id WHERE tstzrange(dp.valid_from,dp.valid_to,'[)') @> p_at
 ), seed AS (
 SELECT ci_id FROM ci WHERE p_system_key IS NULL AND p_environment IS NULL AND first_seen_at<=p_at AND (retired_at IS NULL OR retired_at>p_at)
 UNION SELECT ci_id FROM core UNION SELECT room_id FROM locations UNION SELECT rack_id FROM locations WHERE rack_id IS NOT NULL UNION SELECT site_id FROM locations
 UNION SELECT ip.installation_id FROM installation_placement ip JOIN core c ON c.ci_id=ip.host_id WHERE tstzrange(ip.valid_from,ip.valid_to,'[)') @> p_at
 UNION SELECT va.volume_id FROM volume_attachment va JOIN core c ON c.ci_id=va.host_id WHERE tstzrange(va.valid_from,va.valid_to,'[)') @> p_at
 UNION SELECT cm.cluster_id FROM cluster_member cm JOIN core c ON c.ci_id=cm.member_id WHERE tstzrange(cm.valid_from,cm.valid_to,'[)') @> p_at
 ), walk AS (
 SELECT ci_id FROM seed UNION
 SELECT d.provider_id FROM walk w JOIN dependency d ON d.dependent_id=w.ci_id WHERE d.dependency_type<>'application' AND tstzrange(d.valid_from,d.valid_to,'[)') @> p_at
 ) SELECT ci_id FROM walk
$$;


--
-- Name: system_software(text, text, timestamp with time zone); Type: FUNCTION; Schema: dcmon; Owner: -
--

-- Returns distinct software installations placed on nodes of selected execution paths at p_at
-- with optional system/environment filters (NULL is unrestricted).
-- association=explicit_dependency means the installation itself is a path node; otherwise
-- installed_on_execution_path means presence on a path host, not proof of use. Only placement is
-- effective-dated: version, product and instance inventory remain current attributes. Unmapped
-- compute is not added by this function.
CREATE FUNCTION dcmon.system_software(p_system_key text DEFAULT NULL::text, p_environment text DEFAULT NULL::text, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(system_key text, environment text, server_key text, installation_key text, product_code text, category text, version text, association text)
    LANGUAGE sql STABLE
    SET search_path TO 'dcmon', 'public'
    AS $$
 SELECT DISTINCT e.system_key,e.environment,e.server_key,ic.ci_key,sp.code,sp.category,si.version,
 CASE WHEN si.ci_id=ANY(e.node_ids) THEN 'explicit_dependency' ELSE 'installed_on_execution_path' END
 FROM execution_paths(p_at) e JOIN installation_placement ip ON ip.host_id=ANY(e.node_ids) AND tstzrange(ip.valid_from,ip.valid_to,'[)') @> p_at
 JOIN software_installation si ON si.ci_id=ip.installation_id JOIN software_product sp ON sp.id=si.product_id JOIN ci ic ON ic.ci_id=si.ci_id
 WHERE (p_system_key IS NULL OR e.system_key=p_system_key) AND (p_environment IS NULL OR e.environment=p_environment)
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: backup_run; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.backup_run (
    id bigint NOT NULL,
    environment_id bigint NOT NULL,
    job_key text NOT NULL,
    source_id bigint NOT NULL,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    recovery_point_at timestamp with time zone,
    status text NOT NULL,
    size_gib numeric(16,3),
    restore_test_at timestamp with time zone,
    CONSTRAINT backup_run_check CHECK (((finished_at IS NULL) OR (finished_at >= started_at))),
    CONSTRAINT backup_run_check1 CHECK (((recovery_point_at IS NULL) OR (recovery_point_at <= finished_at))),
    CONSTRAINT backup_run_check2 CHECK (((status <> 'success'::text) OR ((finished_at IS NOT NULL) AND (recovery_point_at IS NOT NULL)))),
    CONSTRAINT backup_run_size_gib_check CHECK ((size_gib >= (0)::numeric)),
    CONSTRAINT backup_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'success'::text, 'failed'::text])))
);


--
-- Name: backup_run_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.backup_run ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.backup_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ci; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.ci (
    ci_id bigint NOT NULL,
    ci_key text NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    owner_team_id bigint NOT NULL,
    lifecycle text NOT NULL,
    retired_at timestamp with time zone,
    first_seen_at timestamp with time zone NOT NULL,
    last_seen_at timestamp with time zone NOT NULL,
    CONSTRAINT ci_check CHECK ((last_seen_at >= first_seen_at)),
    CONSTRAINT ci_check1 CHECK (((lifecycle = 'retired'::text) = (retired_at IS NOT NULL))),
    CONSTRAINT ci_check2 CHECK (((retired_at IS NULL) OR (retired_at >= first_seen_at))),
    CONSTRAINT ci_kind_check CHECK ((kind = ANY (ARRAY['site'::text, 'room'::text, 'rack'::text, 'device'::text, 'runtime'::text, 'cluster'::text, 'installation'::text, 'system'::text, 'component'::text, 'volume'::text]))),
    CONSTRAINT ci_lifecycle_check CHECK ((lifecycle = ANY (ARRAY['planned'::text, 'active'::text, 'retired'::text])))
);


--
-- Name: ci_ci_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.ci ALTER COLUMN ci_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.ci_ci_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cluster; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.cluster (
    ci_id bigint NOT NULL,
    cluster_type text NOT NULL,
    platform text NOT NULL,
    CONSTRAINT cluster_cluster_type_check CHECK ((cluster_type = ANY (ARRAY['virtualization'::text, 'kubernetes'::text, 'database'::text, 'storage'::text])))
);


--
-- Name: cluster_member; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.cluster_member (
    id bigint NOT NULL,
    cluster_id bigint NOT NULL,
    member_id bigint NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT cluster_member_check CHECK ((cluster_id <> member_id)),
    CONSTRAINT cluster_member_check1 CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: cluster_member_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.cluster_member ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.cluster_member_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: component; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.component (
    ci_id bigint NOT NULL,
    environment_id bigint NOT NULL,
    component_role text NOT NULL,
    description text NOT NULL,
    CONSTRAINT component_component_role_check CHECK ((component_role = ANY (ARRAY['web'::text, 'api'::text, 'database'::text, 'queue'::text, 'batch'::text])))
);


--
-- Name: dependency; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.dependency (
    id bigint NOT NULL,
    dependent_id bigint NOT NULL,
    provider_id bigint NOT NULL,
    dependency_type text NOT NULL,
    redundancy_group text,
    source_id bigint NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT dependency_check CHECK ((dependent_id <> provider_id)),
    CONSTRAINT dependency_check1 CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),
    CONSTRAINT dependency_dependency_type_check CHECK ((dependency_type = ANY (ARRAY['application'::text, 'power'::text, 'cooling'::text, 'network'::text, 'storage'::text])))
);


--
-- Name: dependency_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.dependency ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deployment; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.deployment (
    id bigint NOT NULL,
    component_id bigint NOT NULL,
    target_id bigint NOT NULL,
    role text NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT deployment_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),
    CONSTRAINT deployment_role_check CHECK ((role = ANY (ARRAY['primary'::text, 'replica'::text, 'standby'::text, 'worker'::text])))
);


--
-- Name: deployment_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.deployment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.deployment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: device; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.device (
    ci_id bigint NOT NULL,
    device_class text NOT NULL,
    manufacturer text NOT NULL,
    model text NOT NULL,
    serial_number text,
    cpu_cores integer,
    memory_gib numeric(12,2),
    CONSTRAINT device_cpu_cores_check CHECK ((cpu_cores > 0)),
    CONSTRAINT device_device_class_check CHECK ((device_class = ANY (ARRAY['server'::text, 'storage'::text, 'switch'::text, 'ups'::text, 'pdu'::text, 'crac'::text, 'chiller'::text, 'generator'::text, 'fire_sensor'::text, 'access_controller'::text]))),
    CONSTRAINT device_memory_gib_check CHECK ((memory_gib > (0)::numeric))
);


--
-- Name: device_placement; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.device_placement (
    id bigint NOT NULL,
    device_id bigint NOT NULL,
    room_id bigint NOT NULL,
    rack_id bigint,
    u_start integer,
    u_height integer,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT device_placement_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),
    CONSTRAINT device_placement_check1 CHECK ((((u_start IS NULL) AND (u_height IS NULL)) OR ((rack_id IS NOT NULL) AND (u_start > 0) AND (u_height > 0)))),
    CONSTRAINT device_placement_check2 CHECK (((rack_id IS NOT NULL) OR ((u_start IS NULL) AND (u_height IS NULL))))
);


--
-- Name: device_placement_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.device_placement ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.device_placement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: external_identity; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.external_identity (
    source_id bigint NOT NULL,
    external_id text NOT NULL,
    ci_id bigint NOT NULL,
    last_seen_at timestamp with time zone NOT NULL
);


--
-- Name: hosting; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.hosting (
    id bigint NOT NULL,
    guest_id bigint NOT NULL,
    host_id bigint NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT hosting_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),
    CONSTRAINT hosting_check1 CHECK ((guest_id <> host_id))
);


--
-- Name: hosting_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.hosting ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.hosting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: incident; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.incident (
    id bigint NOT NULL,
    incident_key text NOT NULL,
    source_id bigint NOT NULL,
    external_id text NOT NULL,
    title text NOT NULL,
    severity text NOT NULL,
    detected_at timestamp with time zone NOT NULL,
    owner_team_id bigint NOT NULL,
    response_due_at timestamp with time zone,
    CONSTRAINT incident_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])))
);


--
-- Name: incident_ci; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.incident_ci (
    incident_id bigint NOT NULL,
    ci_id bigint NOT NULL,
    impact_role text NOT NULL,
    linked_at timestamp with time zone NOT NULL,
    CONSTRAINT incident_ci_impact_role_check CHECK ((impact_role = ANY (ARRAY['cause'::text, 'affected'::text, 'at_risk'::text])))
);


--
-- Name: incident_event; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.incident_event (
    id bigint NOT NULL,
    incident_id bigint NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    state text NOT NULL,
    note text NOT NULL,
    CONSTRAINT incident_event_state_check CHECK ((state = ANY (ARRAY['open'::text, 'acknowledged'::text, 'in_progress'::text, 'resolved'::text, 'closed'::text])))
);


--
-- Name: incident_event_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.incident_event ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.incident_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: incident_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.incident ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.incident_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: information_system; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.information_system (
    ci_id bigint NOT NULL,
    description text NOT NULL,
    criticality text NOT NULL,
    target_rto_min integer,
    target_rpo_min integer,
    CONSTRAINT information_system_criticality_check CHECK ((criticality = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text]))),
    CONSTRAINT information_system_target_rpo_min_check CHECK ((target_rpo_min >= 0)),
    CONSTRAINT information_system_target_rto_min_check CHECK ((target_rto_min >= 0))
);


--
-- Name: ingestion_run; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.ingestion_run (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    state text NOT NULL,
    cursor_value text,
    accepted_rows integer NOT NULL,
    rejected_rows integer NOT NULL,
    error_summary text,
    CONSTRAINT ingestion_run_accepted_rows_check CHECK ((accepted_rows >= 0)),
    CONSTRAINT ingestion_run_check CHECK (((finished_at IS NULL) OR (finished_at >= started_at))),
    CONSTRAINT ingestion_run_rejected_rows_check CHECK ((rejected_rows >= 0)),
    CONSTRAINT ingestion_run_state_check CHECK ((state = ANY (ARRAY['running'::text, 'success'::text, 'partial'::text, 'failed'::text])))
);


--
-- Name: ingestion_run_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.ingestion_run ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.ingestion_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: installation_placement; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.installation_placement (
    id bigint NOT NULL,
    installation_id bigint NOT NULL,
    host_id bigint NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT installation_placement_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: installation_placement_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.installation_placement ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.installation_placement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: maintenance_window; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.maintenance_window (
    id bigint NOT NULL,
    ci_id bigint NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    reason text NOT NULL,
    change_ref text NOT NULL,
    CONSTRAINT maintenance_window_check CHECK ((ends_at > starts_at))
);


--
-- Name: maintenance_window_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.maintenance_window ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.maintenance_window_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: metric_definition; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.metric_definition (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    unit text NOT NULL,
    metric_type text NOT NULL,
    valid_min numeric,
    valid_max numeric,
    warning_above numeric,
    critical_above numeric,
    CONSTRAINT metric_definition_check CHECK (((valid_max IS NULL) OR (valid_min IS NULL) OR (valid_max >= valid_min))),
    CONSTRAINT metric_definition_check1 CHECK (((critical_above IS NULL) OR (warning_above IS NULL) OR (critical_above >= warning_above))),
    CONSTRAINT metric_definition_metric_type_check CHECK ((metric_type = ANY (ARRAY['gauge'::text, 'counter'::text])))
);


--
-- Name: metric_definition_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.metric_definition ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.metric_definition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Telemetry separates observed_at from ingested_at; quality controls NULL values.
-- Name: metric_sample; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.metric_sample (
    series_id bigint NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    ingested_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    value numeric,
    quality text NOT NULL,
    CONSTRAINT metric_sample_check CHECK ((((quality = 'ok'::text) AND (value IS NOT NULL) AND (value <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric]))) OR ((quality <> 'ok'::text) AND (value IS NULL)))),
    CONSTRAINT metric_sample_quality_check CHECK ((quality = ANY (ARRAY['ok'::text, 'missing'::text, 'error'::text])))
);


--
-- Name: metric_series; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.metric_series (
    series_id bigint NOT NULL,
    ci_id bigint NOT NULL,
    metric_id bigint NOT NULL,
    source_id bigint NOT NULL,
    labels jsonb DEFAULT '{}'::jsonb NOT NULL,
    expected_interval_sec integer NOT NULL,
    stale_after_sec integer NOT NULL,
    CONSTRAINT metric_series_check CHECK ((stale_after_sec >= expected_interval_sec)),
    CONSTRAINT metric_series_expected_interval_sec_check CHECK ((expected_interval_sec > 0)),
    CONSTRAINT metric_series_labels_check CHECK ((jsonb_typeof(labels) = 'object'::text)),
    CONSTRAINT metric_series_stale_after_sec_check CHECK ((stale_after_sec > 0))
);


--
-- Name: metric_series_series_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.metric_series ALTER COLUMN series_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.metric_series_series_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: network_link; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.network_link (
    id bigint NOT NULL,
    port_a_id bigint NOT NULL,
    port_b_id bigint NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT network_link_check CHECK ((port_a_id < port_b_id)),
    CONSTRAINT network_link_check1 CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: network_link_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.network_link ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.network_link_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: network_port; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.network_port (
    id bigint NOT NULL,
    device_id bigint NOT NULL,
    name text NOT NULL,
    speed_mbps bigint,
    mac_address macaddr,
    CONSTRAINT network_port_speed_mbps_check CHECK ((speed_mbps > 0))
);


--
-- Name: network_port_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.network_port ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.network_port_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: rack; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.rack (
    ci_id bigint NOT NULL,
    room_id bigint NOT NULL,
    height_u integer NOT NULL,
    power_limit_kw numeric(10,2) NOT NULL,
    x_m numeric(10,3) NOT NULL,
    y_m numeric(10,3) NOT NULL,
    CONSTRAINT rack_height_u_check CHECK ((height_u > 0)),
    CONSTRAINT rack_power_limit_kw_check CHECK ((power_limit_kw > (0)::numeric))
);


--
-- Name: room; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.room (
    ci_id bigint NOT NULL,
    site_id bigint NOT NULL,
    floor_no integer NOT NULL,
    area_m2 numeric(10,2),
    room_type text NOT NULL,
    CONSTRAINT room_area_m2_check CHECK ((area_m2 > (0)::numeric)),
    CONSTRAINT room_room_type_check CHECK ((room_type = ANY (ARRAY['data_hall'::text, 'power'::text, 'cooling'::text, 'other'::text])))
);


--
-- Name: runtime; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.runtime (
    ci_id bigint NOT NULL,
    runtime_kind text NOT NULL,
    namespace text,
    workload_name text,
    image_ref text,
    vcpu_allocated numeric(10,3),
    memory_gib_allocated numeric(12,3),
    CONSTRAINT runtime_memory_gib_allocated_check CHECK ((memory_gib_allocated >= (0)::numeric)),
    CONSTRAINT runtime_runtime_kind_check CHECK ((runtime_kind = ANY (ARRAY['vm'::text, 'pod'::text, 'container'::text]))),
    CONSTRAINT runtime_vcpu_allocated_check CHECK ((vcpu_allocated >= (0)::numeric))
);


--
-- Name: scene_object; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.scene_object (
    id bigint NOT NULL,
    scene_key text NOT NULL,
    ci_id bigint NOT NULL,
    asset_ref text NOT NULL,
    x numeric(12,3) NOT NULL,
    y numeric(12,3) NOT NULL,
    z numeric(12,3) NOT NULL,
    rotation_deg numeric(7,3) NOT NULL,
    scale numeric(10,4) NOT NULL,
    CONSTRAINT scene_object_scale_check CHECK ((scale > (0)::numeric))
);


--
-- Name: scene_object_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.scene_object ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.scene_object_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: site; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.site (
    ci_id bigint NOT NULL,
    city text NOT NULL,
    timezone text NOT NULL,
    latitude numeric(9,6),
    longitude numeric(9,6),
    design_it_kw numeric(12,2),
    CONSTRAINT site_check CHECK (((latitude IS NULL) = (longitude IS NULL))),
    CONSTRAINT site_design_it_kw_check CHECK ((design_it_kw > (0)::numeric)),
    CONSTRAINT site_latitude_check CHECK (((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric))),
    CONSTRAINT site_longitude_check CHECK (((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric)))
);


--
-- Name: software_installation; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.software_installation (
    ci_id bigint NOT NULL,
    product_id bigint NOT NULL,
    version text NOT NULL,
    instance_name text NOT NULL,
    listen_port integer,
    CONSTRAINT software_installation_listen_port_check CHECK (((listen_port >= 1) AND (listen_port <= 65535)))
);


--
-- Name: software_product; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.software_product (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    category text NOT NULL,
    vendor text NOT NULL,
    CONSTRAINT software_product_category_check CHECK ((category = ANY (ARRAY['os'::text, 'dbms'::text, 'platform'::text, 'middleware'::text, 'agent'::text])))
);


--
-- Name: software_product_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.software_product ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.software_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: source_system; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.source_system (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    method text NOT NULL,
    endpoint_ref text,
    owner_team text NOT NULL
);


--
-- Name: source_system_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.source_system ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.source_system_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: status_observation; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.status_observation (
    ci_id bigint NOT NULL,
    observed_at timestamp with time zone NOT NULL,
    state text NOT NULL,
    reason text NOT NULL,
    valid_for_sec integer NOT NULL,
    source_id bigint NOT NULL,
    CONSTRAINT status_observation_state_check CHECK ((state = ANY (ARRAY['healthy'::text, 'warning'::text, 'critical'::text, 'unknown'::text, 'maintenance'::text]))),
    CONSTRAINT status_observation_valid_for_sec_check CHECK ((valid_for_sec > 0))
);


--
-- Name: storage_volume; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.storage_volume (
    ci_id bigint NOT NULL,
    storage_device_id bigint NOT NULL,
    capacity_gib numeric(16,3) NOT NULL,
    protocol text NOT NULL,
    CONSTRAINT storage_volume_capacity_gib_check CHECK ((capacity_gib > (0)::numeric)),
    CONSTRAINT storage_volume_protocol_check CHECK ((protocol = ANY (ARRAY['FC'::text, 'iSCSI'::text, 'NFS'::text, 'NVMe-oF'::text])))
);


--
-- Name: system_environment; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.system_environment (
    id bigint NOT NULL,
    system_id bigint NOT NULL,
    environment text NOT NULL,
    service_owner_team_id bigint NOT NULL,
    CONSTRAINT system_environment_environment_check CHECK ((environment = ANY (ARRAY['PROD'::text, 'TEST'::text, 'DEV'::text])))
);


--
-- Name: system_environment_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.system_environment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.system_environment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: team; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.team (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    contact_ref text
);


--
-- Name: team_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.team ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.team_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_inventory_summary; Type: VIEW; Schema: dcmon; Owner: -
--

CREATE VIEW dcmon.v_inventory_summary AS
 SELECT kind,
    count(*) AS objects
   FROM dcmon.ci c
  WHERE (lifecycle = 'active'::text)
  GROUP BY kind;


--
-- Name: v_unmapped_compute; Type: VIEW; Schema: dcmon; Owner: -
--

CREATE VIEW dcmon.v_unmapped_compute AS
 SELECT ci_id,
    ci_key,
    kind
   FROM dcmon.ci c
  WHERE ((kind = ANY (ARRAY['device'::text, 'runtime'::text])) AND (lifecycle = 'active'::text) AND dcmon.is_compute(ci_id) AND (NOT (EXISTS ( SELECT 1
           FROM dcmon.execution_paths(now()) e(system_key, environment, component_key, target_key, server_key, server_id, node_ids)
          WHERE (c.ci_id = ANY (e.node_ids))))));


--
-- Name: volume_attachment; Type: TABLE; Schema: dcmon; Owner: -
--

CREATE TABLE dcmon.volume_attachment (
    id bigint NOT NULL,
    volume_id bigint NOT NULL,
    host_id bigint NOT NULL,
    mount_ref text NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone,
    CONSTRAINT volume_attachment_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))
);


--
-- Name: volume_attachment_id_seq; Type: SEQUENCE; Schema: dcmon; Owner: -
--

ALTER TABLE dcmon.volume_attachment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dcmon.volume_attachment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: backup_run backup_run_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.backup_run
    ADD CONSTRAINT backup_run_pkey PRIMARY KEY (id);


--
-- Name: backup_run backup_run_source_id_job_key_started_at_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.backup_run
    ADD CONSTRAINT backup_run_source_id_job_key_started_at_key UNIQUE (source_id, job_key, started_at);


--
-- Name: ci ci_ci_key_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.ci
    ADD CONSTRAINT ci_ci_key_key UNIQUE (ci_key);


--
-- Name: ci ci_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.ci
    ADD CONSTRAINT ci_pkey PRIMARY KEY (ci_id);


--
-- Name: cluster_member cluster_member_cluster_id_member_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster_member
    ADD CONSTRAINT cluster_member_cluster_id_member_id_tstzrange_excl EXCLUDE USING gist (cluster_id WITH =, member_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: cluster_member cluster_member_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster_member
    ADD CONSTRAINT cluster_member_pkey PRIMARY KEY (id);


--
-- Name: cluster cluster_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster
    ADD CONSTRAINT cluster_pkey PRIMARY KEY (ci_id);


--
-- Name: component component_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.component
    ADD CONSTRAINT component_pkey PRIMARY KEY (ci_id);


--
-- Name: dependency dependency_dependent_id_provider_id_dependency_type_tstzra_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.dependency
    ADD CONSTRAINT dependency_dependent_id_provider_id_dependency_type_tstzra_excl EXCLUDE USING gist (dependent_id WITH =, provider_id WITH =, dependency_type WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: dependency dependency_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.dependency
    ADD CONSTRAINT dependency_pkey PRIMARY KEY (id);


--
-- Name: deployment deployment_component_id_target_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.deployment
    ADD CONSTRAINT deployment_component_id_target_id_tstzrange_excl EXCLUDE USING gist (component_id WITH =, target_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: deployment deployment_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.deployment
    ADD CONSTRAINT deployment_pkey PRIMARY KEY (id);


--
-- Name: device device_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device
    ADD CONSTRAINT device_pkey PRIMARY KEY (ci_id);


--
-- Name: device_placement device_placement_device_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_device_id_tstzrange_excl EXCLUDE USING gist (device_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: device_placement device_placement_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_pkey PRIMARY KEY (id);


--
-- Name: device_placement device_placement_rack_id_int4range_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_rack_id_int4range_tstzrange_excl EXCLUDE USING gist (rack_id WITH =, int4range(u_start, (u_start + u_height), '[)'::text) WITH &&, tstzrange(valid_from, valid_to, '[)'::text) WITH &&) WHERE ((u_start IS NOT NULL));


--
-- Name: device device_serial_number_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device
    ADD CONSTRAINT device_serial_number_key UNIQUE (serial_number);


--
-- Name: external_identity external_identity_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.external_identity
    ADD CONSTRAINT external_identity_pkey PRIMARY KEY (source_id, external_id);


--
-- Name: hosting hosting_guest_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.hosting
    ADD CONSTRAINT hosting_guest_id_tstzrange_excl EXCLUDE USING gist (guest_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: hosting hosting_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.hosting
    ADD CONSTRAINT hosting_pkey PRIMARY KEY (id);


--
-- Name: incident_ci incident_ci_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_ci
    ADD CONSTRAINT incident_ci_pkey PRIMARY KEY (incident_id, ci_id);


--
-- Name: incident_event incident_event_incident_id_occurred_at_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_event
    ADD CONSTRAINT incident_event_incident_id_occurred_at_key UNIQUE (incident_id, occurred_at);


--
-- Name: incident_event incident_event_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_event
    ADD CONSTRAINT incident_event_pkey PRIMARY KEY (id);


--
-- Name: incident incident_incident_key_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident
    ADD CONSTRAINT incident_incident_key_key UNIQUE (incident_key);


--
-- Name: incident incident_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident
    ADD CONSTRAINT incident_pkey PRIMARY KEY (id);


--
-- Name: incident incident_source_id_external_id_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident
    ADD CONSTRAINT incident_source_id_external_id_key UNIQUE (source_id, external_id);


--
-- Name: information_system information_system_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.information_system
    ADD CONSTRAINT information_system_pkey PRIMARY KEY (ci_id);


--
-- Name: ingestion_run ingestion_run_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.ingestion_run
    ADD CONSTRAINT ingestion_run_pkey PRIMARY KEY (id);


--
-- Name: installation_placement installation_placement_installation_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.installation_placement
    ADD CONSTRAINT installation_placement_installation_id_tstzrange_excl EXCLUDE USING gist (installation_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: installation_placement installation_placement_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.installation_placement
    ADD CONSTRAINT installation_placement_pkey PRIMARY KEY (id);


--
-- Name: maintenance_window maintenance_window_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.maintenance_window
    ADD CONSTRAINT maintenance_window_pkey PRIMARY KEY (id);


--
-- Name: metric_definition metric_definition_code_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_definition
    ADD CONSTRAINT metric_definition_code_key UNIQUE (code);


--
-- Name: metric_definition metric_definition_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_definition
    ADD CONSTRAINT metric_definition_pkey PRIMARY KEY (id);


--
-- Name: metric_sample metric_sample_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_sample
    ADD CONSTRAINT metric_sample_pkey PRIMARY KEY (series_id, observed_at);


--
-- Name: metric_series metric_series_ci_id_metric_id_labels_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_series
    ADD CONSTRAINT metric_series_ci_id_metric_id_labels_key UNIQUE (ci_id, metric_id, labels);


--
-- Name: metric_series metric_series_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_series
    ADD CONSTRAINT metric_series_pkey PRIMARY KEY (series_id);


--
-- Name: network_link network_link_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_link
    ADD CONSTRAINT network_link_pkey PRIMARY KEY (id);


--
-- Name: network_port network_port_device_id_name_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_port
    ADD CONSTRAINT network_port_device_id_name_key UNIQUE (device_id, name);


--
-- Name: network_port network_port_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_port
    ADD CONSTRAINT network_port_pkey PRIMARY KEY (id);


--
-- Name: network_link no_port_overlap; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_link
    ADD CONSTRAINT no_port_overlap EXCLUDE USING gist (int8multirange(VARIADIC ARRAY[int8range(port_a_id, port_a_id, '[]'::text), int8range(port_b_id, port_b_id, '[]'::text)]) WITH &&, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: rack rack_ci_id_room_id_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.rack
    ADD CONSTRAINT rack_ci_id_room_id_key UNIQUE (ci_id, room_id);


--
-- Name: rack rack_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.rack
    ADD CONSTRAINT rack_pkey PRIMARY KEY (ci_id);


--
-- Name: room room_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.room
    ADD CONSTRAINT room_pkey PRIMARY KEY (ci_id);


--
-- Name: runtime runtime_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.runtime
    ADD CONSTRAINT runtime_pkey PRIMARY KEY (ci_id);


--
-- Name: scene_object scene_object_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.scene_object
    ADD CONSTRAINT scene_object_pkey PRIMARY KEY (id);


--
-- Name: scene_object scene_object_scene_key_ci_id_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.scene_object
    ADD CONSTRAINT scene_object_scene_key_ci_id_key UNIQUE (scene_key, ci_id);


--
-- Name: site site_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (ci_id);


--
-- Name: software_installation software_installation_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.software_installation
    ADD CONSTRAINT software_installation_pkey PRIMARY KEY (ci_id);


--
-- Name: software_product software_product_code_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.software_product
    ADD CONSTRAINT software_product_code_key UNIQUE (code);


--
-- Name: software_product software_product_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.software_product
    ADD CONSTRAINT software_product_pkey PRIMARY KEY (id);


--
-- Name: source_system source_system_code_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.source_system
    ADD CONSTRAINT source_system_code_key UNIQUE (code);


--
-- Name: source_system source_system_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.source_system
    ADD CONSTRAINT source_system_pkey PRIMARY KEY (id);


--
-- Name: status_observation status_observation_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.status_observation
    ADD CONSTRAINT status_observation_pkey PRIMARY KEY (ci_id, observed_at);


--
-- Name: storage_volume storage_volume_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.storage_volume
    ADD CONSTRAINT storage_volume_pkey PRIMARY KEY (ci_id);


--
-- Name: system_environment system_environment_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.system_environment
    ADD CONSTRAINT system_environment_pkey PRIMARY KEY (id);


--
-- Name: system_environment system_environment_system_id_environment_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.system_environment
    ADD CONSTRAINT system_environment_system_id_environment_key UNIQUE (system_id, environment);


--
-- Name: team team_code_key; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.team
    ADD CONSTRAINT team_code_key UNIQUE (code);


--
-- Name: team team_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (id);


--
-- Name: volume_attachment volume_attachment_pkey; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.volume_attachment
    ADD CONSTRAINT volume_attachment_pkey PRIMARY KEY (id);


--
-- Name: volume_attachment volume_attachment_volume_id_host_id_tstzrange_excl; Type: CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.volume_attachment
    ADD CONSTRAINT volume_attachment_volume_id_host_id_tstzrange_excl EXCLUDE USING gist (volume_id WITH =, host_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&);


--
-- Name: component_environment_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX component_environment_idx ON dcmon.component USING btree (environment_id);


--
-- Name: dependency_dependent_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX dependency_dependent_idx ON dcmon.dependency USING btree (dependent_id);


--
-- Name: dependency_provider_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX dependency_provider_idx ON dcmon.dependency USING btree (provider_id);


--
-- Name: deployment_target_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX deployment_target_idx ON dcmon.deployment USING btree (target_id);


--
-- Name: external_identity_ci_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX external_identity_ci_idx ON dcmon.external_identity USING btree (ci_id);


--
-- Name: hosting_host_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX hosting_host_idx ON dcmon.hosting USING btree (host_id);


--
-- Name: incident_ci_reverse_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX incident_ci_reverse_idx ON dcmon.incident_ci USING btree (ci_id);


--
-- Name: incident_event_latest_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX incident_event_latest_idx ON dcmon.incident_event USING btree (incident_id, occurred_at DESC);


--
-- Name: installation_host_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX installation_host_idx ON dcmon.installation_placement USING btree (host_id);


--
-- Name: metric_sample_latest_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX metric_sample_latest_idx ON dcmon.metric_sample USING btree (series_id, observed_at DESC);


--
-- Name: metric_sample_time_brin; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX metric_sample_time_brin ON dcmon.metric_sample USING brin (observed_at);


--
-- Name: metric_series_ci_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX metric_series_ci_idx ON dcmon.metric_series USING btree (ci_id);


--
-- Name: placement_rack_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX placement_rack_idx ON dcmon.device_placement USING btree (rack_id);


--
-- Name: scene_ci_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX scene_ci_idx ON dcmon.scene_object USING btree (ci_id);


--
-- Name: status_latest_idx; Type: INDEX; Schema: dcmon; Owner: -
--

CREATE INDEX status_latest_idx ON dcmon.status_observation USING btree (ci_id, observed_at DESC);


--
-- Name: ci ci_kind_immutable; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER ci_kind_immutable BEFORE UPDATE OF kind ON dcmon.ci FOR EACH ROW EXECUTE FUNCTION dcmon.immutable_ci_kind();


--
-- Name: device device_class_guard; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER device_class_guard BEFORE UPDATE OF device_class ON dcmon.device FOR EACH ROW EXECUTE FUNCTION dcmon.immutable_device_class();


--
-- Name: rack rack_height_guard; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER rack_height_guard BEFORE UPDATE OF height_u ON dcmon.rack FOR EACH ROW EXECUTE FUNCTION dcmon.prevent_rack_shrink();


--
-- Name: runtime runtime_kind_guard; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER runtime_kind_guard BEFORE UPDATE OF runtime_kind ON dcmon.runtime FOR EACH ROW EXECUTE FUNCTION dcmon.immutable_runtime_kind();


--
-- Name: cluster subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.cluster FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('cluster');


--
-- Name: component subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.component FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('component');


--
-- Name: device subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.device FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('device');


--
-- Name: information_system subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.information_system FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('system');


--
-- Name: rack subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.rack FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('rack');


--
-- Name: room subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.room FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('room');


--
-- Name: runtime subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.runtime FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('runtime');


--
-- Name: site subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.site FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('site');


--
-- Name: software_installation subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.software_installation FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('installation');


--
-- Name: storage_volume subtype_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.storage_volume FOR EACH ROW EXECUTE FUNCTION dcmon.require_ci_kind('volume');


--
-- Name: dependency valid_dependency; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_dependency BEFORE INSERT OR UPDATE ON dcmon.dependency FOR EACH ROW EXECUTE FUNCTION dcmon.check_dependency();


--
-- Name: deployment valid_deployment; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_deployment BEFORE INSERT OR UPDATE ON dcmon.deployment FOR EACH ROW EXECUTE FUNCTION dcmon.check_compute_reference();


--
-- Name: hosting valid_hosting; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_hosting BEFORE INSERT OR UPDATE ON dcmon.hosting FOR EACH ROW EXECUTE FUNCTION dcmon.check_hosting();


--
-- Name: installation_placement valid_installation_host; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_installation_host BEFORE INSERT OR UPDATE ON dcmon.installation_placement FOR EACH ROW EXECUTE FUNCTION dcmon.check_compute_reference();


--
-- Name: metric_sample valid_metric_range; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_metric_range BEFORE INSERT OR UPDATE ON dcmon.metric_sample FOR EACH ROW EXECUTE FUNCTION dcmon.check_metric_value();


--
-- Name: device_placement valid_rack_space; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_rack_space BEFORE INSERT OR UPDATE ON dcmon.device_placement FOR EACH ROW EXECUTE FUNCTION dcmon.check_rack_space();


--
-- Name: volume_attachment valid_volume_host; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER valid_volume_host BEFORE INSERT OR UPDATE ON dcmon.volume_attachment FOR EACH ROW EXECUTE FUNCTION dcmon.check_compute_reference();


--
-- Name: storage_volume volume_storage_kind; Type: TRIGGER; Schema: dcmon; Owner: -
--

CREATE TRIGGER volume_storage_kind BEFORE INSERT OR UPDATE ON dcmon.storage_volume FOR EACH ROW EXECUTE FUNCTION dcmon.check_storage_device();


--
-- Name: backup_run backup_run_environment_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.backup_run
    ADD CONSTRAINT backup_run_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES dcmon.system_environment(id);


--
-- Name: backup_run backup_run_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.backup_run
    ADD CONSTRAINT backup_run_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: ci ci_owner_team_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.ci
    ADD CONSTRAINT ci_owner_team_id_fkey FOREIGN KEY (owner_team_id) REFERENCES dcmon.team(id);


--
-- Name: cluster cluster_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster
    ADD CONSTRAINT cluster_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: cluster_member cluster_member_cluster_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster_member
    ADD CONSTRAINT cluster_member_cluster_id_fkey FOREIGN KEY (cluster_id) REFERENCES dcmon.cluster(ci_id);


--
-- Name: cluster_member cluster_member_member_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.cluster_member
    ADD CONSTRAINT cluster_member_member_id_fkey FOREIGN KEY (member_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: component component_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.component
    ADD CONSTRAINT component_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: component component_environment_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.component
    ADD CONSTRAINT component_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES dcmon.system_environment(id);


--
-- Name: dependency dependency_dependent_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.dependency
    ADD CONSTRAINT dependency_dependent_id_fkey FOREIGN KEY (dependent_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: dependency dependency_provider_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.dependency
    ADD CONSTRAINT dependency_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: dependency dependency_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.dependency
    ADD CONSTRAINT dependency_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: deployment deployment_component_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.deployment
    ADD CONSTRAINT deployment_component_id_fkey FOREIGN KEY (component_id) REFERENCES dcmon.component(ci_id);


--
-- Name: deployment deployment_target_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.deployment
    ADD CONSTRAINT deployment_target_id_fkey FOREIGN KEY (target_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: device device_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device
    ADD CONSTRAINT device_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: device_placement device_placement_device_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_device_id_fkey FOREIGN KEY (device_id) REFERENCES dcmon.device(ci_id);


--
-- Name: device_placement device_placement_rack_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_rack_id_fkey FOREIGN KEY (rack_id) REFERENCES dcmon.rack(ci_id);


--
-- Name: device_placement device_placement_rack_id_room_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_rack_id_room_id_fkey FOREIGN KEY (rack_id, room_id) REFERENCES dcmon.rack(ci_id, room_id);


--
-- Name: device_placement device_placement_room_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.device_placement
    ADD CONSTRAINT device_placement_room_id_fkey FOREIGN KEY (room_id) REFERENCES dcmon.room(ci_id);


--
-- Name: external_identity external_identity_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.external_identity
    ADD CONSTRAINT external_identity_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: external_identity external_identity_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.external_identity
    ADD CONSTRAINT external_identity_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: hosting hosting_guest_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.hosting
    ADD CONSTRAINT hosting_guest_id_fkey FOREIGN KEY (guest_id) REFERENCES dcmon.runtime(ci_id);


--
-- Name: hosting hosting_host_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.hosting
    ADD CONSTRAINT hosting_host_id_fkey FOREIGN KEY (host_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: incident_ci incident_ci_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_ci
    ADD CONSTRAINT incident_ci_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: incident_ci incident_ci_incident_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_ci
    ADD CONSTRAINT incident_ci_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES dcmon.incident(id);


--
-- Name: incident_event incident_event_incident_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident_event
    ADD CONSTRAINT incident_event_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES dcmon.incident(id);


--
-- Name: incident incident_owner_team_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident
    ADD CONSTRAINT incident_owner_team_id_fkey FOREIGN KEY (owner_team_id) REFERENCES dcmon.team(id);


--
-- Name: incident incident_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.incident
    ADD CONSTRAINT incident_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: information_system information_system_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.information_system
    ADD CONSTRAINT information_system_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: ingestion_run ingestion_run_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.ingestion_run
    ADD CONSTRAINT ingestion_run_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: installation_placement installation_placement_host_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.installation_placement
    ADD CONSTRAINT installation_placement_host_id_fkey FOREIGN KEY (host_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: installation_placement installation_placement_installation_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.installation_placement
    ADD CONSTRAINT installation_placement_installation_id_fkey FOREIGN KEY (installation_id) REFERENCES dcmon.software_installation(ci_id);


--
-- Name: maintenance_window maintenance_window_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.maintenance_window
    ADD CONSTRAINT maintenance_window_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: metric_sample metric_sample_series_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_sample
    ADD CONSTRAINT metric_sample_series_id_fkey FOREIGN KEY (series_id) REFERENCES dcmon.metric_series(series_id);


--
-- Name: metric_series metric_series_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_series
    ADD CONSTRAINT metric_series_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: metric_series metric_series_metric_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_series
    ADD CONSTRAINT metric_series_metric_id_fkey FOREIGN KEY (metric_id) REFERENCES dcmon.metric_definition(id);


--
-- Name: metric_series metric_series_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.metric_series
    ADD CONSTRAINT metric_series_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: network_link network_link_port_a_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_link
    ADD CONSTRAINT network_link_port_a_id_fkey FOREIGN KEY (port_a_id) REFERENCES dcmon.network_port(id);


--
-- Name: network_link network_link_port_b_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_link
    ADD CONSTRAINT network_link_port_b_id_fkey FOREIGN KEY (port_b_id) REFERENCES dcmon.network_port(id);


--
-- Name: network_port network_port_device_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.network_port
    ADD CONSTRAINT network_port_device_id_fkey FOREIGN KEY (device_id) REFERENCES dcmon.device(ci_id);


--
-- Name: rack rack_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.rack
    ADD CONSTRAINT rack_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: rack rack_room_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.rack
    ADD CONSTRAINT rack_room_id_fkey FOREIGN KEY (room_id) REFERENCES dcmon.room(ci_id);


--
-- Name: room room_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.room
    ADD CONSTRAINT room_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: room room_site_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.room
    ADD CONSTRAINT room_site_id_fkey FOREIGN KEY (site_id) REFERENCES dcmon.site(ci_id);


--
-- Name: runtime runtime_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.runtime
    ADD CONSTRAINT runtime_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: scene_object scene_object_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.scene_object
    ADD CONSTRAINT scene_object_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: site site_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.site
    ADD CONSTRAINT site_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: software_installation software_installation_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.software_installation
    ADD CONSTRAINT software_installation_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: software_installation software_installation_product_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.software_installation
    ADD CONSTRAINT software_installation_product_id_fkey FOREIGN KEY (product_id) REFERENCES dcmon.software_product(id);


--
-- Name: status_observation status_observation_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.status_observation
    ADD CONSTRAINT status_observation_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: status_observation status_observation_source_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.status_observation
    ADD CONSTRAINT status_observation_source_id_fkey FOREIGN KEY (source_id) REFERENCES dcmon.source_system(id);


--
-- Name: storage_volume storage_volume_ci_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.storage_volume
    ADD CONSTRAINT storage_volume_ci_id_fkey FOREIGN KEY (ci_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: storage_volume storage_volume_storage_device_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.storage_volume
    ADD CONSTRAINT storage_volume_storage_device_id_fkey FOREIGN KEY (storage_device_id) REFERENCES dcmon.device(ci_id);


--
-- Name: system_environment system_environment_service_owner_team_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.system_environment
    ADD CONSTRAINT system_environment_service_owner_team_id_fkey FOREIGN KEY (service_owner_team_id) REFERENCES dcmon.team(id);


--
-- Name: system_environment system_environment_system_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.system_environment
    ADD CONSTRAINT system_environment_system_id_fkey FOREIGN KEY (system_id) REFERENCES dcmon.information_system(ci_id);


--
-- Name: volume_attachment volume_attachment_host_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.volume_attachment
    ADD CONSTRAINT volume_attachment_host_id_fkey FOREIGN KEY (host_id) REFERENCES dcmon.ci(ci_id);


--
-- Name: volume_attachment volume_attachment_volume_id_fkey; Type: FK CONSTRAINT; Schema: dcmon; Owner: -
--

ALTER TABLE ONLY dcmon.volume_attachment
    ADD CONSTRAINT volume_attachment_volume_id_fkey FOREIGN KEY (volume_id) REFERENCES dcmon.storage_volume(ci_id);


--
-- PostgreSQL database dump complete
--
