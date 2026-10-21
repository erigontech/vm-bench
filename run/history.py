#!/usr/bin/env python3
"""Build docs/index.html from history/*/: the latest table and Mgas/s over time per client."""
import csv, json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
runs = []
for d in sorted(p for p in (root / "history").iterdir() if p.is_dir()):
    run = {"date": d.name, "versions": {}, "ns": {}, "rpc": [], "calls": {}, "bt": {}, "rpcw": [], "node": {}, "nodePass": {}, "nodebal": {}, "nodebalPass": {}, "callsneth": {}, "c1neth": {}}
    for f in d.glob("*.csv"):
        if f.name == "versions.csv":
            run["versions"] = dict(csv.reader(open(f)))
            continue
        if f.name == "blocktest.csv":
            for file, client, gas, ms, twin in csv.reader(open(f)):
                run["bt"].setdefault(file, {})[client] = {"gas": int(gas), "ms": int(ms), "twin": int(twin)}
            continue
        if f.name in ("node.csv", "nodebal.csv"):
            for test, client, mgas in csv.reader(open(f)):
                run[f.stem].setdefault(test, {})[client] = float(mgas)
            continue
        if f.name in ("pass.csv", "passbal.csv"):
            run["nodePass" if f.name == "pass.csv" else "nodebalPass"] = {client: float(r) for client, r in csv.reader(open(f))}
            continue
        if f.name == "rpcw.csv":
            run["rpcw"] = [dict(zip(("workload", "client", "rate", "rps", "p50", "p95", "p99", "err"), (r[0], r[1], *map(float, r[2:])))) for r in csv.reader(open(f))]
            continue
        if f.name in ("callsneth.csv", "c1neth.csv"):
            for r in csv.reader(open(f)):
                run[f.stem].setdefault(r[0], {})[r[1]] = dict(zip(("rps", "p50", "p99", "err"), map(float, r[2:])))
            continue
        if f.name == "calls.csv":
            for r in csv.reader(open(f)):
                run["calls"].setdefault(r[0], {})[r[1]] = dict(zip(("rps", "p50", "p99", "err"), map(float, r[2:])))
            continue
        if f.name == "rpc.csv":
            run["rpc"] = [dict(zip(("scenario", "client", "rps", "p50", "p99"), (r[0], r[1], *map(float, r[2:])))) for r in csv.reader(open(f))]
            continue
        for fixture, client, ns in csv.reader(open(f)):
            run["ns"].setdefault(fixture, {})[client] = int(ns)
    runs.append(run)
# The page shows only the latest node and blocktest tables.
for k in ("node", "nodePass", "nodebal", "nodebalPass", "bt"):
    for run in [r for r in runs if r[k]][:-1]:
        run[k] = {}
gas = {p.parent.name + "/" + p.stem: int(next(iter(json.load(open(p)).values()))["_info"]["gasUsed"], 16)
       for p in (root / "fixtures").glob("*/*.json")}
progress = root / "history" / "runs.json"
progress = json.load(open(progress)) if progress.exists() else []
html = (root / "run" / "page.html").read_text().replace("/*DATA*/", json.dumps({"runs": runs, "gas": gas, "progress": progress}))
(root / "docs").mkdir(exist_ok=True)
(root / "docs" / ".nojekyll").touch()
(root / "docs" / "index.html").write_text(html)
