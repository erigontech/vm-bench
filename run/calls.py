#!/usr/bin/env python3
"""eth_call request bodies for the mainnet fixtures: one JSON-RPC body per line, prefixed by the fixture
name and a tab, then the same call at "latest" after another tab. The call runs on the state before the
fixture's block, the closest an RPC node offers to the fixture's pre-state (transactions earlier in the
same block are not applied); the "latest" body is for a node that no longer keeps that state."""
import json, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
for p in sorted((root / "fixtures").glob("mainnet*/*.json")):
    fx = next(iter(json.load(open(p)).values()))
    tx, env = fx["transaction"], fx["env"]
    call = {"from": tx["sender"], "to": tx["to"], "gas": tx["gasLimit"][0], "value": tx["value"][0], "data": tx["data"][0]}
    if tx.get("accessLists") and tx["accessLists"][0]:
        call["accessList"] = tx["accessLists"][0]
    if "gasPrice" in tx:
        call["gasPrice"] = tx["gasPrice"]
    else:
        call["maxFeePerGas"], call["maxPriorityFeePerGas"] = tx["maxFeePerGas"], tx["maxPriorityFeePerGas"]
    block = hex(int(env["currentNumber"], 16) - 1)
    body = {"jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [call, block]}
    # Without its fee fields the call skips the balance check: the sender may hold no ETH at latest.
    latest = {**body, "params": [{k: v for k, v in call.items() if k not in ("gasPrice", "maxFeePerGas", "maxPriorityFeePerGas")}, "latest"]}
    print(p.parent.name + "/" + p.stem, json.dumps(body, separators=(",", ":")), json.dumps(latest, separators=(",", ":")), sep="\t")
