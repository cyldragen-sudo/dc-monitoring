# Contributing

Start with [development](docs/development.md), the [data model](docs/data-model.md) and [dataset contracts](docs/dataset-contract.md). This is a reproducible synthetic demonstration; preserve its identities, fixed snapshot, temporal rules, metric units, unavailable-data gaps and navigation unless the change explicitly revises those contracts.

Use a focused branch and describe the concrete problem and resulting behavior. Edit query builders rather than only generated SQL. Regenerate SQL/manifest/XML/FVS together with `make build`. Keep explanations, public documentation and code comments in English; stable identifiers and source test data are not display prose.

Before submitting a change:

1. Run `make test` and `make audit`.
2. For SQL/schema/fixture changes, restore a fresh isolated PostgreSQL 16 database and run `python3 scripts/verify_database.py`.
3. For interface or navigation changes, inspect all affected pages in your licensed runtime and follow the relevant walkthrough cases, including empty scope and missing telemetry.
4. Update contracts, guides, changelog and provenance when their meaning changes.

Include the tests actually run, tested runtime versions and any remaining limitations. A passing source suite does not establish a fresh vendor installation or browser rendering. Add regression coverage for meaningful changed behavior, including failure cases, rather than duplicating implementation internals.

Never submit passwords, completed `.env` files, PostgreSQL password files, private connection configurations, local machine paths, vendor binaries/JARs, license files, build backups or real operational data. FVS files are ZIP archives and can hide connection settings; the audit checks their XML, but reviewers must still inspect intended changes. Keep vendor notices intact.

Project-code contributions are made under the [MIT license](LICENSE). New third-party material must have a documented source and compatible permission; record generated-image provenance separately from code. Do not represent generated equipment illustrations as accurate inventory diagrams or source measurements.

For a bug report, provide the affected page, expected and actual behavior, shared/local filter choices, tool/runtime versions, sanitized error text and steps to reproduce using the synthetic fixture. Screenshots should retain vendor banners and exclude private connection details. For potential vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of posting sensitive details publicly.
