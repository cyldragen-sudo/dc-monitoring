# Installation

Run commands from the repository root. Use a new demonstration database, separate from any existing monitoring system. The database restore and report installer are independent; neither configures the vendor runtime for you.

## Prerequisites

- PostgreSQL 16 server and client tools (`psql`, `createdb`). Newer servers pass the installer's minimum-version check, but version 16 is the validated baseline.
- Python 3.9 or later; no Python packages are required.
- Node.js 22 or later for source tests; local verification used Node.js 24. No npm install is needed.
- Your separately installed FineReport runtime/Designer with FineVIS v11 support. The existing demonstration uses FineVIS v11 4.13.0. The report carries older `com.fr.plugin.wysiwyg.v11` version 3.4.1 metadata; that does not establish a compatible minimum. Check your own vendor-supported runtime combination.
- Permission to create the `btree_gist` extension in the destination database when absent, and to create the `dcmon` schema and its objects.
- An existing FineReport webroot containing `WEB-INF/reportlets`, writable by the installing operator.

The fixture contains 1,058,182 metric samples, so restore and verification take longer than a small example database. No FineReport container image, JDBC binary or license is redistributed here.

## Option A: an existing PostgreSQL server

Create a fresh database with an account authorized to create databases and restore the schema. Substitute your actual host, port and owner. Do not point `PGDATABASE` at a live monitoring database.

```sh
export PGHOST=127.0.0.1
export PGPORT=5432
export PGUSER=postgres
export PGDATABASE=dc_monitoring_demo
export PGOPTIONS='-c search_path=dcmon,public -c timezone=Europe/Moscow'
createdb --maintenance-db=postgres "$PGDATABASE"
```

Configure password-file authentication before running the Python scripts. Put the matching `host:port:database:user:password` entry in your private `.pgpass` file, or an equivalent file selected by `PGPASSFILE`. Protect that file with `chmod 600` on Unix. Keep it outside the repository. Use a wildcard database entry only if you intend it to cover both the maintenance and demonstration database. Client startup files are ignored and password prompts disabled by the scripts: absent credentials fail instead of hanging. `PSQL` can select a client executable if `psql` is not on PATH:

```sh
export PSQL="$(command -v psql)"
```

`PGOPTIONS` also makes ad hoc writes and helper-function calls use `search_path=dcmon,public`. Some preserved trigger helpers use unqualified names, so that path matters beyond the initial restore. The verifier sets its own transaction-local path and timezone.

## Option B: optional Docker Compose PostgreSQL

Copy the example and set a private password in `.env` using your editor. The file is ignored by Git. Compose reads it; the Python tools do **not** load it.

```sh
cp .env.example .env
# Edit .env: supply POSTGRES_PASSWORD and optionally DC_POSTGRES_PORT.
docker compose up -d --wait postgres
export PGHOST=127.0.0.1
export PGPORT=55432
export PGDATABASE=dc_monitoring_demo
export PGUSER=postgres
export PGOPTIONS='-c search_path=dcmon,public -c timezone=Europe/Moscow'
```

If you change `DC_POSTGRES_PORT`, export the same `PGPORT`. Configure a private `.pgpass`/`PGPASSFILE` entry matching this connection and the password supplied to Compose. Install a host PostgreSQL 16 client for the repository scripts. The container creates `dc_monitoring_demo` on its first initialization; do not run `createdb` for this option. Changing `.env` later does not change credentials in an already initialized volume.

The mapping is localhost-only, `127.0.0.1:55432 → 5432`, and the named volume `dc_demo_data` persists across container restarts. `docker compose stop` stops the service without deleting its data; `docker compose start` resumes it. This setup never resets an existing volume automatically. FineReport remains a separate installation.

## Restore and validate

Confirm the target explicitly before restoring:

```sh
psql -X -w -c 'SELECT current_database(), current_user, version();'
python3 scripts/database.py init
python3 scripts/verify_database.py --require-sequences
```

`init` checks that `dcmon` does not exist, then applies `001_schema.sql`, decompressed `002_demo_data.sql.gz`, `003_comments.sql` and `ANALYZE` in one transaction. SQL failures roll back the restore; a concurrent schema creator also causes failure. Temporary decompressed data is removed on exit. An existing schema is a reason to select a new database, not an invitation to drop it.

Verification runs read-only transactions, checks catalog row counts and English descriptions, executes all 22 datasets, and checks issue counts, missing telemetry, disk/port histories and intersecting filters. The owner-side `--require-sequences` option also requires exact identity ownership and all 22 allocation states (`last_value`, `is_called` and the computed next ID relative to the restored maximum), without consuming IDs. This exact-state check targets a fresh restore; normal writes can legitimately advance sequence allocation later. It does not call FineReport or test its license. To reapply descriptions only, with an account that owns the restored objects:

```sh
python3 scripts/database.py comments
```

That command updates English descriptions; it does not update data, permissions or object definitions.

## Create a separate read-only report account

Use the restoring administrator connection for this step. Choose a unique role name if `dcmon_report` already exists; `CREATE ROLE` deliberately fails for an existing role. The password is entered privately through `psql`, not included in SQL files or command-line arguments.

