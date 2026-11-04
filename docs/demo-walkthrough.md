# Demo walkthrough

Allow about ten minutes after [installation](installation.md). Reset system, environment, software and site to All. Keep the snapshot at **2026-10-21 14:32 MSK**; changing SQL to use today's date invalidates these expected results.

## 1. Establish the population

Open DC network (page 1). The physical scene contains 3 sites, 6 halls, 48 racks, 972 servers and 96 switches. Each server has two drives, for 1,944 in total. Look at the site cards and power history. Identify a missing-data marker and explain why incomplete coverage does not become a zero reading or a healthy state.

Open Issues (page 4). With all shared and local filters cleared, expect 13 issue rows: 4 critical, 7 warning, 2 unknown, on five devices, including one active incident. A single server or switch can have several issue rows. These are regression expectations for the full fixture, not a claim about a real installation.

## 2. Follow the North cooling context

Find `CRAC-02`, device ID **3**, and server `SRV-12-07`, ID **13**, in North. Use an issue's Equipment link to focus the room/device in Infrastructure, then inspect the rack containing server 13. The CRAC is floor equipment, with no rack U interval. The server's related incident is dependency context; it does not by itself prove application downtime.

Use the IT card link and return to Infrastructure. The return should reopen the rack with the server selected. Compare the physical rack occupancy with the selected-server count: filters must not erase installed equipment from occupied rack units.

## 3. Inspect an East disk

Select server `SRV-E-09`, ID **91**, in East, through Issues, Infrastructure or the History device selector. Open its **sdb** disk history. The latest `disk_c` point is **58°C**, above the critical threshold of **55°C**. The value at the threshold would not be critical because comparison is strictly greater.

Switch among the 30-minute, 60-minute and two-hour periods. The same aligned source payload has 7, 13 and 25 inclusive displayed points. Check usage, temperature, I/O, latency, IOPS and throughput as distinct units. Follow Equipment back to the disk focus; a disk index is a component selector, not a new device ID.

## 4. Inspect a switch port

Select `SW-12-01`, device ID **11**. Its History payload has **24 distinct ports**. Choose **port-1**; the final `net_util_pct` reading is **92%**. Compare receive/transmit Mbps with utilization percent and link 1/0. Inspect another port before assuming a down port is faulty: only an actively connected link reported down is critical.

Issue-to-History navigation should focus the matching series while leaving the other device series available. The corresponding Equipment link targets the inventory port ID, not its displayed ordinal.

## 5. Keep missing data visible

Select Reserve server `SRV-R-16`, ID **156**. Its CPU history contains known earlier readings and a NULL final point. The chart ends with a gap; the UI must not draw the line to zero or continue a flat last-known value. Compare reported status, metric availability and queue rows as separate signals. An unknown issue is actionable data-quality context, not a measured critical temperature.

## 6. Demonstrate intersecting filters

In IT · servers choose the business system identified by stable key **`SYS-DBO`**, environment **PROD** and software **PostgreSQL**. The verified scene server population for this intersection is **two physical servers**. Avoid assuming the system has the same numeric ID in a new dataset. Find IDs from the restored source or the filter datasets:

```sh
psql -X -w -c "SELECT s.ci_id, c.ci_key, c.name FROM dcmon.information_system s JOIN dcmon.ci c ON c.ci_id=s.ci_id WHERE c.ci_key='SYS-DBO';"
psql -X -w -c "SELECT id, code, name FROM dcmon.software_product WHERE lower(name)='postgresql';"
```

Review the software list and selected server's system associations. A host qualifies through the matching execution path, not merely because an unrelated VM on that host has PostgreSQL. Open Issues again: site equipment remains in scope while servers follow these application filters.

Select North alone while explicitly requesting East device 91 in History. The payload must have no chosen device and no series; it must not silently substitute a North device. Reset the excluding site or choose Auto-select device to recover.

## Optional direct links

Replace the host/port with your runtime. These examples preserve the current root `/webroot` convention:

```text
http://localhost:8075/webroot/decision/view/duchamp?viewlet=DC_MONITORING%252FInfrastructure_Overview.fvs&page_number=3&p_scene_target=91&p_scene_part=2
http://localhost:8075/webroot/decision/view/duchamp?viewlet=DC_MONITORING%252FInfrastructure_Overview.fvs&page_number=5&p_history_device=11
http://localhost:8075/webroot/decision/view/duchamp?viewlet=DC_MONITORING%252FInfrastructure_Overview.fvs&page_number=5&p_history_device=156
```

The first opens server 91's second disk; the others open switch and missing-data histories. Full report navigation requires the licensed runtime. The browser HTML files by themselves have no database connection or automatic payload.

## Reproduce the checks without FineReport

With the fixture restored and libpq variables/password file configured:

```sh
python3 scripts/verify_database.py
make test
```

The database verifier executes all 22 datasets and checks the full inventory, issue severity totals, East disk point, switch ports, Reserve missing-data gap and intersecting filters. Source tests validate browser interpretation and navigation plus isolated installer safety. These checks complement a visual pass through a separately installed runtime; they do not install or validate a vendor license.
