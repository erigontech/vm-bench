#!/usr/bin/env bash
# One workload against a running node, at each rate of its ladder: vegeta open loop (workers grow as needed, so a
# rate above the node's capacity shows as rps below rate), 5 s warm-up, SECS (default 20) measured, responses
# discarded (-max-body=0).
# usage: run/rpc.sh <workload> <url> <client>   -> workload,client,rate,rps,p50_ms,p95_ms,p99_ms,err
set -euo pipefail
cd "$(dirname "$0")/.."
wl=$1 url=$2 client=$3
tmp=$(mktemp -d)
python3 -c '
import base64, json, sys
for line in sys.stdin:
    print(json.dumps({"method": "POST", "url": sys.argv[1], "body": base64.b64encode(line.strip().encode()).decode(), "header": {"Content-Type": ["application/json"]}}))' "$url" < "workloads/$wl/requests.jsonl" > "$tmp/targets"
# A node that cannot serve the workload (pruned blocks, missing API) answers errors inside HTTP 200, which vegeta cannot
# see with -max-body=0: probe the first 100 bodies once and refuse the workload when more than 5% of them fail.
bad=$(head -100 "workloads/$wl/requests.jsonl" | while read -r body; do curl -s -m 60 -H 'Content-Type: application/json' --data-binary "$body" "$url" | head -c 200 | grep -c '"error"' || true; done | awk '{s += $1} END {print s + 0}')
if [ "$bad" -gt 5 ]; then echo "$wl: $client answers errors to $bad of the first 100 requests, skipped" >&2; rm -r "$tmp"; exit 0; fi
attack() { vegeta attack -format=json -targets="$tmp/targets" -rate="$1" -duration="$2" -timeout=30s -max-body=0 -workers=16; }
for rate in $(cat "workloads/$wl/rates"); do
	attack "$rate" 5s > /dev/null
	attack "$rate" "${SECS:-20}s" | vegeta report -type=json |
		jq -r --arg w "$wl" --arg c "$client" --arg r "$rate" '[$w, $c, $r, (.throughput | floor), (.latencies["50th"] / 1e4 | round / 100), (.latencies["95th"] / 1e4 | round / 100), (.latencies["99th"] / 1e4 | round / 100), (.requests - (.requests * .success | round))] | @csv' | tr -d '"'
done
rm -r "$tmp"
