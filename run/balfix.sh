#!/usr/bin/env bash
# balfix.sh [out dir]: download (default) or, with FILL=1, build the BAL-on node-tier fixtures (default balfix/): EEST tests-glamsterdam-devnet@v8.1.4
# tests/benchmark/compute filled for Amsterdam at 150M gas with the geth glamsterdam-devnet-8 t8n, plus geth/besu/nethermind
# genesis files for the pre-alloc group. Prints the fixture digest and fails when it differs from the published set.
# Needs git, go (any version that can download go1.25.7), uv, python3, curl; NPROC fill workers (default 3, up to ~20 GB RAM each).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(realpath -m "${1:-balfix}") && W=$out.work
EEST_TAG=tests-glamsterdam-devnet@v8.1.4 EEST_SHA=7341820b5b394b1934dfe7bb6f621fcdab7baf7f
GETH_SHA=aa1f2fcf512988eb8890d9352e601b898d6fdb2c # go-ethereum glamsterdam-devnet-8
GENESIS_URL=https://github.com/ethereum/execution-specs/releases/download/tests-benchmark%40v0.0.9/benchmark_genesis.tar.gz
GENESIS_SHA256=cb545c1ed581920004ffded3a4ef73ec5f7e168fefbc1a2b6972e11cbe8beaa8 TEMPLATE=0xfcc99d2c100c8860
WANT="1163 07fb92b20617f6c2cc79ae490374590d0630a11aea8f8ab5417a8a154d2f1537"
# The published set lacks these tests (filling ran out of memory). The 5 blockhash tests are in its pre-alloc group without a
# fixture, so phase 1 keeps them and phase 2 drops them; the group alloc decides the genesis hash in every payload.
K="not test_unchunkified_bytecode and not test_block_full_access_list_and_data and not (test_bls12_pairing_uncachable and num_pairs_24)"
RELEASE_URL=https://github.com/erigontech/vm-bench/releases/download/balfix-glamsterdam-devnet-v8.1.4/balfix.tgz
RELEASE_SHA256=7567d80889c41ad6f92b8c524b99ee4c3c5d63738835db150dfc4a3940b855f7
if [ -z "${FILL:-}" ]; then # the published set; FILL=1 rebuilds it from source instead
	mkdir -p "$W" && curl -sSfL -o "$W/balfix.tgz" $RELEASE_URL
	echo "$RELEASE_SHA256  $W/balfix.tgz" | sha256sum -c -
	rm -rf "$out" && mkdir -p "$out" && tar xzf "$W/balfix.tgz" -C "$out"
	got=$(python3 run/balfix-digest.py "$out/fixtures")
	echo "fixtures $got, published $WANT"
	[ "$got" = "$WANT" ]
	exit
fi
mkdir -p "$W"
[ -d "$W/execution-specs" ] || git clone -q --depth 1 --branch "$EEST_TAG" https://github.com/ethereum/execution-specs.git "$W/execution-specs"
[ "$(git -C "$W/execution-specs" rev-parse HEAD)" = $EEST_SHA ] || { echo "$W/execution-specs is not at $EEST_SHA"; exit 1; }
if [ ! -x "$W/evm" ]; then
	git init -q "$W/go-ethereum"
	git -C "$W/go-ethereum" fetch -q --depth 1 https://github.com/ethereum/go-ethereum.git $GETH_SHA
	git -C "$W/go-ethereum" checkout -q FETCH_HEAD
	# go1.27 does not build this geth (cockroachdb/swiss).
	(cd "$W/go-ethereum" && GOTOOLCHAIN=go1.25.7 go build -o "$W/evm" ./cmd/evm)
fi
fill() { uv run fill --fork=Amsterdam --gas-benchmark-values 150 ./tests/benchmark/compute --evm-bin="$W/evm" \
	-n "${NPROC:-3}" --dist=worksteal --output "$W/fixtures" --no-html "$@"; }
rm -rf "$W/fixtures"
(
	cd "$W/execution-specs"
	uv sync --all-extras -q || uv sync -q
	fill --generate-pre-alloc-groups -k "$K"
	fill --use-pre-alloc-groups -k "$K and not test_blockhash"
)
rm -rf "$out" && mkdir -p "$out/fixtures"
cp -r "$W/fixtures/blockchain_tests_engine_x" "$out/fixtures/"
curl -sSfL -o "$W/benchmark_genesis.tar.gz" $GENESIS_URL
echo "$GENESIS_SHA256  $W/benchmark_genesis.tar.gz" | sha256sum -c -
mkdir -p "$W/tpl" && tar xzf "$W/benchmark_genesis.tar.gz" -C "$W/tpl" genesis/$TEMPLATE
python3 run/balfix-genesis.py "$out/fixtures" "$W/tpl/genesis/$TEMPLATE" "$out/genesis"
got=$(python3 run/balfix-digest.py "$out/fixtures")
echo "fixtures $got, published $WANT"
[ "$got" = "$WANT" ]
