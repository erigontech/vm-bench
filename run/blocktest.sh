#!/usr/bin/env bash
# Blockchain-test fixtures through each client's own test runner, wall time minus the no-block twin.
# usage: run/blocktest.sh <client>   client = erigon | geth | revme | nethermind | evmone  (FILTER=<file glob>)
# One block per process (see eest-select.py), no CPU pinning: a client may use its background threads as in production.
# prints file,client,gas,ms,twin_ms  (ms = best of REPEAT runs of the whole file)
set -uo pipefail
cd "$(dirname "$0")/.."
client=$1
case $client in
	erigon)     cmd=("${ERIGON_EVM:-$HOME/bin/erigon-evm}" blocktest) ;;
	geth)       cmd=(evm blocktest) ;;
	revme)      cmd=(revme blockchaintest) ;;
	nethermind) cmd=("${NETHTEST:-$HOME/nethtest/nethtest}" -b --parallelExecution false -i) ;;  # sequential EVM, like the others
	evmone)     cmd=("${EVMONE:-$HOME/evmone/bin/evmone}" test) ;;
	*) echo "unknown client $client" >&2; exit 2 ;;
esac
now() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1e3'; }
if [ "$client" = nethermind ]; then
	exec run/nethtest-stream.py "${NETHTEST:-$HOME/nethtest/nethtest}" "${REPEAT:-3}" blocktests/eest/*/${FILTER:-*}.json
fi
best() { local b=; for _ in $(seq "${REPEAT:-3}"); do s=$(now); "${cmd[@]}" "$1" >/dev/null 2>&1 || return 1; e=$(now); [ -z "$b" ] || [ $((e - s)) -lt "$b" ] && b=$((e - s)); done; echo "$b"; }
for f in blocktests/eest/*/${FILTER:-*}.json; do
	name=${f#blocktests/eest/}; name=${name%.json}
	gas=$(python3 -c 'import json,sys; print(sum(int(b["blockHeader"]["gasUsed"],16) for t in json.load(open(sys.argv[1])).values() for b in t["blocks"]))' "$f")
	t=$(best "$f") || { echo "$client: $name failed" >&2; continue; }
	tw=$(best "blocktests/eest-twin/$name.json") || { echo "$client: $name twin failed" >&2; continue; }
	echo "$name,$client,$gas,$t,$tw"
done
