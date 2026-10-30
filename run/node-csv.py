#!/usr/bin/env python3
# node-csv.py RESULTS_PREFIX OUTDIR: newPayload Mgas/s of the "test" step per test, client and pass from <prefix>-p{1,2}-<client>.
# Drops the first test of every genesis group (a fresh container: warm-up), keeps tests valid in all runs, writes OUTDIR/node.csv
# (test,client,mgas_s = mean of the passes) and OUTDIR/pass.csv (client,pass2/pass1 geomean), prints verdict and erigon's worst tests.
import csv, glob, json, math, sys

pre, out = sys.argv[1:3]
C = ["erigon", "reth", "nethermind", "geth"]
g = lambda xs: math.exp(sum(map(math.log, xs)) / len(xs))


def load(d):
    r = json.load(open(glob.glob(f"{d}/runs/*/result.json")[0]))
    seen, warm = set(), set()
    for t in json.load(open(glob.glob(f"{d}/suites/*/summary.json")[0]))["tests"]:
        if t["genesis"] not in seen:
            seen.add(t["genesis"])
            warm.add(t["name"])
    v = {}
    for n, t in r["tests"].items():
        a = t["steps"].get("test", {}).get("aggregated")
        if n not in warm and a and a["fail"] == 0 and a["success"] > 0 and a["gas_used_time_total"] > 0:
            v[n] = a["gas_used_total"] / a["gas_used_time_total"] * 1e3
    return v, len(r["tests"])


runs = {(c, p): load(f"{pre}-p{p}-{c}") for c in C for p in (1, 2)}
for (c, p), (v, n) in runs.items():
    print(f"run {c} p{p}: {len(v)} valid of {n}")
tests = sorted(set.intersection(*(set(v) for v, _ in runs.values())))
mean = {(t, c): (runs[c, 1][0][t] + runs[c, 2][0][t]) / 2 for t in tests for c in C}
with open(f"{out}/node.csv", "w", newline="") as f:
    csv.writer(f).writerows((t, c, f"{mean[t, c]:.2f}") for t in tests for c in C)
pp = {c: g([runs[c, 2][0][t] / runs[c, 1][0][t] for t in tests]) for c in C}
with open(f"{out}/pass.csv", "w") as f:
    f.writelines(f"{c},{pp[c]:.4f}\n" for c in C)
gm = {c: g([mean[t, c] for t in tests]) for c in C}
print(f"VERDICT {len(tests)} tests in all runs; geomean Mgas/s " + ", ".join(
    f"{c} {gm[c]:.1f} (x{gm['erigon'] / gm[c]:.2f} erigon/{c}, p2/p1 {100 * (pp[c] - 1):+.2f}%)" for c in C))
for c in C:
    if abs(pp[c] - 1) > 0.02:
        print(f"PASS_TO_PASS_OUTSIDE_2% {c} {100 * (pp[c] - 1):+.2f}%")
gap = sorted(tests, key=lambda t: mean[t, "erigon"] / max(mean[t, c] for c in C))
print("erigon furthest behind the best client:")
for t in gap[:5]:
    best = max(C, key=lambda c: mean[t, c])
    print(f"  {mean[t, 'erigon'] / mean[t, best]:.2f}  erigon {mean[t, 'erigon']:.1f} vs {best} {mean[t, best]:.1f}  {t}")
