#!/usr/bin/env python3
"""calls-match.py BASE.csv OTHER.csv...: calls.sh rows of several clients, kept only where every client ran the row at the same
at and executed the same gas; a row that differs is left out and named on stderr, so no ratio compares different calls."""
import csv, sys

runs = [{r[0]: r for r in csv.reader(open(f))} for f in sys.argv[1:]]
w = csv.writer(sys.stdout)
for fixture, base in runs[0].items():
    rows = [run.get(fixture) for run in runs]
    if any(r is None for r in rows):
        print(f"{fixture}: not run by every client", file=sys.stderr)
        continue
    if len({(r[6], r[7]) for r in rows}) > 1:
        print(f"{fixture}: not comparable: " + ", ".join(f"{r[1]} at {r[6]} gas {r[7]}" for r in rows), file=sys.stderr)
        continue
    for r in rows:
        w.writerow(r)
