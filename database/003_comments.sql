-- English metadata only: this script changes no data, definitions, grants or owners.
-- Safe to reapply after reviewing the public dictionary. Qualifies every target.
COMMENT ON SCHEMA dcmon IS 'Synthetic data-center monitoring inventory, effective-dated topology, telemetry and incident model. All demo thresholds and recovery targets are illustrative.';

-- backup_run
COMMENT ON TABLE dcmon.backup_run IS 'Synthetic backup job outcomes for a system environment. Success alone does not prove RPO compliance or recoverability.';
COMMENT ON COLUMN dcmon.backup_run.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.backup_run.environment_id IS 'System environment owning or protected by this record.';
COMMENT ON COLUMN dcmon.backup_run.job_key IS 'Stable job identity supplied by the backup system.';
COMMENT ON COLUMN dcmon.backup_run.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.backup_run.started_at IS 'Start time of the operation.';
COMMENT ON COLUMN dcmon.backup_run.finished_at IS 'Operation completion time; NULL while running.';
COMMENT ON COLUMN dcmon.backup_run.recovery_point_at IS 'Timestamp of the data represented by the backup; basis for recovery-point age.';
COMMENT ON COLUMN dcmon.backup_run.status IS 'Backup job result: running, success or failed. Partial is an ingestion state, not a backup result.';
COMMENT ON COLUMN dcmon.backup_run.size_gib IS 'Size of the created backup in GiB.';
COMMENT ON COLUMN dcmon.backup_run.restore_test_at IS 'Last restore test of this exact copy; NULL means no recorded verification.';

-- ci
COMMENT ON TABLE dcmon.ci IS 'Stable configuration-item identity shared by inventory, topology, telemetry and incidents. Type-specific attributes live in subtype tables.';
COMMENT ON COLUMN dcmon.ci.ci_id IS 'Stable internal CI identifier, never reused across object lifecycles.';
COMMENT ON COLUMN dcmon.ci.ci_key IS 'Stable readable object key; changing a hostname does not create a new CI.';
COMMENT ON COLUMN dcmon.ci.kind IS 'Configuration-item subtype discriminator.';
COMMENT ON COLUMN dcmon.ci.name IS 'Human-readable display name; does not replace a stable identifier.';
COMMENT ON COLUMN dcmon.ci.owner_team_id IS 'Team responsible for the object or incident.';
COMMENT ON COLUMN dcmon.ci.lifecycle IS 'Inventory lifecycle, separate from technical health and incident workflow state.';
COMMENT ON COLUMN dcmon.ci.retired_at IS 'Retirement time; NULL before retirement. Preserves historical object visibility.';
COMMENT ON COLUMN dcmon.ci.first_seen_at IS 'First discovery time in an inventory source.';
COMMENT ON COLUMN dcmon.ci.last_seen_at IS 'Last source confirmation of existence or identity; not telemetry observation time.';

-- cluster
COMMENT ON TABLE dcmon.cluster IS 'Logical virtualization, Kubernetes, database or storage cluster; membership may span sites.';
COMMENT ON COLUMN dcmon.cluster.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.cluster.cluster_type IS 'Cluster purpose or orchestration type.';
COMMENT ON COLUMN dcmon.cluster.platform IS 'Technology or platform implementing the cluster.';

-- cluster_member
COMMENT ON TABLE dcmon.cluster_member IS 'Effective-dated membership of a configuration item in a logical cluster.';
COMMENT ON COLUMN dcmon.cluster_member.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.cluster_member.cluster_id IS 'Logical cluster receiving the member.';
COMMENT ON COLUMN dcmon.cluster_member.member_id IS 'Cluster member CI: a device, runtime or software installation.';
COMMENT ON COLUMN dcmon.cluster_member.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.cluster_member.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- component
COMMENT ON TABLE dcmon.component IS 'Logical application component within one system environment; multiple deployments can implement the same component.';
COMMENT ON COLUMN dcmon.component.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.component.environment_id IS 'System environment owning or protected by this record.';
COMMENT ON COLUMN dcmon.component.component_role IS 'Architectural role within the application, such as web or database.';
COMMENT ON COLUMN dcmon.component.description IS 'Component purpose and responsibility boundary.';

-- dependency
COMMENT ON TABLE dcmon.dependency IS 'Directed consumer-to-provider dependency, including shared applications, power, cooling, network and storage. A dependency alone does not prove application failure.';
COMMENT ON COLUMN dcmon.dependency.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.dependency.dependent_id IS 'Consumer CI that relies on the provider; traversal follows this direction.';
COMMENT ON COLUMN dcmon.dependency.provider_id IS 'Provider CI supplying an application or infrastructure resource.';
COMMENT ON COLUMN dcmon.dependency.dependency_type IS 'Dependency category controlling allowed endpoint types and graph traversal.';
COMMENT ON COLUMN dcmon.dependency.redundancy_group IS 'Optional redundancy label such as A/B; does not itself calculate resilience.';
COMMENT ON COLUMN dcmon.dependency.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.dependency.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.dependency.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- deployment
COMMENT ON TABLE dcmon.deployment IS 'Effective-dated deployment of a component onto compute or a software installation; multiple components may share a host.';
COMMENT ON COLUMN dcmon.deployment.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.deployment.component_id IS 'Application component being deployed.';
COMMENT ON COLUMN dcmon.deployment.target_id IS 'Compute or software-installation CI receiving the component; validated by trigger.';
COMMENT ON COLUMN dcmon.deployment.role IS 'Deployment role such as primary or standby; standby does not imply failure.';
COMMENT ON COLUMN dcmon.deployment.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.deployment.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- device
COMMENT ON TABLE dcmon.device IS 'Physical equipment inventory: servers, storage, switches, power, cooling and safety devices.';
COMMENT ON COLUMN dcmon.device.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.device.device_class IS 'Physical device class; immutable after creation to protect typed relationships.';
COMMENT ON COLUMN dcmon.device.manufacturer IS 'Equipment manufacturer; synthetic demo attribution.';
COMMENT ON COLUMN dcmon.device.model IS 'Equipment model or synthetic chassis description.';
COMMENT ON COLUMN dcmon.device.serial_number IS 'Device serial number; NULL when the source provides none.';
COMMENT ON COLUMN dcmon.device.cpu_cores IS 'Installed physical CPU cores on a server; distinct from allocated vCPU.';
COMMENT ON COLUMN dcmon.device.memory_gib IS 'Installed server memory in GiB.';

-- device_placement
COMMENT ON TABLE dcmon.device_placement IS 'Effective-dated physical placement. Rack equipment occupies a U interval; floor equipment has a room without a rack.';
COMMENT ON COLUMN dcmon.device_placement.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.device_placement.device_id IS 'Physical device owning the port or placement.';
COMMENT ON COLUMN dcmon.device_placement.room_id IS 'Physical room containing this object.';
COMMENT ON COLUMN dcmon.device_placement.rack_id IS 'Rack containing the device; NULL for floor equipment.';
COMMENT ON COLUMN dcmon.device_placement.u_start IS 'First occupied rack unit, counted from 1; NULL for floor or 0U equipment.';
COMMENT ON COLUMN dcmon.device_placement.u_height IS 'Number of occupied rack units; NULL together with u_start for 0U equipment.';
COMMENT ON COLUMN dcmon.device_placement.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.device_placement.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- external_identity
COMMENT ON TABLE dcmon.external_identity IS 'Mapping of stable CI identities to source-specific identifiers such as NetBox IDs, vCenter IDs and Kubernetes UIDs.';
COMMENT ON COLUMN dcmon.external_identity.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.external_identity.external_id IS 'Unique identity within a source; Kubernetes uses UID rather than name alone.';
COMMENT ON COLUMN dcmon.external_identity.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.external_identity.last_seen_at IS 'Last source confirmation of existence or identity; not telemetry observation time.';

-- hosting
COMMENT ON TABLE dcmon.hosting IS 'Effective-dated VM, pod and container hosting. Endpoint type rules prevent invalid hosting cycles.';
COMMENT ON COLUMN dcmon.hosting.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.hosting.guest_id IS 'Guest runtime CI: VM, pod or container.';
COMMENT ON COLUMN dcmon.hosting.host_id IS 'Compute host CI; endpoint type is validated.';
COMMENT ON COLUMN dcmon.hosting.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.hosting.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- incident
COMMENT ON TABLE dcmon.incident IS 'Stable incident identity and descriptive attributes. Current and historical workflow state come from incident_event.';
COMMENT ON COLUMN dcmon.incident.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.incident.incident_key IS 'Stable human-readable incident key.';
COMMENT ON COLUMN dcmon.incident.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.incident.external_id IS 'Incident identity within its source system.';
COMMENT ON COLUMN dcmon.incident.title IS 'Short incident description.';
COMMENT ON COLUMN dcmon.incident.severity IS 'Incident impact severity, separate from business-system criticality.';
COMMENT ON COLUMN dcmon.incident.detected_at IS 'First detection timestamp.';
COMMENT ON COLUMN dcmon.incident.owner_team_id IS 'Team responsible for the object or incident.';
COMMENT ON COLUMN dcmon.incident.response_due_at IS 'Response deadline under the agreed service rule.';

-- incident_ci
COMMENT ON TABLE dcmon.incident_ci IS 'Explicit incident-to-CI links distinguishing cause, confirmed impact and potential risk.';
COMMENT ON COLUMN dcmon.incident_ci.incident_id IS 'Incident record referenced by this link or event.';
COMMENT ON COLUMN dcmon.incident_ci.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.incident_ci.impact_role IS 'cause, affected or at_risk; potential risk does not assert a confirmed outage.';
COMMENT ON COLUMN dcmon.incident_ci.linked_at IS 'Time the object association was confirmed; respected by historical scope queries.';

-- incident_event
COMMENT ON TABLE dcmon.incident_event IS 'Incident workflow event history, used to reconstruct the state at a requested time.';
COMMENT ON COLUMN dcmon.incident_event.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.incident_event.incident_id IS 'Incident record referenced by this link or event.';
COMMENT ON COLUMN dcmon.incident_event.occurred_at IS 'Time the incident workflow transition occurred.';
COMMENT ON COLUMN dcmon.incident_event.state IS 'Workflow state after the event: open, acknowledged, in_progress, resolved or closed.';
COMMENT ON COLUMN dcmon.incident_event.note IS 'Synthetic action or diagnostic note without personal information.';

