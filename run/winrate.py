#!/usr/bin/env python3
# winrate.py: Lab mainnet newPayload wins per client of the eip7870-block-builder reference nodes, one row per day and client.
# Fetches the last 14 finished UTC days that no history/*/winrate.csv holds yet; writes them to history/<UTC now>/winrate.csv
# (day,client,wins). A day the API has no rows for is not written, so the next run asks again.
import csv, datetime, json, sys, urllib.request
from pathlib import Path

API = "https://cbt-api-mainnet.analytics.production.platform.ethpandaops.io/api/v1/fct_engine_new_payload_winrate_daily"
CLASS = "eip7870-block-builder"
hist = Path(__file__).resolve().parent.parent / "history"
have = {r[0] for f in hist.glob("*/winrate.csv") for r in csv.reader(open(f))}
now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for i in range(14, 0, -1):
    day = (now.date() - datetime.timedelta(days=i)).isoformat()
    if day in have:
        continue
    # the API answers 403 to urllib's default User-Agent
    req = urllib.request.Request(f"{API}?day_start_date_eq={day}&page_size=100", headers={"User-Agent": "vm-bench"})
    with urllib.request.urlopen(req, timeout=60) as r:
        got = json.load(r)["fct_engine_new_payload_winrate_daily"]
    assert len(got) < 100, f"{day}: a full page, rows may be cut"
    rows += sorted((day, x["meta_execution_implementation"], x["win_count"]) for x in got if x["node_class"] == CLASS)
if rows:
    out = hist / now.strftime("%Y-%m-%dT%H%M")
    out.mkdir(exist_ok=True)
    with open(out / "winrate.csv", "a", newline="") as f:
        csv.writer(f).writerows(rows)
print(f"winrate: {len({r[0] for r in rows})} new days", file=sys.stderr)
