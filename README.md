# vm-bench

Results: **https://erigontech.github.io/vm-bench/** (updated nightly).

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

## RPC workloads

`workloads/<name>/` is a request corpus anyone can replay against their own mainnet node: `requests.jsonl` (one
JSON-RPC body per line, block tags pinned to a block number), `rates` (the open-loop rate ladder) and a `README` with
the method shares and the blocks a node must hold. `run/rpc.sh <workload> <url> <client>` runs the ladder with vegeta
and prints `workload,client,rate,rps,p50_ms,p95_ms,p99_ms,err`; `run/rpc-workload.py` builds a new workload from a
vegeta targets file or a file of JSON-RPC bodies. Results from different machines compare on latency at equal rate and
on the knee rate, not on peak rps.
[`workloads/README.md`](workloads/README.md) lists the node flags each client needs, which workloads each client can
serve, and how to regenerate the QA workloads at a new block.
