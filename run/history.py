#!/usr/bin/env python3
"""Build docs/index.html from history/*/.
run/history.py <dir> <page> <branch>: the same page for a branch build, e.g. branches/dbg docs/dbg.html dbg."""
import csv, json, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
hidden = {"besu", "ethrex", "nimbus"}
runs = []
src, page, branch = (root / sys.argv[1], root / sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else (root / "history", root / "docs" / "index.html", None)
for d in sorted(p for p in src.iterdir() if p.is_dir()):
    run = {"date": d.name, "versions": {}, "ns": {}, "rpc": [], "calls": {}, "bt": {}, "rpcw": [], "node": {}, "nodePass": {}, "nodebal": {}, "nodebalPass": {}, "callsneth": {}, "st": {}, "stArms": [], "nodeab": {}, "nodeabArms": []}
    if (d / "errors.txt").exists():
        run["errors"] = (d / "errors.txt").read_text().split("\n")[:-1]
    for f in d.glob("*.csv"):
        if f.name == "versions.csv":
            run["versions"] = {c: v for c, v in csv.reader(open(f)) if c not in hidden}
            if "modes" in run["versions"]:
                run["versions"]["modes"] = "; ".join(m for m in run["versions"]["modes"].split("; ") if m.split(" ")[0] not in hidden)
            continue
        if f.name == "subtests.csv":
            for r in csv.reader(open(f)):  # a sub-test name may contain commas
                file, sub, (arm, gas, ms, twin) = r[0], ",".join(r[1:-4]), r[-4:]
                run["st"].setdefault(file, {}).setdefault(sub, {})[arm] = {"gas": int(gas), "ms": int(ms), "twin": int(twin)}
            continue
        if f.name == "nodeab.csv":
            run["nodeab"] = {t: {"a": float(a), "b": float(b)} for t, a, b in csv.reader(open(f))}
            continue
        if f.name == "nodeab-arms.csv":
            run["nodeabArms"] = [r for r in csv.reader(open(f))]
            continue
        if f.name == "subtest-arms.csv":
            run["stArms"] = [r for r in csv.reader(open(f))]
            continue
        if f.name == "blocktest.csv":
            for file, client, gas, ms, twin in csv.reader(open(f)):
                run["bt"].setdefault(file, {})[client] = {"gas": int(gas), "ms": int(ms), "twin": int(twin)}
            continue
        if f.name in ("node.csv", "nodebal.csv"):
            for test, client, mgas in csv.reader(open(f)):
                if client not in hidden:
                    run[f.stem].setdefault(test, {})[client] = float(mgas)
            continue
        if f.name in ("pass.csv", "passbal.csv"):
            run["nodePass" if f.name == "pass.csv" else "nodebalPass"] = {client: float(r) for client, r in csv.reader(open(f)) if client not in hidden}
            continue
        if f.name == "rpcw.csv":
            run["rpcw"] = [dict(zip(("workload", "client", "rate", "rps", "p50", "p95", "p99", "err"), (r[0], r[1], *map(float, r[2:])))) for r in csv.reader(open(f))]
            continue
        if f.name == "callsneth.csv":
            for r in csv.reader(open(f)):
                run[f.stem].setdefault(r[0], {})[r[1]] = dict(zip(("rps", "p50", "p99", "err", "gas"), map(float, r[2:])))
            continue
        if f.name == "calls.csv":
            for r in csv.reader(open(f)):
                run["calls"].setdefault(r[0], {})[r[1]] = {**dict(zip(("rps", "p50", "p99", "err"), map(float, r[2:6]))), "at": r[6] if len(r) > 6 else "block"}
            continue
        if f.name == "rpc.csv":
            run["rpc"] = [dict(zip(("scenario", "client", "rps", "p50", "p99"), (r[0], r[1], *map(float, r[2:])))) for r in csv.reader(open(f))]
            continue
        for fixture, client, ns in csv.reader(open(f)):
            run["ns"].setdefault(fixture, {})[client] = int(ns)
    runs.append(run)
# The page shows one table per tier: the latest dbg build (main + open PRs) unless a later day has a main run, else the latest run.
isdbg = lambda r: r["versions"].get("erigon", "").startswith("dbg")
for ks in (("node", "nodePass"), ("nodebal", "nodebalPass"), ("bt",), ("st", "stArms")):
    has = [r for r in runs if r[ks[0]]]
    d = [r for r in has if isdbg(r)]
    keep = d[-1] if d and d[-1]["date"][:10] >= has[-1]["date"][:10] else has[-1] if has else None
    for run in has:
        if run is not keep:
            for k in ks:
                run[k] = {}
progress = src / "runs.json"
progress = json.load(open(progress)) if progress.exists() else []
# eth_call fixture -> block, so the page can list the fixtures a node could not run.
callFixtures = {f"{p.parent.name}/{p.stem}": int(next(iter(json.load(open(p)).values()))["env"]["currentNumber"], 16) for p in root.glob("fixtures/mainnet*/*.json")}
html = (root / "run" / "page.html").read_text().replace("/*DATA*/", json.dumps({"runs": runs, "progress": progress, "branch": branch, "callFixtures": callFixtures}))
(root / "docs").mkdir(exist_ok=True)
(root / "docs" / ".nojekyll").touch()
page.write_text(html)
