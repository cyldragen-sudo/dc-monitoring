#!/usr/bin/env python3
"""Audit the exact public file set, including compressed SQL and FineVIS XML.

The release allowlist deliberately excludes private scratch work, Git metadata,
build outputs and planning notes. This heuristic scan is a review aid, not a
guarantee against every secret format. It reports paths and categories, never
the matching secret. Local .env/.pgpass files must remain outside publication.
"""

import gzip
import json
from pathlib import Path
import re
import tokenize
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOP_FILES = {"README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "CONTRIBUTING.md",
             "SECURITY.md", "CHANGELOG.md", ".gitignore", ".env.example", "Makefile", "compose.yaml"}
TOP_DIRS = {"dashboard", "database", "docs", "scripts", "tests", ".github"}
EXCLUDED = {"__pycache__", "node_modules", ".DS_Store", "superpowers"}
TEXT_EXT = {".md", ".sql", ".json", ".xml", ".py", ".mjs", ".js", ".css", ".html", ".yaml", ".yml"}
REQUIRED = {"README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "CONTRIBUTING.md", "SECURITY.md",
            "database/001_schema.sql", "database/002_demo_data.sql.gz", "database/003_comments.sql",
            "database/catalog.json", "docs/installation.md", "docs/data-model.md", "docs/data-dictionary.md",
            "docs/dataset-contract.md", "dashboard/report/Infrastructure_Overview.fvs"}
PATTERNS = {
    "author machine path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "private key": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    "access token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b"),
    "credential URL": re.compile(r"(?:postgres(?:ql)?|https?)://[^\s/:]+:[^\s/@]+@"),
}


def public_files():
    """Return stable relative ordering and refuse symlinks in the public tree."""
    result = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if relative.parts[0] not in TOP_DIRS and str(relative) not in TOP_FILES:
            continue
        if any(part in EXCLUDED for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError("Public symlink is not permitted: " + str(relative))
        if path.is_file():
            result.append(path)
    return sorted(result, key=lambda p: p.relative_to(ROOT).as_posix())


def audit():
    """Check sources, Markdown links, SQL metadata and ZIP connection definitions."""
    failures = []
    files = public_files()
    missing = REQUIRED - {path.relative_to(ROOT).as_posix() for path in files}
    failures.extend("Required public file missing: " + name for name in sorted(missing))
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if (path.suffix not in TEXT_EXT | {".png", ".fvs", ".gz"} and path.name not in TOP_FILES
                or any(part in {".private", ".env", ".pgpass", "credentials", "vendor"} for part in path.relative_to(ROOT).parts)):
            failures.append(relative + ": prohibited artifact")
        contents = []
        if path.suffix == ".fvs":
            with zipfile.ZipFile(path) as archive:
                for name in archive.namelist():
                    if name.endswith((".tpl", ".chart", ".xml")):
                        value = archive.read(name).decode("utf-8")
                        contents.append((relative + "!" + name, value))
                        root = ET.fromstring(value)
                        if root.findall(".//Password"):
                            failures.append(relative + ": embedded password element")
                        for connection in root.findall(".//Connection"):
                            if connection.get("class") != "com.fr.data.impl.NameDatabaseConnection" or connection.findtext("DatabaseName", "").strip() != "DC_MONITORING":
                                failures.append(relative + ": nonportable database connection")
        elif path.suffix == ".gz":
            with gzip.open(path, "rt", encoding="utf-8") as stream:
                contents.append((relative, stream.read()))
        elif path.suffix in TEXT_EXT or path.name in TOP_FILES:
            contents.append((relative, path.read_text()))
        for label, value in contents:
            for category, pattern in PATTERNS.items():
                if pattern.search(value):
                    failures.append(label + ": " + category)
        if path.suffix == ".md":
            if re.search(r"[\u0400-\u04ff]", path.read_text()):
                failures.append(relative + ": non-English documentation")
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
                target = target.split("#")[0]
                if target and not re.match(r"[a-z]+:", target) and not (path.parent / target).exists():
                    failures.append(relative + ": missing local documentation target " + target)
        if path.suffix == ".py":
            with tokenize.open(path) as source:
                for token in tokenize.generate_tokens(source.readline):
                    if token.type == tokenize.COMMENT and re.search(r"[\u0400-\u04ff]", token.string):
                        failures.append(relative + ": non-English Python comment")
    manifest = json.loads((ROOT / "dashboard/datasets.json").read_text())
    with zipfile.ZipFile(ROOT / "dashboard/report/Infrastructure_Overview.fvs") as archive:
        root = ET.fromstring(archive.read("editor.tpl"))
    report_queries = {t.get("name"): t.findtext("Query", "").strip() for t in root.findall("TableDataMap/TableData")}
    if len(report_queries) != 22 or set(report_queries) != {d["name"] for d in manifest}:
        failures.append("Report dataset set differs from manifest")
    for item in manifest:
        if report_queries.get(item["name"]) != (ROOT / "dashboard" / item["file"]).read_text().strip():
            failures.append("Stale report SQL: " + item["name"])
    if failures:
        raise RuntimeError("Publication audit failed:\n" + "\n".join(failures))
    print("Publication audit passed:", len(files), "files; report SQL and portable connections verified.")
    return files


if __name__ == "__main__":
    audit()
