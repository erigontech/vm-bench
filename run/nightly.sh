#!/usr/bin/env bash
# Cron entry point: pull, run every runner, commit the history snapshot and the page, push if the box can.
# crontab: 30 3 * * * EVMONE=... NETHTEST=... PATH=... flock -n /tmp/vmbench.lock ~/vm-bench/run/nightly.sh >> ~/vm-bench/nightly.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
git pull -q --ff-only
run/all.sh > /dev/null
git add history docs
git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "history: $(ls history | tail -1) on $(hostname)" || exit 0
git push -q origin HEAD:main || echo "push failed, history kept locally"
