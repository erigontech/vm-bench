#!/usr/bin/env python3
"""balfix-genesis.py <fixtures> <template-group-dir> <out>: client genesis files for EEST engine_x pre_alloc groups, Amsterdam at 0.

Templates are one group of an EEST benchmark_genesis release (Osaka): config/params are kept, alloc and header are replaced."""
import json, sys
from pathlib import Path

# Nethermind schedules forks per EIP; the glamsterdam-devnet-8 set from benchmarkoor-tests clients.yaml.
NETH_EIPS = [2780, 7708, 7778, 7843, 7928, 7954, 7976, 7981, 7997, 8024, 8037, 8038, 8246, 8282]
fx, tpl, out = map(Path, sys.argv[1:4])
geth_t = json.load(open(tpl / "go-ethereum_default/genesis.json"))
besu_t = json.load(open(tpl / "besu_default/genesis.json"))
neth_t = json.load(open(tpl / "nethermind_default/chainspec.json"))
HDR = ("parentHash", "stateRoot", "hash", "transactionsTrie", "receiptTrie", "uncleHash", "bloom", "withdrawalsRoot", "requestsHash")
for f in sorted((fx / "blockchain_tests_engine_x/pre_alloc").glob("*.json")):
    g = json.load(open(f))
    assert g["network"] == "Amsterdam", (f, g["network"])
    h = g["genesis"]
    cid = int(g["chainId"], 16) if isinstance(g["chainId"], str) else g["chainId"]
    head = {k: h[k] for k in ("nonce", "timestamp", "extraData", "gasLimit", "difficulty", "mixHash", "coinbase", "number", "gasUsed",
                              "parentHash", "baseFeePerGas", "excessBlobGas", "blobGasUsed")}
    alloc = {a.lower(): v for a, v in g["pre"].items()}
    d = out / "genesis" / f.stem
    for name, t in (("go-ethereum_default", geth_t), ("besu_default", besu_t)):
        x = {k: v for k, v in t.items() if k not in HDR and k != "alloc"}
        ck = "chainId" if "chainId" in t["config"] else "chainID"
        x.update(head, config=dict(t["config"], **{ck: cid}, amsterdamTime=0), alloc=alloc)
        (d / name).mkdir(parents=True, exist_ok=True)
        json.dump(x, open(d / name / "genesis.json", "w"))
    c = dict(neth_t)
    c["params"] = dict(neth_t["params"], **{f"eip{n}TransitionTimestamp": "0x0" for n in NETH_EIPS}, chainID=hex(cid))
    c["genesis"] = dict(neth_t["genesis"], timestamp=h["timestamp"], gasLimit=h["gasLimit"], baseFeePerGas=h["baseFeePerGas"],
                        difficulty=h["difficulty"], author=h["coinbase"])
    builtins = {a: v for a, v in neth_t["accounts"].items() if "builtin" in v}
    c["accounts"] = {**builtins, **alloc}
    (d / "nethermind_default").mkdir(parents=True, exist_ok=True)
    json.dump(c, open(d / "nethermind_default/chainspec.json", "w"))
    print(f.stem, len(alloc), len(g.get("testIds", [])), "expect genesis", h["hash"])
