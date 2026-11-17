#!/bin/bash
# rivals.sh: BAL-on newPayload (the weekly's nodebal set) for the latest main/master images of reth, nethermind and geth.
# Writes the images, their digests and source revisions to ~/rivals/versions.txt; nodebal.sh writes history/<UTC>/nodebal.csv.
set -u
mkdir -p ~/rivals; v=~/rivals/versions.txt; : > $v
declare -A REF=([reth]=ethpandaops/reth:main [nethermind]=ethpandaops/nethermind:master [geth]=ethpandaops/geth:master)
for c in reth nethermind geth; do
  docker pull -q "${REF[$c]}" > /dev/null || { echo "$c PULL_FAILED ${REF[$c]}" >> $v; continue; }
  dig=$(docker image inspect --format '{{index .RepoDigests 0}}' "${REF[$c]}")
  rev=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${REF[$c]}")
  created=$(docker image inspect --format '{{.Created}}' "${REF[$c]}")
  ver=$(docker run --rm --entrypoint "" "${REF[$c]}" sh -c 'for b in reth geth nethermind /nethermind/nethermind; do command -v $b >/dev/null && { $b --version 2>/dev/null || $b version 2>/dev/null; break; }; done' 2>/dev/null | tr '\n' ' ' | cut -c1-200)
  echo "$c ${REF[$c]} revision=${rev:-unknown} created=$created digest=$dig version: $ver" >> $v
  export "IMG_$c=$dig"
done
cat $v
cd ~/vm-bench && env ERIGON_SRC=$HOME/erigon-vmb-main BENCHMARKOOR=$HOME/vm-bench-tools/benchmarkoor BALFIX=$HOME/bench/balfix ORDER="reth nethermind geth" BENCH_LOCK=/tmp/n5bench.lock run/nodebal.sh
echo RIVALS_DONE
