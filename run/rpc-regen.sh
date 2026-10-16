#!/usr/bin/env bash
# Regenerate the QA workloads at a new pinned block: qa-mixed and qa-getlogs from rpc_pattern_gen (erigontech/rpc-tests)
# with the QA settings, against a node that does not advance; written to workloads/<name>@<head>/, the old ones stay.
# usage: run/rpc-regen.sh <url> <rpc-tests checkout with build/bin/rpc_pattern_gen>
set -euo pipefail
cd "$(dirname "$0")/.."
url=$1 rt=$2
gen=$rt/build/bin/rpc_pattern_gen
head() { curl -s -m 10 -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' "$url" |
	python3 -c 'import json, sys; print(int(json.load(sys.stdin)["result"], 16))'; }
pin=$(head)
tmp=$(mktemp -d)
"$gen" --profile "$rt/perf/pattern/mainnet/config/mixed.profile" --url "$url" \
	--counts 120000 --block-tag latest --verify --keep ok --fees drop --max-blocks 2500 --out "$tmp/mixed.tar"
"$gen" eth_getLogs --url "$url" --counts 200000 --block-tag latest --verify --keep ok --fees drop --out "$tmp/getlogs.tar"
if [ "$(head)" != "$pin" ]; then echo "head moved from $pin during generation: use a node without a consensus client" >&2; rm -r "$tmp"; exit 1; fi
tar -xf "$tmp/mixed.tar" -C "$tmp" && tar -xf "$tmp/getlogs.tar" -C "$tmp"
NOTE="QA 'mixed' profile, regenerated with rpc_pattern_gen (--counts 120000 --max-blocks 2500) against a mainnet node at block $pin" \
	run/rpc-workload.py "qa-mixed@$pin" "$(find "$tmp" -name 'vegeta_*mixed*.txt')" "$pin" $(cat workloads/qa-mixed/rates)
NOTE="QA eth_getLogs profile, regenerated with rpc_pattern_gen (--counts 200000) against a mainnet node at block $pin" \
	run/rpc-workload.py "qa-getlogs@$pin" "$(find "$tmp" -name 'vegeta_*getLogs*.txt')" "$pin" $(cat workloads/qa-getlogs/rates)
rm -r "$tmp"
