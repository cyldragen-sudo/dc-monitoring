# Security

This project is a synthetic demonstration, not a production monitoring service. It contains no live collection agent or production credentials. Use the current reviewed source and a separate demonstration database; no supported-version or security-response-time commitment is established yet.

## Report a vulnerability

Use the hosting repository's private vulnerability-reporting facility if one is available. Do not post passwords, private configurations, exploitable deployment details or complete operational payloads in a public issue. If private reporting is unavailable, open a minimal public issue requesting a private contact channel without disclosing the sensitive details. No private email address is configured in this prepared repository.

Include affected source revision, relevant file/page, reproduction using synthetic data, expected impact and a proposed fix if known. FineReport/FineVIS engine or licensing vulnerabilities should also be reported through the vendor's own security process; this project cannot patch or redistribute the proprietary engine.

## Operational boundaries

- Restore with a dedicated authorized owner and query through a separate non-owner read-only role. Configure `search_path=dcmon,public`; use only a trusted demonstration database/schema and review role inheritance and `PUBLIC` privileges on shared servers.
- Store passwords in private password files or protected runtime connection settings. Never embed credentials in FVS files, report URLs or committed `.env` files. Base64 payloads are readable data, not encrypted secrets.
- The optional Compose database binds localhost and uses a persistent volume. Its password is chosen by you. The fixed CI password applies only to the disposable CI service and must not be reused elsewhere.
- Report and iframe access control is provided by your vendor runtime and deployment. This project does not add user authentication, row-level authorization, TLS termination or a production authorization boundary around numeric report parameters.
- The installer writes only the selected DC report and static directory, refuses existing targets unless `--replace` is supplied, backs them up and rolls back failed replacement. Review the explicit webroot and existing targets before installation.
- Initialization refuses an existing `dcmon` schema and wraps restore in one transaction. It is not a migration/reset tool. Keep backups and operating-system permissions appropriate to your environment.

`make audit` checks publication contents for common secret formats, local paths, prohibited artifacts and nonportable report connections. It is a heuristic review aid and cannot detect every secret or unsafe configuration. The release ZIP includes synthetic data intended for distribution, not permission to distribute data from a real system. See [installation](docs/installation.md) and [release](docs/release.md).
