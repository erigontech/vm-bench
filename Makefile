# fill: rebuild fixtures/mainnet from erigon BenchmarkTxReplay fixtures (TXREPLAY=<dir>)
# bench: run every mainnet fixture on erigon's EVM
TXREPLAY ?= testdata/txreplay

fill:
	VMBENCH_TXREPLAY=$(abspath $(TXREPLAY)) go test ./fill -run TestFill -count=1

bench:
	go test -run '^$$' -bench BenchmarkMainnet -benchmem $(ARGS)
