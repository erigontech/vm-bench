#!/usr/bin/env python3
"""One block per file: the first test of the chosen gas variant from every EEST benchmark blockchain-test file goes to
blocktests/eest/<category>/<name>.json (category = instruction, precompile or scenario), its no-block twin
(same genesis, no blocks, post = pre) to blocktests/eest-twin/<category>/<name>.json.
One test per process keeps runners that execute a file's tests in parallel honest.
usage: run/eest-select.py <fixtures dir of benchmark@vX> [gas variant, default 150M]"""
import json, sys
from pathlib import Path

src, variant = Path(sys.argv[1]), (sys.argv[2] if len(sys.argv) > 2 else "150M")
root = Path(__file__).resolve().parent.parent
out, twin = root / "blocktests" / "eest", root / "blocktests" / "eest-twin"
files = tests = 0
for p in sorted((src / "blockchain_tests").rglob("*.json")):
    d = json.load(open(p))
    keep = dict(sorted((k, v) for k, v in d.items() if f"gas-value_{variant}" in k)[:1])
    if not keep: continue
    name = p.relative_to(src / "blockchain_tests" / "benchmark" / "compute").parts[0] + "/" + p.stem
    (out / name).parent.mkdir(parents=True, exist_ok=True); (twin / name).parent.mkdir(parents=True, exist_ok=True)
    json.dump(keep, open(out / f"{name}.json", "w"), separators=(",", ":"))
    json.dump({k: {**v, "blocks": [], "lastblockhash": v["genesisBlockHeader"]["hash"], "postState": v["pre"]} for k, v in keep.items()},
              open(twin / f"{name}.json", "w"), separators=(",", ":"))
    files += 1; tests += len(keep)
print(f"{files} files, {tests} tests, variant {variant}")
