#!/usr/bin/env bash
# Blockchain-test fixtures through each client's own test runner, wall time minus the no-block twin.
# usage: run/blocktest.sh <client>   client = erigon | geth | revme | nethermind | evmone  (FILTER=<file glob>)
# One block per process (see eest-select.py), no CPU pinning: a client may use its background threads as in production.
# prints file,client,gas,ms,twin_ms  (ms = best of REPEAT runs of the whole file)
# nethermind: file and twin each run second in one nethtest process, after a pass of the file, so dotnet start-up and JIT warm-up cancel.
set -uo pipefail
cd "$(dirname "$0")/.."
client=$1
case $client in
	# erigon's Close waits for background file builds in 3 s ticks, which added 0-12 s to a file at random; the builds are node
	# maintenance, not block execution
	erigon)     cmd=(env NO_BACKGROUND_E3_BUILD=true "${ERIGON_EVM:-$HOME/bin/erigon-evm}" blocktest) ;;
	geth)       cmd=(evm blocktest) ;;
	revme)      cmd=(revme blockchaintest) ;;
	nethermind) cmd=("${NETHTEST:-$HOME/nethtest/nethtest}" -b --parallelExecution false -x -j -n) ;;  # sequential EVM, like the others; file names on stdin
	evmone)     cmd=("${EVMONE:-$HOME/evmone/bin/evmone}" test) ;;
	*) echo "unknown client $client" >&2; exit 2 ;;
esac
now() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1e3'; }
run() { if [ "$client" = nethermind ]; then printf '%s\n' "$@" "" | "${cmd[@]}" | { ! grep -q '"pass": false'; }; else "${cmd[@]}" "$1" >/dev/null; fi; }
best() { local b=; for _ in $(seq "${REPEAT:-3}"); do s=$(now); run "$@" 2>/dev/null || return 1; e=$(now); [ -z "$b" ] || [ $((e - s)) -lt "$b" ] && b=$((e - s)); done; echo "$b"; }
for f in blocktests/eest/*/${FILTER:-*}.json; do
	name=${f#blocktests/eest/}; name=${name%.json}
	gas=$(python3 -c 'import json,sys; print(sum(int(b["blockHeader"]["gasUsed"],16) for t in json.load(open(sys.argv[1])).values() for b in t["blocks"]))' "$f")
	warm=; [ "$client" = nethermind ] && warm=$f
	t=$(best $warm "$f") || { echo "$client: $name failed" >&2; continue; }
	tw=$(best $warm "blocktests/eest-twin/$name.json") || { echo "$client: $name twin failed" >&2; continue; }
	echo "$name,$client,$gas,$t,$tw"
done
