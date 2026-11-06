#!/usr/bin/env python3
"""Fails (exit 1) when a page section's newest history snapshot is older than 36 h; writes the verdict to the marker file."""
import datetime
import os
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
marker = pathlib.Path(os.environ.get("SELFCHECK_MARKER", pathlib.Path.home() / "vm-bench-selfcheck.txt"))
sections = {"EEST blocks": "blocktest.csv", "EEST sub-tests": "subtests.csv", "newPayload BAL-off": "node.csv",
            "newPayload BAL-on": "nodebal.csv", "eth_call": "calls.csv"}
now = datetime.datetime.now(datetime.timezone.utc)
stale = []
for name, f in sections.items():
    dirs = sorted(d.name for d in (root / "history").iterdir() if (d / f).exists())
    if not dirs:
        stale.append(f"{name}: no data")
        continue
    t = datetime.datetime.strptime(dirs[-1][:15], "%Y-%m-%dT%H%M").replace(tzinfo=datetime.timezone.utc)
    if now - t > datetime.timedelta(hours=36):
        stale.append(f"{name}: {dirs[-1]} ({(now - t).total_seconds() / 3600:.0f} h)")
verdict = ("STALE " + "; ".join(stale)) if stale else "OK"
marker.write_text(f"{now:%Y-%m-%dT%H:%MZ} {verdict}\n")
print(f"selfcheck: {verdict}")
sys.exit(1 if stale else 0)
