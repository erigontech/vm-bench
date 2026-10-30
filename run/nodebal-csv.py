#!/usr/bin/env python3
# nodebal-csv.py RESULTS_PREFIX OUTDIR CLIENT...: newPayload Mgas/s of the "test" step per test and client from <prefix>-p{1,2}-<client>.
# Drops the first test of every genesis group in run order (fresh container: warm-up). Writes OUTDIR/nodebal.csv (test,client,mgas =
# mean of the passes, only tests valid in both passes of that client) and OUTDIR/passbal.csv (client,pass2/pass1 geomean), prints
# coverage, geomean over the tests valid for every client and erigon's furthest-behind families.
import csv, glob, json, math, re, sys

pre, out, C = sys.argv[1], sys.argv[2], sys.argv[3:]
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
both = {c: set(runs[c, 1][0]) & set(runs[c, 2][0]) for c in C}
mean = {(t, c): (runs[c, 1][0][t] + runs[c, 2][0][t]) / 2 for c in C for t in both[c]}
with open(f"{out}/nodebal.csv", "w", newline="") as f:
    csv.writer(f).writerows((t, c, f"{mean[t, c]:.2f}") for t in sorted(set().union(*both.values())) for c in C if (t, c) in mean)
pp = {c: g([runs[c, 2][0][t] / runs[c, 1][0][t] for t in both[c]]) for c in C}
with open(f"{out}/passbal.csv", "w") as f:
    f.writelines(f"{c},{pp[c]:.4f}\n" for c in C)
common = sorted(set.intersection(*both.values()))
hero = [t for t in common if "/precompile/" not in t]
gm = {c: g([mean[t, c] for t in hero]) for c in C}
print(f"VERDICT {len(hero)} hero tests valid for all; geomean " + ", ".join(f"{c} {gm[c]:.1f} p2/p1 {100 * (pp[c] - 1):+.2f}% ({len(both[c])} valid)" for c in C))
fam = lambda t: re.sub(r"\[.*", "", t.split("::")[1])
fams = {}
for t in hero:
    fams.setdefault(fam(t), []).append(t)
if "erigon" in C and len(C) > 1:
    rows = []
    for k, ts in fams.items():
        best = max((c for c in C if c != "erigon"), key=lambda c: g([mean[t, c] for t in ts]))
        rows.append((g([mean[t, "erigon"] for t in ts]) / g([mean[t, best] for t in ts]), k, best, len(ts)))
    print("erigon families furthest behind the best other client:")
    for r in sorted(rows)[:8]:
        print(f"  {r[0]:.2f} vs {r[2]} {r[1]} ({r[3]} tests)")
