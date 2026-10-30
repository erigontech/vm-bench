---
name: vm-bench
description: Work in the vm-bench repo (cross-client EVM, node and RPC benchmarks, results page at erigontech.github.io/vm-bench). Use for any change to fixtures, runners, workloads, history snapshots or the page, and before measuring anything on the bench boxes.
---

# vm-bench

Fair, reproducible numbers across EVM clients, published at https://erigontech.github.io/vm-bench/
(`docs/index.html`, GitHub Pages from `main:/docs`). Three tiers, each honest about what it measures:

```
tier          what                                               clients                              script -> snapshot file
EVM blocks    EEST benchmark blocks through each client's own    erigon, geth, revm, evmone,          run/all.sh -> blocktest.csv
              blockchain-test tool, minus a no-block twin        nethermind, gevm
EVM sub-test  one 150M block per EEST sub-test, erigon builds    erigon builds, nethermind            run/subtests.sh + run/subtests-publish.py
              against each other (one exec worker)                                                     -> subtests.csv, subtest-arms.csv
node          benchmarkoor newPayload Mgas/s, EEST genesis per   erigon, reth, nethermind, geth       run/node.sh -> node.csv, pass.csv
              test (small state)
node BAL-on   same on Amsterdam blocks with a BAL                + besu, ethrex, nimbus               run/balfix.sh, run/nodebal.sh -> nodebal.csv
RPC           replayable request corpora, open-loop rate ladder  erigon, reth                         run/rpc.sh -> rpcw.csv
RPC           recorded-request scenarios; eth_call per fixture   erigon (+ reth)                      run/rpc-import.py, run/calls.sh -> rpc.csv, calls.csv
```

The older state-test runners (`run/<client>.sh`, `fixtures/`, `history/<t>/<client>.csv`) stay for erigon-vs-revm only:
geth's `--bench` rebuilds the pre-state per iteration and evmone/nethtest are process wall time, so their columns are
marked `*` and must never be quoted as an EVM comparison.

## Rules that keep the numbers fair

- **Trend = main, tables = dbg.** The Progress trend has one main point per day. Its last point is today's dbg build
  (the dbg branch = main + open PRs): an entry in `history/runs.json` with `"dbg": true`, drawn hollow with its sha, and
  replaced by that day's main point the next day; older dbg entries stay in the file but are never drawn. Every table
  shows the latest dbg run (`versions.csv` has `erigon,dbg-<sha>`) and falls back to the latest main run when dbg has no
  data for the tier or a later day has a main run; each table names the build it shows. Measure main HEAD and dbg HEAD
  every night in every tier, the RPC throughput scenarios (`rpcenv.sh <ref> m33,cal33,callmany11,est33,trace33,trc33,trcblk33,trcmany11 base=`
  on the RPC box, then `run/rpc-import.py <log>`) and `run/calls.sh` included; when the RPC box is busy with another
  run, skip it that night and say so. Main feeds the trend and the nightly diff, dbg feeds the tables and today's point. A
  journal card compares main with the previous main point, never with a dbg build. One page only: no per-branch pages.
- **Measure only on the bench box, under its lock.** Every measuring script takes the lock in `BENCH_LOCK`
  (`run/all.sh` does it itself). Never build, profile or run anything else on the box while a run holds the lock.
  Numbers taken without the lock are void; delete them from history. Never measure on a laptop.
- **Setup is subtracted, not estimated.** Mgas/s = gas / (T(file) − T(twin)); the twin is the same genesis with no
  blocks. Grey (excluded from the hero and the trend) when twin/T > 0.3, net < 100 ms, or the file carries a setup block
  before its benchmark block (gas > eight 150M blocks): the twin drops the setup, so the time would measure it. A client with fewer than half its blocks valid
  is left out of the hero.
- **Same work for every client.** One test per file, eight sequential copies of its 150M-gas block
  (`run/eest-select.py <fixtures> 150M 8`), so runners that parallelise a file's tests (nethtest, revme) cannot.
  nethtest runs with `--parallelExecution false` (no BAL parallel execution). nethtest's ~3 s dotnet start-up is
  cancelled by timing the file and the twin in one process after a warm pass; so its twin/T is always high and only
  the 100 ms floor greys its cells.
- **The EVM tier compares interpreters: one thread per client.** erigon runs with one exec worker (`EXEC3_WORKERS=1`
  in `run/blocktest.sh`), like the serial path; its default parallel executor would spread a one-sender block over
  several cores. The node tier keeps every client's default multi-core node.
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

## Refresh the page for today's main and dbg

Every tier measures both builds: main feeds the trend, dbg (main + open PRs) feeds the tables.

```
make -C <erigon main checkout> evm  &&  make -C <erigon dbg checkout> evm     # one binary per build, note both shas
ERIGON_EVM=<dbg evm> CLIENTS=erigon run/all.sh    # EVM blocks for dbg (the nightly cron does main and the other clients)
run/subtests.sh main=<main evm> dbg=<dbg evm> nethermind > results/subtests.csv
run/subtests-publish.py results/subtests.csv 'main=main <sha>' 'dbg=dbg <sha>'
ERIGON_SRC=<checkout> ERIGON_LABEL=dbg run/node.sh                             # node tier, same for main
ERIGON_SRC=<checkout> ERIGON_LABEL=dbg run/nodebal.sh                          # needs run/balfix.sh once
run/history.py   # then the JS OK check below, then commit history/ + docs/
```

List erigon arms base build first: the sub-test table compares later builds with the first, and the last with nethermind.
Each section of the page prints the build and date it shows; data older than 36 h is red. A section with stale data is
rerun, not explained.

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
node -e 'const fs=require("fs");const h=fs.readFileSync("docs/index.html","utf8");const m=h.match(/<script>([\s\S]*)<\/script>/);const document={getElementById:()=>({set innerHTML(v){},set textContent(v){},addEventListener(){},set hidden(v){},scrollIntoView(){},getBoundingClientRect:()=>({top:0})}),querySelectorAll:()=>[],querySelector:()=>({classList:{add(){}}}),documentElement:{},addEventListener(){}};globalThis.document=document;globalThis.addEventListener=()=>{};globalThis.getComputedStyle=()=>({getPropertyValue:()=>"#000"});eval(m[1]);console.log("JS OK")'
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
