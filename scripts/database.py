#!/usr/bin/env python3
"""Initialize an empty demo database, or update English object descriptions only.

Connection details come exclusively from libpq (PGHOST, PGPORT, PGDATABASE,
PGUSER, .pgpass/PGPASSFILE). PSQL may select an absolute client executable.
Passwords are never accepted as command-line arguments or written by this tool.
The destination database must already exist. No database or schema is dropped.

Initialization combines schema, the full compressed synthetic fixture, and
metadata in one PostgreSQL transaction. Any SQL error rolls everything back.
An existing dcmon schema is rejected, including a concurrent creator (CREATE
SCHEMA fails inside the transaction). Temporary decompressed data is private
and deleted on exit. The comments command changes descriptions, not data,
constraints, permissions, ownership, or definitions.
"""

import argparse
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def psql(*args, **kwargs):
    """Run a client without startup files, password prompts, or a shell.

    ON_ERROR_STOP makes COPY/DDL failures visible to automation. Connection
    failures must be fixed by the operator, never by falling back to another DB.
    """
    if not os.environ.get("PGDATABASE"):
        raise RuntimeError("Set PGDATABASE explicitly to the demo database.")
    return subprocess.run(
        [os.environ.get("PSQL", "psql"), "-X", "-w", "-v", "ON_ERROR_STOP=1", *args],
        check=True, **kwargs
    )


def scalar(sql):
    """Return an unaligned scalar result; used only for trusted internal SQL."""
    return psql("-Atq", "-c", sql, capture_output=True, text=True).stdout.strip()


def initialize():
    """Restore all objects and rows atomically, refusing an occupied namespace."""
    if scalar("SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='dcmon')") != "f":
        raise RuntimeError("Refusing initialization: dcmon already exists. Use a new database.")
    if int(scalar("SHOW server_version_num")) < 160000:
        raise RuntimeError("PostgreSQL 16 or newer is required; version 16 is validated.")
    with tempfile.TemporaryDirectory(prefix="dc-monitoring-") as temporary:
        script = Path(temporary) / "restore.sql"
        # Stream the largest input instead of holding a million rows in memory.
        with script.open("wb") as output:
            for name in ("001_schema.sql", "002_demo_data.sql.gz", "003_comments.sql"):
                source = ROOT / "database" / name
                opener = gzip.open if source.suffix == ".gz" else open
                with opener(source, "rb") as stream:
                    shutil.copyfileobj(stream, output)
                output.write(b"\n")
            output.write(b"ANALYZE;\n")
        psql("--single-transaction", "-q", "-f", str(script))
    print("Initialized dcmon; schema, synthetic data and English comments committed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "comments"))
    args = parser.parse_args()
    if args.command == "init":
        initialize()
    else:
        psql("--single-transaction", "-q", "-f", str(ROOT / "database/003_comments.sql"))
        print("Applied English descriptions only.")


if __name__ == "__main__":
    main()
