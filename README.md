# vm-bench

Results: **https://erigontech.github.io/vm-bench/** (EVM blocks tier nightly, other tiers when rerun).

Cross-client EVM and node benchmarks for erigon: where erigon is slower than other clients, and whether erigon's
`dbg` build (main + open PRs) regressed against main. Every number on the page can be rerun from this repository.

```
tier                what is timed                                         clients                          how to run
EVM blocks          EEST tests-benchmark@v0.0.9 150M blocks through each  erigon geth nethermind evmone    run/all.sh (nightly, run/nightly.sh)
                    client's blockchain-test tool, minus a no-block twin  revm gevm
EVM per sub-test    one 150M block per EEST sub-test, erigon builds       erigon builds, nethermind        run/subtests.sh, see "Per sub-test"
                    against each other
Node                benchmarkoor engine_newPayload Mgas/s, small state    erigon reth nethermind geth      run/node.sh, see "Node tier"
Node, BAL on        same on Amsterdam blocks with a block access list     + besu ethrex nimbus             run/nodebal.sh, see "BAL-on node tier"
RPC                 replayable request corpora, open-loop rate ladder     erigon reth                      run/rpc.sh, see "RPC workloads"
State tests         mainnet transactions as EEST state tests              erigon (geth revm evmone neth)   make bench, run/<client>.sh
```

Each run writes one snapshot `history/<UTC time>/*.csv` (+ `versions.csv`); `run/history.py` turns all snapshots into
`docs/index.html`, the published page. Measure on a quiet Linux box, never a laptop, one run at a time under one lock
(`BENCH_LOCK`).

## State tests

