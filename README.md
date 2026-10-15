# vm-bench

Real mainnet transactions as [EEST state tests](https://github.com/ethereum/execution-spec-tests), to compare EVM implementations on the same work.

`fixtures/mainnet/` holds one state test per mainnet transaction: the prestate the transaction touched, the block environment, the signed transaction (`txbytes`, so no secret key) and the post-state root and logs hash. Every runner that reads the EEST state-test format can time them; this repository ships the erigon runner.

```
make bench                      # erigon, every fixture, go benchmark output
make bench ARGS='-bench Mainnet/4-'   # one fixture
make fill TXREPLAY=<dir>        # rebuild fixtures/mainnet from erigon TxReplay fixtures
make fill-benchmarkoor PAYLOADS=<dir>   # rebuild fixtures/benchmarkoor from the benchmarkoor compute payloads
make refill                     # recompute every fixture's post state after a format change
run/all.sh                      # every installed runner, then the Mgas/s table
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
