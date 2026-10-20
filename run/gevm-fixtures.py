#!/usr/bin/env python3
"""Write blocktests/eest-gevm: the EEST fixtures with an explicit postState from geth's `evm blocktest --dump`.
gevm has no state trie, so it checks a postState account by account and ignores postStateHash."""
import glob, json, os, subprocess, sys

evm = os.environ.get("GETH_EVM", "evm")
for f in sorted(glob.glob("blocktests/eest/*/*.json")):
    out = f.replace("blocktests/eest/", "blocktests/eest-gevm/", 1)
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(f):
        continue
    r = subprocess.run([evm, "blocktest", "--dump", f], capture_output=True, text=True)
    dumps = {d["name"]: d for d in json.loads(r.stdout or "[]")}
    tests = json.load(open(f))
    for name, t in tests.items():
        d = dumps.get(name)
        if not d or not d["pass"]:
            sys.exit(f"{f}: geth did not pass {name}")
        t.pop("postStateHash", None)
        t["postState"] = {
            a: {
                "balance": hex(int(v["balance"])),
                "nonce": hex(v["nonce"]),
                "code": v.get("code", "0x"),
                "storage": {k: "0x" + (s.lstrip("0") or "0") for k, s in v.get("storage", {}).items()},
            }
            for a, v in d["state"]["accounts"].items()
        }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(tests, open(out, "w"))
    print(out)
