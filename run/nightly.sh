#!/usr/bin/env bash
# Cron entry point: pull, run every runner, commit the history snapshot and the page, push if the box can.
# crontab: 30 3 * * * BENCH_LOCK=/tmp/bench.lock CALLS_FROM=<host>:vm-bench-calls/out/ flock -n /tmp/vmbench.lock ~/vm-bench/run/nightly.sh >> ~/vm-bench/nightly.log 2>&1
# BENCH_LOCK is the box's bench lock, shared with every other measuring script on the box.
set -euo pipefail
cd "$(dirname "$0")/.."
git checkout -q -- docs
git pull -q --rebase || { git rebase --abort; echo "pull failed"; }
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
# subtests.sh takes the box lock itself: wrapping it in flock here deadlocks.
dsrc=${ERIGON_DBG:-$HOME/erigon-vmb-dbg}
[ -d "$dsrc" ] || git -C "$HOME/erigon" worktree add -q --detach "$dsrc" origin/main
dref=$(git -C "$dsrc" ls-remote --heads origin 'alex/dbg_20*' | sort -k2 | tail -1 | cut -f1)
if [ -n "$dref" ] && git -C "$dsrc" fetch -q origin "$dref" && git -C "$dsrc" checkout -q --detach "$dref" &&
	flock "${BENCH_LOCK:-/tmp/bench.lock}" make -C "$dsrc" evm > results/erigon-dbg-build.log 2>&1; then
	cp "$dsrc/build/bin/evm" "$HOME/bin/erigon-evm-dbg"
	run/subtests.sh main="$HOME/bin/erigon-evm" dbg="$HOME/bin/erigon-evm-dbg" > results/st.csv 2> results/st.err &&
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
	rsync -qr --remove-source-files -e "ssh -o BatchMode=yes -o ConnectTimeout=20" "$CALLS_FROM" "$in/" || echo "eth_call: import from $CALLS_FROM failed"
	for f in "$in"/*.csv; do
		[ -e "$f" ] || break
		s=$(basename "$f" .csv)
		mkdir -p "history/${s%-*}"
		mv "$f" "history/${s%-*}/calls.csv"
	done
	# Per-fixture CPU profiles of the last 7 nights (main and dbg), outside the repo: ~/vm-bench-prof/<stamp>-<arm>/<fixture>.pb.gz.
	for f in "$in"/*.prof.tgz; do
		[ -e "$f" ] || break
		d=$HOME/vm-bench-prof/$(basename "$f" .prof.tgz)
		mkdir -p "$d" && tar -xzf "$f" -C "$d" && rm -f "$f"
	done
	ls -1d "$HOME"/vm-bench-prof/*/ 2>/dev/null | sort | head -n -14 | xargs -r rm -rf || true # no profiles yet must not end the run
	run/history.py
fi
# Goal section: Lab mainnet win rate (missing days only) and this week's merged wins; a failed fetch keeps the old data, selfcheck flags it.
run/winrate.py || echo "Lab win rate: fetch failed"
run/wins.py || echo "merged wins: fetch failed"
# Loud staleness check: the verdict goes to nightly.log, ~/vm-bench-selfcheck.txt and the system journal; the page is
# still published, then the run exits 1.
sc=0
run/selfcheck.py || { sc=1; echo "SELFCHECK FAILED: $(cat "$HOME/vm-bench-selfcheck.txt")" | tee >(logger -t vm-bench -p user.err); }
# Commit the snapshot alone, rebase it onto main (daytime edits push there too), rebuild the page on the merged tree, push;
# a rejected push drops only the page commit and tries again. The snapshot commit is never dropped.
git checkout -q -- docs
git add history
git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "history: $(ls history | tail -1)" || exit 0
for i in 1 2 3; do
	git pull -q --rebase origin main || { git rebase --abort; echo "rebase failed, the snapshot commit stays on this clone"; exit 1; }
	run/history.py
	git add docs && git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "page: $(ls history | tail -1)"
	git push -q origin HEAD:main && exit $sc
	echo "push attempt $i failed"; [[ $(git log -1 --format=%s) == page:* ]] && git reset -q --hard HEAD~1; sleep 30
done
echo "push failed, the snapshot commit stays on this clone"
exit 1
