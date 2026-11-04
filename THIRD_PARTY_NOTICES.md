# Third-party notices

## Project code

Original project code is distributed under the [MIT license](LICENSE). The notice does not relicense separately installed dependencies, vendor trademarks or material for which the project cannot grant rights. Synthetic fixture data and original explanatory documentation are supplied as part of this demonstration; no real customer/production dataset is represented.

## FineReport and FineVIS

FineReport and FineVIS are proprietary vendor products. They are not included in this repository or its release archive. Install an appropriately licensed runtime, plugin and required drivers separately under their applicable terms. The `.fvs` file is the project's report definition and refers to the named database connection `DC_MONITORING`; it is not the reporting engine.

The report records FineVIS v11 plugin metadata version 3.4.1. That historical template metadata is not proof of a minimum compatible runtime. The local existing demonstration uses FineVIS v11 4.13.0; exact FineReport patch compatibility is not asserted. See [validation](docs/validation.md) for what was actually checked. Project scripts do not modify licensing, remove notices or provide a licensing workaround. Screenshots retain the vendor runtime banner; visible vendor UI remains vendor material and does not imply endorsement.

## PostgreSQL and optional containers

PostgreSQL and its `btree_gist` extension are separately obtained dependencies under their own distribution terms. The optional Compose definition selects the `postgres:16` image; the image and its component software are not redistributed inside the release ZIP. Python, Node.js, Docker/Compose, the JDBC driver and CI actions also remain separately installed or remotely executed tooling under their respective terms. Native browser source tests require no npm packages.

## Illustration assets

Six generic raster illustrations are included under `dashboard/scene/assets`. Five have retained built-in ImageGen generation records dated 2026-10-26; the network overview illustration has a separate source record dated 2026-10-25. Prompts and reference basenames describe derivation from user-supplied concept images. See the [asset notes](dashboard/scene/assets/README.md) and [provenance manifest](dashboard/scene/assets/provenance.json) for recorded prompts, processing notes and final SHA-256 hashes.

These AI-generated illustrations are documented separately from the MIT project code. They show neutral equipment/architecture with no intended logos, labels or live status. Their generated content is not guaranteed unique; this notice makes no exclusive-rights or third-party-rights claim about reference material. Any reuse remains subject to rights in the supplied references and applicable generation-service terms. Do not treat a generic generated cabinet, port or building as a measured physical layout.

The network illustration is also embedded in the FVS as `dc-network-scene.png`. Source reference images and vendor binaries are not included. Public provenance removes personal filesystem paths while preserving generation instructions, reference basenames and asset integrity hashes.
