#!/usr/bin/env bash
# node.sh [filter] [smoke filter]: node tier. benchmarkoor newPayload Mgas/s over EEST tests-benchmark@v0.0.9 (engine_x, a genesis
# per group, small state) for erigon and the pinned release images of reth, nethermind and geth, one fresh container per client
# and pass. Smoke every client on <smoke filter> (one test; stops unless every client passes it), then <filter> in ORDER and
# reversed, then run/node-csv.py into history/<UTC time>/{node,pass,versions}.csv. Env: see run/node-lib.sh.
FILTER=${1:-value_150M} SMOKE=${2:-absent_accounts_False-opcode_BALANCE-benchmark-gas-value_150M}
FIX=tests-benchmark@v0.0.9 TIER=node ORDER="erigon reth nethermind geth"
declare -A IMG=(
	[reth]=ghcr.io/paradigmxyz/reth:v2.7.0@sha256:a7f059d470878a5a59f3c575f3fc81b536d0d2d56d7a1cbed73e717a4f766336
	[nethermind]=nethermind/nethermind:2.2.0@sha256:5cc0061e6a317e9249e1e1f537a0a40a2036525c62f1cb250943432f4c000a38
	[geth]=ethereum/client-go:v1.17.8@sha256:abf3605177f8bdcfce436985a8054cca4ae59256323a4ffb72c56c04f3d1fadd)
SOURCE="          github_repo: ethereum/execution-specs
          github_release: $FIX"
. "$(dirname "$0")/node-lib.sh"
echo "filter=$FILTER smoke=$SMOKE fixtures=$FIX"
{
	echo "fixtures,$FIX"
	echo "erigon,$EV"
	for c in reth nethermind geth; do r=${REF[$c]%@*}; echo "$c,${r##*:}"; done
} > "$D/versions.csv"

bad=""
for c in $ORDER; do
	arm $c smoke-$c "$SMOKE"
	passed1 smoke-$c || bad="$bad $c"
done
[ -z "$bad" ] || fail "SMOKE_FAIL$bad" "$D/run-smoke-${bad##* }.log"
echo SMOKE_OK
passes "$FILTER" $ORDER
snapshot node-csv.py "node.csv pass.csv"
echo NODE_DONE