-- information_system
COMMENT ON TABLE dcmon.information_system IS 'Business-system catalog and recovery requirements; requirements are separate from measured availability.';
COMMENT ON COLUMN dcmon.information_system.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.information_system.description IS 'Purpose of the business application.';
COMMENT ON COLUMN dcmon.information_system.criticality IS 'Business criticality classification; independent of current faults.';
COMMENT ON COLUMN dcmon.information_system.target_rto_min IS 'Required recovery time in minutes; a target rather than observed recovery duration.';
COMMENT ON COLUMN dcmon.information_system.target_rpo_min IS 'Required maximum data-loss time in minutes; agreed with the service owner.';

-- ingestion_run
COMMENT ON TABLE dcmon.ingestion_run IS 'Synthetic ingestion audit trail: processing state, cursor watermark and accepted/rejected row counts.';
COMMENT ON COLUMN dcmon.ingestion_run.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.ingestion_run.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.ingestion_run.started_at IS 'Start time of the operation.';
COMMENT ON COLUMN dcmon.ingestion_run.finished_at IS 'Operation completion time; NULL while running.';
COMMENT ON COLUMN dcmon.ingestion_run.state IS 'Ingestion state: running, success, partial or failed.';
COMMENT ON COLUMN dcmon.ingestion_run.cursor_value IS 'Watermark or API cursor after a processed batch; never an access token.';
COMMENT ON COLUMN dcmon.ingestion_run.accepted_rows IS 'Number of rows accepted by the ingestion run.';
COMMENT ON COLUMN dcmon.ingestion_run.rejected_rows IS 'Number of rows rejected by validation or processing.';
COMMENT ON COLUMN dcmon.ingestion_run.error_summary IS 'Short sanitized processing diagnostic; NULL if no error is recorded.';

-- installation_placement
COMMENT ON TABLE dcmon.installation_placement IS 'Effective-dated placement of a software installation on a physical server, VM or container.';
COMMENT ON COLUMN dcmon.installation_placement.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.installation_placement.installation_id IS 'Concrete software installation referenced by the placement.';
COMMENT ON COLUMN dcmon.installation_placement.host_id IS 'Compute host CI; endpoint type is validated.';
COMMENT ON COLUMN dcmon.installation_placement.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.installation_placement.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- maintenance_window
COMMENT ON TABLE dcmon.maintenance_window IS 'Approved planned maintenance for a CI; displayed separately from unplanned technical faults.';
COMMENT ON COLUMN dcmon.maintenance_window.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.maintenance_window.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.maintenance_window.starts_at IS 'Inclusive start of the agreed maintenance window.';
COMMENT ON COLUMN dcmon.maintenance_window.ends_at IS 'End of the agreed maintenance window; strictly after starts_at.';
COMMENT ON COLUMN dcmon.maintenance_window.reason IS 'Description of planned maintenance work.';
COMMENT ON COLUMN dcmon.maintenance_window.change_ref IS 'Approved change reference from the service-management process.';

-- metric_definition
COMMENT ON TABLE dcmon.metric_definition IS 'Canonical metric names, units, value domains and illustrative demo thresholds.';
COMMENT ON COLUMN dcmon.metric_definition.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.metric_definition.code IS 'Stable machine-readable catalog code.';
COMMENT ON COLUMN dcmon.metric_definition.name IS 'Human-readable metric label; values use the canonical unit column.';
COMMENT ON COLUMN dcmon.metric_definition.unit IS 'Canonical unit after normalization; interpreted together with metric code.';
COMMENT ON COLUMN dcmon.metric_definition.metric_type IS 'gauge is an instantaneous reading; counter is cumulative and requires rate conversion for throughput.';
COMMENT ON COLUMN dcmon.metric_definition.valid_min IS 'Lower valid value boundary; NULL leaves the lower side unrestricted.';
COMMENT ON COLUMN dcmon.metric_definition.valid_max IS 'Upper valid value boundary; NULL leaves the upper side unrestricted.';
COMMENT ON COLUMN dcmon.metric_definition.warning_above IS 'Illustrative demo upper warning threshold; NULL means no such threshold.';
COMMENT ON COLUMN dcmon.metric_definition.critical_above IS 'Illustrative demo upper critical threshold; NULL means no such threshold.';

-- metric_sample
COMMENT ON TABLE dcmon.metric_sample IS 'Numeric telemetry facts with distinct observation and ingestion times. Missing/error samples have NULL values, never fabricated zeros.';
COMMENT ON COLUMN dcmon.metric_sample.series_id IS 'Stable metric-series identity referencing dcmon.metric_series.';
COMMENT ON COLUMN dcmon.metric_sample.observed_at IS 'Time the fact was observed in the source; used for as-of selection.';
COMMENT ON COLUMN dcmon.metric_sample.ingested_at IS 'Time the observation reached the warehouse; separate from observed_at.';
COMMENT ON COLUMN dcmon.metric_sample.value IS 'Numeric value in metric_definition.unit; NULL for missing/error quality, never a substituted zero.';
COMMENT ON COLUMN dcmon.metric_sample.quality IS 'Point quality: ok requires a finite value; missing and error require NULL.';

-- metric_series
COMMENT ON TABLE dcmon.metric_series IS 'One CI, metric and JSON label set measured by a selected authoritative source; collection and freshness budgets are explicit.';
COMMENT ON COLUMN dcmon.metric_series.series_id IS 'Stable metric-series identity referencing dcmon.metric_series.';
COMMENT ON COLUMN dcmon.metric_series.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.metric_series.metric_id IS 'Definition providing metric code, unit, value range and thresholds.';
COMMENT ON COLUMN dcmon.metric_series.source_id IS 'Authoritative source record in dcmon.source_system.';
COMMENT ON COLUMN dcmon.metric_series.labels IS 'Low-cardinality JSON dimensions such as disk, port, sensor or power feed; not request IDs.';
COMMENT ON COLUMN dcmon.metric_series.expected_interval_sec IS 'Expected measurement collection interval in seconds; positive.';
COMMENT ON COLUMN dcmon.metric_series.stale_after_sec IS 'Maximum accepted observation age in seconds; at least the expected interval.';

-- network_link
COMMENT ON TABLE dcmon.network_link IS 'Effective-dated physical connection between two ports. Exclusion constraints prevent a port from having concurrent cables.';
COMMENT ON COLUMN dcmon.network_link.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.network_link.port_a_id IS 'Lower numeric endpoint port ID; canonical ordering avoids mirrored links.';
COMMENT ON COLUMN dcmon.network_link.port_b_id IS 'Higher numeric endpoint port ID; canonical ordering avoids mirrored links.';
COMMENT ON COLUMN dcmon.network_link.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.network_link.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- network_port
COMMENT ON TABLE dcmon.network_port IS 'Physical network interface belonging to a device; nominal speed is not measured traffic.';
COMMENT ON COLUMN dcmon.network_port.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.network_port.device_id IS 'Physical device owning the port or placement.';
COMMENT ON COLUMN dcmon.network_port.name IS 'Port name unique within its physical device.';
COMMENT ON COLUMN dcmon.network_port.speed_mbps IS 'Nominal interface speed in megabits per second; positive and distinct from measured traffic.';
COMMENT ON COLUMN dcmon.network_port.mac_address IS 'Hardware MAC address when applicable; NULL when unknown or inapplicable.';

-- rack
COMMENT ON TABLE dcmon.rack IS 'Rack location, U capacity, power budget and floor-plan coordinates within a room.';
COMMENT ON COLUMN dcmon.rack.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.rack.room_id IS 'Physical room containing this object.';
COMMENT ON COLUMN dcmon.rack.height_u IS 'Rack equipment capacity in rack units (U).';
COMMENT ON COLUMN dcmon.rack.power_limit_kw IS 'Allowed aggregate rack power in kilowatts; a capacity limit rather than a measurement.';
COMMENT ON COLUMN dcmon.rack.x_m IS 'Floor-plan X coordinate in meters.';
COMMENT ON COLUMN dcmon.rack.y_m IS 'Floor-plan Y coordinate in meters.';

-- room
COMMENT ON TABLE dcmon.room IS 'Data hall or technical room belonging to a data-center site.';
COMMENT ON COLUMN dcmon.room.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.room.site_id IS 'Data-center site containing the room.';
COMMENT ON COLUMN dcmon.room.floor_no IS 'Building floor number.';
COMMENT ON COLUMN dcmon.room.area_m2 IS 'Room floor area in square meters.';
COMMENT ON COLUMN dcmon.room.room_type IS 'Room purpose: data_hall, power, cooling or other.';

-- runtime
COMMENT ON TABLE dcmon.runtime IS 'VM, pod or container inventory. A recreated pod/container receives a new CI; a reused name does not establish identity.';
COMMENT ON COLUMN dcmon.runtime.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.runtime.runtime_kind IS 'VM, pod or container type; immutable after creation.';
COMMENT ON COLUMN dcmon.runtime.namespace IS 'Orchestrator namespace; NULL for virtual machines.';
COMMENT ON COLUMN dcmon.runtime.workload_name IS 'Logical deployment, StatefulSet or VM-group name; not object identity.';
COMMENT ON COLUMN dcmon.runtime.image_ref IS 'Container image/digest or VM template reference, without access credentials.';
COMMENT ON COLUMN dcmon.runtime.vcpu_allocated IS 'Allocated or requested vCPU; not actual CPU utilization.';
COMMENT ON COLUMN dcmon.runtime.memory_gib_allocated IS 'Allocated or requested RAM in GiB; not measured memory utilization.';

