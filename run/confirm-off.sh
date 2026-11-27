#!/usr/bin/env bash
# confirm-off.sh <prev sha> <cur sha> [filter]: BAL-off node tier (run/node.sh) for erigon at both commits, interleaved prev,cur,cur,prev,prev,cur,
# from a copy of run/ so no snapshot reaches history/; prints "RATIO <median over the filter's tests of cur/prev median Mgas/s>" and "GEOMEAN <their geomean>".
set -uo pipefail
cd "$(dirname "$0")/.."
W=${CONFIRM_DIR:-$HOME/vmb-confirm-off}; V=$W/vb; rm -rf "$V"; mkdir -p "$V/history"; cp -r run "$V/"
for x in *; do [ "$x" = run ] || [ "$x" = history ] || ln -s "$PWD/$x" "$V/$x"; done
for s in "$1" "$2"; do
	[ -d "$W/src-$s" ] || { git -C "$HOME/erigon" fetch -q origin && git -C "$HOME/erigon" worktree add -q --detach "$W/src-$s" "$s"; } || exit 1
done
F=${3:-value_150M}
for s in "$1" "$2" "$2" "$1" "$1" "$2"; do
	(cd "$V" && ORDER=erigon ERIGON_SRC="$W/src-$s" ERIGON_LABEL="c$s" run/node.sh "$F") > "$W/run-$s.log" 2>&1
done
python3 - "$V/history" "$1" "$2" <<'PY'
import csv, math, pathlib, statistics, sys
vals = {}
for d in pathlib.Path(sys.argv[1]).iterdir():
    sha = next(l.strip().split(",")[1].split("-")[-1] for l in open(d / "versions.csv") if l.startswith("erigon,"))
    for r in csv.reader(open(d / "node.csv")):
        if len(r) >= 3 and r[1] == "erigon":
            vals.setdefault(sha, {}).setdefault(r[0], []).append(float(r[2]))
p, c = vals.get(sys.argv[2][:10], {}), vals.get(sys.argv[3][:10], {})
ratios = [statistics.median(c[t]) / statistics.median(p[t]) for t in p.keys() & c.keys()]
if ratios:
    print("RATIO %.4f" % statistics.median(ratios))
    print("GEOMEAN %.4f" % math.exp(statistics.fmean(map(math.log, ratios))))
PY
