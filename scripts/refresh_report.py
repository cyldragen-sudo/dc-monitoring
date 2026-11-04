#!/usr/bin/env python3
"""Synchronize the portable FineVIS report with the checked-in SQL manifest.

This does not redesign the report: widget IDs, events, parameters, chart files,
images and named database connections remain intact. Only Query text changes.
Builders must be run first. Normal output goes to build/, so the reviewed source
report is not overwritten unless --output explicitly names it. ZIP timestamps
are fixed to make repeated builds byte-for-byte reproducible.
"""

import argparse
import copy
import html
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "dashboard/report/Infrastructure_Overview.fvs"


def xml_bytes(root):
    """Keep SQL in CDATA while safely handling the XML CDATA closing sequence."""
    value = ET.tostring(root, encoding="unicode")
    value = re.sub(r"<Query>(.*?)</Query>", lambda match:
                   "<Query><![CDATA[" + html.unescape(match[1]).replace("]]>", "]]]]><![CDATA[>") + "]]></Query>",
                   value, flags=re.S)
    return value.encode("utf-8")


def build(output):
    """Require the exact dataset set and portable named connections before writing."""
    manifest = json.loads((ROOT / "dashboard/datasets.json").read_text())
    with zipfile.ZipFile(REPORT) as archive:
        entries = {item.filename: archive.read(item) for item in archive.infolist()}
    root = ET.fromstring(entries["editor.tpl"])
    table_map = root.find("TableDataMap")
    tables = {table.get("name"): table for table in table_map.findall("TableData")}
    if set(tables) != {item["name"] for item in manifest}:
        raise ValueError("Dataset names differ between SQL manifest and report.")
    for item in manifest:
        table = tables[item["name"]]
        connection = table.find("Connection")
        if (connection.get("class") != "com.fr.data.impl.NameDatabaseConnection"
                or connection.findtext("DatabaseName", "").strip() != "DC_MONITORING"):
            raise ValueError("The report must use only the DC_MONITORING named connection.")
        actual_params = {p.get("name") for p in table.findall("Parameters/Parameter/Attributes")}
        if actual_params != set(item["parameters"]):
            raise ValueError("Dataset parameter contract changed: " + item["name"])
        table.find("Query").text = (ROOT / "dashboard" / item["file"]).read_text()
    entries["editor.tpl"] = xml_bytes(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 21, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)
    # This XML is useful when importing datasets separately in the Designer.
    (ROOT / "dashboard/datasets.xml").write_bytes(xml_bytes(copy.deepcopy(table_map)))
    print("Refreshed", len(tables), "datasets:", output.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/Infrastructure_Overview.fvs")
    build(parser.parse_args().output.resolve())
