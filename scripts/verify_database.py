#!/usr/bin/env python3
"""Verify the restored fixture, metadata coverage and all 22 report datasets.

Every query runs in an explicit READ ONLY transaction at a fixed display timezone.
The checks intentionally use source contracts: inventory cardinality, nullable
telemetry, exact issue grain, scoped empty results and known disk/port histories.
This is a synthetic fixture regression check, not a production health checker.
Connection settings and PSQL follow scripts/database.py. Owner-side restore
verification uses --require-sequences; report readers without SELECT privileges
on sequences retain structural checks and explicitly skip allocation-state reads.
"""

import argparse
import base64
from collections import Counter
import json
from pathlib import Path
import re

from database import ROOT, psql


def rows(sql):
    """Serialize result rows in PostgreSQL so NULL and numeric values survive."""
    statement = ("BEGIN READ ONLY; SET LOCAL search_path=dcmon,public; "
                 "SET LOCAL TIME ZONE 'Europe/Moscow'; SET LOCAL statement_timeout='120s'; "
                 "SELECT coalesce(json_agg(result),'[]'::json) FROM (\n" +
                 sql.strip().rstrip(";") + "\n) result; COMMIT;")
    return json.loads(psql("-Atq", "-c", statement, capture_output=True, text=True).stdout)


def query(name, **parameters):
    """Bind only declared integer report parameters; never interpolate user SQL."""
    manifest = json.loads((ROOT / "dashboard/datasets.json").read_text())
    item = next(item for item in manifest if item["name"] == name)
    if set(parameters) - set(item["parameters"]):
        raise ValueError("Unknown parameter for dataset " + name)
    values = {**item["parameters"], **parameters}
    for value in values.values():
        if type(value) is not int:
            raise ValueError("Dataset parameters must be integers.")
    sql = (ROOT / "dashboard" / item["file"]).read_text()
    sql = re.sub(r"\$\{INT\((?:NVL\()?([a-z_]+)(?:,0\))?\)\}",
                 lambda match: str(values[match[1]]), sql)
    if "${" in sql:
        raise ValueError("Unsupported FineReport parameter expression.")
    return rows(sql)


def payload(name, **parameters):
    """Decode the same UTF-8/base64 JSON transport used by the browser iframe."""
    return json.loads(base64.b64decode(query(name, **parameters)[0]["payload_base64"]))


def require(condition, message):
    """Raise even with Python optimization enabled; assertions must not disappear."""
    if not condition:
        raise RuntimeError(message)


def quote_identifier(value):
    """Quote catalog identifiers without treating their contents as SQL."""
    return '"' + value.replace('"', '""') + '"'


