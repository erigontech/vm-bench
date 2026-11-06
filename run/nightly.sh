#!/usr/bin/env bash
# Cron entry point: pull, run every runner, commit the history snapshot and the page, push if the box can.
# crontab: 30 3 * * * BENCH_LOCK=/tmp/bench.lock CALLS_FROM=<host>:vm-bench-calls/out/ flock -n /tmp/vmbench.lock ~/vm-bench/run/nightly.sh >> ~/vm-bench/nightly.log 2>&1
# BENCH_LOCK is the box's bench lock, shared with every other measuring script on the box.
set -euo pipefail
cd "$(dirname "$0")/.."
git checkout -q -- docs
git pull -q --ff-only
# The EVM blocks table measures erigon main of tonight: rebuild the runner under the box lock, or say it failed.
src=${ERIGON_MAIN:-$HOME/erigon-vmb-main}
[ -d "$src" ] || git -C "$HOME/erigon" worktree add -q --detach "$src" origin/main
mkdir -p results
if git -C "$src" fetch -q origin main && git -C "$src" checkout -q --detach FETCH_HEAD &&
	flock "${BENCH_LOCK:-/tmp/bench.lock}" make -C "$src" evm > results/erigon-build.log 2>&1; then
	cp "$src/build/bin/evm" "$HOME/bin/erigon-evm"
	echo "main-$(git -C "$src" rev-parse --short=9 HEAD)" > "$HOME/bin/erigon-evm.version"
else
	echo "erigon-evm: build of main failed, see results/erigon-build.log" > results/build-errors.txt
fi
BLOCKTEST_ONLY=1 REPEAT=3 run/all.sh > /dev/null
# Sub-tests: erigon main and the newest dbg branch (alex/dbg_<YYYYMMDD>, main + open PRs); history.py keeps nethermind's column from its latest run.
dsrc=${ERIGON_DBG:-$HOME/erigon-vmb-dbg}
[ -d "$dsrc" ] || git -C "$HOME/erigon" worktree add -q --detach "$dsrc" origin/main
dref=$(git -C "$dsrc" ls-remote --heads origin 'alex/dbg_20*' | sort -k2 | tail -1 | cut -f1)
if [ -n "$dref" ] && git -C "$dsrc" fetch -q origin "$dref" && git -C "$dsrc" checkout -q --detach "$dref" &&
	flock "${BENCH_LOCK:-/tmp/bench.lock}" make -C "$dsrc" evm > results/erigon-dbg-build.log 2>&1; then
	cp "$dsrc/build/bin/evm" "$HOME/bin/erigon-evm-dbg"
	flock "${BENCH_LOCK:-/tmp/bench.lock}" run/subtests.sh main="$HOME/bin/erigon-evm" dbg="$HOME/bin/erigon-evm-dbg" > results/st.csv 2> results/st.err &&
		run/subtests-publish.py results/st.csv "main=$(cat "$HOME/bin/erigon-evm.version")" "dbg=dbg-${dref:0:10}" > /dev/null ||
		echo "sub-tests failed, see results/st.err" >> results/build-errors.txt
else
	echo "erigon-evm: build of the dbg branch failed, see results/erigon-dbg-build.log" >> results/build-errors.txt
fi
# The node tiers re-measure erigon main only; history.py fills the other clients from their latest full run.
export BENCHMARKOOR=${BENCHMARKOOR:-$HOME/bm24402727/src/benchmarkoor/bin/benchmarkoor}
ERIGON_SRC=$src ORDER=erigon run/node.sh > results/node-nightly.log 2>&1 || echo "node tier failed, see results/node-nightly.log" >> results/build-errors.txt
BALFIX=${BALFIX:-$HOME/bench/balfix} ERIGON_SRC=$src ORDER=erigon run/nodebal.sh > results/nodebal-nightly.log 2>&1 || echo "BAL-on node tier failed, see results/nodebal-nightly.log" >> results/build-errors.txt
# eth_call tier: the box with the mainnet node measures it from its own cron (CALLS_FROM = rsync source of its CSVs,
# named <UTC stamp>-<arm>.csv); each CSV becomes history/<stamp>/calls.csv.
if [ -n "${CALLS_FROM:-}" ]; then
	in=$HOME/vm-bench-calls-in
	mkdir -p "$in"
	rsync -q --remove-source-files -e "ssh -o BatchMode=yes -o ConnectTimeout=20" "$CALLS_FROM" "$in/" || echo "eth_call: import from $CALLS_FROM failed"
	for f in "$in"/*.csv; do
		[ -e "$f" ] || break
		s=$(basename "$f" .csv)
		mkdir -p "history/${s%-*}"
		mv "$f" "history/${s%-*}/calls.csv"
	done
	run/history.py
fi
# Loud staleness check: the verdict goes to nightly.log and ~/vm-bench-selfcheck.txt, which the patrol reads.
run/selfcheck.py || echo "SELFCHECK FAILED: $(cat "$HOME/vm-bench-selfcheck.txt")"
git add history docs
git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "history: $(ls history | tail -1)" || exit 0
git push -q origin HEAD:main || { echo "push failed, history kept in the tree"; git reset -q origin/main; }
