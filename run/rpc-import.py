#!/usr/bin/env python3
"""history/<time>/rpc.csv from rpcenv.sh logs: scenario,client,rps,p50_ms,p99_ms, median over rounds of one arm.

usage: run/rpc-import.py [--arm base] <rpcenv log>...
"""
import re, statistics, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
args = sys.argv[1:]
arm = "base"
if args and args[0] == "--arm":
    arm, args = args[1], args[2:]
for path in args:
    text = Path(path).read_text()
    ref = re.search(r"\bref=([0-9a-f]{40})", text).group(1)
    stamp = re.search(r"/rpc-[0-9a-f]+-(\d{2})(\d{2})(\d{2})(\d{2})/", text)
    date = f"20{'26'}-{stamp.group(1)}-{stamp.group(2)}T{stamp.group(3)}{stamp.group(4)}"
    rows = {}
    for m in re.finditer(rf"^{arm}-r\d+ (\S+) rps=(\d+) err=\d+ p50=([\d.]+)ms p99=([\d.]+)ms", text, re.M):
        rows.setdefault(m.group(1), []).append(tuple(float(x) for x in m.group(2, 3, 4)))
    if not rows:
        sys.exit(f"{path}: no {arm}-r* lines")
    out = root / "history" / date
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "rpc.csv", "w") as f:
        for scenario, samples in sorted(rows.items()):
            med = [statistics.median(col) for col in zip(*samples)]
            f.write(f"{scenario},erigon-{ref[:8]},{med[0]:.0f},{med[1]:.2f},{med[2]:.2f}\n")
    print(out / "rpc.csv", len(rows), "scenarios")