def verify_sequences(catalog, require_states=False):
    """Check identity ownership and allocation without calling nextval/setval.

    Identity columns have an internal pg_depend dependency (deptype i), often
    no nextval default. Inspect dependencies and pg_sequence rather than
    inferring ownership from a column default or a sequence name. SELECT on a
    sequence is sufficient to inspect state; USAGE/UPDATE is never requested.
    Reporting roles may omit SELECT on sequences. Their structural checks still
    run, while --require-sequences makes unreadable state a verification error.
    This exact-state invariant targets a freshly restored synthetic fixture;
    generated IDs consumed by normal writes can legitimately advance it later.
    """
    actual = rows("""SELECT s.relname name, tn.nspname table_schema,
        t.relname table_name, a.attname column_name,
        t.relname||'.'||a.attname owned_by, d.deptype dependency_type,
        CASE a.attidentity WHEN 'd' THEN 'BY DEFAULT'
             WHEN 'a' THEN 'ALWAYS' ELSE NULL END identity_generation,
        CASE WHEN t.oid IS NOT NULL THEN
          pg_get_serial_sequence(format('%I.%I',tn.nspname,t.relname),a.attname)
          END assigned_sequence,
        q.seqstart start_value, q.seqincrement increment_by, q.seqmin min_value,
        q.seqmax max_value, q.seqcycle cycle, q.seqcache cache_size,
        has_sequence_privilege(s.oid,'SELECT') readable
        FROM pg_class s JOIN pg_namespace n ON n.oid=s.relnamespace
        JOIN pg_sequence q ON q.seqrelid=s.oid
        LEFT JOIN pg_depend d ON d.classid='pg_class'::regclass
          AND d.objid=s.oid AND d.refclassid='pg_class'::regclass AND d.deptype IN ('a','i')
        LEFT JOIN pg_class t ON t.oid=d.refobjid
        LEFT JOIN pg_namespace tn ON tn.oid=t.relnamespace
        LEFT JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=d.refobjsubid
        WHERE n.nspname='dcmon' AND s.relkind='S' ORDER BY s.relname""")
    wanted = {item['name']: item for item in catalog['sequences']}
    require(len(actual) == len(wanted) == 22 and
            {item['name'] for item in actual} == set(wanted),
            'Identity sequence set differs from the 22 published sequences.')
    keys = ('table_name', 'column_name', 'owned_by', 'dependency_type',
            'identity_generation', 'start_value', 'increment_by', 'min_value',
            'max_value', 'cycle', 'cache_size')
    checked, skipped = 0, []
    for sequence in actual:
        name = sequence['name']
        expected = wanted[name]
        require(sequence['table_schema'] == 'dcmon' and
                sequence['assigned_sequence'] == 'dcmon.' + name and
                all(sequence[key] == expected[key] for key in keys),
                'Identity ownership or definition mismatch: ' + name)
        if not sequence['readable']:
            skipped.append(name)
            continue
        table = 'dcmon.' + quote_identifier(sequence['table_name'])
        column = quote_identifier(sequence['column_name'])
        state = rows('SELECT last_value, is_called, (SELECT max(' + column +
                     ') FROM ' + table + ') max_id FROM dcmon.' +
                     quote_identifier(name))[0]
        maximum = state['max_id']
        expected_last = expected['start_value'] if maximum is None else maximum
        expected_called = maximum is not None
        next_value = (state['last_value'] + sequence['increment_by']
                      if state['is_called'] else state['last_value'])
        expected_next = (expected['start_value'] if maximum is None else
                         maximum + sequence['increment_by'])
        require(state['last_value'] == expected_last and
                state['is_called'] == expected_called and next_value == expected_next,
                'Identity sequence state mismatch: %s last_value=%s is_called=%s '
                'max_id=%s next_value=%s; expected last_value=%s is_called=%s next_value=%s.' %
                (name, state['last_value'], state['is_called'], maximum, next_value,
                 expected_last, expected_called, expected_next))
        require(sequence['min_value'] <= next_value <= sequence['max_value'],
                'Identity sequence would exhaust on next insert: ' + name)
        checked += 1
    require(not require_states or not skipped,
            'Sequence state checks require SELECT on all sequences; unreadable: ' +
            ', '.join(skipped))
    print('Verified', len(actual), 'identity sequence ownership/definitions and',
          checked, 'allocation states without consuming IDs.', flush=True)
    if skipped:
        print('Skipped sequence state checks for', len(skipped),
              'sequences: SELECT privilege unavailable. Use --require-sequences '
              'with the database owner for strict restore verification.', flush=True)


