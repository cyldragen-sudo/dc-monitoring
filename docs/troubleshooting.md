# Troubleshooting

Start by distinguishing database results, FineReport execution and iframe rendering. Run `python3 scripts/verify_database.py` against the intended demo database, test the named FineReport connection, then check browser network/console errors. Keep passwords and complete operational payloads out of public issue reports.

| Symptom | Likely cause and action |
|---|---|
| `Set PGDATABASE explicitly` | Export `PGDATABASE=dc_monitoring_demo` (or your chosen new database). Scripts do not infer the destination from `.env` |
| Connection refused / authentication failed | Verify `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` and private `.pgpass`/`PGPASSFILE`. Compose uses port 55432 by default; native PostgreSQL often uses 5432. Scripts disable prompts with `-w` |
| Compose refuses a missing password | Copy `.env.example` to `.env` and supply your private `POSTGRES_PASSWORD`. Python still requires exported libpq settings; editing `.env` does not export them |
| Changed Compose password has no effect | Initialization settings only apply to a new volume. Update the existing database through authorized PostgreSQL administration; do not assume a container restart resets credentials |
| `dcmon already exists` | The safety check is working. Create/select a different empty database. The installer has no automatic drop/reset option |
| Permission denied creating extension/schema | Use an authorized restore owner; `btree_gist` may need administrator installation. The report role is intentionally not a restore owner |
| Relation/helper not found during writes or direct view calls | Set `search_path=dcmon,public`. Preserved trigger/helper functions can use unqualified names. Role/database settings in installation apply this to the report session |
| Catalog counts or descriptions differ | Confirm this repository's full fixture and metadata were restored, and that you are checking the intended database. `database.py comments` repairs descriptions only, not missing rows/schema |
| FineReport says connection not found | Create a named PostgreSQL connection exactly `DC_MONITORING` in the runtime handling the request. A Designer-only connection may not be configured on another server |
| Named connection works locally but not on server | Recheck host/port from the FineReport machine's perspective. `localhost` in a container is that container. Verify JDBC driver, PostgreSQL network access and the report role's grants |
| SQL syntax error at `${…}` in psql | FineReport expressions are placeholders. Use FineReport or the verifier, which safely binds the declared integer parameters |
| Report page loads but iframe is missing | Confirm installation wrote `DC_MONITORING_3D` under the runtime's actual webroot. Check static-file requests and the root `/webroot` context; do not install into the Git repository |
| JavaScript module MIME error | Use the installer: it deploys `.mjs` as `.js` and rewrites imports. Copying source modules manually can produce vendor static-server MIME failures |
| `Infrastructure unavailable` / missing payload | The iframe must receive base64 JSON from the report. Opening `index.html` alone has no payload. Check its URL fragment, dataset execution, payload decoding and same-origin report setup |
| Cross-page links go to the wrong place | Existing links assume `/webroot/decision/view/duchamp` and `DC_MONITORING%252FInfrastructure_Overview.fvs` in the browser URL. A proxy prefix/different context needs coordinated report and browser URL changes |
| Existing dashboard installation is refused | Review both existing DC targets. `--replace` explicitly permits their backed-up replacement; it does not update vendor configuration or other reports |
| Values do not change after refresh | Expected: the fixture is frozen at 21 October 2026, 14:32 MSK. There is no live collector |
| CPU/power chart contains gaps | Check missing/stale/error observations and coverage. NULLs intentionally remain gaps; power is withheld for incomplete selected-server coverage |
| A site maximum has `≥` | Some selected servers lack a valid CPU/RAM reading. The maximum of known values is only a lower bound for the full population |
| Healthy device appears in Issues | Reported device state and individual metric thresholds are independent; a disk/port may have a problem while device status is healthy |
| Queue counts differ from server totals | Issues are per problematic metric, fallback state or unique incident. One device can have multiple rows. Reset local queue search/severity/category controls as well as shared filters |
| Equipment remains after a software filter | Expected: servers follow the application path; network/facility equipment covers the selected site |
| History shows no matching device | An explicit requested device is outside scope or absent. Clear it to Auto-select, or reset the excluding site/application filters |
| IT selected a different server | IT intentionally falls back to the first ranked in-scope server if the requested server is excluded. History has stricter explicit-device empty semantics |
| Vendor watermark/banner appears | This belongs to the separately installed vendor runtime. Follow the vendor's licensing process; project scripts do not suppress notices or alter license files |
| `make audit` reports a local path or secret | Remove that content from public sources, including FVS XML/compressed SQL if reported. Keep personal settings, connection files and build backups outside the public allowlist |

The read-only [database verifier](../scripts/verify_database.py) is a fixture regression tool, not a production health checker. A passing verifier does not establish FineVIS runtime compatibility, browser rendering or licensing. Report runtime versions, page/filter choices and sanitized errors when seeking help; see [contribution guidance](../CONTRIBUTING.md).
