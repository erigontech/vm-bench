#!/usr/bin/env python3
"""cached-valid.py SUITE_DIR > run/cached-valid.txt: the tests of a benchmarkoor suite (results/node/<run>/res-*/suites/<hash>)
whose test block (last newPayload) is byte-identical to an earlier test's block in suite order. Every client answers a block it
already has with a quick VALID, so such a test times no execution; run/history.py keeps it out of every BAL-on mean."""
import glob, json, os, sys

d = sys.argv[1]
tests = json.load(open(os.path.join(d, "summary.json")))["tests"]
reqs = {os.path.relpath(os.path.dirname(p), d): p for p in glob.glob(os.path.join(glob.escape(d), "**", "test.request"), recursive=True)}


def request(name):
    if name in reqs:
        return reqs[name]
    # benchmarkoor cuts a long test dir name and appends -<16 hex>
    m = [p for k, p in reqs.items() if len(k) > 17 and k[-17] == "-" and name.startswith(k[:-17])]
    assert len(m) == 1, (name, len(m))
    return m[0]


seen = {}
print(f"# BAL-on tests whose block repeats an earlier test's block (cached VALID). run/cached-valid.py, suite {os.path.basename(d.rstrip('/'))}")
for t in tests:
    h = [r for r in map(json.loads, open(request(t["name"]))) if r["method"].startswith("engine_newPayload")][-1]["params"][0]["blockHash"]
    if h in seen:
        print(t["name"])
    seen.setdefault(h, t["name"])
