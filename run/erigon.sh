#!/usr/bin/env bash
# erigon's EVM through bench_test.go; ns per transaction, execution only.
set -euo pipefail
cd "$(dirname "$0")/.."
go test -run '^$' -bench BenchmarkFixtures -count="${REPEAT:-3}" 2>/dev/null |
	awk '/^BenchmarkFixtures\// { name = $1; sub(/^BenchmarkFixtures\//, "", name); sub(/-[0-9]+$/, "", name) }
	     /ns\/op/ { for (i = 2; i <= NF; i++) if ($i == "ns/op") t = $(i - 1); if (!(name in ns) || t < ns[name]) ns[name] = t }
	     END { for (f in ns) print f ",erigon," ns[f] }'
