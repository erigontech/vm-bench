# fill: rebuild fixtures/mainnet from erigon BenchmarkTxReplay fixtures (TXREPLAY=<dir>)
# # refill: recompute hash/logs of every fixture after a format change
refill:
	VMBENCH_REFILL=1 go test ./fill -run TestRefill -count=1

bench: run every fixture on erigon's EVM
TXREPLAY ?= testdata/txreplay

fill:
	VMBENCH_TXREPLAY=$(abspath $(TXREPLAY)) go test ./fill -run TestFill -count=1

bench:
	go test -run '^$$' -bench BenchmarkFixtures -benchmem $(ARGS)

# fill-benchmarkoor: rebuild fixtures/benchmarkoor from the benchmarkoor compute payloads (PAYLOADS=<blockchain_tests_stateful_engine dir>)
PAYLOADS ?= testdata/benchmarkoor
fill-benchmarkoor:
	VMBENCH_BENCHMARKOOR=$(abspath $(PAYLOADS)) go test ./fill -run TestFillBenchmarkoor -count=1
