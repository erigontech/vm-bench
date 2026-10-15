#!/usr/bin/env python3
"""Mgas/s per client from the runners' CSV files, and erigon/client: above 1 means erigon is faster.

usage: run/compare.py results/*.csv
"""
import csv, json, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
ns = {}
for path in sys.argv[1:]:
    for fixture, client, t in csv.reader(open(path)):
        ns.setdefault(fixture, {})[client] = int(t)
clients = sorted({c for row in ns.values() for c in row}, key=lambda c: (c != "erigon", c))

def mgas(fixture, client):
    gas = int(next(iter(json.load(open(root / "fixtures" / (fixture + ".json"))).values()))["_info"]["gasUsed"], 16)
    return gas / ns[fixture][client] * 1e3

width = max(map(len, ns)) + 2
print("fixture".ljust(width) + "".join(f"{c:>12}" for c in clients) + "".join(f"{'erigon/' + c:>14}" for c in clients if c != "erigon"))
for fixture in sorted(ns):
    row = {c: mgas(fixture, c) for c in clients if c in ns[fixture]}
    cells = "".join(f"{row[c]:>12.1f}" if c in row else f"{'-':>12}" for c in clients)
    ratios = "".join(f"{row['erigon'] / row[c]:>14.2f}" if c in row and "erigon" in row else f"{'-':>14}" for c in clients if c != "erigon")
    print(fixture.ljust(width) + cells + ratios)
