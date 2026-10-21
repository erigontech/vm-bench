---
name: vm-bench
description: Work in the vm-bench repo (cross-client EVM, node and RPC benchmarks, results page at erigontech.github.io/vm-bench). Use for any change to fixtures, runners, workloads, history snapshots or the page, and before measuring anything on the bench boxes.
---

# vm-bench

Fair, reproducible numbers across EVM clients, published at https://erigontech.github.io/vm-bench/
(`docs/index.html`, GitHub Pages from `main:/docs`). Three tiers, each honest about what it measures:

```
tier    what                                              clients                                 data
EVM     EEST benchmark blocks through each client's own    erigon, geth, revm (reth's EVM),        history/<t>/blocktest.csv
        blockchain-test tool, minus a no-block twin        evmone, nethermind
node    benchmarkoor newPayload Mgas/s, EEST               erigon, reth, nethermind, geth          history/<t>/node.csv
        tests-benchmark genesis per test (small state)
RPC     replayable request corpora, open-loop rate ladder  erigon, reth (geth/neth full nodes      history/<t>/rpcw.csv
                                                           cannot serve historical calls)
```

The older state-test runners (`run/<client>.sh`, `fixtures/`, `history/<t>/<client>.csv`) stay for erigon-vs-revm only:
geth's `--bench` rebuilds the pre-state per iteration and evmone/nethtest are process wall time, so their columns are
marked `*` and must never be quoted as an EVM comparison.

## Rules that keep the numbers fair

- **Measure only on the bench box, under its lock.** Every measuring script takes the lock in `BENCH_LOCK`
  (`run/all.sh` does it itself). Never build, profile or run anything else on the box while a run holds the lock.
  Numbers taken without the lock are void; delete them from history. Never measure on a laptop.
- **Setup is subtracted, not estimated.** Mgas/s = gas / (T(file) − T(twin)); the twin is the same genesis with no
  blocks. Grey (excluded from the hero) when twin/T > 0.3 or net < 100 ms. A client with fewer than half its blocks valid
  is left out of the hero.
- **Same work for every client.** One test per file, eight sequential copies of its 150M-gas block
  (`run/eest-select.py <fixtures> 150M 8`), so runners that parallelise a file's tests (nethtest, revme) cannot.
  nethtest runs with `--parallelExecution false` (no BAL parallel execution). nethtest's ~3 s dotnet start-up is
  cancelled by timing the file and the twin in one process after a warm pass; so its twin/T is always high and only
  the 100 ms floor greys its cells.
- **Precompile groups compare caches.** EEST precompile tests repeat one input and geth and nethermind cache precompile
  results, so precompile rows stay in the tables but never in a hero.
- **Reproducibility is part of the result.** Rerun the same binaries: the EVM tier reproduces within 0.4% (nethermind ±4%: quote its geomean with that, never one cell), the node
  tier within 1.3% pass to pass. RPC: compare on the knee rung (highest rate served in full without errors) and on
  latency one rung below it; latency at the knee is not reproducible (open loop). Each rung sends ≥ 20000 requests.
- **Node tier: one execution per test per container.** Sending the same test again in one container measures nothing:
  erigon answers a block it already has with VALID in under a millisecond. Take more samples with more fresh containers.
- **Pin everything.** Client versions go to `history/<t>/versions.csv`; RPC corpora pin `latest` to a block number;
  node-tier images are pinned by digest in the run log.

## Layout

```
fixtures/{benchmarkoor,mainnet-edge-cases,mainnet-popular}   state tests (plain minified JSON, committed)
blocktests/                                                  EEST blocks + twins, gitignored, rebuilt by run/eest-select.py
workloads/<name>[@<block>]/{requests.jsonl,rates,README}     RPC corpora (plain JSONL, committed; never gzip or tar)
history/<UTC time>/                                          one snapshot per run: *.csv + versions.csv
run/page.html  ->  run/history.py  ->  docs/index.html       page template, data inliner, published page
```

## Common tasks

```
run/all.sh                                  # state tests + EEST blocks for every client, snapshot, page (takes the lock)
CLIENTS="erigon" run/all.sh                 # one client; replaces only its rows
FILTER="keccak*" REPEAT=1 run/blocktest.sh <client>    # quick check of a few EEST files
run/rpc.sh <workload> <url> <client>        # one RPC workload's ladder
run/rpc-regen.sh <url> <rpc-tests checkout> # new qa-mixed@<head>, qa-getlogs@<head>; old corpora stay
run/rpc-workload.py <name> <corpus> <block> <rates...>   # new workload from vegeta targets or JSON-RPC bodies
make fetch TX=0xhash=label,... GROUP=mainnet-popular      # add a mainnet tx as a state test
run/popular.py 10 200 [end block]           # top contracts by gas, one representative tx each
```

After any change to `run/page.html` or a snapshot:

```
run/history.py
node -e 'const fs=require("fs");const h=fs.readFileSync("docs/index.html","utf8");const m=h.match(/<script>([\s\S]*)<\/script>/);const document={getElementById:()=>({set innerHTML(v){},set textContent(v){},addEventListener(){},set hidden(v){},scrollIntoView(){}}),querySelectorAll:()=>[],querySelector:()=>({classList:{add(){}}}),documentElement:{},addEventListener(){}};globalThis.document=document;globalThis.getComputedStyle=()=>({getPropertyValue:()=>"#000"});eval(m[1]);console.log("JS OK")'
```

One JS error blanks the whole page, so never push `docs/` without the `JS OK` line. Screenshot with headless Chrome
when the layout changed.

## Bench box

- Runner paths come from `run/all.sh` (env `EVMONE`, `NETHTEST`, `DOTNET_ROOT`, `LD_LIBRARY_PATH`); set them there,
  not in the per-client scripts.
- The erigon runner must be built from current erigon main with the Makefile's cgo flags (`-O3 -DNDEBUG`); a stale
  or plain `go build` binary hides erigon work and inflates cgo precompiles. `run/versions.sh` records its version.
  It runs with `NO_BACKGROUND_E3_BUILD=true`: without it, Close waits for background file builds in 3 s ticks and a
  file reads up to 16x slower at random.
- Fixtures: `fixtures_benchmark.tar.gz` of the execution-specs release `tests-benchmark@v0.0.9` (the version erigon's CI pins),
  sha256 `5aee5d1bf7430d5b6ca5b48269dd2a1fb0f9df39ac1e980bac9fc56ad403b8c7`, checked after download and unpacked on the box.
  A fixture change breaks every EVM-tier cell: rerun all clients and start a new series in `history/runs.json`.
  The node tier needs a benchmarkoor checkout and docker.
- If the box has no GitHub credentials, commit there and push from a machine that has them. Keep both clones in
  sync: `git checkout -- docs` and remove an already-pushed snapshot dir before `git pull` on the box.
- The nightly cron (`run/nightly.sh`) also takes the lock.

## Writing

- Page and README text: no box names, no run counts, no internal ticket or agent names. State fixture tag, client
  versions, what the number is and is not (for example "small state, not the large-state number").
- Commits `area: subject`, terse; no attribution lines.
- A result with a known harness artifact gets fixed in the harness and re-measured, not footnoted.
