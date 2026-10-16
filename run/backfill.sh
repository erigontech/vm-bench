#!/usr/bin/env bash
# One history/ snapshot per week of erigon main, dated by the commit; WEEKS=N back (default 12).
# ERIGON_REPO points at an erigon checkout used only to resolve dates to commits.
set -uo pipefail
cd "$(dirname "$0")/.."
repo=${ERIGON_REPO:-$HOME/erigon}
git -C "$repo" fetch -q origin main
for ((i = 1; i <= ${WEEKS:-12}; i++)); do
	sha=$(git -C "$repo" rev-list -1 --before="$i weeks ago" origin/main)
	snap=history/$(TZ=UTC git -C "$repo" show -s --format=%cd --date=format-local:%Y-%m-%dT%H%M "$sha")
	[ -e "$snap/erigon.csv" ] && continue
	csv=$(ERIGON=$sha run/erigon.sh) || { echo "$sha: failed" >&2; continue; }
	mkdir -p "$snap"
	sed 's/,erigon-[0-9a-f]*,/,erigon,/' <<<"$csv" > "$snap/erigon.csv"
	echo "erigon,$sha" > "$snap/versions.csv"
	echo "$snap <- $sha"
done
run/history.py
