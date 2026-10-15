#!/usr/bin/env bash
# evmone: `evmone test` has no timer, so this is process wall time: JSON load + execution, best of REPEAT.
# Meaningful for the benchmarkoor fixtures (100 ms and up), not for 1 ms mainnet transactions.
# install: untar a release from https://github.com/ethereum/evmone/releases, set EVMONE=<dir>/bin/evmone
set -euo pipefail
cd "$(dirname "$0")/.."
EVMONE=${EVMONE:-evmone}
now() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1e9'; }
for f in fixtures/*/*.json; do
	key=${f#fixtures/}; key=${key%.json}
	best=
	for _ in $(seq "${REPEAT:-3}"); do
		s=$(now); "$EVMONE" test "$f" >/dev/null 2>&1 || { best=; break; }; e=$(now)
		[ -z "$best" ] || [ $((e - s)) -lt "$best" ] && best=$((e - s))
	done
	[ -n "$best" ] && echo "$key,evmone,$best" || echo "evmone: $key failed" >&2
done
