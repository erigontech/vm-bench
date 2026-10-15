#!/usr/bin/env bash
# erigon's EVM through bench_test.go; ns per transaction, execution only.
# ERIGON=<git ref or local checkout> measures that erigon instead of go.mod's; the column is erigon-<ref>.
set -euo pipefail
cd "$(dirname "$0")/.."
client=erigon
modflag=()
export GONOSUMDB=github.com/erigontech/erigon
if [ -n "${ERIGON:-}" ]; then
	mod=$(mktemp -d)/go.mod
	cp go.mod "$mod"; cp go.sum "${mod%.mod}.sum"
	if [ -d "$ERIGON" ]; then
		go mod edit -modfile="$mod" -replace "github.com/erigontech/erigon=$ERIGON"
	else
		go get -modfile="$mod" "github.com/erigontech/erigon@$ERIGON" 2>&1 | grep -v '^go: downloading' >&2 || true
	fi
	go mod tidy -modfile="$mod" >/dev/null 2>&1
	modflag=(-modfile="$mod")
	client=erigon-${ERIGON##*/}
fi
go test "${modflag[@]}" -run '^$' -bench "BenchmarkFixtures/${FILTER:-}" -count="${REPEAT:-3}" |
	awk '/^BenchmarkFixtures\// { name = $1; sub(/^BenchmarkFixtures\//, "", name); sub(/-[0-9]+$/, "", name) }
	     /ns\/op/ { for (i = 2; i <= NF; i++) if ($i == "ns/op") t = $(i - 1); if (!(name in ns) || t < ns[name]) ns[name] = t }
	     END { for (f in ns) print f "," client "," ns[f] }' client="$client"
