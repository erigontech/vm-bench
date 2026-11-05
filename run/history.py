#!/usr/bin/env python3
"""Build docs/index.html from history/*/.
run/history.py <dir> <page> <branch>: the same page for a branch build, e.g. branches/dbg docs/dbg.html dbg."""
import datetime
import csv, json, math, re, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
hidden = {"besu", "ethrex", "nimbus"}
runs = []
src, page, branch = (root / sys.argv[1], root / sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else (root / "history", root / "docs" / "index.html", None)
for d in sorted(p for p in src.iterdir() if p.is_dir()):
    run = {"date": d.name, "versions": {}, "bt": {}, "node": {}, "nodePass": {}, "nodebal": {}, "nodebalPass": {}, "st": {}, "stArms": [] }
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
                if not re.fullmatch(r"pr\d+", arm):
                    run["st"].setdefault(file, {}).setdefault(sub, {})[arm] = {"gas": int(gas), "ms": int(ms), "twin": int(twin)}
            continue
        if f.name == "subtest-arms.csv":
            run["stArms"] = [[r[0], ",".join(r[1:])] for r in csv.reader(open(f)) if not re.fullmatch(r"pr\d+", r[0])]  # a label may contain commas
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
            continue
    runs.append(run)
# Scenario blocks per run, before the per-tier pruning below drops older bt data: erigon's geometric mean Mgas/s and erigon / best client,
# both over cells that are not grey (twin under 30% of the run, net at least 100 ms, no setup block: gas at most 1.25e9, as the page's btGrey).
# revme and gevm compute no state root, so they are no peers.
def scenario_point(run):
    def mgas(f, c):
        x = run["bt"][f].get(c)
        return x["gas"] / (x["ms"] - x["twin"]) / 1e3 if x and x["ms"] - x["twin"] >= 100 and x["gas"] <= 1.25e9 and (c == "nethermind" or x["twin"] / x["ms"] <= 0.3) else None
    gm = lambda xs: math.exp(sum(map(math.log, xs)) / len(xs))
    files = [f for f in run["bt"] if f.startswith("scenario/")]
    e = {f: mgas(f, "erigon") for f in files}
    if not files or sum(v is not None for v in e.values()) * 2 < len(files):
        return None
    peers = {}
    for c in {c for f in files for c in run["bt"][f]} - {"erigon", "gevm", "revme"}:
        both = [f for f in files if e[f] and mgas(f, c)]
        if len(both) * 2 >= len(files):
            peers[c] = gm([e[f] for f in both]) / gm([mgas(f, c) for f in both])
    if not peers:
        return None
    best = min(peers, key=peers.get)
    build = run["versions"].get("erigon-evm") or run["versions"].get("erigon", "")
    return {"date": run["date"], "build": build, "blocks": len(files), "mgas": round(gm([v for v in e.values() if v]), 1),
            "ratio": round(peers[best], 3), "best": best}
scenario = list(map(scenario_point, (r for r in runs if r["bt"])))
# a trend whose newest run gives no point would show an old number as current
scenario = [p for p in scenario if p] if scenario and scenario[-1] else []
# The page shows one table per tier: the latest dbg build (main + open PRs) unless a later main run exists, else the latest run.
isdbg = lambda r: r["versions"].get("erigon", "").startswith("dbg")
for ks in (("node", "nodePass"), ("nodebal", "nodebalPass"), ("bt",), ("st", "stArms")):
    has = [r for r in runs if r[ks[0]]]
    d = [r for r in has if isdbg(r)]
    keep = d[-1] if d and d[-1] is has[-1] else has[-1] if has else None
    # A nightly sub-test run measures erigon builds only: keep each other client's column from its latest earlier run.
    if keep and ks[0] == "st":
        peers = {"nethermind", "geth", "revme", "evmone"}
        for old in reversed(has):
            if old is keep:
                continue
            for arm, label in old["stArms"]:
                if arm in peers and arm not in {a for a, _ in keep["stArms"]}:
                    keep["stArms"].append([arm, f"{label} (measured {old['date'][:10]})"])
                    for file, subs in old["st"].items():
                        for sub, row in subs.items():
                            if arm in row and sub in keep["st"].get(file, {}):
                                keep["st"][file][sub][arm] = row[arm]
    # A nightly node-tier run measures erigon only: fill each other client from its latest earlier run.
    if keep and ks[0] in ("node", "nodebal"):
        for old in reversed(has):
            if old is keep:
                continue
            for c in {c for row in old[ks[0]].values() for c in row} - {c for row in keep[ks[0]].values() for c in row}:
                for test, row in old[ks[0]].items():
                    if c in row and test in keep[ks[0]]:
                        keep[ks[0]][test][c] = row[c]
                if c in old[ks[1]]:
                    keep[ks[1]][c] = old[ks[1]][c]
                if c in old["versions"] and c not in keep["versions"]:
                    keep["versions"][c] = f"{old['versions'][c]} (measured {old['date'][:10]})"
    for run in has:
        if run is not keep:
            for k in ks:
                run[k] = {}
progress = src / "runs.json"
progress = json.load(open(progress)) if progress.exists() else []
stateful = src / "stateful.json"
stateful = json.load(open(stateful)) if stateful.exists() else None
html = (root / "run" / "page.html").read_text().replace("/*DATA*/", json.dumps({"runs": runs, "progress": progress, "stateful": stateful, "branch": branch, "layoutSensitive": [l for l in (root / "run" / "layout-sensitive.txt").read_text().split("\n") if l and not l.startswith("#")], "scenario": scenario, "updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"), "mainSha": next((r["versions"].get("erigon-evm", "")[5:] for r in reversed(runs) if r["versions"].get("erigon-evm", "").startswith("main-")), "")}))
(root / "docs").mkdir(exist_ok=True)
(root / "docs" / ".nojekyll").touch()
page.write_text(html)
