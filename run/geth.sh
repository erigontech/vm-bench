#!/usr/bin/env bash
# go-ethereum: evm statetest --bench; ns per transaction, execution only.
# install: go install github.com/ethereum/go-ethereum/cmd/evm@latest
set -euo pipefail
cd "$(dirname "$0")/.."
for f in fixtures/*/*.json; do
	key=${f#fixtures/}; key=${key%.json}
	ns=$(evm statetest --bench "$f" 2>/dev/null | jq '.[0] | select(.pass) | .benchStats.time')
	[ -n "$ns" ] && echo "$key,geth,$ns" || echo "geth: $key failed" >&2
done
