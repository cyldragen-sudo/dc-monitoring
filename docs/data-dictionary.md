# Data dictionary

This dictionary documents every public `dcmon` table, view, column, constraint, index, trigger and function. It describes the exported PostgreSQL 16 definitions; [the model guide](data-model.md) explains cross-object semantics. [`database/catalog.json`](../database/catalog.json) contains the same inventory in machine-readable form. `001_schema.sql` is authoritative for executable definitions and `003_comments.sql` applies English catalog comments.

The fixture contains 36 tables, two views, 221 exposed columns, 20 functions, 187 constraints and 75 indexes. Table row counts below refer to the frozen synthetic fixture at **2026-10-21 11:32 UTC**. Views are evaluated at query time. SQL NULL means absent/unknown or inapplicable according to the column contract; it never silently means zero.

## Object index

| Object | Kind | Demo rows | Purpose |
|---|---|---:|---|
| [backup_run](#backup_run) | table | 54 | Synthetic backup job outcomes for a system environment. Success alone does not prove RPO compliance or recoverability. |
| [ci](#ci) | table | 4495 | Stable configuration-item identity shared by inventory, topology, telemetry and incidents. Type-specific attributes live in subtype tables. |
| [cluster](#cluster) | table | 5 | Logical virtualization, Kubernetes, database or storage cluster; membership may span sites. |
| [cluster_member](#cluster_member) | table | 74 | Effective-dated membership of a configuration item in a logical cluster. |
| [component](#component) | table | 36 | Logical application component within one system environment; multiple deployments can implement the same component. |
| [dependency](#dependency) | table | 3997 | Directed consumer-to-provider dependency, including shared applications, power, cooling, network and storage. A dependency alone does not prove application failure. |
| [deployment](#deployment) | table | 965 | Effective-dated deployment of a component onto compute or a software installation; multiple components may share a host. |
| [device](#device) | table | 1200 | Physical equipment inventory: servers, storage, switches, power, cooling and safety devices. |
| [device_placement](#device_placement) | table | 1200 | Effective-dated physical placement. Rack equipment occupies a U interval; floor equipment has a room without a rack. |
| [external_identity](#external_identity) | table | 619 | Mapping of stable CI identities to source-specific identifiers such as NetBox IDs, vCenter IDs and Kubernetes UIDs. |
| [hosting](#hosting) | table | 146 | Effective-dated VM, pod and container hosting. Endpoint type rules prevent invalid hosting cycles. |
| [incident](#incident) | table | 2 | Stable incident identity and descriptive attributes. Current and historical workflow state come from incident_event. |
| [incident_ci](#incident_ci) | table | 4 | Explicit incident-to-CI links distinguishing cause, confirmed impact and potential risk. |
| [incident_event](#incident_event) | table | 5 | Incident workflow event history, used to reconstruct the state at a requested time. |
| [information_system](#information_system) | table | 6 | Business-system catalog and recovery requirements; requirements are separate from measured availability. |
| [ingestion_run](#ingestion_run) | table | 8 | Synthetic ingestion audit trail: processing state, cursor watermark and accepted/rejected row counts. |
| [installation_placement](#installation_placement) | table | 3040 | Effective-dated placement of a software installation on a physical server, VM or container. |
| [maintenance_window](#maintenance_window) | table | 1 | Approved planned maintenance for a CI; displayed separately from unplanned technical faults. |
| [metric_definition](#metric_definition) | table | 26 | Canonical metric names, units, value domains and illustrative demo thresholds. |
| [metric_sample](#metric_sample) | table | 1058182 | Numeric telemetry facts with distinct observation and ingestion times. Missing/error samples have NULL values, never fabricated zeros. |
| [metric_series](#metric_series) | table | 40574 | One CI, metric and JSON label set measured by a selected authoritative source; collection and freshness budgets are explicit. |
| [network_link](#network_link) | table | 1944 | Effective-dated physical connection between two ports. Exclusion constraints prevent a port from having concurrent cables. |
| [network_port](#network_port) | table | 4248 | Physical network interface belonging to a device; nominal speed is not measured traffic. |
| [rack](#rack) | table | 48 | Rack location, U capacity, power budget and floor-plan coordinates within a room. |
| [room](#room) | table | 6 | Data hall or technical room belonging to a data-center site. |
| [runtime](#runtime) | table | 145 | VM, pod or container inventory. A recreated pod/container receives a new CI; a reused name does not establish identity. |
| [scene_object](#scene_object) | table | 60 | Optional presentation coordinates and asset references for a CI. This legacy 3D mapping is inventory metadata, not required by the current illustrative browser views. |
| [site](#site) | table | 3 | Data-center site at the top of the physical navigation hierarchy. |
| [software_installation](#software_installation) | table | 3040 | Concrete installed software instance such as a machine OS, database instance or Java runtime. |
| [software_product](#software_product) | table | 7 | Software product catalog for operating systems, databases, platforms, middleware and agents; distinct from business systems. |
| [source_system](#source_system) | table | 8 | Data-source integration registry containing configuration references and ownership, without passwords or access secrets. |
| [status_observation](#status_observation) | table | 1725 | Technical CI status history with an explicit freshness lifetime; separate from lifecycle and incident counts. |
| [storage_volume](#storage_volume) | table | 6 | Logical storage volume and its serving storage device; internal pool details remain in the storage source. |
| [system_environment](#system_environment) | table | 18 | PROD, TEST or DEV environment of one business system; placement and ownership remain environment-specific. |
| [team](#team) | table | 4 | Synthetic service and operations teams; contains no personal contact details. |
| [volume_attachment](#volume_attachment) | table | 48 | Effective-dated attachment of a logical volume to compute; shared volumes can serve multiple hosts. |
| [v_inventory_summary](#v_inventory_summary) | view | query time | Counts of currently active inventory grouped by CI kind; planned and retired lifecycle entries are excluded. |
| [v_unmapped_compute](#v_unmapped_compute) | view | query time | Active physical servers and runtimes without an application execution-path association at now(); excludes software installations and does not invent an owner. |

## backup_run

Synthetic backup job outcomes for a system environment. Success alone does not prove RPO compliance or recoverability.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (backup_run_id_seq)` | Stable internal record identifier; not reused. |
| `environment_id` | `bigint` | yes | none | System environment owning or protected by this record. |
| `job_key` | `text` | yes | none | Stable job identity supplied by the backup system. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `started_at` | `timestamp with time zone` | yes | none | Start time of the operation. |
| `finished_at` | `timestamp with time zone` | no | none | Operation completion time; NULL while running. |
| `recovery_point_at` | `timestamp with time zone` | no | none | Timestamp of the data represented by the backup; basis for recovery-point age. |
| `status` | `text` | yes | none | Backup job result: running, success or failed. Partial is an ingestion state, not a backup result. |
| `size_gib` | `numeric(16,3)` | no | none | Size of the created backup in GiB. |
| `restore_test_at` | `timestamp with time zone` | no | none | Last restore test of this exact copy; NULL means no recorded verification. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `backup_run_check` | check | `CHECK (((finished_at IS NULL) OR (finished_at >= started_at)))` |
| `backup_run_check1` | check | `CHECK (((recovery_point_at IS NULL) OR (recovery_point_at <= finished_at)))` |
| `backup_run_check2` | check | `CHECK (((status <> 'success'::text) OR ((finished_at IS NOT NULL) AND (recovery_point_at IS NOT NULL))))` |
| `backup_run_environment_id_fkey` | foreign key | `FOREIGN KEY (environment_id) REFERENCES system_environment(id)` |
| `backup_run_pkey` | primary key | `PRIMARY KEY (id)` |
| `backup_run_size_gib_check` | check | `CHECK ((size_gib >= (0)::numeric))` |
| `backup_run_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |
| `backup_run_source_id_job_key_started_at_key` | unique | `UNIQUE (source_id, job_key, started_at)` |
| `backup_run_status_check` | check | `CHECK ((status = ANY (ARRAY['running'::text, 'success'::text, 'failed'::text])))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `backup_run_pkey` | Enforces the stable primary-key identity on backup_run. Definition: btree (id). |
| `backup_run_source_id_job_key_started_at_key` | Prevents duplicate natural identities on backup_run. Definition: btree (source_id, job_key, started_at). |

## ci

Stable configuration-item identity shared by inventory, topology, telemetry and incidents. Type-specific attributes live in subtype tables.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | `IDENTITY BY DEFAULT (ci_ci_id_seq)` | Stable internal CI identifier, never reused across object lifecycles. |
| `ci_key` | `text` | yes | none | Stable readable object key; changing a hostname does not create a new CI. |
| `kind` | `text` | yes | none | Configuration-item subtype discriminator. |
| `name` | `text` | yes | none | Human-readable display name; does not replace a stable identifier. |
| `owner_team_id` | `bigint` | yes | none | Team responsible for the object or incident. |
| `lifecycle` | `text` | yes | none | Inventory lifecycle, separate from technical health and incident workflow state. |
| `retired_at` | `timestamp with time zone` | no | none | Retirement time; NULL before retirement. Preserves historical object visibility. |
| `first_seen_at` | `timestamp with time zone` | yes | none | First discovery time in an inventory source. |
| `last_seen_at` | `timestamp with time zone` | yes | none | Last source confirmation of existence or identity; not telemetry observation time. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `ci_check` | check | `CHECK ((last_seen_at >= first_seen_at))` |
| `ci_check1` | check | `CHECK (((lifecycle = 'retired'::text) = (retired_at IS NOT NULL)))` |
| `ci_check2` | check | `CHECK (((retired_at IS NULL) OR (retired_at >= first_seen_at)))` |
| `ci_ci_key_key` | unique | `UNIQUE (ci_key)` |
| `ci_kind_check` | check | `CHECK ((kind = ANY (ARRAY['site'::text, 'room'::text, 'rack'::text, 'device'::text, 'runtime'::text, 'cluster'::text, 'installation'::text, 'system'::text, 'component'::text, 'volume'::text])))` |
| `ci_lifecycle_check` | check | `CHECK ((lifecycle = ANY (ARRAY['planned'::text, 'active'::text, 'retired'::text])))` |
| `ci_owner_team_id_fkey` | foreign key | `FOREIGN KEY (owner_team_id) REFERENCES team(id)` |
| `ci_pkey` | primary key | `PRIMARY KEY (ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `ci_ci_key_key` | Prevents duplicate natural identities on ci. Definition: btree (ci_key). |
| `ci_pkey` | Enforces the stable primary-key identity on ci. Definition: btree (ci_id). |

**Triggers**

- `ci_kind_immutable`: Before ci kind updates, rejects a different subtype with SQLSTATE 23514 so existing subtype, topology and telemetry references retain their interpretation. Other inventory attributes may change. Retiring/replacing a CI preserves identity history instead of retyping it. `CREATE TRIGGER ci_kind_immutable BEFORE UPDATE OF kind ON dcmon.ci FOR EACH ROW EXECUTE FUNCTION immutable_ci_kind()`

## cluster

Logical virtualization, Kubernetes, database or storage cluster; membership may span sites.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `cluster_type` | `text` | yes | none | Cluster purpose or orchestration type. |
| `platform` | `text` | yes | none | Technology or platform implementing the cluster. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `cluster_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `cluster_cluster_type_check` | check | `CHECK ((cluster_type = ANY (ARRAY['virtualization'::text, 'kubernetes'::text, 'database'::text, 'storage'::text])))` |
| `cluster_pkey` | primary key | `PRIMARY KEY (ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `cluster_pkey` | Enforces the stable primary-key identity on cluster. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.cluster FOR EACH ROW EXECUTE FUNCTION require_ci_kind('cluster')`

## cluster_member

Effective-dated membership of a configuration item in a logical cluster.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (cluster_member_id_seq)` | Stable internal record identifier; not reused. |
| `cluster_id` | `bigint` | yes | none | Logical cluster receiving the member. |
| `member_id` | `bigint` | yes | none | Cluster member CI: a device, runtime or software installation. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `cluster_member_check` | check | `CHECK ((cluster_id <> member_id))` |
| `cluster_member_check1` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `cluster_member_cluster_id_fkey` | foreign key | `FOREIGN KEY (cluster_id) REFERENCES cluster(ci_id)` |
| `cluster_member_cluster_id_member_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (cluster_id WITH =, member_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `cluster_member_member_id_fkey` | foreign key | `FOREIGN KEY (member_id) REFERENCES ci(ci_id)` |
| `cluster_member_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `cluster_member_cluster_id_member_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on cluster_member. Definition: gist (cluster_id, member_id, tstzrange(valid_from, valid_to, '[)'::text)). |
| `cluster_member_pkey` | Enforces the stable primary-key identity on cluster_member. Definition: btree (id). |

## component

Logical application component within one system environment; multiple deployments can implement the same component.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `environment_id` | `bigint` | yes | none | System environment owning or protected by this record. |
| `component_role` | `text` | yes | none | Architectural role within the application, such as web or database. |
| `description` | `text` | yes | none | Component purpose and responsibility boundary. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `component_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `component_component_role_check` | check | `CHECK ((component_role = ANY (ARRAY['web'::text, 'api'::text, 'database'::text, 'queue'::text, 'batch'::text])))` |
| `component_environment_id_fkey` | foreign key | `FOREIGN KEY (environment_id) REFERENCES system_environment(id)` |
| `component_pkey` | primary key | `PRIMARY KEY (ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `component_environment_idx` | Finds application components for a selected system environment on component. Definition: btree (environment_id). |
| `component_pkey` | Enforces the stable primary-key identity on component. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.component FOR EACH ROW EXECUTE FUNCTION require_ci_kind('component')`

## dependency

Directed consumer-to-provider dependency, including shared applications, power, cooling, network and storage. A dependency alone does not prove application failure.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (dependency_id_seq)` | Stable internal record identifier; not reused. |
| `dependent_id` | `bigint` | yes | none | Consumer CI that relies on the provider; traversal follows this direction. |
| `provider_id` | `bigint` | yes | none | Provider CI supplying an application or infrastructure resource. |
| `dependency_type` | `text` | yes | none | Dependency category controlling allowed endpoint types and graph traversal. |
| `redundancy_group` | `text` | no | none | Optional redundancy label such as A/B; does not itself calculate resilience. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `dependency_check` | check | `CHECK ((dependent_id <> provider_id))` |
| `dependency_check1` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `dependency_dependency_type_check` | check | `CHECK ((dependency_type = ANY (ARRAY['application'::text, 'power'::text, 'cooling'::text, 'network'::text, 'storage'::text])))` |
| `dependency_dependent_id_fkey` | foreign key | `FOREIGN KEY (dependent_id) REFERENCES ci(ci_id)` |
| `dependency_dependent_id_provider_id_dependency_type_tstzra_excl` | exclusion | `EXCLUDE USING gist (dependent_id WITH =, provider_id WITH =, dependency_type WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `dependency_pkey` | primary key | `PRIMARY KEY (id)` |
| `dependency_provider_id_fkey` | foreign key | `FOREIGN KEY (provider_id) REFERENCES ci(ci_id)` |
| `dependency_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `dependency_dependent_id_provider_id_dependency_type_tstzra_excl` | Prevents overlapping effective-dated relationships on dependency. Definition: gist (dependent_id, provider_id, dependency_type, tstzrange(valid_from, valid_to, '[)'::text)). |
| `dependency_dependent_idx` | Traverses directed dependencies from consumer to infrastructure provider on dependency. Definition: btree (dependent_id). |
| `dependency_pkey` | Enforces the stable primary-key identity on dependency. Definition: btree (id). |
| `dependency_provider_idx` | Finds consumers of a provider for inventory investigation; traversal direction remains explicit on dependency. Definition: btree (provider_id). |

**Triggers**

- `valid_dependency`: Checks directed consumer/provider types on dependency INSERT/UPDATE. Application: component to component/installation; power: device/rack to PDU/UPS/generator; cooling: room/rack/device to CRAC/chiller; network: device/runtime to switch; storage: device/runtime to storage. Rejects unknown/missing endpoint types with SQLSTATE 23514; does not infer availability, redundancy or traversal in the reverse direction. Uses caller search_path dcmon,public. `CREATE TRIGGER valid_dependency BEFORE INSERT OR UPDATE ON dcmon.dependency FOR EACH ROW EXECUTE FUNCTION check_dependency()`

## deployment

Effective-dated deployment of a component onto compute or a software installation; multiple components may share a host.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (deployment_id_seq)` | Stable internal record identifier; not reused. |
| `component_id` | `bigint` | yes | none | Application component being deployed. |
| `target_id` | `bigint` | yes | none | Compute or software-installation CI receiving the component; validated by trigger. |
| `role` | `text` | yes | none | Deployment role such as primary or standby; standby does not imply failure. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `deployment_check` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `deployment_component_id_fkey` | foreign key | `FOREIGN KEY (component_id) REFERENCES component(ci_id)` |
| `deployment_component_id_target_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (component_id WITH =, target_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `deployment_pkey` | primary key | `PRIMARY KEY (id)` |
| `deployment_role_check` | check | `CHECK ((role = ANY (ARRAY['primary'::text, 'replica'::text, 'standby'::text, 'worker'::text])))` |
| `deployment_target_id_fkey` | foreign key | `FOREIGN KEY (target_id) REFERENCES ci(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `deployment_component_id_target_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on deployment. Definition: gist (component_id, target_id, tstzrange(valid_from, valid_to, '[)'::text)). |
| `deployment_pkey` | Enforces the stable primary-key identity on deployment. Definition: btree (id). |
| `deployment_target_idx` | Finds component deployments targeting a compute or installation CI on deployment. Definition: btree (target_id). |

**Triggers**

- `valid_deployment`: Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public. `CREATE TRIGGER valid_deployment BEFORE INSERT OR UPDATE ON dcmon.deployment FOR EACH ROW EXECUTE FUNCTION check_compute_reference()`

## device

Physical equipment inventory: servers, storage, switches, power, cooling and safety devices.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `device_class` | `text` | yes | none | Physical device class; immutable after creation to protect typed relationships. |
| `manufacturer` | `text` | yes | none | Equipment manufacturer; synthetic demo attribution. |
| `model` | `text` | yes | none | Equipment model or synthetic chassis description. |
| `serial_number` | `text` | no | none | Device serial number; NULL when the source provides none. |
| `cpu_cores` | `integer` | no | none | Installed physical CPU cores on a server; distinct from allocated vCPU. |
| `memory_gib` | `numeric(12,2)` | no | none | Installed server memory in GiB. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `device_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `device_cpu_cores_check` | check | `CHECK ((cpu_cores > 0))` |
| `device_device_class_check` | check | `CHECK ((device_class = ANY (ARRAY['server'::text, 'storage'::text, 'switch'::text, 'ups'::text, 'pdu'::text, 'crac'::text, 'chiller'::text, 'generator'::text, 'fire_sensor'::text, 'access_controller'::text])))` |
| `device_memory_gib_check` | check | `CHECK ((memory_gib > (0)::numeric))` |
| `device_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `device_serial_number_key` | unique | `UNIQUE (serial_number)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `device_pkey` | Enforces the stable primary-key identity on device. Definition: btree (ci_id). |
| `device_serial_number_key` | Prevents duplicate natural identities on device. Definition: btree (serial_number). |

**Triggers**

- `device_class_guard`: Before device_class updates, rejects a different class with SQLSTATE 23514 because dependency and hosting rules rely on that class. Replace or retire an incorrectly classified device through an explicit migration rather than silently reinterpreting relationships. `CREATE TRIGGER device_class_guard BEFORE UPDATE OF device_class ON dcmon.device FOR EACH ROW EXECUTE FUNCTION immutable_device_class()`
- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.device FOR EACH ROW EXECUTE FUNCTION require_ci_kind('device')`

## device_placement

Effective-dated physical placement. Rack equipment occupies a U interval; floor equipment has a room without a rack.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (device_placement_id_seq)` | Stable internal record identifier; not reused. |
| `device_id` | `bigint` | yes | none | Physical device owning the port or placement. |
| `room_id` | `bigint` | yes | none | Physical room containing this object. |
| `rack_id` | `bigint` | no | none | Rack containing the device; NULL for floor equipment. |
| `u_start` | `integer` | no | none | First occupied rack unit, counted from 1; NULL for floor or 0U equipment. |
| `u_height` | `integer` | no | none | Number of occupied rack units; NULL together with u_start for 0U equipment. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `device_placement_check` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `device_placement_check1` | check | `CHECK ((((u_start IS NULL) AND (u_height IS NULL)) OR ((rack_id IS NOT NULL) AND (u_start > 0) AND (u_height > 0))))` |
| `device_placement_check2` | check | `CHECK (((rack_id IS NOT NULL) OR ((u_start IS NULL) AND (u_height IS NULL))))` |
| `device_placement_device_id_fkey` | foreign key | `FOREIGN KEY (device_id) REFERENCES device(ci_id)` |
| `device_placement_device_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (device_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `device_placement_pkey` | primary key | `PRIMARY KEY (id)` |
| `device_placement_rack_id_fkey` | foreign key | `FOREIGN KEY (rack_id) REFERENCES rack(ci_id)` |
| `device_placement_rack_id_int4range_tstzrange_excl` | exclusion | `EXCLUDE USING gist (rack_id WITH =, int4range(u_start, (u_start + u_height), '[)'::text) WITH &&, tstzrange(valid_from, valid_to, '[)'::text) WITH &&) WHERE ((u_start IS NOT NULL))` |
| `device_placement_rack_id_room_id_fkey` | foreign key | `FOREIGN KEY (rack_id, room_id) REFERENCES rack(ci_id, room_id)` |
| `device_placement_room_id_fkey` | foreign key | `FOREIGN KEY (room_id) REFERENCES room(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `device_placement_device_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on device_placement. Definition: gist (device_id, tstzrange(valid_from, valid_to, '[)'::text)). |
| `device_placement_pkey` | Enforces the stable primary-key identity on device_placement. Definition: btree (id). |
| `device_placement_rack_id_int4range_tstzrange_excl` | Prevents overlapping effective-dated relationships on device_placement. Definition: gist (rack_id, int4range(u_start, (u_start + u_height), '[)'::text), tstzrange(valid_from, valid_to, '[)'::text)) WHERE (u_start IS NOT NULL). |
| `placement_rack_idx` | Finds all device placements in a rack for layout and capacity checks on device_placement. Definition: btree (rack_id). |

**Triggers**

- `valid_rack_space`: On device_placement INSERT/UPDATE with a U interval, acquires a shared lock on the target rack and checks inclusive top U (u_start+u_height-1) against height_u. NULL U denotes floor/0U placement and bypasses the capacity test; table checks and exclusions enforce other shape/overlap rules. Raises SQLSTATE 23514 on overflow. Uses caller search_path dcmon,public. `CREATE TRIGGER valid_rack_space BEFORE INSERT OR UPDATE ON dcmon.device_placement FOR EACH ROW EXECUTE FUNCTION check_rack_space()`

## external_identity

Mapping of stable CI identities to source-specific identifiers such as NetBox IDs, vCenter IDs and Kubernetes UIDs.

**Grain:** One row per PRIMARY KEY (source_id, external_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `external_id` | `text` | yes | none | Unique identity within a source; Kubernetes uses UID rather than name alone. |
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `last_seen_at` | `timestamp with time zone` | yes | none | Last source confirmation of existence or identity; not telemetry observation time. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `external_identity_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `external_identity_pkey` | primary key | `PRIMARY KEY (source_id, external_id)` |
| `external_identity_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `external_identity_ci_idx` | Finds all source-specific identities associated with one stable CI on external_identity. Definition: btree (ci_id). |
| `external_identity_pkey` | Enforces the stable primary-key identity on external_identity. Definition: btree (source_id, external_id). |

## hosting

Effective-dated VM, pod and container hosting. Endpoint type rules prevent invalid hosting cycles.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (hosting_id_seq)` | Stable internal record identifier; not reused. |
| `guest_id` | `bigint` | yes | none | Guest runtime CI: VM, pod or container. |
| `host_id` | `bigint` | yes | none | Compute host CI; endpoint type is validated. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `hosting_check` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `hosting_check1` | check | `CHECK ((guest_id <> host_id))` |
| `hosting_guest_id_fkey` | foreign key | `FOREIGN KEY (guest_id) REFERENCES runtime(ci_id)` |
| `hosting_guest_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (guest_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `hosting_host_id_fkey` | foreign key | `FOREIGN KEY (host_id) REFERENCES ci(ci_id)` |
| `hosting_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `hosting_guest_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on hosting. Definition: gist (guest_id, tstzrange(valid_from, valid_to, '[)'::text)). |
| `hosting_host_idx` | Finds guests on a host for explicit inventory lookup, without implying reverse scope traversal on hosting. Definition: btree (host_id). |
| `hosting_pkey` | Enforces the stable primary-key identity on hosting. Definition: btree (id). |

**Triggers**

- `valid_hosting`: Checks hosting INSERT/UPDATE hierarchy: VM to physical server, pod to VM/server, container to pod. Rejects invalid or missing endpoint types with SQLSTATE 23514. Effective-dated overlap constraints separately prevent simultaneous hosts. Uses caller search_path dcmon,public. `CREATE TRIGGER valid_hosting BEFORE INSERT OR UPDATE ON dcmon.hosting FOR EACH ROW EXECUTE FUNCTION check_hosting()`

## incident

Stable incident identity and descriptive attributes. Current and historical workflow state come from incident_event.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (incident_id_seq)` | Stable internal record identifier; not reused. |
| `incident_key` | `text` | yes | none | Stable human-readable incident key. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `external_id` | `text` | yes | none | Incident identity within its source system. |
| `title` | `text` | yes | none | Short incident description. |
| `severity` | `text` | yes | none | Incident impact severity, separate from business-system criticality. |
| `detected_at` | `timestamp with time zone` | yes | none | First detection timestamp. |
| `owner_team_id` | `bigint` | yes | none | Team responsible for the object or incident. |
| `response_due_at` | `timestamp with time zone` | no | none | Response deadline under the agreed service rule. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `incident_incident_key_key` | unique | `UNIQUE (incident_key)` |
| `incident_owner_team_id_fkey` | foreign key | `FOREIGN KEY (owner_team_id) REFERENCES team(id)` |
| `incident_pkey` | primary key | `PRIMARY KEY (id)` |
| `incident_severity_check` | check | `CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])))` |
| `incident_source_id_external_id_key` | unique | `UNIQUE (source_id, external_id)` |
| `incident_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `incident_incident_key_key` | Prevents duplicate natural identities on incident. Definition: btree (incident_key). |
| `incident_pkey` | Enforces the stable primary-key identity on incident. Definition: btree (id). |
| `incident_source_id_external_id_key` | Prevents duplicate natural identities on incident. Definition: btree (source_id, external_id). |

## incident_ci

Explicit incident-to-CI links distinguishing cause, confirmed impact and potential risk.

**Grain:** One row per PRIMARY KEY (incident_id, ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `incident_id` | `bigint` | yes | none | Incident record referenced by this link or event. |
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `impact_role` | `text` | yes | none | cause, affected or at_risk; potential risk does not assert a confirmed outage. |
| `linked_at` | `timestamp with time zone` | yes | none | Time the object association was confirmed; respected by historical scope queries. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `incident_ci_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `incident_ci_impact_role_check` | check | `CHECK ((impact_role = ANY (ARRAY['cause'::text, 'affected'::text, 'at_risk'::text])))` |
| `incident_ci_incident_id_fkey` | foreign key | `FOREIGN KEY (incident_id) REFERENCES incident(id)` |
| `incident_ci_pkey` | primary key | `PRIMARY KEY (incident_id, ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `incident_ci_pkey` | Enforces the stable primary-key identity on incident_ci. Definition: btree (incident_id, ci_id). |
| `incident_ci_reverse_idx` | Finds incident links for an in-scope configuration item on incident_ci. Definition: btree (ci_id). |

## incident_event

Incident workflow event history, used to reconstruct the state at a requested time.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (incident_event_id_seq)` | Stable internal record identifier; not reused. |
| `incident_id` | `bigint` | yes | none | Incident record referenced by this link or event. |
| `occurred_at` | `timestamp with time zone` | yes | none | Time the incident workflow transition occurred. |
| `state` | `text` | yes | none | Workflow state after the event: open, acknowledged, in_progress, resolved or closed. |
| `note` | `text` | yes | none | Synthetic action or diagnostic note without personal information. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `incident_event_incident_id_fkey` | foreign key | `FOREIGN KEY (incident_id) REFERENCES incident(id)` |
| `incident_event_incident_id_occurred_at_key` | unique | `UNIQUE (incident_id, occurred_at)` |
| `incident_event_pkey` | primary key | `PRIMARY KEY (id)` |
| `incident_event_state_check` | check | `CHECK ((state = ANY (ARRAY['open'::text, 'acknowledged'::text, 'in_progress'::text, 'resolved'::text, 'closed'::text])))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `incident_event_incident_id_occurred_at_key` | Prevents duplicate natural identities on incident_event. Definition: btree (incident_id, occurred_at). |
| `incident_event_latest_idx` | Selects the latest workflow event at or before a requested incident time on incident_event. Definition: btree (incident_id, occurred_at DESC). |
| `incident_event_pkey` | Enforces the stable primary-key identity on incident_event. Definition: btree (id). |

## information_system

Business-system catalog and recovery requirements; requirements are separate from measured availability.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `description` | `text` | yes | none | Purpose of the business application. |
| `criticality` | `text` | yes | none | Business criticality classification; independent of current faults. |
| `target_rto_min` | `integer` | no | none | Required recovery time in minutes; a target rather than observed recovery duration. |
| `target_rpo_min` | `integer` | no | none | Required maximum data-loss time in minutes; agreed with the service owner. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `information_system_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `information_system_criticality_check` | check | `CHECK ((criticality = ANY (ARRAY['critical'::text, 'high'::text, 'standard'::text])))` |
| `information_system_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `information_system_target_rpo_min_check` | check | `CHECK ((target_rpo_min >= 0))` |
| `information_system_target_rto_min_check` | check | `CHECK ((target_rto_min >= 0))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `information_system_pkey` | Enforces the stable primary-key identity on information_system. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.information_system FOR EACH ROW EXECUTE FUNCTION require_ci_kind('system')`

## ingestion_run

Synthetic ingestion audit trail: processing state, cursor watermark and accepted/rejected row counts.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (ingestion_run_id_seq)` | Stable internal record identifier; not reused. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `started_at` | `timestamp with time zone` | yes | none | Start time of the operation. |
| `finished_at` | `timestamp with time zone` | no | none | Operation completion time; NULL while running. |
| `state` | `text` | yes | none | Ingestion state: running, success, partial or failed. |
| `cursor_value` | `text` | no | none | Watermark or API cursor after a processed batch; never an access token. |
| `accepted_rows` | `integer` | yes | none | Number of rows accepted by the ingestion run. |
| `rejected_rows` | `integer` | yes | none | Number of rows rejected by validation or processing. |
| `error_summary` | `text` | no | none | Short sanitized processing diagnostic; NULL if no error is recorded. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `ingestion_run_accepted_rows_check` | check | `CHECK ((accepted_rows >= 0))` |
| `ingestion_run_check` | check | `CHECK (((finished_at IS NULL) OR (finished_at >= started_at)))` |
| `ingestion_run_pkey` | primary key | `PRIMARY KEY (id)` |
| `ingestion_run_rejected_rows_check` | check | `CHECK ((rejected_rows >= 0))` |
| `ingestion_run_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |
| `ingestion_run_state_check` | check | `CHECK ((state = ANY (ARRAY['running'::text, 'success'::text, 'partial'::text, 'failed'::text])))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `ingestion_run_pkey` | Enforces the stable primary-key identity on ingestion_run. Definition: btree (id). |

## installation_placement

Effective-dated placement of a software installation on a physical server, VM or container.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (installation_placement_id_seq)` | Stable internal record identifier; not reused. |
| `installation_id` | `bigint` | yes | none | Concrete software installation referenced by the placement. |
| `host_id` | `bigint` | yes | none | Compute host CI; endpoint type is validated. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `installation_placement_check` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `installation_placement_host_id_fkey` | foreign key | `FOREIGN KEY (host_id) REFERENCES ci(ci_id)` |
| `installation_placement_installation_id_fkey` | foreign key | `FOREIGN KEY (installation_id) REFERENCES software_installation(ci_id)` |
| `installation_placement_installation_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (installation_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |
| `installation_placement_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `installation_host_idx` | Finds software placed on nodes of an execution path on installation_placement. Definition: btree (host_id). |
| `installation_placement_installation_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on installation_placement. Definition: gist (installation_id, tstzrange(valid_from, valid_to, '[)'::text)). |
| `installation_placement_pkey` | Enforces the stable primary-key identity on installation_placement. Definition: btree (id). |

**Triggers**

- `valid_installation_host`: Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public. `CREATE TRIGGER valid_installation_host BEFORE INSERT OR UPDATE ON dcmon.installation_placement FOR EACH ROW EXECUTE FUNCTION check_compute_reference()`

## maintenance_window

Approved planned maintenance for a CI; displayed separately from unplanned technical faults.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (maintenance_window_id_seq)` | Stable internal record identifier; not reused. |
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `starts_at` | `timestamp with time zone` | yes | none | Inclusive start of the agreed maintenance window. |
| `ends_at` | `timestamp with time zone` | yes | none | End of the agreed maintenance window; strictly after starts_at. |
| `reason` | `text` | yes | none | Description of planned maintenance work. |
| `change_ref` | `text` | yes | none | Approved change reference from the service-management process. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `maintenance_window_check` | check | `CHECK ((ends_at > starts_at))` |
| `maintenance_window_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `maintenance_window_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `maintenance_window_pkey` | Enforces the stable primary-key identity on maintenance_window. Definition: btree (id). |

## metric_definition

Canonical metric names, units, value domains and illustrative demo thresholds.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (metric_definition_id_seq)` | Stable internal record identifier; not reused. |
| `code` | `text` | yes | none | Stable machine-readable catalog code. |
| `name` | `text` | yes | none | Human-readable metric label; values use the canonical unit column. |
| `unit` | `text` | yes | none | Canonical unit after normalization; interpreted together with metric code. |
| `metric_type` | `text` | yes | none | gauge is an instantaneous reading; counter is cumulative and requires rate conversion for throughput. |
| `valid_min` | `numeric` | no | none | Lower valid value boundary; NULL leaves the lower side unrestricted. |
| `valid_max` | `numeric` | no | none | Upper valid value boundary; NULL leaves the upper side unrestricted. |
| `warning_above` | `numeric` | no | none | Illustrative demo upper warning threshold; NULL means no such threshold. |
| `critical_above` | `numeric` | no | none | Illustrative demo upper critical threshold; NULL means no such threshold. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `metric_definition_check` | check | `CHECK (((valid_max IS NULL) OR (valid_min IS NULL) OR (valid_max >= valid_min)))` |
| `metric_definition_check1` | check | `CHECK (((critical_above IS NULL) OR (warning_above IS NULL) OR (critical_above >= warning_above)))` |
| `metric_definition_code_key` | unique | `UNIQUE (code)` |
| `metric_definition_metric_type_check` | check | `CHECK ((metric_type = ANY (ARRAY['gauge'::text, 'counter'::text])))` |
| `metric_definition_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `metric_definition_code_key` | Prevents duplicate natural identities on metric_definition. Definition: btree (code). |
| `metric_definition_pkey` | Enforces the stable primary-key identity on metric_definition. Definition: btree (id). |

## metric_sample

Numeric telemetry facts with distinct observation and ingestion times. Missing/error samples have NULL values, never fabricated zeros.

**Grain:** One row per PRIMARY KEY (series_id, observed_at).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `series_id` | `bigint` | yes | none | Stable metric-series identity referencing dcmon.metric_series. |
| `observed_at` | `timestamp with time zone` | yes | none | Time the fact was observed in the source; used for as-of selection. |
| `ingested_at` | `timestamp with time zone` | yes | `clock_timestamp()` | Time the observation reached the warehouse; separate from observed_at. |
| `value` | `numeric` | no | none | Numeric value in metric_definition.unit; NULL for missing/error quality, never a substituted zero. |
| `quality` | `text` | yes | none | Point quality: ok requires a finite value; missing and error require NULL. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `metric_sample_check` | check | `CHECK ((((quality = 'ok'::text) AND (value IS NOT NULL) AND (value <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric]))) OR ((quality <> 'ok'::text) AND (value IS NULL))))` |
| `metric_sample_pkey` | primary key | `PRIMARY KEY (series_id, observed_at)` |
| `metric_sample_quality_check` | check | `CHECK ((quality = ANY (ARRAY['ok'::text, 'missing'::text, 'error'::text])))` |
| `metric_sample_series_id_fkey` | foreign key | `FOREIGN KEY (series_id) REFERENCES metric_series(series_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `metric_sample_latest_idx` | Selects the most recent sample at or before p_at for each series on metric_sample. Definition: btree (series_id, observed_at DESC). |
| `metric_sample_pkey` | Enforces the stable primary-key identity on metric_sample. Definition: btree (series_id, observed_at). |
| `metric_sample_time_brin` | Uses compact block-range summaries for observed-time range scans on append-like telemetry on metric_sample. Definition: brin (observed_at). |

**Triggers**

- `valid_metric_range`: On metric_sample INSERT/UPDATE, validates only quality=ok against its definition valid_min/valid_max. NULL bounds leave that side unrestricted. Table checks independently require finite values for ok and NULL for missing/error. Warning and critical thresholds are presentation guidance, never validity limits. Raises SQLSTATE 23514 for a range breach. Uses caller search_path dcmon,public. `CREATE TRIGGER valid_metric_range BEFORE INSERT OR UPDATE ON dcmon.metric_sample FOR EACH ROW EXECUTE FUNCTION check_metric_value()`

## metric_series

One CI, metric and JSON label set measured by a selected authoritative source; collection and freshness budgets are explicit.

**Grain:** One row per PRIMARY KEY (series_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `series_id` | `bigint` | yes | `IDENTITY BY DEFAULT (metric_series_series_id_seq)` | Stable metric-series identity referencing dcmon.metric_series. |
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `metric_id` | `bigint` | yes | none | Definition providing metric code, unit, value range and thresholds. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |
| `labels` | `jsonb` | yes | `'{}'::jsonb` | Low-cardinality JSON dimensions such as disk, port, sensor or power feed; not request IDs. |
| `expected_interval_sec` | `integer` | yes | none | Expected measurement collection interval in seconds; positive. |
| `stale_after_sec` | `integer` | yes | none | Maximum accepted observation age in seconds; at least the expected interval. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `metric_series_check` | check | `CHECK ((stale_after_sec >= expected_interval_sec))` |
| `metric_series_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `metric_series_ci_id_metric_id_labels_key` | unique | `UNIQUE (ci_id, metric_id, labels)` |
| `metric_series_expected_interval_sec_check` | check | `CHECK ((expected_interval_sec > 0))` |
| `metric_series_labels_check` | check | `CHECK ((jsonb_typeof(labels) = 'object'::text))` |
| `metric_series_metric_id_fkey` | foreign key | `FOREIGN KEY (metric_id) REFERENCES metric_definition(id)` |
| `metric_series_pkey` | primary key | `PRIMARY KEY (series_id)` |
| `metric_series_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |
| `metric_series_stale_after_sec_check` | check | `CHECK ((stale_after_sec > 0))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `metric_series_ci_id_metric_id_labels_key` | Prevents duplicate natural identities on metric_series. Definition: btree (ci_id, metric_id, labels). |
| `metric_series_ci_idx` | Finds metric series for a selected configuration item on metric_series. Definition: btree (ci_id). |
| `metric_series_pkey` | Enforces the stable primary-key identity on metric_series. Definition: btree (series_id). |

## network_link

Effective-dated physical connection between two ports. Exclusion constraints prevent a port from having concurrent cables.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (network_link_id_seq)` | Stable internal record identifier; not reused. |
| `port_a_id` | `bigint` | yes | none | Lower numeric endpoint port ID; canonical ordering avoids mirrored links. |
| `port_b_id` | `bigint` | yes | none | Higher numeric endpoint port ID; canonical ordering avoids mirrored links. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `network_link_check` | check | `CHECK ((port_a_id < port_b_id))` |
| `network_link_check1` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `network_link_pkey` | primary key | `PRIMARY KEY (id)` |
| `network_link_port_a_id_fkey` | foreign key | `FOREIGN KEY (port_a_id) REFERENCES network_port(id)` |
| `network_link_port_b_id_fkey` | foreign key | `FOREIGN KEY (port_b_id) REFERENCES network_port(id)` |
| `no_port_overlap` | exclusion | `EXCLUDE USING gist (int8multirange(VARIADIC ARRAY[int8range(port_a_id, port_a_id, '[]'::text), int8range(port_b_id, port_b_id, '[]'::text)]) WITH &&, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `network_link_pkey` | Enforces the stable primary-key identity on network_link. Definition: btree (id). |
| `no_port_overlap` | Prevents overlapping effective-dated relationships on network_link. Definition: gist (int8multirange(VARIADIC ARRAY[int8range(port_a_id, port_a_id, '[]'::text), int8range(port_b_id, port_b_id, '[]'::text)]), tstzrange(valid_from, valid_to, '[)'::text)). |

## network_port

Physical network interface belonging to a device; nominal speed is not measured traffic.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (network_port_id_seq)` | Stable internal record identifier; not reused. |
| `device_id` | `bigint` | yes | none | Physical device owning the port or placement. |
| `name` | `text` | yes | none | Port name unique within its physical device. |
| `speed_mbps` | `bigint` | no | none | Nominal interface speed in megabits per second; positive and distinct from measured traffic. |
| `mac_address` | `macaddr` | no | none | Hardware MAC address when applicable; NULL when unknown or inapplicable. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `network_port_device_id_fkey` | foreign key | `FOREIGN KEY (device_id) REFERENCES device(ci_id)` |
| `network_port_device_id_name_key` | unique | `UNIQUE (device_id, name)` |
| `network_port_pkey` | primary key | `PRIMARY KEY (id)` |
| `network_port_speed_mbps_check` | check | `CHECK ((speed_mbps > 0))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `network_port_device_id_name_key` | Prevents duplicate natural identities on network_port. Definition: btree (device_id, name). |
| `network_port_pkey` | Enforces the stable primary-key identity on network_port. Definition: btree (id). |

## rack

Rack location, U capacity, power budget and floor-plan coordinates within a room.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `room_id` | `bigint` | yes | none | Physical room containing this object. |
| `height_u` | `integer` | yes | none | Rack equipment capacity in rack units (U). |
| `power_limit_kw` | `numeric(10,2)` | yes | none | Allowed aggregate rack power in kilowatts; a capacity limit rather than a measurement. |
| `x_m` | `numeric(10,3)` | yes | none | Floor-plan X coordinate in meters. |
| `y_m` | `numeric(10,3)` | yes | none | Floor-plan Y coordinate in meters. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `rack_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `rack_ci_id_room_id_key` | unique | `UNIQUE (ci_id, room_id)` |
| `rack_height_u_check` | check | `CHECK ((height_u > 0))` |
| `rack_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `rack_power_limit_kw_check` | check | `CHECK ((power_limit_kw > (0)::numeric))` |
| `rack_room_id_fkey` | foreign key | `FOREIGN KEY (room_id) REFERENCES room(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `rack_ci_id_room_id_key` | Prevents duplicate natural identities on rack. Definition: btree (ci_id, room_id). |
| `rack_pkey` | Enforces the stable primary-key identity on rack. Definition: btree (ci_id). |

**Triggers**

- `rack_height_guard`: Before rack height updates, rejects any height below the inclusive top U of an existing placement, including historical/closed intervals. Preserves historical physical validity; it is intentionally stricter than checking only current placements. Raises SQLSTATE 23514. Uses caller search_path dcmon,public. `CREATE TRIGGER rack_height_guard BEFORE UPDATE OF height_u ON dcmon.rack FOR EACH ROW EXECUTE FUNCTION prevent_rack_shrink()`
- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.rack FOR EACH ROW EXECUTE FUNCTION require_ci_kind('rack')`

## room

Data hall or technical room belonging to a data-center site.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `site_id` | `bigint` | yes | none | Data-center site containing the room. |
| `floor_no` | `integer` | yes | none | Building floor number. |
| `area_m2` | `numeric(10,2)` | no | none | Room floor area in square meters. |
| `room_type` | `text` | yes | none | Room purpose: data_hall, power, cooling or other. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `room_area_m2_check` | check | `CHECK ((area_m2 > (0)::numeric))` |
| `room_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `room_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `room_room_type_check` | check | `CHECK ((room_type = ANY (ARRAY['data_hall'::text, 'power'::text, 'cooling'::text, 'other'::text])))` |
| `room_site_id_fkey` | foreign key | `FOREIGN KEY (site_id) REFERENCES site(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `room_pkey` | Enforces the stable primary-key identity on room. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.room FOR EACH ROW EXECUTE FUNCTION require_ci_kind('room')`

## runtime

VM, pod or container inventory. A recreated pod/container receives a new CI; a reused name does not establish identity.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `runtime_kind` | `text` | yes | none | VM, pod or container type; immutable after creation. |
| `namespace` | `text` | no | none | Orchestrator namespace; NULL for virtual machines. |
| `workload_name` | `text` | no | none | Logical deployment, StatefulSet or VM-group name; not object identity. |
| `image_ref` | `text` | no | none | Container image/digest or VM template reference, without access credentials. |
| `vcpu_allocated` | `numeric(10,3)` | no | none | Allocated or requested vCPU; not actual CPU utilization. |
| `memory_gib_allocated` | `numeric(12,3)` | no | none | Allocated or requested RAM in GiB; not measured memory utilization. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `runtime_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `runtime_memory_gib_allocated_check` | check | `CHECK ((memory_gib_allocated >= (0)::numeric))` |
| `runtime_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `runtime_runtime_kind_check` | check | `CHECK ((runtime_kind = ANY (ARRAY['vm'::text, 'pod'::text, 'container'::text])))` |
| `runtime_vcpu_allocated_check` | check | `CHECK ((vcpu_allocated >= (0)::numeric))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `runtime_pkey` | Enforces the stable primary-key identity on runtime. Definition: btree (ci_id). |

**Triggers**

- `runtime_kind_guard`: Before runtime_kind updates, rejects changing VM/pod/container type with SQLSTATE 23514 because hosting rules depend on the subtype. A newly created workload instance requires its own identity. `CREATE TRIGGER runtime_kind_guard BEFORE UPDATE OF runtime_kind ON dcmon.runtime FOR EACH ROW EXECUTE FUNCTION immutable_runtime_kind()`
- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.runtime FOR EACH ROW EXECUTE FUNCTION require_ci_kind('runtime')`

## scene_object

Optional presentation coordinates and asset references for a CI. This legacy 3D mapping is inventory metadata, not required by the current illustrative browser views.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (scene_object_id_seq)` | Stable internal record identifier; not reused. |
| `scene_key` | `text` | yes | none | Presentation scene key for network, site, hall or rack. |
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `asset_ref` | `text` | yes | none | Relative legacy 3D asset reference; not a bundled runtime or database dependency. |
| `x` | `numeric(12,3)` | yes | none | X coordinate in scene-specific presentation units. |
| `y` | `numeric(12,3)` | yes | none | Y coordinate in scene-specific presentation units. |
| `z` | `numeric(12,3)` | yes | none | Z coordinate in scene-specific presentation units. |
| `rotation_deg` | `numeric(7,3)` | yes | none | Rotation around the vertical axis in degrees. |
| `scale` | `numeric(10,4)` | yes | none | Positive presentation scale multiplier. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `scene_object_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `scene_object_pkey` | primary key | `PRIMARY KEY (id)` |
| `scene_object_scale_check` | check | `CHECK ((scale > (0)::numeric))` |
| `scene_object_scene_key_ci_id_key` | unique | `UNIQUE (scene_key, ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `scene_ci_idx` | Finds optional presentation coordinates and assets for a CI on scene_object. Definition: btree (ci_id). |
| `scene_object_pkey` | Enforces the stable primary-key identity on scene_object. Definition: btree (id). |
| `scene_object_scene_key_ci_id_key` | Prevents duplicate natural identities on scene_object. Definition: btree (scene_key, ci_id). |

## site

Data-center site at the top of the physical navigation hierarchy.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `city` | `text` | yes | none | Synthetic city/location label for demonstration. |
| `timezone` | `text` | yes | none | IANA timezone used when presenting local timestamps. |
| `latitude` | `numeric(9,6)` | no | none | Latitude in degrees; NULL with longitude when unavailable or withheld. |
| `longitude` | `numeric(9,6)` | no | none | Longitude in degrees; NULL with latitude when unavailable or withheld. |
| `design_it_kw` | `numeric(12,2)` | no | none | Design IT power capacity in kilowatts; not measured consumption. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `site_check` | check | `CHECK (((latitude IS NULL) = (longitude IS NULL)))` |
| `site_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `site_design_it_kw_check` | check | `CHECK ((design_it_kw > (0)::numeric))` |
| `site_latitude_check` | check | `CHECK (((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric)))` |
| `site_longitude_check` | check | `CHECK (((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric)))` |
| `site_pkey` | primary key | `PRIMARY KEY (ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `site_pkey` | Enforces the stable primary-key identity on site. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.site FOR EACH ROW EXECUTE FUNCTION require_ci_kind('site')`

## software_installation

Concrete installed software instance such as a machine OS, database instance or Java runtime.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `product_id` | `bigint` | yes | none | Software product referenced by this installation. |
| `version` | `text` | yes | none | Current inventory version; historical upgrades require an external change audit. |
| `instance_name` | `text` | yes | none | Concrete OS, service or database-instance name. |
| `listen_port` | `integer` | no | none | Service port from 1 to 65535 when applicable; NULL otherwise. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `software_installation_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `software_installation_listen_port_check` | check | `CHECK (((listen_port >= 1) AND (listen_port <= 65535)))` |
| `software_installation_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `software_installation_product_id_fkey` | foreign key | `FOREIGN KEY (product_id) REFERENCES software_product(id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `software_installation_pkey` | Enforces the stable primary-key identity on software_installation. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.software_installation FOR EACH ROW EXECUTE FUNCTION require_ci_kind('installation')`

## software_product

Software product catalog for operating systems, databases, platforms, middleware and agents; distinct from business systems.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (software_product_id_seq)` | Stable internal record identifier; not reused. |
| `code` | `text` | yes | none | Stable machine-readable catalog code. |
| `name` | `text` | yes | none | Human-readable display name; does not replace a stable identifier. |
| `category` | `text` | yes | none | Software class: os, dbms, platform, middleware or agent. |
| `vendor` | `text` | yes | none | Software vendor or maintaining community. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `software_product_category_check` | check | `CHECK ((category = ANY (ARRAY['os'::text, 'dbms'::text, 'platform'::text, 'middleware'::text, 'agent'::text])))` |
| `software_product_code_key` | unique | `UNIQUE (code)` |
| `software_product_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `software_product_code_key` | Prevents duplicate natural identities on software_product. Definition: btree (code). |
| `software_product_pkey` | Enforces the stable primary-key identity on software_product. Definition: btree (id). |

## source_system

Data-source integration registry containing configuration references and ownership, without passwords or access secrets.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (source_system_id_seq)` | Stable internal record identifier; not reused. |
| `code` | `text` | yes | none | Stable machine-readable catalog code. |
| `name` | `text` | yes | none | Human-readable display name; does not replace a stable identifier. |
| `method` | `text` | yes | none | Integration method such as REST, JSON-RPC, exporter, gateway or file. |
| `endpoint_ref` | `text` | no | none | Non-secret endpoint or connector configuration reference; not a credential store. |
| `owner_team` | `text` | yes | none | Team accountable for availability of the integration. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `source_system_code_key` | unique | `UNIQUE (code)` |
| `source_system_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `source_system_code_key` | Prevents duplicate natural identities on source_system. Definition: btree (code). |
| `source_system_pkey` | Enforces the stable primary-key identity on source_system. Definition: btree (id). |

## status_observation

Technical CI status history with an explicit freshness lifetime; separate from lifecycle and incident counts.

**Grain:** One row per PRIMARY KEY (ci_id, observed_at).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `observed_at` | `timestamp with time zone` | yes | none | Time the fact was observed in the source; used for as-of selection. |
| `state` | `text` | yes | none | Technical state used for status colors and labels; independent of lifecycle and incident state. |
| `reason` | `text` | yes | none | Source-provided explanation of the technical state. |
| `valid_for_sec` | `integer` | yes | none | Maximum accepted age of this status observation, in seconds. |
| `source_id` | `bigint` | yes | none | Authoritative source record in dcmon.source_system. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `status_observation_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `status_observation_pkey` | primary key | `PRIMARY KEY (ci_id, observed_at)` |
| `status_observation_source_id_fkey` | foreign key | `FOREIGN KEY (source_id) REFERENCES source_system(id)` |
| `status_observation_state_check` | check | `CHECK ((state = ANY (ARRAY['healthy'::text, 'warning'::text, 'critical'::text, 'unknown'::text, 'maintenance'::text])))` |
| `status_observation_valid_for_sec_check` | check | `CHECK ((valid_for_sec > 0))` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `status_latest_idx` | Selects the latest status observation at or before p_at per CI on status_observation. Definition: btree (ci_id, observed_at DESC). |
| `status_observation_pkey` | Enforces the stable primary-key identity on status_observation. Definition: btree (ci_id, observed_at). |

## storage_volume

Logical storage volume and its serving storage device; internal pool details remain in the storage source.

**Grain:** One row per PRIMARY KEY (ci_id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | yes | none | Stable reference to the configuration item in dcmon.ci. |
| `storage_device_id` | `bigint` | yes | none | Serving physical device; trigger requires the storage device class. |
| `capacity_gib` | `numeric(16,3)` | yes | none | Allocated logical volume capacity in GiB; not used space. |
| `protocol` | `text` | yes | none | Volume access protocol: FC, iSCSI, NFS or NVMe-oF. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `storage_volume_capacity_gib_check` | check | `CHECK ((capacity_gib > (0)::numeric))` |
| `storage_volume_ci_id_fkey` | foreign key | `FOREIGN KEY (ci_id) REFERENCES ci(ci_id)` |
| `storage_volume_pkey` | primary key | `PRIMARY KEY (ci_id)` |
| `storage_volume_protocol_check` | check | `CHECK ((protocol = ANY (ARRAY['FC'::text, 'iSCSI'::text, 'NFS'::text, 'NVMe-oF'::text])))` |
| `storage_volume_storage_device_id_fkey` | foreign key | `FOREIGN KEY (storage_device_id) REFERENCES device(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `storage_volume_pkey` | Enforces the stable primary-key identity on storage_volume. Definition: btree (ci_id). |

**Triggers**

- `subtype_kind`: On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public. `CREATE TRIGGER subtype_kind BEFORE INSERT OR UPDATE ON dcmon.storage_volume FOR EACH ROW EXECUTE FUNCTION require_ci_kind('volume')`
- `volume_storage_kind`: On storage_volume INSERT/UPDATE, requires storage_device_id to identify a device of class storage. Rejects absent or other-class devices with SQLSTATE 23514. A foreign key alone cannot express the device-class requirement. Uses caller search_path dcmon,public. `CREATE TRIGGER volume_storage_kind BEFORE INSERT OR UPDATE ON dcmon.storage_volume FOR EACH ROW EXECUTE FUNCTION check_storage_device()`

## system_environment

PROD, TEST or DEV environment of one business system; placement and ownership remain environment-specific.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (system_environment_id_seq)` | Stable internal record identifier; not reused. |
| `system_id` | `bigint` | yes | none | Business system owning this environment. |
| `environment` | `text` | yes | none | Operating environment: PROD, TEST or DEV. |
| `service_owner_team_id` | `bigint` | yes | none | Operations team responsible for this particular environment. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `system_environment_environment_check` | check | `CHECK ((environment = ANY (ARRAY['PROD'::text, 'TEST'::text, 'DEV'::text])))` |
| `system_environment_pkey` | primary key | `PRIMARY KEY (id)` |
| `system_environment_service_owner_team_id_fkey` | foreign key | `FOREIGN KEY (service_owner_team_id) REFERENCES team(id)` |
| `system_environment_system_id_environment_key` | unique | `UNIQUE (system_id, environment)` |
| `system_environment_system_id_fkey` | foreign key | `FOREIGN KEY (system_id) REFERENCES information_system(ci_id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `system_environment_pkey` | Enforces the stable primary-key identity on system_environment. Definition: btree (id). |
| `system_environment_system_id_environment_key` | Prevents duplicate natural identities on system_environment. Definition: btree (system_id, environment). |

## team

Synthetic service and operations teams; contains no personal contact details.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (team_id_seq)` | Stable internal record identifier; not reused. |
| `code` | `text` | yes | none | Stable machine-readable catalog code. |
| `name` | `text` | yes | none | Human-readable display name; does not replace a stable identifier. |
| `contact_ref` | `text` | no | none | Synthetic service group or on-call reference; no personal password or private contact. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `team_code_key` | unique | `UNIQUE (code)` |
| `team_pkey` | primary key | `PRIMARY KEY (id)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `team_code_key` | Prevents duplicate natural identities on team. Definition: btree (code). |
| `team_pkey` | Enforces the stable primary-key identity on team. Definition: btree (id). |

## volume_attachment

Effective-dated attachment of a logical volume to compute; shared volumes can serve multiple hosts.

**Grain:** One row per PRIMARY KEY (id).

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` | yes | `IDENTITY BY DEFAULT (volume_attachment_id_seq)` | Stable internal record identifier; not reused. |
| `volume_id` | `bigint` | yes | none | Logical storage volume referenced by the attachment. |
| `host_id` | `bigint` | yes | none | Compute host CI; endpoint type is validated. |
| `mount_ref` | `text` | yes | none | Datastore, mount point or drive-letter reference without credentials. |
| `valid_from` | `timestamp with time zone` | yes | none | Inclusive start of the relationship validity interval; business event time, not ingestion time. |
| `valid_to` | `timestamp with time zone` | no | none | Exclusive end of the relationship validity interval; NULL means open-ended. |

**Integrity rules**

| Constraint | Type | Exact rule |
|---|---|---|
| `volume_attachment_check` | check | `CHECK (((valid_to IS NULL) OR (valid_to > valid_from)))` |
| `volume_attachment_host_id_fkey` | foreign key | `FOREIGN KEY (host_id) REFERENCES ci(ci_id)` |
| `volume_attachment_pkey` | primary key | `PRIMARY KEY (id)` |
| `volume_attachment_volume_id_fkey` | foreign key | `FOREIGN KEY (volume_id) REFERENCES storage_volume(ci_id)` |
| `volume_attachment_volume_id_host_id_tstzrange_excl` | exclusion | `EXCLUDE USING gist (volume_id WITH =, host_id WITH =, tstzrange(valid_from, valid_to, '[)'::text) WITH &&)` |

**Indexes**

| Index | Purpose and definition |
|---|---|
| `volume_attachment_pkey` | Enforces the stable primary-key identity on volume_attachment. Definition: btree (id). |
| `volume_attachment_volume_id_host_id_tstzrange_excl` | Prevents overlapping effective-dated relationships on volume_attachment. Definition: gist (volume_id, host_id, tstzrange(valid_from, valid_to, '[)'::text)). |

**Triggers**

- `valid_volume_host`: Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public. `CREATE TRIGGER valid_volume_host BEFORE INSERT OR UPDATE ON dcmon.volume_attachment FOR EACH ROW EXECUTE FUNCTION check_compute_reference()`

## v_inventory_summary

Counts of currently active inventory grouped by CI kind; planned and retired lifecycle entries are excluded.

**Grain:** Defined by the view query below.

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `kind` | `text` | expression-derived | none | CI subtype included in the current active-inventory aggregation. |
| `objects` | `bigint` | expression-derived | none | Number of active inventory items of this subtype. |

```sql
SELECT kind,
    count(*) AS objects
   FROM dcmon.ci c
  WHERE (lifecycle = 'active'::text)
  GROUP BY kind;
```

## v_unmapped_compute

Active physical servers and runtimes without an application execution-path association at now(); excludes software installations and does not invent an owner.

**Grain:** Defined by the view query below.

| Column | PostgreSQL type | Required | Default | Meaning |
|---|---|---|---|---|
| `ci_id` | `bigint` | expression-derived | none | Physical server or runtime CI lacking an execution-path association at now(). |
| `ci_key` | `text` | expression-derived | none | Readable key of the unmapped server or runtime. |
| `kind` | `text` | expression-derived | none | CI kind of the unmapped item: device for a physical server, or runtime. |

```sql
SELECT ci_id,
    ci_key,
    kind
   FROM dcmon.ci c
  WHERE ((kind = ANY (ARRAY['device'::text, 'runtime'::text])) AND (lifecycle = 'active'::text) AND dcmon.is_compute(ci_id) AND (NOT (EXISTS ( SELECT 1
           FROM dcmon.execution_paths(now()) e(system_key, environment, component_key, target_key, server_key, server_id, node_ids)
          WHERE (c.ci_id = ANY (e.node_ids))))));
```

## Function contracts

`p_at` is `timestamp with time zone`; all functions accepting it default to `now()`. Pass the frozen demo timestamp explicitly for reproducible screenshots and validation. Optional text filters accept SQL NULL as unrestricted; empty text is a literal filter. SQL table-returning functions fix `search_path` to `dcmon,public`; trigger helpers and `is_compute` retain the deployed caller-path behavior, so write sessions must use `SET search_path=dcmon,public`. Functions are not security-definer APIs.

### check_compute_reference

`check_compute_reference()`

Returns `trigger`.

Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public.

### check_dependency

`check_dependency()`

Returns `trigger`.

Checks directed consumer/provider types on dependency INSERT/UPDATE. Application: component to component/installation; power: device/rack to PDU/UPS/generator; cooling: room/rack/device to CRAC/chiller; network: device/runtime to switch; storage: device/runtime to storage. Rejects unknown/missing endpoint types with SQLSTATE 23514; does not infer availability, redundancy or traversal in the reverse direction. Uses caller search_path dcmon,public.

### check_hosting

`check_hosting()`

Returns `trigger`.

Checks hosting INSERT/UPDATE hierarchy: VM to physical server, pod to VM/server, container to pod. Rejects invalid or missing endpoint types with SQLSTATE 23514. Effective-dated overlap constraints separately prevent simultaneous hosts. Uses caller search_path dcmon,public.

### check_metric_value

`check_metric_value()`

Returns `trigger`.

On metric_sample INSERT/UPDATE, validates only quality=ok against its definition valid_min/valid_max. NULL bounds leave that side unrestricted. Table checks independently require finite values for ok and NULL for missing/error. Warning and critical thresholds are presentation guidance, never validity limits. Raises SQLSTATE 23514 for a range breach. Uses caller search_path dcmon,public.

### check_rack_space

`check_rack_space()`

Returns `trigger`.

On device_placement INSERT/UPDATE with a U interval, acquires a shared lock on the target rack and checks inclusive top U (u_start+u_height-1) against height_u. NULL U denotes floor/0U placement and bypasses the capacity test; table checks and exclusions enforce other shape/overlap rules. Raises SQLSTATE 23514 on overflow. Uses caller search_path dcmon,public.

### check_storage_device

`check_storage_device()`

Returns `trigger`.

On storage_volume INSERT/UPDATE, requires storage_device_id to identify a device of class storage. Rejects absent or other-class devices with SQLSTATE 23514. A foreign key alone cannot express the device-class requirement. Uses caller search_path dcmon,public.

### compute_paths

`compute_paths(p_at timestamp with time zone)`

Returns `TABLE(origin_id bigint, server_id bigint, node_ids bigint[])`.

Returns origin_id, terminal physical server_id and ordered node_ids for server/runtime/installation origins visible at p_at. Follows hosting and installation_placement intervals [valid_from,valid_to), excludes planned origins, respects origin first_seen_at/retired_at, and includes a physical server own one-node path. Rejects revisiting a path node and caps node count at 64. Multiple legitimate paths remain separate; downstream selection deduplicates hosts. Does not reconstruct historical software versions.

### execution_paths

`execution_paths(p_at timestamp with time zone)`

Returns `TABLE(system_key text, environment text, component_key text, target_key text, server_key text, server_id bigint, node_ids bigint[])`.

Returns application-to-server execution paths at p_at: component root, first target, ordered node_ids and system/environment keys. Traverses effective deployment, directed application dependencies, installation placement and guest-to-host hosting using half-open intervals. The visited-node guard prevents cycles and the 64-node cap bounds recursion. Emits each path ending at a physical server; does not deduplicate paths or apply CI lifecycle visibility independently of relationship intervals.

### immutable_ci_kind

`immutable_ci_kind()`

Returns `trigger`.

Before ci kind updates, rejects a different subtype with SQLSTATE 23514 so existing subtype, topology and telemetry references retain their interpretation. Other inventory attributes may change. Retiring/replacing a CI preserves identity history instead of retyping it.

### immutable_device_class

`immutable_device_class()`

Returns `trigger`.

Before device_class updates, rejects a different class with SQLSTATE 23514 because dependency and hosting rules rely on that class. Replace or retire an incorrectly classified device through an explicit migration rather than silently reinterpreting relationships.

### immutable_runtime_kind

`immutable_runtime_kind()`

Returns `trigger`.

Before runtime_kind updates, rejects changing VM/pod/container type with SQLSTATE 23514 because hosting rules depend on the subtype. A newly created workload instance requires its own identity.

### is_compute

`is_compute(p_id bigint)`

Returns `boolean`.

Returns true if p_id is a physical device of class server or a runtime; false for missing IDs and other physical equipment. It is a type predicate, not a lifecycle, health, placement or capacity test. Uses caller search_path dcmon,public.

### metric_snapshot

`metric_snapshot(p_at timestamp with time zone)`

Returns `TABLE(series_id bigint, ci_id bigint, object_key text, metric_code text, unit text, labels jsonb, observed_at timestamp with time zone, raw_value numeric, display_value numeric, freshness text, age_seconds numeric)`.

For every metric_series, selects the latest sample with observed_at<=p_at, independent of ingestion time. Returns raw_value for diagnosis and display_value only when quality=ok and observation age is <=stale_after_sec. No point yields missing; age strictly above the budget yields stale before checking point quality; otherwise quality missing/error propagates, or ok becomes fresh. Age is in seconds and no value or timestamp is fabricated. Does not filter series by CI lifecycle or first_seen_at; labels/definitions are current inventory attributes.

### prevent_rack_shrink

`prevent_rack_shrink()`

Returns `trigger`.

Before rack height updates, rejects any height below the inclusive top U of an existing placement, including historical/closed intervals. Preserves historical physical validity; it is intentionally stricter than checking only current placements. Raises SQLSTATE 23514. Uses caller search_path dcmon,public.

### require_ci_kind

`require_ci_kind()`

Returns `trigger`.

On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.

### status_snapshot

`status_snapshot(p_at timestamp with time zone)`

Returns `TABLE(ci_id bigint, object_key text, state text, reason text, observed_at timestamp with time zone)`.

For each CI with first_seen_at<=p_at and no retirement at/before p_at, selects its latest status_observation with observed_at<=p_at. No observation or age strictly greater than valid_for_sec becomes unknown, with an English reason; equality remains fresh. Preserves the source timestamp for stale diagnostics. Does not exclude planned lifecycle CIs or infer status from incidents/metrics.

### system_hosts

`system_hosts(p_system_key text, p_environment text, p_software_code text, p_at timestamp with time zone)`

Returns `TABLE(server_id bigint, server_key text, server_name text, rack_key text, room_key text, site_key text)`.

Returns distinct physical servers selected by optional system key, environment and software product code at p_at; NULL means no restriction. Uses execution_paths and, only with both system/environment NULL, compute_paths to retain unmapped hosts. Software must be on the selected path or installed on a node of that path, avoiding sibling VM leakage. Current effective device placement supplies optional rack/room/site keys; unplaced hosts remain with NULL location. Does not test historical software version.

### system_incidents

`system_incidents(p_system_key text, p_environment text, p_at timestamp with time zone)`

Returns `TABLE(incident_key text, title text, severity text, state text, detected_at timestamp with time zone, matched_objects bigint, interpretation text)`.

Returns one row per incident in system_scope at p_at with detection and incident-CI link times not after p_at. Latest workflow event determines state; resolved/closed incidents are excluded. matched_objects counts distinct in-scope linked CIs and all impact_role values may match, so potential risk is not a confirmed application outage. Multiple links do not multiply incidents. Interpretation remains explicitly advisory.

### system_scope

`system_scope(p_system_key text, p_environment text, p_at timestamp with time zone)`

Returns `TABLE(ci_id bigint)`.

Builds CI scope for optional system/environment at p_at from execution-path nodes, matching components and systems, effective physical locations, software installed on core nodes, attached volumes and containing clusters. With both filters NULL it also seeds historically visible CIs. Recurses only consumer-to-provider through non-application infrastructure dependencies; UNION deduplicates nodes and terminates cycles. Never traverses reverse hosting to sibling VMs. Location/attachment expansion uses the core set, not every later infrastructure node; the function does not infer transitive impact severity.

### system_software

`system_software(p_system_key text, p_environment text, p_at timestamp with time zone)`

Returns `TABLE(system_key text, environment text, server_key text, installation_key text, product_code text, category text, version text, association text)`.

Returns distinct software installations placed on nodes of selected execution paths at p_at with optional system/environment filters (NULL is unrestricted). association=explicit_dependency means the installation itself is a path node; otherwise installed_on_execution_path means presence on a path host, not proof of use. Only placement is effective-dated: version, product and instance inventory remain current attributes. Unmapped compute is not added by this function.

## Sequences

Only the following columns use source sequences; other IDs are assigned explicitly by ingestion/demo creation. The fixture sets each sequence to the maximum restored owned ID with `is_called=true`. Empty tables use value 1 with `is_called=false`. The next generated ID is therefore above restored data without reading private source sequence state.

Identity ownership is resolved through PostgreSQL `pg_depend` with dependency type `i`, not a `nextval` column default. All 22 sequences are `GENERATED BY DEFAULT AS IDENTITY`, start at 1, increment by 1, cache 1, and do not cycle. The owner-mode verifier checks this structure and reads `last_value`/`is_called` without consuming IDs. Reader roles without SELECT on sequences explicitly skip state reads unless `--require-sequences` is requested.

| Sequence | Owned column | Identity dependency |
|---|---|---|
| `backup_run_id_seq` | `backup_run.id` | `i`: BY DEFAULT |
| `ci_ci_id_seq` | `ci.ci_id` | `i`: BY DEFAULT |
| `cluster_member_id_seq` | `cluster_member.id` | `i`: BY DEFAULT |
| `dependency_id_seq` | `dependency.id` | `i`: BY DEFAULT |
| `deployment_id_seq` | `deployment.id` | `i`: BY DEFAULT |
| `device_placement_id_seq` | `device_placement.id` | `i`: BY DEFAULT |
| `hosting_id_seq` | `hosting.id` | `i`: BY DEFAULT |
| `incident_event_id_seq` | `incident_event.id` | `i`: BY DEFAULT |
| `incident_id_seq` | `incident.id` | `i`: BY DEFAULT |
| `ingestion_run_id_seq` | `ingestion_run.id` | `i`: BY DEFAULT |
| `installation_placement_id_seq` | `installation_placement.id` | `i`: BY DEFAULT |
| `maintenance_window_id_seq` | `maintenance_window.id` | `i`: BY DEFAULT |
| `metric_definition_id_seq` | `metric_definition.id` | `i`: BY DEFAULT |
| `metric_series_series_id_seq` | `metric_series.series_id` | `i`: BY DEFAULT |
| `network_link_id_seq` | `network_link.id` | `i`: BY DEFAULT |
| `network_port_id_seq` | `network_port.id` | `i`: BY DEFAULT |
| `scene_object_id_seq` | `scene_object.id` | `i`: BY DEFAULT |
| `software_product_id_seq` | `software_product.id` | `i`: BY DEFAULT |
| `source_system_id_seq` | `source_system.id` | `i`: BY DEFAULT |
| `system_environment_id_seq` | `system_environment.id` | `i`: BY DEFAULT |
| `team_id_seq` | `team.id` | `i`: BY DEFAULT |
| `volume_attachment_id_seq` | `volume_attachment.id` | `i`: BY DEFAULT |

## Metric definitions

These are canonical storage units and illustrative upper thresholds, not universal operational limits. NULL threshold means unconfigured, not zero. `gauge` values are instantaneous measurements or already calculated rates. `counter` values accumulate and require reset-aware differences over elapsed time before reporting throughput. Percent is stored on a 0–100 scale. `boolean` link state is numeric 0/1. `C` and `celsius` both express degrees Celsius but remain distinct original unit strings. GiB and MiB use binary powers; Mbps uses megabits per second.

| Code | Label | Unit | Type | Valid range | Warning above | Critical above | Series |
|---|---|---|---|---:|---:|---:|
| `cpu_pct` | CPU utilization | `percent` | gauge | 0 … 100 | 80 | 95 | 1,164 |
| `memory_pct` | Memory utilization | `percent` | gauge | 0 … 100 | 85 | 95 | 1,164 |
| `storage_pct` | Storage utilization | `percent` | gauge | 0 … 100 | 80 | 95 | 972 |
| `power_w` | Active power | `W` | gauge | 0 … NULL | NULL | NULL | 972 |
| `inlet_c` | Inlet temperature | `celsius` | gauge | -40 … 100 | 28 | 32 | 990 |
| `humidity_pct` | Humidity | `percent` | gauge | 0 … 100 | 65 | 75 | 6 |
| `fan_rpm` | Fan speed | `rpm` | gauge | 0 … 50000 | NULL | NULL | 1 |
| `network_rx_bytes` | Received bytes | `bytes` | counter | 0 … NULL | NULL | NULL | 1 |
| `disk_capacity_gib` | Disk capacity | `GiB` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_used_gib` | Disk space used | `GiB` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_used_pct` | Disk utilization | `percent` | gauge | 0 … 100 | 80 | 95 | 1,944 |
| `disk_c` | Disk temperature | `C` | gauge | -20 … 100 | 45 | 55 | 1,944 |
| `disk_read_iops` | Read IOPS | `IOPS` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_write_iops` | Write IOPS | `IOPS` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_read_mib_s` | Read throughput | `MiB/s` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_write_mib_s` | Write throughput | `MiB/s` | gauge | 0 … NULL | NULL | NULL | 1,944 |
| `disk_latency_ms` | Disk latency | `ms` | gauge | 0 … NULL | 20 | 40 | 1,944 |
| `disk_busy_pct` | I/O utilization | `percent` | gauge | 0 … 100 | 80 | 95 | 1,944 |
| `disk_smart_errors` | SMART errors | `count` | gauge | 0 … NULL | 0 | 5 | 1,944 |
| `net_rx_mbps` | Receive throughput | `Mbps` | gauge | 0 … NULL | NULL | NULL | 2,304 |
| `net_tx_mbps` | Transmit throughput | `Mbps` | gauge | 0 … NULL | NULL | NULL | 2,304 |
| `net_util_pct` | Port utilization | `percent` | gauge | 0 … 100 | 80 | 95 | 2,304 |
| `net_errors_s` | Errors per second | `errors/s` | gauge | 0 … NULL | 0 | 10 | 2,304 |
| `net_discards_s` | Discards per second | `packets/s` | gauge | 0 … NULL | 0 | 20 | 2,304 |
| `net_link_up` | Port link state | `boolean` | gauge | 0 … 1 | NULL | NULL | 2,304 |
| `switch_c` | Switch temperature | `C` | gauge | -20 … 100 | 65 | 80 | 96 |
