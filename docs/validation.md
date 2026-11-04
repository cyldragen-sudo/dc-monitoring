# Publication validation

Validation date: **2026-11-04**. Data snapshot: **2026-10-21 14:32 Europe/Moscow**.
These dates have different meanings: preparing the package did not advance the
synthetic monitoring clock or collect new measurements.

## Verified locally

| Area | Evidence |
|---|---|
| Database bootstrap | Complete schema, fixture and English descriptions restored into an empty database on a separate PostgreSQL 16.2 cluster, with no access to the existing demo server required |
| Fixture | 36 tables, 1,125,949 total rows, including 1,058,182 metric samples and 40,574 series; all table counts checked against the public catalog |
| Generated IDs | All 22 identity sequences reset after COPY. Strict owner verification checks ownership, `last_value`, `is_called` and the next-ID relationship without consuming IDs; the check fails the deliberately retained earlier restore with counters at 1 |
| Inventory | 3 sites, 6 halls, 48 racks, 972 servers and the current hardware telemetry fixture |
| English metadata | Exact descriptions verified for 38 tables/views, 221 columns and 20 functions; prepared comments additionally cover constraints, indexes, sequences and triggers |
| Report datasets | All 22 queries executed successfully, including the scene, issues and history payloads |
| Read-only account | Dataset verification passed under a separate role granted only schema usage, table SELECT and function EXECUTE, with a read-only transaction default. Sequence ownership is checked; unavailable sequence state is explicitly reported as skipped. Strict `--require-sequences` verification is an owner step, not a reason to grant the report account sequence privileges |
| Scope | Digital Banking / PROD / PostgreSQL yields two physical servers; invalid site returns an empty issue queue; an excluded server has no history payload |
| Problems | 13 distinct issues: 4 critical, 7 warning, 2 unknown; one active incident |
| Hardware/history | East server disk temperature 58 °C; switch port utilization 92%; 24 switch ports; 25 aligned history points; missing CPU remains NULL |
| Browser logic | 35 Node.js tests pass, covering navigation, physical placement, scope aggregation, hardware severity, threshold boundaries, history gaps and exact component links |
| Installation/build safety | Four Python tests pass: protected replacement and project isolation, symlink/invalid-target refusal, rollback after a simulated write failure, and comment-aware recursive SQL localization |
| Source preservation | All 20 browser/test modules have the same executable JavaScript syntax tree as the working source; changes are formatting and comments. All 22 SQL statements retain the same executable tokens and literals |
| Reproducible build | Repeated query/report generation produces identical SQL, manifest, dataset XML and FVS bytes |
| Current UI | All five pages and 513 widgets use the deployed English dashboard's exact UI store; report database references are converted to the portable named connection |
| Packaging | Public allowlist excludes private credentials, local paths, vendor binaries, scratch work and installation backups; compressed SQL and report XML are included in the audit |
| Compose | Configuration validates; the database bootstrap itself was exercised on native PostgreSQL rather than Docker |

The final source archive contains `SHA256SUMS` for every payload file and has a
separate ZIP checksum. See [release preparation](release.md) for reproducible
packaging and [installation](installation.md) for commands to repeat the database
checks in your own environment.

Independent review caught missing identity-sequence resets in an intermediate
fixture. The final fixture contains 22 explicit resets, and its COPY data remains
unchanged. Catalog and dictionary entries now identify each sequence's actual
owned table and column. CI requires the strict owner check so a SELECT-only
dashboard success cannot hide this restore defect again.

## Runtime boundary

The existing local runtime uses FineVIS v11 plugin 4.13.0. The report retains
older template metadata identifying version 3.4.1; that metadata does not establish
a supported minimum runtime version. A native template-parser check read the
report and its three resources, but its standalone plugin manager emitted warnings.
Treat this as a structural compatibility check, not an end-to-end runtime test.

A fresh proprietary FineReport/FineVIS installation, its license, JDBC connection,
authentication, browser rendering and reverse-proxy configuration were **not**
provisioned automatically. They are external prerequisites. The installer was
tested against an isolated webroot layout, not by overwriting the running demo.
The retained screenshots show the existing English dashboard and include the
vendor's banner. GitHub Actions is configured but has not run on GitHub before
publication. Follow the [demo walkthrough](demo-walkthrough.md) after configuring
your runtime to complete acceptance on that environment.

The public comments are included in the restored database. Applying them to a
separate existing database is an explicit owner operation using
`python3 scripts/database.py comments`; preparation does not silently modify that
database. No unrelated project or installed report is changed by the package build.
