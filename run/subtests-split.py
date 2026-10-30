#!/usr/bin/env python3
"""One fixture per 150M sub-test of the EEST compute benchmarks, and its no-block twin (same genesis, no blocks, post = pre),
for run/subtests.sh: blocktests/subtests/{t,w}/<n>.json and blocktests/subtests/index.tsv (n, category, file, gas, sub-test;
tab-separated with the sub-test last, as a sub-test name may contain commas). File names follow run/eest-select.py.
usage: run/subtests-split.py [fixtures_benchmark.tar.gz]   default testdata/fixtures_benchmark.tar.gz of tests-benchmark@v0.0.9,
downloaded if missing; its sha256 is checked either way."""
import hashlib, json, sys, tarfile, urllib.request
from collections import Counter
from pathlib import Path

URL = "https://github.com/ethereum/execution-specs/releases/download/tests-benchmark%40v0.0.9/fixtures_benchmark.tar.gz"
SHA256 = "5aee5d1bf7430d5b6ca5b48269dd2a1fb0f9df39ac1e980bac9fc56ad403b8c7"
root = Path(__file__).resolve().parent.parent
tgz = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "testdata" / "fixtures_benchmark.tar.gz"
if not tgz.exists():
    tgz.parent.mkdir(parents=True, exist_ok=True)
    part = tgz.with_suffix(".part")
    urllib.request.urlretrieve(URL, part)
    part.rename(tgz)
h = hashlib.sha256()
with open(tgz, "rb") as f:
    for b in iter(lambda: f.read(1024 * 1024), b""):
        h.update(b)
if h.hexdigest() != SHA256:
    sys.exit(f"{tgz}: sha256 {h.hexdigest()}, want {SHA256} (tests-benchmark@v0.0.9)")

out = root / "blocktests" / "subtests"
(out / "t").mkdir(parents=True, exist_ok=True); (out / "w").mkdir(parents=True, exist_ok=True)
rows = []
with tarfile.open(tgz) as tar:  # read in archive order: a .tar.gz cannot seek back
    for m in tar:
        p = Path(m.name)
        if not (m.isfile() and p.suffix == ".json" and {"blockchain_tests", "for_osaka_at_0150M", "compute"} <= set(p.parts)):
            continue
        cat = p.parts[p.parts.index("compute") + 1]
        for k, v in sorted(json.load(tar.extractfile(m)).items()):
            if "gas-value_150M" not in k:
                continue
            n = len(rows) + 1
            sub = k.split("[", 1)[1].rstrip("]").replace("fork_Osaka-blockchain_test-", "").replace("-benchmark-gas-value_150M", "")
            assert "\t" not in sub and "\n" not in sub, k
            gas = sum(int(b["blockHeader"]["gasUsed"], 16) for b in v["blocks"])
            json.dump({k: v}, open(out / "t" / f"{n}.json", "w"), separators=(",", ":"))
            w = {**v, "blocks": [], "lastblockhash": v["genesisBlockHeader"]["hash"], "postState": v["pre"]}
            w.pop("postStateHash", None)  # the original post root; nethtest checks it instead of postState
            json.dump({k: w}, open(out / "w" / f"{n}.json", "w"), separators=(",", ":"))
            rows.append((n, cat, p.parent.name, p.stem, gas, sub))
stems = Counter((cat, stem) for cat, mod, stem in {r[1:4] for r in rows})
rows = [(n, cat, (mod + "." if stems[cat, stem] > 1 else "") + stem, gas, sub) for n, cat, mod, stem, gas, sub in rows]
rows.sort(key=lambda r: r[1:3] + (r[4],))
open(out / "index.tsv", "w").write("".join("\t".join(map(str, r)) + "\n" for r in rows))
print(len(rows), "sub-tests in", out)
