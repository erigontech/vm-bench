"""dropunapplied.py RESULTS_PREFIX HISTORY_DIR: drop from HISTORY_DIR/nodebal.csv every (test, client) row whose block the client
did not apply in either pass (benchmarkoor logged "Block number mismatch after rollback"), as run/nodebal-csv.py now does."""
import csv, glob, re, sys

pre, hist = sys.argv[1], sys.argv[2]
bad = set()
for log in glob.glob(f"{pre}-p[12]-*/runs/*/benchmarkoor.log"):
    client = re.search(r"-p[12]-([a-z]+)/", log)[1]
    for line in open(log):
        if "Block number mismatch after rollback" in line and (m := re.search(r'test="([^"]+)"', line)):
            bad.add((m[1], client))
rows = list(csv.reader(open(f"{hist}/nodebal.csv")))
keep = [r for r in rows if len(r) < 3 or (r[0], r[1]) not in bad]
csv.writer(open(f"{hist}/nodebal.csv", "w", newline="")).writerows(keep)
print(f"{hist}: dropped {len(rows) - len(keep)} rows; unapplied per client:", {c: sum(1 for _, x in bad if x == c) for c in sorted({x for _, x in bad})})
