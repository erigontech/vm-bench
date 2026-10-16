#!/usr/bin/env bash
# One workload against a running node, at each rate of its ladder: vegeta open loop, 16 workers, 5 s warm-up,
# SECS (default 20) measured, responses discarded (-max-body=0). JSON-RPC errors inside a 200 are not counted.
# usage: run/rpc.sh <workload> <url> <client>   -> workload,client,rate,rps,p50_ms,p95_ms,p99_ms,err
set -euo pipefail
cd "$(dirname "$0")/.."
wl=$1 url=$2 client=$3
tmp=$(mktemp -d)
gzip -dc "workloads/$wl/requests.jsonl.gz" | python3 -c '
import base64, json, sys
for line in sys.stdin:
    print(json.dumps({"method": "POST", "url": sys.argv[1], "body": base64.b64encode(line.strip().encode()).decode(), "header": {"Content-Type": ["application/json"]}}))' "$url" > "$tmp/targets"
attack() { vegeta attack -format=json -targets="$tmp/targets" -rate="$1" -duration="$2" -timeout=30s -max-body=0 -workers=16 -max-workers=16; }
for rate in $(cat "workloads/$wl/rates"); do
	attack "$rate" 5s > /dev/null
	attack "$rate" "${SECS:-20}s" | vegeta report -type=json |
		jq -r --arg w "$wl" --arg c "$client" --arg r "$rate" '[$w, $c, $r, (.throughput | floor), (.latencies["50th"] / 1e4 | round / 100), (.latencies["95th"] / 1e4 | round / 100), (.latencies["99th"] / 1e4 | round / 100), (.requests - (.requests * .success | round))] | @csv' | tr -d '"'
done
rm -r "$tmp"
