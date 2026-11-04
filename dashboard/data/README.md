# Browser regression fixture

`infrastructure-test-payload.json` is a small synthetic, pre-expansion inventory
used by the layout, navigation and scope tests. Its deliberately sparse racks
make unit positioning, excluded servers and incomplete measurements easy to
exercise without a database. It is not the full demo and is never installed as
runtime data. Display labels have been translated into English; stable IDs and
values remain unchanged. Unicode test strings in the test sources exercise label
length and do not appear in the dashboard UI.

The complete, current 972-server demo lives in
[`database/002_demo_data.sql.gz`](../../database/002_demo_data.sql.gz).
[`scripts/verify_database.py`](../../scripts/verify_database.py) verifies its
live SQL payload, inventory counts, filters and hardware histories separately.
