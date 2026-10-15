#!/usr/bin/env bash
# Nethermind: nethtest has no timer, so this is wall time of REPEAT runs in one process minus
# the process start, divided by REPEAT: JSON load + execution. Meaningful for the benchmarkoor
# fixtures only; nethtest also rejects the mainnet fixtures because it derives the sender from
# secretKey, which only the benchmarkoor fixtures carry.
# install: dotnet build src/Nethermind/Nethermind.Test.Runner -c Release -o <dir>, set NETHTEST=<dir>/nethtest
set -euo pipefail
cd "$(dirname "$0")/.."
NETHTEST=${NETHTEST:-nethtest}
now() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1e9'; }
s=$(now); printf '\n' | "$NETHTEST" --stateTest -n -j -x >/dev/null 2>&1; e=$(now); startup=$((e - s))
for f in fixtures/*/*.json; do
	key=${f#fixtures/}; key=${key%.json}
	"$NETHTEST" --stateTest -n -j -i "$f" 2>/dev/null | jq -e '.[0].pass' >/dev/null || { echo "nethermind: $key failed" >&2; continue; }
	s=$(now); { for _ in $(seq "${REPEAT:-3}"); do echo "$f"; done; echo; } | "$NETHTEST" --stateTest -n -j -x >/dev/null 2>&1; e=$(now)
	echo "$key,nethermind,$(( (e - s - startup) / ${REPEAT:-3} ))"
done
