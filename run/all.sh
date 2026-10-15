#!/usr/bin/env bash
# Run every runner whose tool is installed, then print the comparison.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p results
for client in erigon geth revme evmone nethermind; do
	run/$client.sh > results/$client.csv || echo "$client: runner failed" >&2
done
run/compare.py results/*.csv
