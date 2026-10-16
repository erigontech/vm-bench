#!/usr/bin/env python3
"""Build workloads/<name>/ from a request corpus: requests.jsonl (one JSON-RPC body per line), rates, README.
Input: a vegeta targets file (JSON lines with a base64 body) or a file with one JSON-RPC body per line.
A "latest" block tag is pinned to BLOCK so every node serves the same state.
usage: run/rpc-workload.py <name> <corpus file> <pinned block number> <rates...>  (env NOTE=<one line of provenance>)"""
import base64, collections, json, os, re, sys
from pathlib import Path

name, src, block = sys.argv[1], sys.argv[2], int(sys.argv[3])
rates = sys.argv[4:] or ["100", "1000", "3000"]
out = Path(__file__).resolve().parent.parent / "workloads" / name
out.mkdir(parents=True, exist_ok=True)
methods, blocks, n = collections.Counter(), [], 0
pin = hex(block)
with open(out / "requests.jsonl", "w") as w:
    for line in open(src):
        line = line.strip()
        if not line: continue
        row = json.loads(line)
        body = json.loads(base64.b64decode(row["body"])) if "body" in row and "method" in row and row["method"] == "POST" else row
        body["id"] = 1
        params = body.get("params", [])
        for i, p in enumerate(params):
            if p == "latest": params[i] = pin
            elif isinstance(p, dict) and p.get("fromBlock") == "latest": p["fromBlock"] = pin
            elif isinstance(p, dict) and p.get("toBlock") == "latest": p["toBlock"] = pin
        for p in params:
            if isinstance(p, str) and re.fullmatch(r"0x[0-9a-f]{1,8}", p): blocks.append(int(p, 16))
            if isinstance(p, dict):
                for k in ("fromBlock", "toBlock"):
                    if isinstance(p.get(k), str) and p[k].startswith("0x"): blocks.append(int(p[k], 16))
        methods[body["method"]] += 1; n += 1
        w.write(json.dumps(body, separators=(",", ":")) + "\n")
(out / "rates").write_text(" ".join(rates) + "\n")
share = "\n".join(f"{m:32} {100 * c / n:5.1f}%" for m, c in methods.most_common())
rng = f"{min(blocks)}..{max(blocks)}" if blocks else "none"
(out / "README").write_text(f"""{name}: {n} requests, {len(methods)} methods
{os.environ.get("NOTE", "")}
pinned block for "latest": {block}
blocks referenced: {rng}  (a node must hold their state and history)
rates (open loop, requests per second): {" ".join(rates)}

{share}
""")
print(f"{name}: {n} requests, blocks {rng}")
