#!/usr/bin/env python3
"""Rank mainnet contracts by gas used over the last BLOCKS blocks (default 200) and print one
representative transaction per contract: the successful call closest to that contract's median gas.
usage: run/popular.py [top] [blocks] [end block]   env VMBENCH_RPC (default https://eth.drpc.org)"""
import json, os, statistics, sys, urllib.request

rpc = os.environ.get("VMBENCH_RPC", "https://eth.drpc.org")
top, blocks = int(sys.argv[1]) if len(sys.argv) > 1 else 10, int(sys.argv[2]) if len(sys.argv) > 2 else 200

def call(method, *params):
    req = urllib.request.Request(rpc, json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": list(params)}).encode(), {"Content-Type": "application/json", "User-Agent": "vm-bench"})
    r = json.load(urllib.request.urlopen(req, timeout=60))
    if "error" in r: raise RuntimeError(r["error"])
    return r["result"]

head = int(sys.argv[3]) if len(sys.argv) > 3 else int(call("eth_blockNumber"), 16)
gas, txs = {}, {}
for n in range(head - blocks + 1, head + 1):
    for rc in call("eth_getBlockReceipts", hex(n)):
        to = rc.get("to")
        if not to or rc["status"] != "0x1": continue
        g = int(rc["gasUsed"], 16)
        gas[to] = gas.get(to, 0) + g
        txs.setdefault(to, []).append((g, rc["transactionHash"]))
    print(f"\r{n - head + blocks}/{blocks}", end="", file=sys.stderr)
print(file=sys.stderr)
total = sum(gas.values())
print(f"blocks {head - blocks + 1}..{head}, {total / 1e6:.0f} Mgas of successful calls")
print(f"{'contract':44} {'gas%':>5} {'txs':>6} {'median':>8}  representative tx")
for to, g in sorted(gas.items(), key=lambda kv: -kv[1])[:top]:
    if call("eth_getCode", to, "latest") == "0x": continue
    med = statistics.median(x[0] for x in txs[to])
    rep = min(txs[to], key=lambda x: abs(x[0] - med))
    print(f"{to:44} {100 * g / total:5.1f} {len(txs[to]):6} {int(med):8}  {rep[1]}")
