#!/usr/bin/env bash
# Run every runner whose tool is installed, keep the run under history/<time>/, rebuild docs/index.html,
# print the comparison.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p results
for client in erigon geth revme evmone nethermind; do
	run/$client.sh > results/$client.csv || echo "$client: runner failed" >&2
done
snap=history/$(date -u +%Y-%m-%dT%H%M)
mkdir -p "$snap"
for f in results/*.csv; do [ -s "$f" ] && cp "$f" "$snap/"; done
run/versions.sh > "$snap/versions.csv"
run/history.py
run/compare.py results/*.csv