-- scene_object
COMMENT ON TABLE dcmon.scene_object IS 'Optional presentation coordinates and asset references for a CI. This legacy 3D mapping is inventory metadata, not required by the current illustrative browser views.';
COMMENT ON COLUMN dcmon.scene_object.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.scene_object.scene_key IS 'Presentation scene key for network, site, hall or rack.';
COMMENT ON COLUMN dcmon.scene_object.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.scene_object.asset_ref IS 'Relative legacy 3D asset reference; not a bundled runtime or database dependency.';
COMMENT ON COLUMN dcmon.scene_object.x IS 'X coordinate in scene-specific presentation units.';
COMMENT ON COLUMN dcmon.scene_object.y IS 'Y coordinate in scene-specific presentation units.';
COMMENT ON COLUMN dcmon.scene_object.z IS 'Z coordinate in scene-specific presentation units.';
COMMENT ON COLUMN dcmon.scene_object.rotation_deg IS 'Rotation around the vertical axis in degrees.';
COMMENT ON COLUMN dcmon.scene_object.scale IS 'Positive presentation scale multiplier.';

-- site
COMMENT ON TABLE dcmon.site IS 'Data-center site at the top of the physical navigation hierarchy.';
COMMENT ON COLUMN dcmon.site.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.site.city IS 'Synthetic city/location label for demonstration.';
COMMENT ON COLUMN dcmon.site.timezone IS 'IANA timezone used when presenting local timestamps.';
COMMENT ON COLUMN dcmon.site.latitude IS 'Latitude in degrees; NULL with longitude when unavailable or withheld.';
COMMENT ON COLUMN dcmon.site.longitude IS 'Longitude in degrees; NULL with latitude when unavailable or withheld.';
COMMENT ON COLUMN dcmon.site.design_it_kw IS 'Design IT power capacity in kilowatts; not measured consumption.';

-- software_installation
COMMENT ON TABLE dcmon.software_installation IS 'Concrete installed software instance such as a machine OS, database instance or Java runtime.';
COMMENT ON COLUMN dcmon.software_installation.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.software_installation.product_id IS 'Software product referenced by this installation.';
COMMENT ON COLUMN dcmon.software_installation.version IS 'Current inventory version; historical upgrades require an external change audit.';
COMMENT ON COLUMN dcmon.software_installation.instance_name IS 'Concrete OS, service or database-instance name.';
COMMENT ON COLUMN dcmon.software_installation.listen_port IS 'Service port from 1 to 65535 when applicable; NULL otherwise.';

-- software_product
COMMENT ON TABLE dcmon.software_product IS 'Software product catalog for operating systems, databases, platforms, middleware and agents; distinct from business systems.';
COMMENT ON COLUMN dcmon.software_product.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.software_product.code IS 'Stable machine-readable catalog code.';
COMMENT ON COLUMN dcmon.software_product.name IS 'Human-readable display name; does not replace a stable identifier.';
COMMENT ON COLUMN dcmon.software_product.category IS 'Software class: os, dbms, platform, middleware or agent.';
COMMENT ON COLUMN dcmon.software_product.vendor IS 'Software vendor or maintaining community.';

-- source_system
COMMENT ON TABLE dcmon.source_system IS 'Data-source integration registry containing configuration references and ownership, without passwords or access secrets.';
COMMENT ON COLUMN dcmon.source_system.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.source_system.code IS 'Stable machine-readable catalog code.';
COMMENT ON COLUMN dcmon.source_system.name IS 'Human-readable display name; does not replace a stable identifier.';
COMMENT ON COLUMN dcmon.source_system.method IS 'Integration method such as REST, JSON-RPC, exporter, gateway or file.';
COMMENT ON COLUMN dcmon.source_system.endpoint_ref IS 'Non-secret endpoint or connector configuration reference; not a credential store.';
COMMENT ON COLUMN dcmon.source_system.owner_team IS 'Team accountable for availability of the integration.';

-- status_observation
COMMENT ON TABLE dcmon.status_observation IS 'Technical CI status history with an explicit freshness lifetime; separate from lifecycle and incident counts.';
COMMENT ON COLUMN dcmon.status_observation.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.status_observation.observed_at IS 'Time the fact was observed in the source; used for as-of selection.';
COMMENT ON COLUMN dcmon.status_observation.state IS 'Technical state used for status colors and labels; independent of lifecycle and incident state.';
COMMENT ON COLUMN dcmon.status_observation.reason IS 'Source-provided explanation of the technical state.';
COMMENT ON COLUMN dcmon.status_observation.valid_for_sec IS 'Maximum accepted age of this status observation, in seconds.';
COMMENT ON COLUMN dcmon.status_observation.source_id IS 'Authoritative source record in dcmon.source_system.';

-- storage_volume
COMMENT ON TABLE dcmon.storage_volume IS 'Logical storage volume and its serving storage device; internal pool details remain in the storage source.';
COMMENT ON COLUMN dcmon.storage_volume.ci_id IS 'Stable reference to the configuration item in dcmon.ci.';
COMMENT ON COLUMN dcmon.storage_volume.storage_device_id IS 'Serving physical device; trigger requires the storage device class.';
COMMENT ON COLUMN dcmon.storage_volume.capacity_gib IS 'Allocated logical volume capacity in GiB; not used space.';
COMMENT ON COLUMN dcmon.storage_volume.protocol IS 'Volume access protocol: FC, iSCSI, NFS or NVMe-oF.';

-- system_environment
COMMENT ON TABLE dcmon.system_environment IS 'PROD, TEST or DEV environment of one business system; placement and ownership remain environment-specific.';
COMMENT ON COLUMN dcmon.system_environment.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.system_environment.system_id IS 'Business system owning this environment.';
COMMENT ON COLUMN dcmon.system_environment.environment IS 'Operating environment: PROD, TEST or DEV.';
COMMENT ON COLUMN dcmon.system_environment.service_owner_team_id IS 'Operations team responsible for this particular environment.';

-- team
COMMENT ON TABLE dcmon.team IS 'Synthetic service and operations teams; contains no personal contact details.';
COMMENT ON COLUMN dcmon.team.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.team.code IS 'Stable machine-readable catalog code.';
COMMENT ON COLUMN dcmon.team.name IS 'Human-readable display name; does not replace a stable identifier.';
COMMENT ON COLUMN dcmon.team.contact_ref IS 'Synthetic service group or on-call reference; no personal password or private contact.';

-- volume_attachment
COMMENT ON TABLE dcmon.volume_attachment IS 'Effective-dated attachment of a logical volume to compute; shared volumes can serve multiple hosts.';
COMMENT ON COLUMN dcmon.volume_attachment.id IS 'Stable internal record identifier; not reused.';
COMMENT ON COLUMN dcmon.volume_attachment.volume_id IS 'Logical storage volume referenced by the attachment.';
COMMENT ON COLUMN dcmon.volume_attachment.host_id IS 'Compute host CI; endpoint type is validated.';
COMMENT ON COLUMN dcmon.volume_attachment.mount_ref IS 'Datastore, mount point or drive-letter reference without credentials.';
COMMENT ON COLUMN dcmon.volume_attachment.valid_from IS 'Inclusive start of the relationship validity interval; business event time, not ingestion time.';
COMMENT ON COLUMN dcmon.volume_attachment.valid_to IS 'Exclusive end of the relationship validity interval; NULL means open-ended.';

-- v_inventory_summary
COMMENT ON VIEW dcmon.v_inventory_summary IS 'Counts of currently active inventory grouped by CI kind; planned and retired lifecycle entries are excluded.';
COMMENT ON COLUMN dcmon.v_inventory_summary.kind IS 'CI subtype included in the current active-inventory aggregation.';
COMMENT ON COLUMN dcmon.v_inventory_summary.objects IS 'Number of active inventory items of this subtype.';

-- v_unmapped_compute
COMMENT ON VIEW dcmon.v_unmapped_compute IS 'Active physical servers and runtimes without an application execution-path association at now(); excludes software installations and does not invent an owner.';
COMMENT ON COLUMN dcmon.v_unmapped_compute.ci_id IS 'Physical server or runtime CI lacking an execution-path association at now().';
COMMENT ON COLUMN dcmon.v_unmapped_compute.ci_key IS 'Readable key of the unmapped server or runtime.';
COMMENT ON COLUMN dcmon.v_unmapped_compute.kind IS 'CI kind of the unmapped item: device for a physical server, or runtime.';

