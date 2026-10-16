# RPC workloads

Each directory is a request corpus pinned to mainnet block 26065472 (`latest` is replaced by that number), so every node
answers the same question. A node can serve a workload only if it holds what the requests read at those blocks.

## What each client holds

```
client      node flags                                                        history it serves
erigon      --prune.mode=full --prune.experimental.include-commitment-history state and traces 84k blocks below the pin (all seven workloads)
reth        --full                                                            state for the last 10064 blocks of its head
geth        path scheme (default), state history 90000 blocks                 eth_call and traces only for the most recent states; older
                                                                              blocks answer "historical state <root> is not available"
nethermind  full node                                                         no historical eth_call
```

## What each workload needs

```
workload        methods                               blocks below the pin   reads            erigon  reth  geth  nethermind
qa-mixed        13, eth_call 39%, see its README      0..2562                state, traces    yes     yes   no    no
qa-getlogs      eth_getLogs                           0..357                 logs             yes     yes   -     -
call-mix-33     eth_call                              0                      state            yes     yes   no    no
block-receipts  eth_getBlockReceipts                  1..3000                receipts         yes     yes   -     -
getlogs-1block  eth_getLogs                           1..3000                logs             yes     yes   -     -
trace-block-33  trace_block                           83959..83991           state, traces    yes     no    no    no
trace-tx-33     debug_traceTransaction                0                      state, traces    yes     yes   no    no
```

`yes`/`no` are measured or follow from the history above (geth `no` assumes its head is past the pin; a geth stopped at
the pin serves state at the pin, but not the trace-block-33 blocks); `-` is not measured (logs and receipts need no state, so
any node that keeps receipts should serve them). `run/rpc.sh` probes the first 100 requests and skips a workload the
node answers with errors, so a missing row means "cannot serve", not "slow".

## Run and renew

```
run/rpc.sh <workload> <url> <client>          # one workload's rate ladder -> workload,client,rate,rps,p50_ms,p95_ms,p99_ms,err
run/rpc-regen.sh <url> <rpc-tests checkout>   # qa-mixed@<head> and qa-getlogs@<head> from the node's current head
```

`run/rpc-regen.sh` runs `rpc_pattern_gen` from [erigontech/rpc-tests](https://github.com/erigontech/rpc-tests)
(`make rpc_pattern_gen` in the checkout) with the QA settings, then `run/rpc-workload.py` into new
`workloads/qa-mixed@<head>/` and `workloads/qa-getlogs@<head>/` directories; the existing ones stay. Point it at a node
that does not advance (no consensus client attached): its head becomes the pinned block, and the script stops if the
head moves during generation.