```sh
psql -X -w
```

At the `psql` prompt:

```sql
CREATE ROLE dcmon_report LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
\password dcmon_report
GRANT CONNECT ON DATABASE dc_monitoring_demo TO dcmon_report;
GRANT USAGE ON SCHEMA dcmon TO dcmon_report;
GRANT SELECT ON ALL TABLES IN SCHEMA dcmon TO dcmon_report;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dcmon TO dcmon_report;
ALTER ROLE dcmon_report IN DATABASE dc_monitoring_demo SET search_path TO dcmon, public;
ALTER ROLE dcmon_report IN DATABASE dc_monitoring_demo SET timezone TO 'Europe/Moscow';
ALTER ROLE dcmon_report IN DATABASE dc_monitoring_demo SET default_transaction_read_only TO on;
\q
```

Use your actual database name consistently. These grants cover the restored objects, not future migrations; review grants again when adding objects. The role owns no objects and has no insert/update/delete/schema-creation grants from these instructions. Transaction read-only is an extra default, not a substitute for privileges. On shared or previously customized PostgreSQL servers, review inherited and `PUBLIC` privileges too.

Give this role its own password and private password-file entry; do not reuse administrator credentials. Test it without replacing your administrator shell settings:

```sh
PGUSER=dcmon_report psql -X -w -c "SELECT current_user, current_setting('search_path'), count(*) FROM dcmon.device;"
PGUSER=dcmon_report python3 scripts/verify_database.py
```

The report role has no SELECT privilege on sequences. The verifier still checks all 22 identity ownership/definition mappings, explicitly reports skipped allocation-state reads, and completes the table/dataset checks. Do not grant sequence USAGE or UPDATE for verification. Run `--require-sequences` separately with the restoring owner; that option fails when any state is unreadable.

## Configure the named FineReport connection

In your runtime/Designer database-connection administration, create a PostgreSQL connection named exactly **`DC_MONITORING`**, with the report role's credentials, the demonstration database, host and port. Configure the vendor-supported PostgreSQL JDBC driver in your runtime if needed. A typical JDBC address is `jdbc:postgresql://127.0.0.1:55432/dc_monitoring_demo`; it contains no password. For a native PostgreSQL installation use its actual port. From a container or another machine, `127.0.0.1` refers to that machine, so provide an address reachable by FineReport and configure PostgreSQL access accordingly.

Keep credentials in FineReport's protected server connection configuration. The FVS file contains only a `NameDatabaseConnection` reference, never embedded login details. Test the named connection and a query such as `SELECT count(*) FROM dcmon.device`. The role-specific settings ensure `dcmon,public` resolves helpers correctly.

## Install into an explicit webroot

Back up and review any existing DC project first. Substitute the actual vendor webroot; do not use the repository directory as the destination.

```sh
export FINEREPORT_WEBROOT='/path/to/FineReport/webapps/webroot'
python3 scripts/install_dashboard.py --webroot "$FINEREPORT_WEBROOT"
```

This creates only:

- `WEB-INF/reportlets/DC_MONITORING/Infrastructure_Overview.fvs`
- `DC_MONITORING_3D/`, containing browser HTML/CSS/JavaScript and illustration assets

The historical `DC_MONITORING_3D` URL is retained for saved navigation. The current display uses ordinary HTML/CSS/SVG and raster illustrations. The installer converts `.mjs` modules to `.js` and rewrites their imports for FineReport static-file MIME compatibility. It does not change the database, vendor binaries, licensing, server settings or unrelated reports.

Existing owned targets cause refusal. For an intentional update, first review your changes and then use:

```sh
python3 scripts/install_dashboard.py --webroot "$FINEREPORT_WEBROOT" --replace
```

Replacement backs up only the two DC targets under `build/backups/<UTC timestamp>/`; failed writes restore those targets. Symlinked targets that escape the chosen webroot are refused. Backups are local and excluded from releases. The containing reportlets folder and other report projects are not replacement targets.

## Open and check all five pages

Start your licensed runtime using its normal vendor procedure. For a local server on port 8075, open:

```text
http://localhost:8075/webroot/decision/view/duchamp?viewlet=DC_MONITORING%252FInfrastructure_Overview.fvs&page_number=1
```

Use your actual host and port. The `%252F` spelling preserves the encoded separator expected by the report's existing links. You can also open `DC_MONITORING/Infrastructure_Overview.fvs` through the Designer or runtime report browser.

The report's cross-page and iframe URLs assume the **root `/webroot` context**. A reverse-proxy prefix or a different context requires reviewing every report and browser navigation URL; changing only the entry URL is insufficient. Verify `/webroot/DC_MONITORING_3D/index.html` serves successfully; opened alone it has no payload and should show a missing-data error, not an inventory. The full report supplies data in its iframe URL fragment.

Check DC network, IT · servers, Infrastructure, Issues and History using the [walkthrough](demo-walkthrough.md). Preserve any vendor watermark or license banner. Installation does not alter licensing or suppress runtime notices.
