#!/usr/bin/env python3
"""Fails (exit 1) when an erigon section's newest history snapshot is older than 36 h, or another client's weekly
"(measured <date>)" label on the page is older than 8 days; writes the verdict to the marker file. A section listed in
run/paused-sections.txt is reported as PAUSED instead of being checked."""
import datetime
import os
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
marker = pathlib.Path(os.environ.get("SELFCHECK_MARKER", pathlib.Path.home() / "vm-bench-selfcheck.txt"))
sections = {"EEST blocks": "blocktest.csv", "EEST sub-tests": "subtests.csv", "newPayload BAL-off": "node.csv",
            "newPayload BAL-on": "nodebal.csv", "eth_call": "calls.csv"}
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
page = root / "docs" / "index.html"
for d in sorted(set(re.findall(r"\(measured (\d{4}-\d\d-\d\d)\)", page.read_text() if page.exists() else ""))):
    days = (now.date() - datetime.date.fromisoformat(d)).days
    if days > 8:
        stale.append(f"other clients measured {d} ({days} days)")
verdict = ("STALE " + "; ".join(stale)) if stale else "OK"
if paused:
    verdict += " PAUSED " + ", ".join(paused)
marker.write_text(f"{now:%Y-%m-%dT%H:%MZ} {verdict}\n")
print(f"selfcheck: {verdict}")
sys.exit(1 if stale else 0)
