#!/usr/bin/env python3
# history-selftest.py: run/history.py on throwaway node-tier histories; a peer filled in from another run is stale past
# VMB_PEER_DAYS (default 2) or on other fixtures, and a same-run peer never is.
import json, subprocess, sys, tempfile
from pathlib import Path

T = "benchmark/compute/instruction/test_x.py::test_x[fork_Osaka-benchmark-gas-value_150M]"


def stale(runs):
    with tempfile.TemporaryDirectory() as d:
        for date, fixtures, clients in runs:
            (Path(d) / date).mkdir()
            (Path(d) / date / "versions.csv").write_text(f"fixtures,{fixtures}\n")
            (Path(d) / date / "node.csv").write_text("".join(f"{T},{c},100\n" for c in clients))
        subprocess.run([sys.executable, Path(__file__).with_name("history.py"), d, f"{d}/page.html", "selftest"], check=True)
        html = Path(d, "page.html").read_text()
        data = json.loads(html[html.index("const data = ") + 13:].split(";\n", 1)[0])
        return next(r for r in reversed(data["runs"]) if r["node"])["nodeStale"]


fx, peers = "tests-benchmark@v0.0.9", ["reth", "nethermind", "geth"]
got = sorted(stale([("2026-11-21T0122", fx, peers), ("2026-11-26T2305", fx, ["erigon"])]))
assert got == ["geth 2026-11-21", "nethermind 2026-11-21", "reth 2026-11-21"], got
assert stale([("2026-11-24T2306", fx, peers), ("2026-11-26T2305", fx, ["erigon"])]) == []
assert stale([("2026-11-26T2300", "tests-benchmark@v0.1.0", peers), ("2026-11-26T2305", fx, ["erigon"])]) != []
assert stale([("2026-11-26T2305", fx, ["erigon"] + peers)]) == []
print("history-selftest OK")
