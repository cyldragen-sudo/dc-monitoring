#!/usr/bin/env python3
"""Build a deterministic source/demo archive from the reviewed public allowlist.

Run the audit first, freeze bytes in memory, then include SHA256SUMS for every
payload file. The checksum file excludes itself to avoid a circular checksum.
ZIP metadata uses a fixed date and regular read permissions; timestamps and Git
history never affect reproducibility. The sidecar checksum covers the final ZIP.
This command performs no network requests and never publishes a release.
"""

import hashlib
from pathlib import Path
import zipfile

from check_repository import ROOT, audit


def package():
    files = audit()
    payloads = {path.relative_to(ROOT).as_posix(): path.read_bytes() for path in files}
    checksums = "".join(hashlib.sha256(data).hexdigest() + "  " + name + "\n"
                        for name, data in sorted(payloads.items()))
    payloads["SHA256SUMS"] = checksums.encode("utf-8")
    target = ROOT / "dist/dc-monitoring-demo.zip"
    target.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(payloads.items()):
            info = zipfile.ZipInfo("dc-monitoring/" + name, date_time=(2026, 10, 21, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".zip.sha256").write_text(digest + "  " + target.name + "\n")
    print("Packaged", len(payloads), "files:", target)
    print("SHA256:", digest)


if __name__ == "__main__":
    package()