COMMENT ON FUNCTION dcmon.check_compute_reference() IS 'Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.check_dependency() IS 'Checks directed consumer/provider types on dependency INSERT/UPDATE. Application: component to component/installation; power: device/rack to PDU/UPS/generator; cooling: room/rack/device to CRAC/chiller; network: device/runtime to switch; storage: device/runtime to storage. Rejects unknown/missing endpoint types with SQLSTATE 23514; does not infer availability, redundancy or traversal in the reverse direction. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.check_hosting() IS 'Checks hosting INSERT/UPDATE hierarchy: VM to physical server, pod to VM/server, container to pod. Rejects invalid or missing endpoint types with SQLSTATE 23514. Effective-dated overlap constraints separately prevent simultaneous hosts. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.check_metric_value() IS 'On metric_sample INSERT/UPDATE, validates only quality=ok against its definition valid_min/valid_max. NULL bounds leave that side unrestricted. Table checks independently require finite values for ok and NULL for missing/error. Warning and critical thresholds are presentation guidance, never validity limits. Raises SQLSTATE 23514 for a range breach. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.check_rack_space() IS 'On device_placement INSERT/UPDATE with a U interval, acquires a shared lock on the target rack and checks inclusive top U (u_start+u_height-1) against height_u. NULL U denotes floor/0U placement and bypasses the capacity test; table checks and exclusions enforce other shape/overlap rules. Raises SQLSTATE 23514 on overflow. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.check_storage_device() IS 'On storage_volume INSERT/UPDATE, requires storage_device_id to identify a device of class storage. Rejects absent or other-class devices with SQLSTATE 23514. A foreign key alone cannot express the device-class requirement. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.compute_paths(p_at timestamp with time zone) IS 'Returns origin_id, terminal physical server_id and ordered node_ids for server/runtime/installation origins visible at p_at. Follows hosting and installation_placement intervals [valid_from,valid_to), excludes planned origins, respects origin first_seen_at/retired_at, and includes a physical server own one-node path. Rejects revisiting a path node and caps node count at 64. Multiple legitimate paths remain separate; downstream selection deduplicates hosts. Does not reconstruct historical software versions.';
COMMENT ON FUNCTION dcmon.execution_paths(p_at timestamp with time zone) IS 'Returns application-to-server execution paths at p_at: component root, first target, ordered node_ids and system/environment keys. Traverses effective deployment, directed application dependencies, installation placement and guest-to-host hosting using half-open intervals. The visited-node guard prevents cycles and the 64-node cap bounds recursion. Emits each path ending at a physical server; does not deduplicate paths or apply CI lifecycle visibility independently of relationship intervals.';
COMMENT ON FUNCTION dcmon.immutable_ci_kind() IS 'Before ci kind updates, rejects a different subtype with SQLSTATE 23514 so existing subtype, topology and telemetry references retain their interpretation. Other inventory attributes may change. Retiring/replacing a CI preserves identity history instead of retyping it.';
COMMENT ON FUNCTION dcmon.immutable_device_class() IS 'Before device_class updates, rejects a different class with SQLSTATE 23514 because dependency and hosting rules rely on that class. Replace or retire an incorrectly classified device through an explicit migration rather than silently reinterpreting relationships.';
COMMENT ON FUNCTION dcmon.immutable_runtime_kind() IS 'Before runtime_kind updates, rejects changing VM/pod/container type with SQLSTATE 23514 because hosting rules depend on the subtype. A newly created workload instance requires its own identity.';
COMMENT ON FUNCTION dcmon.is_compute(p_id bigint) IS 'Returns true if p_id is a physical device of class server or a runtime; false for missing IDs and other physical equipment. It is a type predicate, not a lifecycle, health, placement or capacity test. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.metric_snapshot(p_at timestamp with time zone) IS 'For every metric_series, selects the latest sample with observed_at<=p_at, independent of ingestion time. Returns raw_value for diagnosis and display_value only when quality=ok and observation age is <=stale_after_sec. No point yields missing; age strictly above the budget yields stale before checking point quality; otherwise quality missing/error propagates, or ok becomes fresh. Age is in seconds and no value or timestamp is fabricated. Does not filter series by CI lifecycle or first_seen_at; labels/definitions are current inventory attributes.';
COMMENT ON FUNCTION dcmon.prevent_rack_shrink() IS 'Before rack height updates, rejects any height below the inclusive top U of an existing placement, including historical/closed intervals. Preserves historical physical validity; it is intentionally stricter than checking only current placements. Raises SQLSTATE 23514. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.require_ci_kind() IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON FUNCTION dcmon.status_snapshot(p_at timestamp with time zone) IS 'For each CI with first_seen_at<=p_at and no retirement at/before p_at, selects its latest status_observation with observed_at<=p_at. No observation or age strictly greater than valid_for_sec becomes unknown, with an English reason; equality remains fresh. Preserves the source timestamp for stale diagnostics. Does not exclude planned lifecycle CIs or infer status from incidents/metrics.';
COMMENT ON FUNCTION dcmon.system_hosts(p_system_key text, p_environment text, p_software_code text, p_at timestamp with time zone) IS 'Returns distinct physical servers selected by optional system key, environment and software product code at p_at; NULL means no restriction. Uses execution_paths and, only with both system/environment NULL, compute_paths to retain unmapped hosts. Software must be on the selected path or installed on a node of that path, avoiding sibling VM leakage. Current effective device placement supplies optional rack/room/site keys; unplaced hosts remain with NULL location. Does not test historical software version.';
COMMENT ON FUNCTION dcmon.system_incidents(p_system_key text, p_environment text, p_at timestamp with time zone) IS 'Returns one row per incident in system_scope at p_at with detection and incident-CI link times not after p_at. Latest workflow event determines state; resolved/closed incidents are excluded. matched_objects counts distinct in-scope linked CIs and all impact_role values may match, so potential risk is not a confirmed application outage. Multiple links do not multiply incidents. Interpretation remains explicitly advisory.';
COMMENT ON FUNCTION dcmon.system_scope(p_system_key text, p_environment text, p_at timestamp with time zone) IS 'Builds CI scope for optional system/environment at p_at from execution-path nodes, matching components and systems, effective physical locations, software installed on core nodes, attached volumes and containing clusters. With both filters NULL it also seeds historically visible CIs. Recurses only consumer-to-provider through non-application infrastructure dependencies; UNION deduplicates nodes and terminates cycles. Never traverses reverse hosting to sibling VMs. Location/attachment expansion uses the core set, not every later infrastructure node; the function does not infer transitive impact severity.';
COMMENT ON FUNCTION dcmon.system_software(p_system_key text, p_environment text, p_at timestamp with time zone) IS 'Returns distinct software installations placed on nodes of selected execution paths at p_at with optional system/environment filters (NULL is unrestricted). association=explicit_dependency means the installation itself is a path node; otherwise installed_on_execution_path means presence on a path host, not proof of use. Only placement is effective-dated: version, product and instance inventory remain current attributes. Unmapped compute is not added by this function.';
COMMENT ON SEQUENCE dcmon.backup_run_id_seq IS 'Allocates new backup_run.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.ci_ci_id_seq IS 'Allocates new ci.ci_id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.cluster_member_id_seq IS 'Allocates new cluster_member.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.dependency_id_seq IS 'Allocates new dependency.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.deployment_id_seq IS 'Allocates new deployment.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.device_placement_id_seq IS 'Allocates new device_placement.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.hosting_id_seq IS 'Allocates new hosting.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.incident_event_id_seq IS 'Allocates new incident_event.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.incident_id_seq IS 'Allocates new incident.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.ingestion_run_id_seq IS 'Allocates new ingestion_run.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.installation_placement_id_seq IS 'Allocates new installation_placement.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.maintenance_window_id_seq IS 'Allocates new maintenance_window.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.metric_definition_id_seq IS 'Allocates new metric_definition.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.metric_series_series_id_seq IS 'Allocates new metric_series.series_id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.network_link_id_seq IS 'Allocates new network_link.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.network_port_id_seq IS 'Allocates new network_port.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.scene_object_id_seq IS 'Allocates new scene_object.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.software_product_id_seq IS 'Allocates new software_product.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.source_system_id_seq IS 'Allocates new source_system.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.system_environment_id_seq IS 'Allocates new system_environment.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.team_id_seq IS 'Allocates new team.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON SEQUENCE dcmon.volume_attachment_id_seq IS 'Allocates new volume_attachment.id identities; fixture reset follows the maximum restored ID.';
COMMENT ON INDEX dcmon.backup_run_pkey IS 'Enforces the stable primary-key identity on backup_run. Definition: btree (id).';
COMMENT ON INDEX dcmon.backup_run_source_id_job_key_started_at_key IS 'Prevents duplicate natural identities on backup_run. Definition: btree (source_id, job_key, started_at).';
COMMENT ON INDEX dcmon.ci_ci_key_key IS 'Prevents duplicate natural identities on ci. Definition: btree (ci_key).';
COMMENT ON INDEX dcmon.ci_pkey IS 'Enforces the stable primary-key identity on ci. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.cluster_pkey IS 'Enforces the stable primary-key identity on cluster. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.cluster_member_cluster_id_member_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on cluster_member. Definition: gist (cluster_id, member_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.cluster_member_pkey IS 'Enforces the stable primary-key identity on cluster_member. Definition: btree (id).';
COMMENT ON INDEX dcmon.component_environment_idx IS 'Finds application components for a selected system environment on component. Definition: btree (environment_id).';
COMMENT ON INDEX dcmon.component_pkey IS 'Enforces the stable primary-key identity on component. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.dependency_dependent_id_provider_id_dependency_type_tstzra_excl IS 'Prevents overlapping effective-dated relationships on dependency. Definition: gist (dependent_id, provider_id, dependency_type, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.dependency_dependent_idx IS 'Traverses directed dependencies from consumer to infrastructure provider on dependency. Definition: btree (dependent_id).';
COMMENT ON INDEX dcmon.dependency_pkey IS 'Enforces the stable primary-key identity on dependency. Definition: btree (id).';
COMMENT ON INDEX dcmon.dependency_provider_idx IS 'Finds consumers of a provider for inventory investigation; traversal direction remains explicit on dependency. Definition: btree (provider_id).';
COMMENT ON INDEX dcmon.deployment_component_id_target_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on deployment. Definition: gist (component_id, target_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.deployment_pkey IS 'Enforces the stable primary-key identity on deployment. Definition: btree (id).';
COMMENT ON INDEX dcmon.deployment_target_idx IS 'Finds component deployments targeting a compute or installation CI on deployment. Definition: btree (target_id).';
COMMENT ON INDEX dcmon.device_pkey IS 'Enforces the stable primary-key identity on device. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.device_serial_number_key IS 'Prevents duplicate natural identities on device. Definition: btree (serial_number).';
COMMENT ON INDEX dcmon.device_placement_device_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on device_placement. Definition: gist (device_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.device_placement_pkey IS 'Enforces the stable primary-key identity on device_placement. Definition: btree (id).';
COMMENT ON INDEX dcmon.device_placement_rack_id_int4range_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on device_placement. Definition: gist (rack_id, int4range(u_start, (u_start + u_height), ''[)''::text), tstzrange(valid_from, valid_to, ''[)''::text)) WHERE (u_start IS NOT NULL).';
COMMENT ON INDEX dcmon.placement_rack_idx IS 'Finds all device placements in a rack for layout and capacity checks on device_placement. Definition: btree (rack_id).';
COMMENT ON INDEX dcmon.external_identity_ci_idx IS 'Finds all source-specific identities associated with one stable CI on external_identity. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.external_identity_pkey IS 'Enforces the stable primary-key identity on external_identity. Definition: btree (source_id, external_id).';
COMMENT ON INDEX dcmon.hosting_guest_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on hosting. Definition: gist (guest_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.hosting_host_idx IS 'Finds guests on a host for explicit inventory lookup, without implying reverse scope traversal on hosting. Definition: btree (host_id).';
COMMENT ON INDEX dcmon.hosting_pkey IS 'Enforces the stable primary-key identity on hosting. Definition: btree (id).';
COMMENT ON INDEX dcmon.incident_incident_key_key IS 'Prevents duplicate natural identities on incident. Definition: btree (incident_key).';
COMMENT ON INDEX dcmon.incident_pkey IS 'Enforces the stable primary-key identity on incident. Definition: btree (id).';
COMMENT ON INDEX dcmon.incident_source_id_external_id_key IS 'Prevents duplicate natural identities on incident. Definition: btree (source_id, external_id).';
COMMENT ON INDEX dcmon.incident_ci_pkey IS 'Enforces the stable primary-key identity on incident_ci. Definition: btree (incident_id, ci_id).';
COMMENT ON INDEX dcmon.incident_ci_reverse_idx IS 'Finds incident links for an in-scope configuration item on incident_ci. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.incident_event_incident_id_occurred_at_key IS 'Prevents duplicate natural identities on incident_event. Definition: btree (incident_id, occurred_at).';
COMMENT ON INDEX dcmon.incident_event_latest_idx IS 'Selects the latest workflow event at or before a requested incident time on incident_event. Definition: btree (incident_id, occurred_at DESC).';
COMMENT ON INDEX dcmon.incident_event_pkey IS 'Enforces the stable primary-key identity on incident_event. Definition: btree (id).';
COMMENT ON INDEX dcmon.information_system_pkey IS 'Enforces the stable primary-key identity on information_system. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.ingestion_run_pkey IS 'Enforces the stable primary-key identity on ingestion_run. Definition: btree (id).';
COMMENT ON INDEX dcmon.installation_host_idx IS 'Finds software placed on nodes of an execution path on installation_placement. Definition: btree (host_id).';
COMMENT ON INDEX dcmon.installation_placement_installation_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on installation_placement. Definition: gist (installation_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.installation_placement_pkey IS 'Enforces the stable primary-key identity on installation_placement. Definition: btree (id).';
COMMENT ON INDEX dcmon.maintenance_window_pkey IS 'Enforces the stable primary-key identity on maintenance_window. Definition: btree (id).';
COMMENT ON INDEX dcmon.metric_definition_code_key IS 'Prevents duplicate natural identities on metric_definition. Definition: btree (code).';
COMMENT ON INDEX dcmon.metric_definition_pkey IS 'Enforces the stable primary-key identity on metric_definition. Definition: btree (id).';
COMMENT ON INDEX dcmon.metric_sample_latest_idx IS 'Selects the most recent sample at or before p_at for each series on metric_sample. Definition: btree (series_id, observed_at DESC).';
COMMENT ON INDEX dcmon.metric_sample_pkey IS 'Enforces the stable primary-key identity on metric_sample. Definition: btree (series_id, observed_at).';
COMMENT ON INDEX dcmon.metric_sample_time_brin IS 'Uses compact block-range summaries for observed-time range scans on append-like telemetry on metric_sample. Definition: brin (observed_at).';
COMMENT ON INDEX dcmon.metric_series_ci_id_metric_id_labels_key IS 'Prevents duplicate natural identities on metric_series. Definition: btree (ci_id, metric_id, labels).';
COMMENT ON INDEX dcmon.metric_series_ci_idx IS 'Finds metric series for a selected configuration item on metric_series. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.metric_series_pkey IS 'Enforces the stable primary-key identity on metric_series. Definition: btree (series_id).';
COMMENT ON INDEX dcmon.network_link_pkey IS 'Enforces the stable primary-key identity on network_link. Definition: btree (id).';
COMMENT ON INDEX dcmon.no_port_overlap IS 'Prevents overlapping effective-dated relationships on network_link. Definition: gist (int8multirange(VARIADIC ARRAY[int8range(port_a_id, port_a_id, ''[]''::text), int8range(port_b_id, port_b_id, ''[]''::text)]), tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON INDEX dcmon.network_port_device_id_name_key IS 'Prevents duplicate natural identities on network_port. Definition: btree (device_id, name).';
COMMENT ON INDEX dcmon.network_port_pkey IS 'Enforces the stable primary-key identity on network_port. Definition: btree (id).';
COMMENT ON INDEX dcmon.rack_ci_id_room_id_key IS 'Prevents duplicate natural identities on rack. Definition: btree (ci_id, room_id).';
COMMENT ON INDEX dcmon.rack_pkey IS 'Enforces the stable primary-key identity on rack. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.room_pkey IS 'Enforces the stable primary-key identity on room. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.runtime_pkey IS 'Enforces the stable primary-key identity on runtime. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.scene_ci_idx IS 'Finds optional presentation coordinates and assets for a CI on scene_object. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.scene_object_pkey IS 'Enforces the stable primary-key identity on scene_object. Definition: btree (id).';
COMMENT ON INDEX dcmon.scene_object_scene_key_ci_id_key IS 'Prevents duplicate natural identities on scene_object. Definition: btree (scene_key, ci_id).';
COMMENT ON INDEX dcmon.site_pkey IS 'Enforces the stable primary-key identity on site. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.software_installation_pkey IS 'Enforces the stable primary-key identity on software_installation. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.software_product_code_key IS 'Prevents duplicate natural identities on software_product. Definition: btree (code).';
COMMENT ON INDEX dcmon.software_product_pkey IS 'Enforces the stable primary-key identity on software_product. Definition: btree (id).';
COMMENT ON INDEX dcmon.source_system_code_key IS 'Prevents duplicate natural identities on source_system. Definition: btree (code).';
COMMENT ON INDEX dcmon.source_system_pkey IS 'Enforces the stable primary-key identity on source_system. Definition: btree (id).';
COMMENT ON INDEX dcmon.status_latest_idx IS 'Selects the latest status observation at or before p_at per CI on status_observation. Definition: btree (ci_id, observed_at DESC).';
COMMENT ON INDEX dcmon.status_observation_pkey IS 'Enforces the stable primary-key identity on status_observation. Definition: btree (ci_id, observed_at).';
COMMENT ON INDEX dcmon.storage_volume_pkey IS 'Enforces the stable primary-key identity on storage_volume. Definition: btree (ci_id).';
COMMENT ON INDEX dcmon.system_environment_pkey IS 'Enforces the stable primary-key identity on system_environment. Definition: btree (id).';
COMMENT ON INDEX dcmon.system_environment_system_id_environment_key IS 'Prevents duplicate natural identities on system_environment. Definition: btree (system_id, environment).';
COMMENT ON INDEX dcmon.team_code_key IS 'Prevents duplicate natural identities on team. Definition: btree (code).';
COMMENT ON INDEX dcmon.team_pkey IS 'Enforces the stable primary-key identity on team. Definition: btree (id).';
COMMENT ON INDEX dcmon.volume_attachment_pkey IS 'Enforces the stable primary-key identity on volume_attachment. Definition: btree (id).';
COMMENT ON INDEX dcmon.volume_attachment_volume_id_host_id_tstzrange_excl IS 'Prevents overlapping effective-dated relationships on volume_attachment. Definition: gist (volume_id, host_id, tstzrange(valid_from, valid_to, ''[)''::text)).';
COMMENT ON TRIGGER ci_kind_immutable ON dcmon.ci IS 'Before ci kind updates, rejects a different subtype with SQLSTATE 23514 so existing subtype, topology and telemetry references retain their interpretation. Other inventory attributes may change. Retiring/replacing a CI preserves identity history instead of retyping it.';
COMMENT ON TRIGGER subtype_kind ON dcmon.cluster IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.component IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_dependency ON dcmon.dependency IS 'Checks directed consumer/provider types on dependency INSERT/UPDATE. Application: component to component/installation; power: device/rack to PDU/UPS/generator; cooling: room/rack/device to CRAC/chiller; network: device/runtime to switch; storage: device/runtime to storage. Rejects unknown/missing endpoint types with SQLSTATE 23514; does not infer availability, redundancy or traversal in the reverse direction. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_deployment ON dcmon.deployment IS 'Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public.';
COMMENT ON TRIGGER device_class_guard ON dcmon.device IS 'Before device_class updates, rejects a different class with SQLSTATE 23514 because dependency and hosting rules rely on that class. Replace or retire an incorrectly classified device through an explicit migration rather than silently reinterpreting relationships.';
COMMENT ON TRIGGER subtype_kind ON dcmon.device IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_rack_space ON dcmon.device_placement IS 'On device_placement INSERT/UPDATE with a U interval, acquires a shared lock on the target rack and checks inclusive top U (u_start+u_height-1) against height_u. NULL U denotes floor/0U placement and bypasses the capacity test; table checks and exclusions enforce other shape/overlap rules. Raises SQLSTATE 23514 on overflow. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_hosting ON dcmon.hosting IS 'Checks hosting INSERT/UPDATE hierarchy: VM to physical server, pod to VM/server, container to pod. Rejects invalid or missing endpoint types with SQLSTATE 23514. Effective-dated overlap constraints separately prevent simultaneous hosts. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.information_system IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_installation_host ON dcmon.installation_placement IS 'Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_metric_range ON dcmon.metric_sample IS 'On metric_sample INSERT/UPDATE, validates only quality=ok against its definition valid_min/valid_max. NULL bounds leave that side unrestricted. Table checks independently require finite values for ok and NULL for missing/error. Warning and critical thresholds are presentation guidance, never validity limits. Raises SQLSTATE 23514 for a range breach. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER rack_height_guard ON dcmon.rack IS 'Before rack height updates, rejects any height below the inclusive top U of an existing placement, including historical/closed intervals. Preserves historical physical validity; it is intentionally stricter than checking only current placements. Raises SQLSTATE 23514. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.rack IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.room IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER runtime_kind_guard ON dcmon.runtime IS 'Before runtime_kind updates, rejects changing VM/pod/container type with SQLSTATE 23514 because hosting rules depend on the subtype. A newly created workload instance requires its own identity.';
COMMENT ON TRIGGER subtype_kind ON dcmon.runtime IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.site IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.software_installation IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER subtype_kind ON dcmon.storage_volume IS 'On subtype INSERT/UPDATE, compares NEW.ci_id to the expected dcmon.ci.kind supplied in the trigger argument. Rejects both missing CIs and mismatches with SQLSTATE 23514; foreign keys separately maintain ownership. Does not require every CI to have a subtype row. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER volume_storage_kind ON dcmon.storage_volume IS 'On storage_volume INSERT/UPDATE, requires storage_device_id to identify a device of class storage. Rejects absent or other-class devices with SQLSTATE 23514. A foreign key alone cannot express the device-class requirement. Uses caller search_path dcmon,public.';
COMMENT ON TRIGGER valid_volume_host ON dcmon.volume_attachment IS 'Validates INSERT/UPDATE targets for deployment, installation_placement and volume_attachment. A compute target is a physical server or any runtime; only deployment may additionally target software_installation. Raises SQLSTATE 23514 on a type mismatch; foreign keys separately require existence. Uses the caller search_path dcmon,public.';
COMMENT ON CONSTRAINT backup_run_check ON dcmon.backup_run IS 'Valid domain and cross-column consistency. Rule: CHECK (((finished_at IS NULL) OR (finished_at >= started_at))).';
COMMENT ON CONSTRAINT backup_run_check1 ON dcmon.backup_run IS 'Valid domain and cross-column consistency. Rule: CHECK (((recovery_point_at IS NULL) OR (recovery_point_at <= finished_at))).';
COMMENT ON CONSTRAINT backup_run_check2 ON dcmon.backup_run IS 'Valid domain and cross-column consistency. Rule: CHECK (((status <> ''success''::text) OR ((finished_at IS NOT NULL) AND (recovery_point_at IS NOT NULL)))).';
COMMENT ON CONSTRAINT backup_run_environment_id_fkey ON dcmon.backup_run IS 'Referential integrity. Rule: FOREIGN KEY (environment_id) REFERENCES system_environment(id).';
COMMENT ON CONSTRAINT backup_run_pkey ON dcmon.backup_run IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT backup_run_size_gib_check ON dcmon.backup_run IS 'Valid domain and cross-column consistency. Rule: CHECK ((size_gib >= (0)::numeric)).';
COMMENT ON CONSTRAINT backup_run_source_id_fkey ON dcmon.backup_run IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT backup_run_source_id_job_key_started_at_key ON dcmon.backup_run IS 'Natural-key uniqueness. Rule: UNIQUE (source_id, job_key, started_at).';
COMMENT ON CONSTRAINT backup_run_status_check ON dcmon.backup_run IS 'Valid domain and cross-column consistency. Rule: CHECK ((status = ANY (ARRAY[''running''::text, ''success''::text, ''failed''::text]))).';
COMMENT ON CONSTRAINT ci_check ON dcmon.ci IS 'Valid domain and cross-column consistency. Rule: CHECK ((last_seen_at >= first_seen_at)).';
COMMENT ON CONSTRAINT ci_check1 ON dcmon.ci IS 'Valid domain and cross-column consistency. Rule: CHECK (((lifecycle = ''retired''::text) = (retired_at IS NOT NULL))).';
COMMENT ON CONSTRAINT ci_check2 ON dcmon.ci IS 'Valid domain and cross-column consistency. Rule: CHECK (((retired_at IS NULL) OR (retired_at >= first_seen_at))).';
COMMENT ON CONSTRAINT ci_ci_key_key ON dcmon.ci IS 'Natural-key uniqueness. Rule: UNIQUE (ci_key).';
COMMENT ON CONSTRAINT ci_kind_check ON dcmon.ci IS 'Valid domain and cross-column consistency. Rule: CHECK ((kind = ANY (ARRAY[''site''::text, ''room''::text, ''rack''::text, ''device''::text, ''runtime''::text, ''cluster''::text, ''installation''::text, ''system''::text, ''component''::text, ''volume''::text]))).';
COMMENT ON CONSTRAINT ci_lifecycle_check ON dcmon.ci IS 'Valid domain and cross-column consistency. Rule: CHECK ((lifecycle = ANY (ARRAY[''planned''::text, ''active''::text, ''retired''::text]))).';
COMMENT ON CONSTRAINT ci_owner_team_id_fkey ON dcmon.ci IS 'Referential integrity. Rule: FOREIGN KEY (owner_team_id) REFERENCES team(id).';
COMMENT ON CONSTRAINT ci_pkey ON dcmon.ci IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT cluster_ci_id_fkey ON dcmon.cluster IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT cluster_cluster_type_check ON dcmon.cluster IS 'Valid domain and cross-column consistency. Rule: CHECK ((cluster_type = ANY (ARRAY[''virtualization''::text, ''kubernetes''::text, ''database''::text, ''storage''::text]))).';
COMMENT ON CONSTRAINT cluster_pkey ON dcmon.cluster IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT cluster_member_check ON dcmon.cluster_member IS 'Valid domain and cross-column consistency. Rule: CHECK ((cluster_id <> member_id)).';
COMMENT ON CONSTRAINT cluster_member_check1 ON dcmon.cluster_member IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT cluster_member_cluster_id_fkey ON dcmon.cluster_member IS 'Referential integrity. Rule: FOREIGN KEY (cluster_id) REFERENCES cluster(ci_id).';
COMMENT ON CONSTRAINT cluster_member_cluster_id_member_id_tstzrange_excl ON dcmon.cluster_member IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (cluster_id WITH =, member_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT cluster_member_member_id_fkey ON dcmon.cluster_member IS 'Referential integrity. Rule: FOREIGN KEY (member_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT cluster_member_pkey ON dcmon.cluster_member IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT component_ci_id_fkey ON dcmon.component IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT component_component_role_check ON dcmon.component IS 'Valid domain and cross-column consistency. Rule: CHECK ((component_role = ANY (ARRAY[''web''::text, ''api''::text, ''database''::text, ''queue''::text, ''batch''::text]))).';
COMMENT ON CONSTRAINT component_environment_id_fkey ON dcmon.component IS 'Referential integrity. Rule: FOREIGN KEY (environment_id) REFERENCES system_environment(id).';
COMMENT ON CONSTRAINT component_pkey ON dcmon.component IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT dependency_check ON dcmon.dependency IS 'Valid domain and cross-column consistency. Rule: CHECK ((dependent_id <> provider_id)).';
COMMENT ON CONSTRAINT dependency_check1 ON dcmon.dependency IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT dependency_dependency_type_check ON dcmon.dependency IS 'Valid domain and cross-column consistency. Rule: CHECK ((dependency_type = ANY (ARRAY[''application''::text, ''power''::text, ''cooling''::text, ''network''::text, ''storage''::text]))).';
COMMENT ON CONSTRAINT dependency_dependent_id_fkey ON dcmon.dependency IS 'Referential integrity. Rule: FOREIGN KEY (dependent_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT dependency_dependent_id_provider_id_dependency_type_tstzra_excl ON dcmon.dependency IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (dependent_id WITH =, provider_id WITH =, dependency_type WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT dependency_pkey ON dcmon.dependency IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT dependency_provider_id_fkey ON dcmon.dependency IS 'Referential integrity. Rule: FOREIGN KEY (provider_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT dependency_source_id_fkey ON dcmon.dependency IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT deployment_check ON dcmon.deployment IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT deployment_component_id_fkey ON dcmon.deployment IS 'Referential integrity. Rule: FOREIGN KEY (component_id) REFERENCES component(ci_id).';
COMMENT ON CONSTRAINT deployment_component_id_target_id_tstzrange_excl ON dcmon.deployment IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (component_id WITH =, target_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT deployment_pkey ON dcmon.deployment IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT deployment_role_check ON dcmon.deployment IS 'Valid domain and cross-column consistency. Rule: CHECK ((role = ANY (ARRAY[''primary''::text, ''replica''::text, ''standby''::text, ''worker''::text]))).';
COMMENT ON CONSTRAINT deployment_target_id_fkey ON dcmon.deployment IS 'Referential integrity. Rule: FOREIGN KEY (target_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT device_ci_id_fkey ON dcmon.device IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT device_cpu_cores_check ON dcmon.device IS 'Valid domain and cross-column consistency. Rule: CHECK ((cpu_cores > 0)).';
COMMENT ON CONSTRAINT device_device_class_check ON dcmon.device IS 'Valid domain and cross-column consistency. Rule: CHECK ((device_class = ANY (ARRAY[''server''::text, ''storage''::text, ''switch''::text, ''ups''::text, ''pdu''::text, ''crac''::text, ''chiller''::text, ''generator''::text, ''fire_sensor''::text, ''access_controller''::text]))).';
COMMENT ON CONSTRAINT device_memory_gib_check ON dcmon.device IS 'Valid domain and cross-column consistency. Rule: CHECK ((memory_gib > (0)::numeric)).';
COMMENT ON CONSTRAINT device_pkey ON dcmon.device IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT device_serial_number_key ON dcmon.device IS 'Natural-key uniqueness. Rule: UNIQUE (serial_number).';
COMMENT ON CONSTRAINT device_placement_check ON dcmon.device_placement IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT device_placement_check1 ON dcmon.device_placement IS 'Valid domain and cross-column consistency. Rule: CHECK ((((u_start IS NULL) AND (u_height IS NULL)) OR ((rack_id IS NOT NULL) AND (u_start > 0) AND (u_height > 0)))).';
COMMENT ON CONSTRAINT device_placement_check2 ON dcmon.device_placement IS 'Valid domain and cross-column consistency. Rule: CHECK (((rack_id IS NOT NULL) OR ((u_start IS NULL) AND (u_height IS NULL)))).';
COMMENT ON CONSTRAINT device_placement_device_id_fkey ON dcmon.device_placement IS 'Referential integrity. Rule: FOREIGN KEY (device_id) REFERENCES device(ci_id).';
COMMENT ON CONSTRAINT device_placement_device_id_tstzrange_excl ON dcmon.device_placement IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (device_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT device_placement_pkey ON dcmon.device_placement IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT device_placement_rack_id_fkey ON dcmon.device_placement IS 'Referential integrity. Rule: FOREIGN KEY (rack_id) REFERENCES rack(ci_id).';
COMMENT ON CONSTRAINT device_placement_rack_id_int4range_tstzrange_excl ON dcmon.device_placement IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (rack_id WITH =, int4range(u_start, (u_start + u_height), ''[)''::text) WITH &&, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&) WHERE ((u_start IS NOT NULL)).';
COMMENT ON CONSTRAINT device_placement_rack_id_room_id_fkey ON dcmon.device_placement IS 'Referential integrity. Rule: FOREIGN KEY (rack_id, room_id) REFERENCES rack(ci_id, room_id).';
COMMENT ON CONSTRAINT device_placement_room_id_fkey ON dcmon.device_placement IS 'Referential integrity. Rule: FOREIGN KEY (room_id) REFERENCES room(ci_id).';
COMMENT ON CONSTRAINT external_identity_ci_id_fkey ON dcmon.external_identity IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT external_identity_pkey ON dcmon.external_identity IS 'Stable record identity. Rule: PRIMARY KEY (source_id, external_id).';
COMMENT ON CONSTRAINT external_identity_source_id_fkey ON dcmon.external_identity IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT hosting_check ON dcmon.hosting IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT hosting_check1 ON dcmon.hosting IS 'Valid domain and cross-column consistency. Rule: CHECK ((guest_id <> host_id)).';
COMMENT ON CONSTRAINT hosting_guest_id_fkey ON dcmon.hosting IS 'Referential integrity. Rule: FOREIGN KEY (guest_id) REFERENCES runtime(ci_id).';
COMMENT ON CONSTRAINT hosting_guest_id_tstzrange_excl ON dcmon.hosting IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (guest_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT hosting_host_id_fkey ON dcmon.hosting IS 'Referential integrity. Rule: FOREIGN KEY (host_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT hosting_pkey ON dcmon.hosting IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT incident_incident_key_key ON dcmon.incident IS 'Natural-key uniqueness. Rule: UNIQUE (incident_key).';
COMMENT ON CONSTRAINT incident_owner_team_id_fkey ON dcmon.incident IS 'Referential integrity. Rule: FOREIGN KEY (owner_team_id) REFERENCES team(id).';
COMMENT ON CONSTRAINT incident_pkey ON dcmon.incident IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT incident_severity_check ON dcmon.incident IS 'Valid domain and cross-column consistency. Rule: CHECK ((severity = ANY (ARRAY[''info''::text, ''warning''::text, ''critical''::text]))).';
COMMENT ON CONSTRAINT incident_source_id_external_id_key ON dcmon.incident IS 'Natural-key uniqueness. Rule: UNIQUE (source_id, external_id).';
COMMENT ON CONSTRAINT incident_source_id_fkey ON dcmon.incident IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT incident_ci_ci_id_fkey ON dcmon.incident_ci IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT incident_ci_impact_role_check ON dcmon.incident_ci IS 'Valid domain and cross-column consistency. Rule: CHECK ((impact_role = ANY (ARRAY[''cause''::text, ''affected''::text, ''at_risk''::text]))).';
COMMENT ON CONSTRAINT incident_ci_incident_id_fkey ON dcmon.incident_ci IS 'Referential integrity. Rule: FOREIGN KEY (incident_id) REFERENCES incident(id).';
COMMENT ON CONSTRAINT incident_ci_pkey ON dcmon.incident_ci IS 'Stable record identity. Rule: PRIMARY KEY (incident_id, ci_id).';
COMMENT ON CONSTRAINT incident_event_incident_id_fkey ON dcmon.incident_event IS 'Referential integrity. Rule: FOREIGN KEY (incident_id) REFERENCES incident(id).';
COMMENT ON CONSTRAINT incident_event_incident_id_occurred_at_key ON dcmon.incident_event IS 'Natural-key uniqueness. Rule: UNIQUE (incident_id, occurred_at).';
COMMENT ON CONSTRAINT incident_event_pkey ON dcmon.incident_event IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT incident_event_state_check ON dcmon.incident_event IS 'Valid domain and cross-column consistency. Rule: CHECK ((state = ANY (ARRAY[''open''::text, ''acknowledged''::text, ''in_progress''::text, ''resolved''::text, ''closed''::text]))).';
COMMENT ON CONSTRAINT information_system_ci_id_fkey ON dcmon.information_system IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT information_system_criticality_check ON dcmon.information_system IS 'Valid domain and cross-column consistency. Rule: CHECK ((criticality = ANY (ARRAY[''critical''::text, ''high''::text, ''standard''::text]))).';
COMMENT ON CONSTRAINT information_system_pkey ON dcmon.information_system IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT information_system_target_rpo_min_check ON dcmon.information_system IS 'Valid domain and cross-column consistency. Rule: CHECK ((target_rpo_min >= 0)).';
COMMENT ON CONSTRAINT information_system_target_rto_min_check ON dcmon.information_system IS 'Valid domain and cross-column consistency. Rule: CHECK ((target_rto_min >= 0)).';
COMMENT ON CONSTRAINT ingestion_run_accepted_rows_check ON dcmon.ingestion_run IS 'Valid domain and cross-column consistency. Rule: CHECK ((accepted_rows >= 0)).';
COMMENT ON CONSTRAINT ingestion_run_check ON dcmon.ingestion_run IS 'Valid domain and cross-column consistency. Rule: CHECK (((finished_at IS NULL) OR (finished_at >= started_at))).';
COMMENT ON CONSTRAINT ingestion_run_pkey ON dcmon.ingestion_run IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT ingestion_run_rejected_rows_check ON dcmon.ingestion_run IS 'Valid domain and cross-column consistency. Rule: CHECK ((rejected_rows >= 0)).';
COMMENT ON CONSTRAINT ingestion_run_source_id_fkey ON dcmon.ingestion_run IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT ingestion_run_state_check ON dcmon.ingestion_run IS 'Valid domain and cross-column consistency. Rule: CHECK ((state = ANY (ARRAY[''running''::text, ''success''::text, ''partial''::text, ''failed''::text]))).';
COMMENT ON CONSTRAINT installation_placement_check ON dcmon.installation_placement IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT installation_placement_host_id_fkey ON dcmon.installation_placement IS 'Referential integrity. Rule: FOREIGN KEY (host_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT installation_placement_installation_id_fkey ON dcmon.installation_placement IS 'Referential integrity. Rule: FOREIGN KEY (installation_id) REFERENCES software_installation(ci_id).';
COMMENT ON CONSTRAINT installation_placement_installation_id_tstzrange_excl ON dcmon.installation_placement IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (installation_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT installation_placement_pkey ON dcmon.installation_placement IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT maintenance_window_check ON dcmon.maintenance_window IS 'Valid domain and cross-column consistency. Rule: CHECK ((ends_at > starts_at)).';
COMMENT ON CONSTRAINT maintenance_window_ci_id_fkey ON dcmon.maintenance_window IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT maintenance_window_pkey ON dcmon.maintenance_window IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT metric_definition_check ON dcmon.metric_definition IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_max IS NULL) OR (valid_min IS NULL) OR (valid_max >= valid_min))).';
COMMENT ON CONSTRAINT metric_definition_check1 ON dcmon.metric_definition IS 'Valid domain and cross-column consistency. Rule: CHECK (((critical_above IS NULL) OR (warning_above IS NULL) OR (critical_above >= warning_above))).';
COMMENT ON CONSTRAINT metric_definition_code_key ON dcmon.metric_definition IS 'Natural-key uniqueness. Rule: UNIQUE (code).';
COMMENT ON CONSTRAINT metric_definition_metric_type_check ON dcmon.metric_definition IS 'Valid domain and cross-column consistency. Rule: CHECK ((metric_type = ANY (ARRAY[''gauge''::text, ''counter''::text]))).';
COMMENT ON CONSTRAINT metric_definition_pkey ON dcmon.metric_definition IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT metric_sample_check ON dcmon.metric_sample IS 'Valid domain and cross-column consistency. Rule: CHECK ((((quality = ''ok''::text) AND (value IS NOT NULL) AND (value <> ALL (ARRAY[''NaN''::numeric, ''Infinity''::numeric, ''-Infinity''::numeric]))) OR ((quality <> ''ok''::text) AND (value IS NULL)))).';
COMMENT ON CONSTRAINT metric_sample_pkey ON dcmon.metric_sample IS 'Stable record identity. Rule: PRIMARY KEY (series_id, observed_at).';
COMMENT ON CONSTRAINT metric_sample_quality_check ON dcmon.metric_sample IS 'Valid domain and cross-column consistency. Rule: CHECK ((quality = ANY (ARRAY[''ok''::text, ''missing''::text, ''error''::text]))).';
COMMENT ON CONSTRAINT metric_sample_series_id_fkey ON dcmon.metric_sample IS 'Referential integrity. Rule: FOREIGN KEY (series_id) REFERENCES metric_series(series_id).';
COMMENT ON CONSTRAINT metric_series_check ON dcmon.metric_series IS 'Valid domain and cross-column consistency. Rule: CHECK ((stale_after_sec >= expected_interval_sec)).';
COMMENT ON CONSTRAINT metric_series_ci_id_fkey ON dcmon.metric_series IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT metric_series_ci_id_metric_id_labels_key ON dcmon.metric_series IS 'Natural-key uniqueness. Rule: UNIQUE (ci_id, metric_id, labels).';
COMMENT ON CONSTRAINT metric_series_expected_interval_sec_check ON dcmon.metric_series IS 'Valid domain and cross-column consistency. Rule: CHECK ((expected_interval_sec > 0)).';
COMMENT ON CONSTRAINT metric_series_labels_check ON dcmon.metric_series IS 'Valid domain and cross-column consistency. Rule: CHECK ((jsonb_typeof(labels) = ''object''::text)).';
COMMENT ON CONSTRAINT metric_series_metric_id_fkey ON dcmon.metric_series IS 'Referential integrity. Rule: FOREIGN KEY (metric_id) REFERENCES metric_definition(id).';
COMMENT ON CONSTRAINT metric_series_pkey ON dcmon.metric_series IS 'Stable record identity. Rule: PRIMARY KEY (series_id).';
COMMENT ON CONSTRAINT metric_series_source_id_fkey ON dcmon.metric_series IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT metric_series_stale_after_sec_check ON dcmon.metric_series IS 'Valid domain and cross-column consistency. Rule: CHECK ((stale_after_sec > 0)).';
COMMENT ON CONSTRAINT network_link_check ON dcmon.network_link IS 'Valid domain and cross-column consistency. Rule: CHECK ((port_a_id < port_b_id)).';
COMMENT ON CONSTRAINT network_link_check1 ON dcmon.network_link IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT network_link_pkey ON dcmon.network_link IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT network_link_port_a_id_fkey ON dcmon.network_link IS 'Referential integrity. Rule: FOREIGN KEY (port_a_id) REFERENCES network_port(id).';
COMMENT ON CONSTRAINT network_link_port_b_id_fkey ON dcmon.network_link IS 'Referential integrity. Rule: FOREIGN KEY (port_b_id) REFERENCES network_port(id).';
COMMENT ON CONSTRAINT no_port_overlap ON dcmon.network_link IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (int8multirange(VARIADIC ARRAY[int8range(port_a_id, port_a_id, ''[]''::text), int8range(port_b_id, port_b_id, ''[]''::text)]) WITH &&, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
COMMENT ON CONSTRAINT network_port_device_id_fkey ON dcmon.network_port IS 'Referential integrity. Rule: FOREIGN KEY (device_id) REFERENCES device(ci_id).';
COMMENT ON CONSTRAINT network_port_device_id_name_key ON dcmon.network_port IS 'Natural-key uniqueness. Rule: UNIQUE (device_id, name).';
COMMENT ON CONSTRAINT network_port_pkey ON dcmon.network_port IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT network_port_speed_mbps_check ON dcmon.network_port IS 'Valid domain and cross-column consistency. Rule: CHECK ((speed_mbps > 0)).';
COMMENT ON CONSTRAINT rack_ci_id_fkey ON dcmon.rack IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT rack_ci_id_room_id_key ON dcmon.rack IS 'Natural-key uniqueness. Rule: UNIQUE (ci_id, room_id).';
COMMENT ON CONSTRAINT rack_height_u_check ON dcmon.rack IS 'Valid domain and cross-column consistency. Rule: CHECK ((height_u > 0)).';
COMMENT ON CONSTRAINT rack_pkey ON dcmon.rack IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT rack_power_limit_kw_check ON dcmon.rack IS 'Valid domain and cross-column consistency. Rule: CHECK ((power_limit_kw > (0)::numeric)).';
COMMENT ON CONSTRAINT rack_room_id_fkey ON dcmon.rack IS 'Referential integrity. Rule: FOREIGN KEY (room_id) REFERENCES room(ci_id).';
COMMENT ON CONSTRAINT room_area_m2_check ON dcmon.room IS 'Valid domain and cross-column consistency. Rule: CHECK ((area_m2 > (0)::numeric)).';
COMMENT ON CONSTRAINT room_ci_id_fkey ON dcmon.room IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT room_pkey ON dcmon.room IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT room_room_type_check ON dcmon.room IS 'Valid domain and cross-column consistency. Rule: CHECK ((room_type = ANY (ARRAY[''data_hall''::text, ''power''::text, ''cooling''::text, ''other''::text]))).';
COMMENT ON CONSTRAINT room_site_id_fkey ON dcmon.room IS 'Referential integrity. Rule: FOREIGN KEY (site_id) REFERENCES site(ci_id).';
COMMENT ON CONSTRAINT runtime_ci_id_fkey ON dcmon.runtime IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT runtime_memory_gib_allocated_check ON dcmon.runtime IS 'Valid domain and cross-column consistency. Rule: CHECK ((memory_gib_allocated >= (0)::numeric)).';
COMMENT ON CONSTRAINT runtime_pkey ON dcmon.runtime IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT runtime_runtime_kind_check ON dcmon.runtime IS 'Valid domain and cross-column consistency. Rule: CHECK ((runtime_kind = ANY (ARRAY[''vm''::text, ''pod''::text, ''container''::text]))).';
COMMENT ON CONSTRAINT runtime_vcpu_allocated_check ON dcmon.runtime IS 'Valid domain and cross-column consistency. Rule: CHECK ((vcpu_allocated >= (0)::numeric)).';
COMMENT ON CONSTRAINT scene_object_ci_id_fkey ON dcmon.scene_object IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT scene_object_pkey ON dcmon.scene_object IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT scene_object_scale_check ON dcmon.scene_object IS 'Valid domain and cross-column consistency. Rule: CHECK ((scale > (0)::numeric)).';
COMMENT ON CONSTRAINT scene_object_scene_key_ci_id_key ON dcmon.scene_object IS 'Natural-key uniqueness. Rule: UNIQUE (scene_key, ci_id).';
COMMENT ON CONSTRAINT site_check ON dcmon.site IS 'Valid domain and cross-column consistency. Rule: CHECK (((latitude IS NULL) = (longitude IS NULL))).';
COMMENT ON CONSTRAINT site_ci_id_fkey ON dcmon.site IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT site_design_it_kw_check ON dcmon.site IS 'Valid domain and cross-column consistency. Rule: CHECK ((design_it_kw > (0)::numeric)).';
COMMENT ON CONSTRAINT site_latitude_check ON dcmon.site IS 'Valid domain and cross-column consistency. Rule: CHECK (((latitude >= (''-90''::integer)::numeric) AND (latitude <= (90)::numeric))).';
COMMENT ON CONSTRAINT site_longitude_check ON dcmon.site IS 'Valid domain and cross-column consistency. Rule: CHECK (((longitude >= (''-180''::integer)::numeric) AND (longitude <= (180)::numeric))).';
COMMENT ON CONSTRAINT site_pkey ON dcmon.site IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT software_installation_ci_id_fkey ON dcmon.software_installation IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT software_installation_listen_port_check ON dcmon.software_installation IS 'Valid domain and cross-column consistency. Rule: CHECK (((listen_port >= 1) AND (listen_port <= 65535))).';
COMMENT ON CONSTRAINT software_installation_pkey ON dcmon.software_installation IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT software_installation_product_id_fkey ON dcmon.software_installation IS 'Referential integrity. Rule: FOREIGN KEY (product_id) REFERENCES software_product(id).';
COMMENT ON CONSTRAINT software_product_category_check ON dcmon.software_product IS 'Valid domain and cross-column consistency. Rule: CHECK ((category = ANY (ARRAY[''os''::text, ''dbms''::text, ''platform''::text, ''middleware''::text, ''agent''::text]))).';
COMMENT ON CONSTRAINT software_product_code_key ON dcmon.software_product IS 'Natural-key uniqueness. Rule: UNIQUE (code).';
COMMENT ON CONSTRAINT software_product_pkey ON dcmon.software_product IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT source_system_code_key ON dcmon.source_system IS 'Natural-key uniqueness. Rule: UNIQUE (code).';
COMMENT ON CONSTRAINT source_system_pkey ON dcmon.source_system IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT status_observation_ci_id_fkey ON dcmon.status_observation IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT status_observation_pkey ON dcmon.status_observation IS 'Stable record identity. Rule: PRIMARY KEY (ci_id, observed_at).';
COMMENT ON CONSTRAINT status_observation_source_id_fkey ON dcmon.status_observation IS 'Referential integrity. Rule: FOREIGN KEY (source_id) REFERENCES source_system(id).';
COMMENT ON CONSTRAINT status_observation_state_check ON dcmon.status_observation IS 'Valid domain and cross-column consistency. Rule: CHECK ((state = ANY (ARRAY[''healthy''::text, ''warning''::text, ''critical''::text, ''unknown''::text, ''maintenance''::text]))).';
COMMENT ON CONSTRAINT status_observation_valid_for_sec_check ON dcmon.status_observation IS 'Valid domain and cross-column consistency. Rule: CHECK ((valid_for_sec > 0)).';
COMMENT ON CONSTRAINT storage_volume_capacity_gib_check ON dcmon.storage_volume IS 'Valid domain and cross-column consistency. Rule: CHECK ((capacity_gib > (0)::numeric)).';
COMMENT ON CONSTRAINT storage_volume_ci_id_fkey ON dcmon.storage_volume IS 'Referential integrity. Rule: FOREIGN KEY (ci_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT storage_volume_pkey ON dcmon.storage_volume IS 'Stable record identity. Rule: PRIMARY KEY (ci_id).';
COMMENT ON CONSTRAINT storage_volume_protocol_check ON dcmon.storage_volume IS 'Valid domain and cross-column consistency. Rule: CHECK ((protocol = ANY (ARRAY[''FC''::text, ''iSCSI''::text, ''NFS''::text, ''NVMe-oF''::text]))).';
COMMENT ON CONSTRAINT storage_volume_storage_device_id_fkey ON dcmon.storage_volume IS 'Referential integrity. Rule: FOREIGN KEY (storage_device_id) REFERENCES device(ci_id).';
COMMENT ON CONSTRAINT system_environment_environment_check ON dcmon.system_environment IS 'Valid domain and cross-column consistency. Rule: CHECK ((environment = ANY (ARRAY[''PROD''::text, ''TEST''::text, ''DEV''::text]))).';
COMMENT ON CONSTRAINT system_environment_pkey ON dcmon.system_environment IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT system_environment_service_owner_team_id_fkey ON dcmon.system_environment IS 'Referential integrity. Rule: FOREIGN KEY (service_owner_team_id) REFERENCES team(id).';
COMMENT ON CONSTRAINT system_environment_system_id_environment_key ON dcmon.system_environment IS 'Natural-key uniqueness. Rule: UNIQUE (system_id, environment).';
COMMENT ON CONSTRAINT system_environment_system_id_fkey ON dcmon.system_environment IS 'Referential integrity. Rule: FOREIGN KEY (system_id) REFERENCES information_system(ci_id).';
COMMENT ON CONSTRAINT team_code_key ON dcmon.team IS 'Natural-key uniqueness. Rule: UNIQUE (code).';
COMMENT ON CONSTRAINT team_pkey ON dcmon.team IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT volume_attachment_check ON dcmon.volume_attachment IS 'Valid domain and cross-column consistency. Rule: CHECK (((valid_to IS NULL) OR (valid_to > valid_from))).';
COMMENT ON CONSTRAINT volume_attachment_host_id_fkey ON dcmon.volume_attachment IS 'Referential integrity. Rule: FOREIGN KEY (host_id) REFERENCES ci(ci_id).';
COMMENT ON CONSTRAINT volume_attachment_pkey ON dcmon.volume_attachment IS 'Stable record identity. Rule: PRIMARY KEY (id).';
COMMENT ON CONSTRAINT volume_attachment_volume_id_fkey ON dcmon.volume_attachment IS 'Referential integrity. Rule: FOREIGN KEY (volume_id) REFERENCES storage_volume(ci_id).';
COMMENT ON CONSTRAINT volume_attachment_volume_id_host_id_tstzrange_excl ON dcmon.volume_attachment IS 'Temporal or physical exclusivity. Rule: EXCLUDE USING gist (volume_id WITH =, host_id WITH =, tstzrange(valid_from, valid_to, ''[)''::text) WITH &&).';
