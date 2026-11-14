#!/usr/bin/env python3
"""Fails (exit 1) when an erigon section's newest history snapshot is older than 36 h, when the newest eth_call run has a
row where erigon's gasUsed differs from reth's (the two nodes replayed different work), or another client's weekly
"(measured <date>)" label on the page is older than 8 days, or a client failed a node-tier smoke test (SMOKE_FAIL in
$SMOKE_REPORT, default ~/vm-bench-weekly.txt); writes the verdict to the marker file. A section listed in
run/paused-sections.txt is reported as PAUSED instead of being checked."""
import csv
import datetime
import os
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
marker = pathlib.Path(os.environ.get("SELFCHECK_MARKER", pathlib.Path.home() / "vm-bench-selfcheck.txt"))
sections = {"EEST blocks": "blocktest.csv", "EEST sub-tests": "subtests.csv", "newPayload BAL-off": "node.csv",
            "newPayload BAL-on": "nodebal.csv", "eth_call": "calls.csv",
            "Goal: Lab win rate": "winrate.csv", "Goal: merged wins": "wins.csv"}
paused_file = root / "run" / "paused-sections.txt"
paused = paused_file.read_text().split("\n") if paused_file.exists() else []
paused = [name for name in paused if name in sections]
now = datetime.datetime.now(datetime.timezone.utc)
stale = []
for name, f in sections.items():
    if name in paused:
        continue
    dirs = sorted(d.name for d in (root / "history").iterdir() if (d / f).exists())
    if not dirs:
        stale.append(f"{name}: no data")
        continue
    t = datetime.datetime.strptime(dirs[-1][:15], "%Y-%m-%dT%H%M").replace(tzinfo=datetime.timezone.utc)
    if now - t > datetime.timedelta(hours=36):
        stale.append(f"{name}: {dirs[-1]} ({(now - t).total_seconds() / 3600:.0f} h)")
calls = sorted(d for d in (root / "history").iterdir() if (d / "calls.csv").exists())
if calls and "eth_call" not in paused:
    gas = {}
    for r in csv.reader(open(calls[-1] / "calls.csv")):
        if len(r) > 7 and r[7]:
            gas.setdefault(r[0], {})["erigon" if r[1].startswith("erigon") else r[1].split("-")[0]] = int(r[7])
    both = [(f, g["erigon"], g["reth"]) for f, g in gas.items() if "erigon" in g and "reth" in g]
    bad = [b for b in both if b[1] != b[2]]
    if bad:
        stale.append(f"eth_call: erigon gas differs from reth in {len(bad)} of {len(both)} rows of {calls[-1].name} "
                     f"(e.g. {bad[0][0].split('/')[-1]}: {bad[0][1]} vs {bad[0][2]})")
page = root / "docs" / "index.html"
for d in sorted(set(re.findall(r"\(measured (\d{4}-\d\d-\d\d)\)", page.read_text() if page.exists() else ""))):
    days = (now.date() - datetime.date.fromisoformat(d)).days
    if days > 8:
        stale.append(f"other clients measured {d} ({days} days)")
smoke = pathlib.Path(os.environ.get("SMOKE_REPORT", pathlib.Path.home() / "vm-bench-weekly.txt"))
for line in smoke.read_text().splitlines() if smoke.exists() else []:
    if " SMOKE_FAIL " in line:
        at, _, tier, client = line.split()[:4]
        stale.append(f"{client} failed the {tier} smoke test at {at}")
verdict = ("STALE " + "; ".join(stale)) if stale else "OK"
if paused:
    verdict += " PAUSED " + ", ".join(paused)
marker.write_text(f"{now:%Y-%m-%dT%H:%MZ} {verdict}\n")
print(f"selfcheck: {verdict}")
sys.exit(1 if stale else 0)
