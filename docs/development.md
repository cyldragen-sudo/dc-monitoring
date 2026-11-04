# Development

Use Python 3.9+, Node.js 22+ and a PostgreSQL 16 client/server for full verification. Python and JavaScript use their standard libraries; no pip/npm installation is required. Local JavaScript verification used Node.js 24; CI selects Node.js 22 and Python 3.12. The vendor runtime is required only for report editing and visual validation, and must be supplied separately.

## Source ownership and build order

Edit query behavior in `dashboard/tools/build_queries.py` and its network/scene/operations registration modules. Edit display translation in `english_locale.py` / `en_translations.json`. `dashboard/sql/*.sql`, `datasets.json` and `datasets.xml` are generated artifacts; direct edits will be overwritten. Edit browser presentation in the `.mjs`, `.html` and `.css` source files under `dashboard/scene`.

```sh
make build
make test
make audit
```

`make build` regenerates all SQL and explicitly refreshes the tracked `dashboard/report/Infrastructure_Overview.fvs`. Review the complete resulting diff. It also refreshes the dataset XML export. To make a report candidate without overwriting the tracked FVS:

```sh
python3 dashboard/tools/build_queries.py
python3 scripts/refresh_report.py
```

That candidate is `build/Infrastructure_Overview.fvs`. Query generation still updates the tracked SQL/manifest; use an isolated branch/workspace when experimenting. The refresh tool validates dataset names, parameter sets and the portable named connection before writing, and preserves report widgets, events and bundled assets.

## Focused source checks

```sh
node --test dashboard/scene/test_*.mjs
python3 -m unittest discover -s tests -v
python3 scripts/check_repository.py
```

The 35 JavaScript tests cover hierarchy, physical occupancy versus filtered telemetry, deterministic selection, metric bounds and nulls, disks/ports, issue filtering and navigation/history semantics. The four Python tests include three installer safety cases and one query-build regression. Installer cases exercise clean installation, replacement refusal/backups and failure rollback using temporary fake webroots; the builder case protects localization of leading SQL comments. No vendor runtime or live webroot is modified. Test counts can grow with future changes.

For a new behavior, add a test at the relevant contract boundary. Avoid tests that merely copy the implementation. A cosmetic documentation edit needs link/content auditing; it does not need a new database regression test.

## Database verification

Configure libpq variables and private password-file authentication as in [installation](installation.md). Use a new database for each clean restore, then run:

```sh
python3 scripts/database.py init
python3 scripts/verify_database.py --require-sequences
```

The verifier uses read-only transactions, explicit `search_path=dcmon,public`, Europe/Moscow time and a statement timeout. It validates catalog descriptions/counts, all 22 identity ownership mappings and exact fresh-restore sequence states, all 22 default datasets, full inventory, issue grain, NULL histories, known component readings, excluded devices and source-backed filter intersection. Sequence checks read `last_value`/`is_called` and compute the next ID without calling `nextval` or `setval`. Without `--require-sequences`, report roles lacking sequence SELECT explicitly skip state reads while retaining ownership and dataset checks. CI uses the strict owner option. `init` must refuse a second restore into the same namespace. Do not add a destructive reset path to make repeated local tests convenient.

Schema/data work requires updating the schema, fixture, metadata, catalog and dictionary consistently. Preserve CI identity, effective-time semantics, typed relationship guards, placement exclusions, metric nulls and incident deduplication. For write sessions and direct helper calls, keep `dcmon,public` in the search path. English descriptions can be refreshed independently using `database.py comments`; that is not a schema migration.

## Editing the FVS in FineVIS

The FVS ZIP contains `editor.tpl`, chart resources and a bundled illustration. Use the vendor Designer/runtime for layout edits; do not treat its large serialized widget JSON as a stable public API. Keep the connection named `DC_MONITORING`, retain numeric parameter contracts, and regenerate dataset text after layout editing. Audit the resulting archive for embedded connections and secrets.

Install candidates only into an explicitly selected test webroot:

```sh
python3 scripts/install_dashboard.py --webroot "$FINEREPORT_WEBROOT" --report build/Infrastructure_Overview.fvs
```

Use `--replace` only after reviewing existing DC targets and the candidate. The installer stores backups in `build/backups/` and rewrites deployed `.mjs` references to `.js`; do not edit that deployed copy as source. The root `/webroot` URL assumption spans report events and browser modules, so test every cross-page/deep link if changing hosting context.

## Visual review

Check all five pages at default scope, one restrictive application scope, an empty result and selected site. Test North cooling/server context, East disk sdb, switch port-1 and Reserve's missing CPU sample using the [walkthrough](demo-walkthrough.md). Inspect readable labels, no fabricated zeroes, rack occupancy, component deep links, history gaps and issue/device/incident count distinctions. Retain vendor runtime notices in review screenshots.

The fixed snapshot makes results repeatable. Replacing it with `now()` is a behavior change: freshness, relationships, incident states and demo expectations all need a coordinated update. New live collection would also require source adapters and operations work beyond this repository's synthetic fixture.

## CI and release

[The workflow](../.github/workflows/validate.yml) rebuilds source artifacts and requires no dashboard diff, runs source/installer tests, restores a disposable PostgreSQL service, checks all datasets and refusal of a repeat initialization, audits contents and packages the source demo. Its disposable CI database password is not a deployable credential. It does not run FineReport or obtain a vendor license.

See [validation evidence](validation.md) for the preparation checks and their limits, and [release preparation](release.md) for deterministic packaging and publication boundaries.
