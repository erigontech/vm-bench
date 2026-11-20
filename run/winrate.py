#!/usr/bin/env python3
# winrate.py: Lab newPayload wins per client, one row per day and client: mainnet eip7870-block-builder reference nodes, and sepolia.
# Fetches the last 14 finished UTC days that no history/*/winrate.csv holds yet; writes them to history/<UTC now>/winrate.csv (sepolia: winrate-sepolia.csv)
# (day,client,wins). A day the API has no rows for is not written, so the next run asks again.
import csv, datetime, json, sys, urllib.request
from pathlib import Path

NETS = (("mainnet", "eip7870-block-builder", "winrate.csv"), ("sepolia", "", "winrate-sepolia.csv"))  # sepolia rows carry no node class
hist = Path(__file__).resolve().parent.parent / "history"
now = datetime.datetime.now(datetime.timezone.utc)
for net, cls, name in NETS:
    api = f"https://cbt-api-{net}.analytics.production.platform.ethpandaops.io/api/v1/fct_engine_new_payload_winrate_daily"
    have = {r[0] for f in hist.glob(f"*/{name}") for r in csv.reader(open(f))}
    rows = []
    for i in range(14, 0, -1):
        day = (now.date() - datetime.timedelta(days=i)).isoformat()
        if day in have:
            continue
        # the API answers 403 to urllib's default User-Agent
        req = urllib.request.Request(f"{api}?day_start_date_eq={day}&page_size=100", headers={"User-Agent": "vm-bench"})
        with urllib.request.urlopen(req, timeout=60) as r:
            got = json.load(r)["fct_engine_new_payload_winrate_daily"]
        assert len(got) < 100, f"{net} {day}: a full page, rows may be cut"
        rows += sorted((day, x["meta_execution_implementation"], x["win_count"]) for x in got if x["node_class"] == cls)
    if rows:
        out = hist / now.strftime("%Y-%m-%dT%H%M")
        out.mkdir(exist_ok=True)
        with open(out / name, "a", newline="") as f:
            csv.writer(f).writerows(rows)
    print(f"winrate {net}: {len({r[0] for r in rows})} new days", file=sys.stderr)
