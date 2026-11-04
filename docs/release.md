# Release preparation

This repository is prepared for publication. Packaging is local: it does not create a GitHub repository, push a branch, create a tag, upload an asset or change an installed demonstration. Choose a destination and publish deliberately after reviewing the complete package.

## Pre-release checks

Run from a clean working tree or an isolated review branch:

```sh
make build
make test
make audit
```

Review generated SQL, manifest, dataset XML and FVS changes. CI additionally expects rebuilding an unchanged checkout to produce no `dashboard/` diff. The source tests need no FineReport runtime. Restore a separate fresh PostgreSQL 16 database and run:

```sh
python3 scripts/database.py init
python3 scripts/verify_database.py --require-sequences
```

Confirm a repeat `init` refuses the existing `dcmon` schema. Do not run destructive cleanup against a shared environment. Follow the [demo walkthrough](demo-walkthrough.md) in your separately installed licensed runtime when a visual compatibility check is required. A clean database restore, source tests, report archive validation and native SQL execution do not imply a newly installed FineReport runtime or freshly verified vendor license. Record actual evidence and limitations in [validation](validation.md).

Review [MIT licensing](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md), generated-asset provenance, retained vendor banners, security guidance and the changelog. Recheck version claims against the actual tested runtime: the template's plugin metadata is an older provenance marker, not a minimum compatibility guarantee.

## Build the deterministic archive

```sh
make package
```

This re-runs the public-content audit, freezes the audited file bytes and writes:

- `dist/dc-monitoring-demo.zip`
- `dist/dc-monitoring-demo.zip.sha256`

The archive has a `dc-monitoring/` top-level directory and an internal `SHA256SUMS` listing every payload file except the checksum file itself. The sidecar hashes the final ZIP. File ordering, permissions and ZIP timestamps are fixed; the same source bytes produce identical archives. A build timestamp, Git history and local runtime are not inputs.

Inspect before distributing:

```sh
python3 -m zipfile -l dist/dc-monitoring-demo.zip
```

On macOS verify the archive sidecar from its directory with `shasum -a 256 -c dc-monitoring-demo.zip.sha256`; on Linux use `sha256sum -c dc-monitoring-demo.zip.sha256`. After unpacking, run the corresponding checksum command on `SHA256SUMS` from inside `dc-monitoring/`.

The public allowlist includes project source, database fixture, report definition, tests, documentation/screenshots, CI and configuration examples. It excludes `.git`, `.work`, `.superpowers`, planning notes under `docs/superpowers`, `build`, `dist`, local `.env`/password files, caches and vendor runtime binaries. The audit also inspects compressed SQL and FVS XML, checks named connections and local Markdown links. It is a review aid, not a proof that every possible secret format has been detected.

## Publish when ready

Configure your own Git author identity if needed; do not invent an identity for another contributor. Review `git status`, the staged diff and the archive, then create the intended commit using your normal workflow. Add the actual repository remote only after choosing it. Push/tag/release creation are separate external publication actions; none is performed by `package_release.py`.

For a hosted release, attach the ZIP and checksum sidecar, include the snapshot date, installation link and tested tool/runtime versions, and explain the separate proprietary FineReport/FineVIS dependency. Do not call it a standalone deployable FineReport distribution. GitHub Pages may host documentation; it cannot host the complete database-backed dashboard.

Keep a record of the archive digest, source revision, tests, database restore result and any visual review. Do not include local database passwords, connection files, installed runtime directories or backups in release notes or uploads.
