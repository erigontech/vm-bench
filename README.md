# vm-bench

Real mainnet transactions as [EEST state tests](https://github.com/ethereum/execution-spec-tests), to compare EVM implementations on the same work.

`fixtures/mainnet/` holds one state test per transaction: the prestate the transaction touched, the block environment, the signed transaction (`txbytes`, so no secret key) and the post-state root and logs hash. Every runner that reads the EEST state-test format can time them; this repository ships the erigon runner.

```
make bench                      # erigon, every fixture, go benchmark output
make bench ARGS='-bench Mainnet/4-'   # one fixture
make fill TXREPLAY=<dir>        # rebuild the fixtures from erigon TxReplay fixtures
```

The erigon runner links erigon, which is LGPL-3.0; this repository is Apache-2.0.
