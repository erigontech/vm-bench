#!/usr/bin/env bash
# eth_call throughput per mainnet fixture against a running node: wrk, 16 connections, SECS per fixture.
# usage: run/calls.sh <client label> [url]  -> fixture,client,rps,p50_ms,p99_ms,err,at,gas on stdout
# gas = the call's gasUsed from debug_traceCall (callTracer, top call), empty when the node has no tracer.
# needs wrk and bodies3.lua (LUA=...). at = block, or latest when the node no longer keeps the fixture's block.
set -euo pipefail
cd "$(dirname "$0")/.."
client=$1 url=${2:-http://127.0.0.1:8545/} LUA=${LUA:-$HOME/bench/bodies3.lua}
tmp=$(mktemp -d)
ok() { curl -s -m 60 -H 'Content-Type: application/json' --data-binary @"$tmp/body" "$url" | grep -q '"result"'; }
run/calls.py | while IFS=$'\t' read -r fixture body latest; do
	at=block
	printf '%s\n' "$body" > "$tmp/body"
	if ! ok; then
		at=latest
		printf '%s\n' "$latest" > "$tmp/body"
		ok || { echo "$fixture: call failed" >&2; continue; }
	fi
	jq -c '.method="debug_traceCall" | .params=(.params[0:2]+[{"tracer":"callTracer","tracerConfig":{"onlyTopCall":true}}])' "$tmp/body" > "$tmp/trace"
	gas=$(curl -s -m 60 -H 'Content-Type: application/json' --data-binary @"$tmp/trace" "$url" | jq -r '.result.gasUsed // empty' 2> /dev/null || true)
	gas=${gas:+$((gas))}
	wrk -t4 -c16 -d"${SECS:-10}"s --timeout 30s -s "$LUA" "$url" -- "$tmp/body" 2>/dev/null | grep '^{' |
		jq -r --arg f "$fixture" --arg c "$client" --arg at "$at" --arg gas "$gas" '[$f, $c, ((.requests - .status - .rpc_err) / (.duration_us / 1e6) | floor), (.p50_us / 10 | round / 100), (.p99_us / 10 | round / 100), (.status + .rpc_err), $at, $gas] | @csv' | tr -d '"'
done
rm -r "$tmp"