def verify(require_sequences=False):
    catalog = json.loads((ROOT / "database/catalog.json").read_text())
    expected = {r["name"]: r for r in catalog["relations"]}
    actual = rows("""SELECT c.relname name, obj_description(c.oid,'pg_class') description
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='dcmon' AND c.relkind IN ('r','v')""")
    require({r["name"] for r in actual} == set(expected), "Schema relation set differs from catalog.")
    column_count = 0
    for relation in actual:
        name = relation["name"]
        require(relation["description"] == expected[name]["comment"], "Relation comment mismatch: " + name)
        columns = rows("""SELECT a.attname name, col_description(a.attrelid,a.attnum) description
            FROM pg_attribute a WHERE a.attrelid='dcmon.%s'::regclass
            AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum""" % name)
        wanted = {c["attname"]: c["comment"] for c in expected[name]["columns"]}
        require({c["name"]: c["description"] for c in columns} == wanted, "Column comment mismatch: " + name)
        for comment in [relation["description"], *wanted.values()]:
            require(bool(comment) and not re.search(r"[\u0400-\u04ff]", comment), "Missing or non-English metadata: " + name)
        column_count += len(columns)
        if expected[name]["kind"] == "table":
            count = rows('SELECT count(*) n FROM dcmon."' + name + '"')[0]["n"]
            require(count == expected[name]["demo_rows"], "Fixture row count mismatch: " + name)
    print("Verified", len(actual), "tables/views and", column_count, "English column descriptions.", flush=True)

    # Functions are part of the public database API, not just implementation
    # details; ensure their deployed descriptions match the published catalog.
    functions = rows("""SELECT p.proname, pg_get_function_identity_arguments(p.oid) args,
        obj_description(p.oid,'pg_proc') description FROM pg_proc p
        JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='dcmon'""")
    descriptions = {(f['proname'], f['args']): f['description'] for f in functions}
    expected_functions = {(f['proname'], f['args']): f['comment'] for f in catalog['functions']}
    require(descriptions == expected_functions, "Function descriptions differ from catalog.")
    print("Verified", len(functions), "English function descriptions.", flush=True)

    verify_sequences(catalog, require_states=require_sequences)

    manifest = json.loads((ROOT / "dashboard/datasets.json").read_text())
    results = {}
    for item in manifest:
        results[item["name"]] = query(item["name"])
        print("Dataset OK:", item["name"], flush=True)
    require(len(results) == 22, "Expected 22 dataset contracts.")
    scene = json.loads(base64.b64decode(results["scene_payload"][0]["payload_base64"]))
    for name, count in (("sites", 3), ("rooms", 6), ("racks", 48), ("servers", 972)):
        require(len(scene[name]) == count, "Scene inventory mismatch: " + name)
    issues = json.loads(base64.b64decode(results["problems_payload"][0]["payload_base64"]))["problems"]
    require(len(issues) == 13 and len({p["id"] for p in issues}) == 13, "Issue identifiers/grain changed.")
    require(Counter(p["severity"] for p in issues) == {"critical": 4, "warning": 7, "unknown": 2}, "Issue severity totals changed.")
    require(sum(p["category"] == "incident" for p in issues) == 1, "Incident count changed.")
    require(payload("problems_payload", p_site=999999)["problems"] == [], "Unknown site is not empty.")

    disk = payload("history_payload", p_history_device=91)
    require(disk["device"]["id"] == 91 and len(disk["times"]) == 25, "Selected-device history grain changed.")
    require(all(len(s["values"]) == 25 for s in disk["series"]), "History axis is not aligned.")
    hot = next(s for s in disk["series"] if s["labels"].get("disk") == "sdb" and s["code"] == "disk_c")
    require(hot["values"][-1] == 58, "Disk temperature fixture changed.")
    network = payload("history_payload", p_history_device=11)
    require(len({s["labels"]["port"] for s in network["series"] if s["labels"].get("port")}) == 24, "Switch port inventory changed.")
    busy = next(s for s in network["series"] if s["labels"].get("port") == "port-1" and s["code"] == "net_util_pct")
    require(busy["values"][-1] == 92, "Port utilization fixture changed.")
    stale = payload("history_payload", p_history_device=156)
    cpu = next(s for s in stale["series"] if s["code"] == "cpu_pct")
    require(cpu["values"][-1] is None and any(v is not None for v in cpu["values"]), "Missing CPU must remain a history gap.")
    excluded = payload("history_payload", p_history_device=91, p_site=1)
    require(excluded["device"] is None and excluded["series"] == [], "Excluded device leaked into history.")
    system_id = rows("SELECT ci_id FROM dcmon.ci WHERE ci_key='SYS-DBO'")[0]["ci_id"]
    software_id = rows("SELECT id FROM dcmon.software_product WHERE lower(name)='postgresql'")[0]["id"]
    filtered = payload("scene_payload", p_system=system_id, p_env=1, p_software=software_id)
    require(len(filtered["servers"]) == 2, "System/environment/software intersection changed.")
    print("Verified full inventory, issue counts, disk/port histories, missing data and intersecting filters.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-sequences', action='store_true',
                        help='Require SELECT access and exact restored allocation state for all 22 identities.')
    options = parser.parse_args()
    verify(require_sequences=options.require_sequences)