Real mainnet transactions as [EEST state tests](https://github.com/ethereum/execution-spec-tests), to compare EVM implementations on the same work.

`fixtures/mainnet-edge-cases/` and `fixtures/mainnet-popular/` hold one state test per mainnet transaction: the prestate the transaction touched, the block environment, the signed transaction (`txbytes`, so no secret key) and the post-state root and logs hash. Every runner that reads the EEST state-test format can time them; this repository ships the erigon runner.

```
make bench                      # erigon, every fixture, go benchmark output
make bench ARGS='-bench Mainnet/4-'   # one fixture
make fetch TX=0xhash=label,... GROUP=mainnet-popular  # add mainnet transactions from an archive node (RPC=<url>, default drpc)
make fill TXREPLAY=<dir>        # rebuild fixtures/mainnet-edge-cases from erigon TxReplay fixtures
make fill-benchmarkoor PAYLOADS=<dir>   # rebuild fixtures/benchmarkoor from the benchmarkoor compute payloads
make refill                     # recompute every fixture's post state after a format change
run/all.sh                      # every installed runner, then the Mgas/s table
ERIGON=<sha|branch|dir> run/erigon.sh   # another erigon as column erigon-<ref>, compared against go.mod's
```

## Other clients

`run/<client>.sh` prints `fixture,client,ns` per transaction; `run/compare.py results/*.csv` turns the files into a Mgas/s table with each client's ratio to erigon. Each script's header says how to install its tool.

```
client      tool                           what the time covers
erigon      bench_test.go                  execution
geth        evm statetest --bench          execution
revme       revme statetest                execution
evmone      evmone test                    process wall time: load + execution
nethermind  nethtest                       process wall time: load + execution, benchmarkoor fixtures only
```

Wall-time numbers are only meaningful on the benchmarkoor fixtures (100 ms and up). nethtest derives the sender from `secretKey`, so it cannot run the mainnet fixtures, whose senders are real accounts; the benchmarkoor fixtures use the EEST test account instead.

`fixtures/benchmarkoor/` holds the compute-suite tests erigon runs slowest, listed in `fill/benchmarkoor_tests.txt`: the setup payloads of each test run on an empty state with funded senders, the state they leave is the prestate, and the first transaction of the benchmark block is the test. The payloads are signed for the devnet's chain id, so these fixtures carry the sender and no `txbytes`.

The erigon runner links erigon, which is LGPL-3.0; this repository is Apache-2.0.

## Fair cross-client numbers: EEST benchmark blocks

The comparable number on the page. Each client runs the same blockchain-test fixture through its own spec-test tool,
so nobody has to accept a benchmark patch and any team can rerun it from the public fixture tarball plus the binaries:

```
geth, erigon   evm blocktest <file>
revm           revme blockchaintest <file>
nethermind     printf '%s\n' <file> <file> '' | nethtest -b --parallelExecution false -x -j -n
evmone         evmone test <file>
```

Why it is fair:

- The unit is big. A file is eight copies of one 150M-gas block from `tests-benchmark@v0.0.9`, run one after another in one
  process; setup is O(pre-state), execution is O(gas). A state-test harness fails on exactly this: a 50k-gas transaction
  against 50 ms of harness.
- Setup is subtracted, not estimated. Every file has a twin with the same genesis and no blocks; Mgas/s = gas /
  (T(file) − T(twin)), best of REPEAT runs. The twin time is kept in the CSV so the harness cost of each client stays
  visible. A result is grey when the twin is more than 30% of the run or the net time is under 100 ms.
- nethtest's dotnet start-up is ~3 s, so nethermind runs the file and the twin as the second input of one process,
  after a pass of the file: ms = T(file, file), twin = T(file, twin). Start-up and JIT warm-up cancel, so nethermind is
  the one client measured warm; its cells are grey only under 100 ms net.
- Everyone does the same work: parse the fixture, execute the block, compute the state root, check it. Runners that
  would execute a file's tests in parallel (nethtest, revme) see one block at a time; nethermind's BAL parallel
  execution is off.
- Same inputs as the EF's benchmarkoor and gas-repricing work, so the table can be cross-checked against their results.

What the groups mean: `instruction` and `scenario` are the EVM comparison. `precompile` repeats one input per block,
and geth and nethermind serve repeated precompile calls from a result cache, so that group compares caches, not
precompiles; it is shown but kept out of the hero.

`run/eest-select.py <fixtures dir> 150M 8` builds `blocktests/eest/` and the twins from the tarball
(`fixtures_benchmark.tar.gz` of the execution-specs release `tests-benchmark@v0.0.9`, the version erigon's CI pins, sha256
`5aee5d1bf7430d5b6ca5b48269dd2a1fb0f9df39ac1e980bac9fc56ad403b8c7`);
`run/blocktest.sh <client>` prints `file,client,gas,ms,twin_ms`; `run/all.sh` includes it when `blocktests/eest/`
exists. The other two tiers on the page are honest about what they measure: the node tier is benchmarkoor
newPayload Mgas/s (erigon, reth, geth, nethermind, no evmone), the RPC tier is eth_call rps on one mainnet node,
erigon and reth only, as a regression tracker.

## Per sub-test

The EVM tier above times the first sub-test of each EEST file, eight copies; this one times every 150M sub-test of the
same tarball (one per opcode, input size or variant), one block per process. Same method: ms minus the no-block twin,
best of REPEAT (default 3), erigon with one exec worker, nethermind warm in one process. Arms run interleaved per
sub-test, so a drift of the machine hits every arm alike. List the erigon builds base first: the page compares every
later build with the first one, and the last one with nethermind.

```
run/subtests-split.py           # download tests-benchmark@v0.0.9 to testdata/, check its sha256, write blocktests/subtests/
mkdir -p results; run/subtests.sh main=<erigon evm binary> dbg=<erigon evm binary> nethermind > results/subtests.csv   # takes BENCH_LOCK
run/subtests-publish.py results/subtests.csv 'main=main <sha>' 'dbg=dbg <sha>'   # new history/<UTC time>/
run/history.py
```

An erigon evm binary is `make evm` in an erigon checkout (`build/bin/evm`). `geth` and `revme` are arms too, run as in
`run/blocktest.sh`; `CATS=precompile` runs one group.

## Node tier

Each client runs as a real node in docker and imports the same EEST benchmark blocks through the engine API;
[benchmarkoor](https://github.com/ethpandaops/benchmarkoor) times every `engine_newPayload` and the number is Mgas/s of
the test block. Linux with docker, Go, python3 and benchmarkoor at commit `3a17faa08a5c` built with
`make build-core` (binary `bin/benchmarkoor`):

```
BENCHMARKOOR=<benchmarkoor>/bin/benchmarkoor ERIGON_SRC=<erigon checkout> CPUSET=5,13,6,14,7,15 run/node.sh
```

- Fixtures: benchmarkoor downloads `tests-benchmark@v0.0.9` from the execution-specs release (`fixtures_benchmark.tar.gz`
  sha256 above, `benchmark_genesis.tar.gz` sha256 `cb545c1ed581920004ffded3a4ef73ec5f7e168fefbc1a2b6972e11cbe8beaa8`),
  every test filled for Osaka at 150M gas.
- Clients: erigon is `make erigon` at the HEAD of a clean `ERIGON_SRC`, copied into
  `ethpandaops/erigon:glamsterdam-devnet-7@sha256:4023a007fe97…` (Debian, glibc 2.41: build on a host with the same or an
  older glibc), or any image in `ERIGON_IMAGE`. reth v2.7.0, nethermind 2.2.0 and geth v1.17.8 are the release images,
  pinned by digest in `run/node.sh`; the run log prints the digest of every image it ran.
- Method: every client first runs one smoke test, and the run stops unless all pass it. Then every client runs the whole
  filter (default `value_150M`, the 150M-gas tests) in a fresh container, in the order erigon, reth, nethermind, geth and
  then reversed. The first test of every genesis group is a warm-up and is dropped. A cell is the mean of the two passes
  over the tests valid in all eight runs; `pass.csv` is each client's pass-2/pass-1 geomean, which should stay within 2%.
- Env: `CPUSET` (full cores with their SMT siblings, default none: the page uses three), `MEMORY` (default 32g),
  `ERIGON_LABEL=dbg` for a branch build, `WORK` (benchmarkoor cache, logs and raw results, default `results/node/`),
  `BENCH_LOCK`. The result lands in `history/<UTC time>/{node,pass,versions}.csv`; `run/history.py` puts it on the page.
- What it is: each client's default node, multi-core, on a small genesis state, so it measures execution plus the
  engine API and state-root path of a node. What it is not: the large-state number. A mainnet-sized state makes reads
  hit disk; that is benchmarkoor's stateful suite, not this tier.

## BAL-on node tier

The same harness on Amsterdam blocks, where every block carries a block-level access list (EIP-7928) and every client
runs in its BAL mode. No published release holds the benchmark tests filled for Amsterdam, so
`run/balfix.sh` downloads the published set (release `balfix-glamsterdam-devnet-v8.1.4`, sha256 checked); `FILL=1 run/balfix.sh` rebuilds it from execution-specs `tests-glamsterdam-devnet@v8.1.4` (commit `7341820b5b39`),
`tests/benchmark/compute`, Amsterdam, 150M gas, t8n = go-ethereum `glamsterdam-devnet-8` at `aa1f2fcf5129` built with
go1.25.7, plus geth/besu/nethermind genesis files made from the `0xfcc99d2c100c8860` group of the v0.0.9
`benchmark_genesis.tar.gz`. The fill needs [uv](https://docs.astral.sh/uv/), takes hours and up to ~20 GB of RAM per
worker; the script ends with a digest of every test's fixture hash and fails if it differs from the published set.

```
run/balfix.sh                    # -> balfix/
BENCHMARKOOR=<benchmarkoor>/bin/benchmarkoor ERIGON_SRC=<erigon checkout> CPUSET=5,13,6,14,7,15 run/nodebal.sh
```

- Clients: erigon as above, with `--exec.no-merge=true --exec.no-prune=true --exec.no-background-maintenance
  --experimental.parallel-commitment`; reth, nethermind, geth, besu, ethrex and nimbus are the ethpandaops
  glamsterdam-devnet-8 images with the BAL-mode flags of
  [benchmarkoor-tests](https://github.com/ethpandaops/benchmarkoor-tests) `clients.yaml`, pinned by digest in
  `run/nodebal.sh`. `ORDER` picks the clients.
- Method: as the node tier, except that a client that fails the smoke test is left out (`NOT_RUN` in the log) and each
  client keeps the tests valid in both of its passes. Output: `history/<UTC time>/{nodebal,passbal,versions}.csv`.
- What it is: Amsterdam gas costs and BAL parallel execution on a small state. What it is not: comparable to the Osaka
  node tier cell by cell (Amsterdam reprices gas), and not the large-state number. 14 of the 1177 tests are absent:
  filling them ran out of memory.

## RPC workloads

`workloads/<name>/` is a request corpus anyone can replay against their own mainnet node: `requests.jsonl` (one
JSON-RPC body per line, block tags pinned to a block number), `rates` (the open-loop rate ladder) and a `README` with
the method shares and the blocks a node must hold. `run/rpc.sh <workload> <url> <client>` runs the ladder with vegeta
and prints `workload,client,rate,rps,p50_ms,p95_ms,p99_ms,err`; `run/rpc-workload.py` builds a new workload from a
vegeta targets file or a file of JSON-RPC bodies. Results from different machines compare on latency at equal rate and
on the knee rate, not on peak rps.
[`workloads/README.md`](workloads/README.md) lists the node flags each client needs, which workloads each client can
serve, and how to regenerate the QA workloads at a new block.
