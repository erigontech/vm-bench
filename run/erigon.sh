#!/usr/bin/env bash
# erigon's EVM through bench_test.go; ns per transaction, execution only.
set -euo pipefail
cd "$(dirname "$0")/.."
go test -run '^$' -bench BenchmarkFixtures -count="${REPEAT:-3}" 2>/dev/null |
	awk '/ns\/op/ { sub(/^BenchmarkFixtures\//, "", $1); sub(/-[0-9]+$/, "", $1); if (!($1 in ns) || $3 < ns[$1]) ns[$1] = $3 }
	     END { for (f in ns) print f ",erigon," ns[f] }'
