#!/usr/bin/env bash
# eth_call throughput per mainnet fixture against a running node: wrk, 16 connections, SECS per fixture.
# usage: run/calls.sh <client label> [url]  -> fixture,client,rps,p50_ms,p99_ms,err on stdout
# needs wrk and bodies3.lua (LUA=...), the node must hold the state of every fixture's block.
set -euo pipefail
cd "$(dirname "$0")/.."
client=$1 url=${2:-http://127.0.0.1:8545/} LUA=${LUA:-$HOME/bench/bodies3.lua}
tmp=$(mktemp -d)
run/calls.py | while IFS=$'\t' read -r fixture body; do
	printf '%s\n' "$body" > "$tmp/body"
	curl -s -m 60 -H 'Content-Type: application/json' --data-binary @"$tmp/body" "$url" | grep -q '"result"' || { echo "$fixture: call fails, skipped" >&2; continue; }
	wrk -t4 -c16 -d"${SECS:-10}"s --timeout 30s -s "$LUA" "$url" -- "$tmp/body" 2>/dev/null | grep '^{' |
		jq -r --arg f "$fixture" --arg c "$client" '[$f, $c, ((.requests - .status - .rpc_err) / (.duration_us / 1e6) | floor), (.p50_us / 10 | round / 100), (.p99_us / 10 | round / 100), (.status + .rpc_err)] | @csv' | tr -d '"'
done
rm -r "$tmp"
