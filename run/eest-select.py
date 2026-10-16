#!/usr/bin/env python3
"""The first test of the chosen gas variant from every EEST benchmark blockchain-test file, repeated COPIES times (default 8)
so that process start-up and genesis setup are a small share even for nethtest, goes to blocktests/eest/<category>/<name>.json (category = instruction, precompile or scenario), its no-block twin
(same genesis, no blocks, post = pre) to blocktests/eest-twin/<category>/<name>.json.
The copies run one after another in every runner (nethtest with --parallelExecution false).
usage: run/eest-select.py <fixtures dir of benchmark@vX> [gas variant, default 150M] [copies, default 8]"""
import json, sys
from pathlib import Path

src, variant = Path(sys.argv[1]), (sys.argv[2] if len(sys.argv) > 2 else "150M")
copies = int(sys.argv[3]) if len(sys.argv) > 3 else 8
root = Path(__file__).resolve().parent.parent
out, twin = root / "blocktests" / "eest", root / "blocktests" / "eest-twin"
files = tests = 0
for p in sorted((src / "blockchain_tests").rglob("*.json")):
    d = json.load(open(p))
    first = sorted((k, v) for k, v in d.items() if f"gas-value_{variant}" in k)[:1]
    if not first: continue
    keep = {f"{first[0][0]}#{i}": first[0][1] for i in range(copies)}
    name = p.relative_to(src / "blockchain_tests" / "benchmark" / "compute").parts[0] + "/" + p.stem
    (out / name).parent.mkdir(parents=True, exist_ok=True); (twin / name).parent.mkdir(parents=True, exist_ok=True)
    json.dump(keep, open(out / f"{name}.json", "w"), separators=(",", ":"))
    json.dump({k: {**v, "blocks": [], "lastblockhash": v["genesisBlockHeader"]["hash"], "postState": v["pre"]} for k, v in keep.items()},
              open(twin / f"{name}.json", "w"), separators=(",", ":"))
    files += 1; tests += len(keep)
print(f"{files} files, {tests} blocks, variant {variant}, {copies} copies per file")
