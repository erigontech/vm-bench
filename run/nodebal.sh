#!/usr/bin/env bash
# nodebal.sh [filter] [smoke filter]: BAL-on node tier. benchmarkoor newPayload Mgas/s over the Amsterdam fixtures that
# run/balfix.sh builds (BALFIX, default balfix/) for erigon and the pinned glamsterdam-devnet-8 BAL-mode images of the
# ethpandaops/benchmarkoor-tests clients.yaml. Smoke every client on <smoke filter> (one test); a client that fails it is reported
# NOT_RUN and left out. Then <filter> in ORDER and reversed, then run/nodebal-csv.py into
# history/<UTC time>/{nodebal,passbal,versions}.csv. SMOKE_ONLY=1 stops after the smoke. Env: see run/node-lib.sh.
FILTER=${1:-value_150M} SMOKE=${2:-opcode_PUSH0-benchmark-gas-value_150M}
TIER=bal ORDER=${ORDER:-"erigon reth nethermind geth besu ethrex nimbus"} PASS_TIMEOUT=2h
declare -A IMG=(
	[reth]=ethpandaops/reth:glamsterdam-devnet-8@sha256:b0ecb38ab4786d67b5a06fe81eec0e7a77f05be7a8e3ab54498f4ad0819879dc
	[nethermind]=ethpandaops/nethermind:master@sha256:99cd7b2404e8eb84f75d38c36056754e09679b0b67a69bc6c86c3ae9809d0224
	[geth]=ethpandaops/geth:master@sha256:58432f6a64144c6ea914092e267af257cae3107a8e3b1b639afdaec62ae72f0d
	[besu]=ethpandaops/besu:main-cf89071@sha256:97f9d2b125a7c6610336d1c37e542307553deb2e5e48a3c6b76cc741accce77d
	[ethrex]=ethpandaops/ethrex:main@sha256:da185f9e7fe28f1d9b54feab76b2b9e88359fccaa7cd13d6c052d879e40f933b
	[nimbus]=ethpandaops/nimbus-eth1:glamsterdam-devnet-8@sha256:e3ffa4a47745753b651d5ef115807086cf5a448d2dca92bfb88520a49f93dd9e)
declare -A ARGS=(
	[erigon]="--exec.no-merge=true --exec.no-prune=true --exec.no-background-maintenance --experimental.parallel-commitment"
	[geth]="--cache.noprecompile --engine.maxreorgdepth=1024"
	[reth]=""
	[nethermind]="--FlatDb.Enabled=true --FlatDb.CompactionOffset=0 --FlatDb.MinReorgDepth=1024 --FlatDb.MaxReorgDepth=1024 --Blocks.ParallelExecution=true --Blocks.ParallelExecutionBatchRead=true"
	[besu]="--Xplugin-rocksdb-high-spec-enabled=true --Xbal-perfect-parallelization-enabled=true --Xbal-state-root-enabled=true"
	[ethrex]="--skip-genesis-validation --no-precompile-cache"
	[nimbus]="")
BALFIX=$(cd "$(dirname "$0")/.." && realpath -m "${BALFIX:-balfix}")
[ -d "$BALFIX/fixtures/blockchain_tests_engine_x" ] || { echo "no fixtures in $BALFIX: run run/balfix.sh first"; exit 1; }
. "$(dirname "$0")/node-lib.sh"
SOURCE="          local_fixtures_dir: $BALFIX
          local_genesis_dir: $BALFIX/genesis"
echo "filter=$FILTER smoke=$SMOKE fixtures=$BALFIX"
{
	echo 'fixtures,"EEST tests-glamsterdam-devnet@v8.1.4 tests/benchmark/compute, filled for Amsterdam at 150M gas with the geth glamsterdam-devnet-8 t8n"'
	echo "erigon,$EV"
	for c in $ORDER; do
		[ $c = erigon ] && continue
		r=${REF[$c]%@*} d=${REF[$c]##*@sha256:}
		echo "$c,${r##*:}@${d:0:12}"
	done
	printf 'modes,"'
	for c in $ORDER; do printf '%s%s %s' "${sep:-}" $c "${ARGS[$c]:-defaults}"; sep="; "; done
	echo '"'
	echo 'missing,"14 of the 1177 tests are absent because filling them ran out of memory: blockhash (5), unchunkified_bytecode (7), bls12_pairing_uncachable with 24 pairs and block_full_access_list_and_data"'
} > "$D/versions.csv"

instance_extra() {
	[ $1 = besu ] && cat << 'YML'
      environment:
        BESU_OPTS: "-Xms8g -Xmx8g -XX:+AlwaysPreTouch"
YML
	if [ -z "${ARGS[$1]:-}" ]; then echo "      extra_args: []"; else
		echo "      extra_args:"
		for a in ${ARGS[$1]:-}; do echo "        - \"$a\""; done
	fi
}
ok=""
for c in $ORDER; do
	arm $c smoke-$c "$SMOKE" 20m
	if passed1 smoke-$c; then ok="$ok $c"; else
		echo "NOT_RUN $c"
		sed "s/\x1b\[[0-9;]*m//g" "$D/run-smoke-$c.log" | grep -iE "error|fail|invalid|mismatch" | tail -8
		ls "$D"/res-smoke-$c/runs/*/container.log 2> /dev/null | head -1 | xargs -r tail -15
	fi
done
echo "SMOKE ok:$ok"
[ -n "$ok" ] || fail SMOKE_FAIL
[ -n "${SMOKE_ONLY:-}" ] && { echo NODEBAL_DONE; exit 0; }
passes "$FILTER" $ok
snapshot nodebal-csv.py "nodebal.csv passbal.csv" $ok
echo NODEBAL_DONE
