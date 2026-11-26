#!/usr/bin/env python3
"""confirm.py <history dir>: BAL-on families whose erigon median dropped >=5% against the previous erigon BAL-on night are
re-run interleaved (previous main, tonight's main, 3 rounds each, same box) by run/confirm.sh, twice when the first re-run is\nalso >=5% slower; history/<newest>/confirm.csv
gets family, nightly ratio, re-run ratio and CONFIRMED or NOISE. The journal reports only CONFIRMED rows.
Only the CONFIRM_MAX (default 8) worst families are re-run, ~6 min each, so the nightly ends in its window; the rest are
written as SKIPPED."""
import csv, os, pathlib, statistics, subprocess, sys
MAX = int(os.environ.get("CONFIRM_MAX", "8"))

hist = pathlib.Path(sys.argv[1])
def load(d):
    out = {}
    for r in csv.reader(open(d / "nodebal.csv")):
        if len(r) >= 3 and r[1] == "erigon":
            try:
                out[r[0]] = float(r[2])
            except ValueError:
                pass
    return out
def erigon_sha(d):
    for line in open(d / "versions.csv"):
        if line.startswith("erigon,"):
            return line.strip().split(",")[1].split("-")[-1]
def rerun_ratio(prev, cur, f):
    out = subprocess.run(["run/confirm.sh", erigon_sha(prev), erigon_sha(cur), f + "["], capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.startswith("RATIO "):
            return float(line.split()[1])
    return None
def family(test):
    return test.split("::")[-1].split("[")[0]

nights = [d for d in sorted(hist.iterdir()) if (d / "nodebal.csv").exists() and load(d)]
if len(nights) < 2:
    sys.exit(0)
prev, cur = nights[-2], nights[-1]
a, b = load(prev), load(cur)
fams = {}
for t in a.keys() & b.keys():
    fams.setdefault(family(t), []).append(b[t] / a[t])  # Mgas/s: below 1 is slower
dropped = sorted((statistics.median(r), f) for f, r in fams.items() if statistics.median(r) <= 0.95)
rows = []
for ratio, f in dropped[MAX:]:
    rows.append([f, f"{ratio:.3f}", "", "SKIPPED"])
for ratio, f in dropped[:MAX]:
    reruns = []
    for _ in range(2):  # one 3-round re-run of a noisy family lands below 0.95 by chance; CONFIRMED needs two
        rerun = rerun_ratio(prev, cur, f)
        reruns.append(rerun)
        if rerun is None or rerun > 0.95:
            break
    worst = None if None in reruns else max(reruns)
    verdict = "FAILED" if worst is None else ("CONFIRMED" if len(reruns) == 2 and worst <= 0.95 else "NOISE")
    rows.append([f, f"{ratio:.3f}", " ".join("" if r is None else f"{r:.3f}" for r in reruns), verdict])
with open(cur / "confirm.csv", "w", newline="") as fh:
    csv.writer(fh).writerows([["family", "nightly_ratio", "rerun_ratio", "verdict"]] + rows)
for r in rows:
    print("confirm:", *r)
