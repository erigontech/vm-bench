#!/usr/bin/env bash
# Cron entry point: pull, run every runner, commit the history snapshot and the page, push if the box can.
# crontab: 30 3 * * * flock -n /tmp/vmbench.lock ~/vm-bench/run/nightly.sh >> ~/vm-bench/nightly.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
git checkout -q -- docs
git pull -q --ff-only
# The EVM blocks table measures erigon main of tonight: rebuild the runner under the box lock, or say it failed.
src=${ERIGON_MAIN:-$HOME/erigon-vmb-main}
[ -d "$src" ] || git -C "$HOME/erigon" worktree add -q --detach "$src" origin/main
mkdir -p results
if git -C "$src" fetch -q origin main && git -C "$src" checkout -q --detach FETCH_HEAD &&
	flock /tmp/n5bench.lock make -C "$src" evm > results/erigon-build.log 2>&1; then
	cp "$src/build/bin/evm" "$HOME/bin/erigon-evm"
	echo "main-$(git -C "$src" rev-parse --short=9 HEAD)" > "$HOME/bin/erigon-evm.version"
else
	echo "erigon-evm: build of main failed, see results/erigon-build.log on $(hostname)" > results/build-errors.txt
fi
BLOCKTEST_ONLY=1 REPEAT=3 run/all.sh > /dev/null
git add history docs
git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "history: $(ls history | tail -1) on $(hostname)" || exit 0
git push -q origin HEAD:main || { echo "push failed, history kept in the tree"; git reset -q origin/main; }
