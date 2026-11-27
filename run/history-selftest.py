#!/usr/bin/env python3
# history-selftest.py: run/history.py on throwaway histories. A node-tier peer filled in from another run is stale past
# VMB_PEER_DAYS (default 2) or on other fixtures, and a same-run peer never is. A BAL-on test of run/cached-valid.txt leaves
# nodebal, so no mean uses it, and keeps every client's number in nodebalCached.
import json, subprocess, sys, tempfile
from pathlib import Path

T = "benchmark/compute/instruction/test_x.py::test_x[fork_Osaka-benchmark-gas-value_150M]"


def page(runs):
    with tempfile.TemporaryDirectory() as d:
        for date, files in runs:
            (Path(d) / date).mkdir()
            for name, text in files.items():
                (Path(d) / date / name).write_text(text)
        subprocess.run([sys.executable, Path(__file__).with_name("history.py"), d, f"{d}/page.html", "selftest"], check=True)
        html = Path(d, "page.html").read_text()
        return json.loads(html[html.index("const data = ") + 13:].split(";\n", 1)[0])["runs"]


def stale(runs):
    runs = page([(date, {"versions.csv": f"fixtures,{fixtures}\n", "node.csv": "".join(f"{T},{c},100\n" for c in clients)}) for date, fixtures, clients in runs])
    return next(r for r in reversed(runs) if r["node"])["nodeStale"]


fx, peers = "tests-benchmark@v0.0.9", ["reth", "nethermind", "geth"]
got = sorted(stale([("2026-11-21T0122", fx, peers), ("2026-11-26T2305", fx, ["erigon"])]))
assert got == ["geth 2026-11-21", "nethermind 2026-11-21", "reth 2026-11-21"], got
assert stale([("2026-11-24T2306", fx, peers), ("2026-11-26T2305", fx, ["erigon"])]) == []
assert stale([("2026-11-26T2300", "tests-benchmark@v0.1.0", peers), ("2026-11-26T2305", fx, ["erigon"])]) != []
assert stale([("2026-11-26T2305", fx, ["erigon"] + peers)]) == []

cv = next(l for l in Path(__file__).with_name("cached-valid.txt").read_text().split("\n") if l and not l.startswith("#"))
bal = "".join(f"{t},{c},100\n" for t in (T, cv) for c in ("erigon", "reth"))
r = next(r for r in page([("2026-11-27T0100", {"versions.csv": f"fixtures,{fx}\n", "nodebal.csv": bal})]) if r["nodebal"])
assert list(r["nodebal"]) == [T] and r["nodebalCached"] == {cv: {"erigon": 100.0, "reth": 100.0}}, r
print("history-selftest OK")
