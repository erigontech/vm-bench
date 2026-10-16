#!/usr/bin/env bash
# Run every runner (CLIENTS=... for a subset, other results/ stay), keep the run under history/<time>/, rebuild docs/index.html,
# print the comparison.
set -uo pipefail
cd "$(dirname "$0")/.."
# The box lock every benchmark script on the box takes, so nothing else measures or builds meanwhile.
exec 9>"${BENCH_LOCK:-/tmp/n5bench.lock}"; flock 9
export PATH=$HOME/go/bin:$HOME/.cargo/bin:$PATH
export DOTNET_ROOT=${DOTNET_ROOT:-$HOME/.dotnet}
export EVMONE=${EVMONE:-$HOME/evmone/bin/evmone} NETHTEST=${NETHTEST:-$HOME/nethtest/nethtest}
export LD_LIBRARY_PATH=$HOME/evmone/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
mkdir -p results
for client in ${CLIENTS:-erigon geth revme evmone nethermind}; do
	run/$client.sh > results/$client.csv || echo "$client: runner failed" >&2
done
if [ -d blocktests/eest ]; then
	touch results/blocktest.csv
	for client in ${CLIENTS:-erigon geth revme evmone nethermind}; do
		grep -v ",$client," results/blocktest.csv > results/blocktest.tmp || true
		REPEAT=${REPEAT:-2} run/blocktest.sh $client >> results/blocktest.tmp
		mv results/blocktest.tmp results/blocktest.csv
	done
fi
snap=history/$(date -u +%Y-%m-%dT%H%M)
mkdir -p "$snap"
for f in results/*.csv; do [ -s "$f" ] && cp "$f" "$snap/"; done
run/versions.sh > "$snap/versions.csv"
run/history.py
run/compare.py results/*.csv
