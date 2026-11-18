#!/bin/bash
# calls1024.sh <ref> <label>: calls1020.sh with p2p/authrpc/torrent ports moved off the archive erigon's 30303/8551/42069.
# SMOKE=1: erigon only, the div-loop fixture only (block body, then latest), 5 s of wrk.
export PATH=/home/erigon/sdk/go1.27.1/bin:/home/erigon/go/bin:$PATH GOTOOLCHAIN=local
B2=/home/erigon/bench B=/home/erigon/bench E=/home/erigon/erigon DONE=CALLS
. $B2/lib.sh
S=$(sha $1) || fail "NO_REF $1"; L=$2
D=$B2/runs/calls-${S:0:8}-$(date -u +%m%d%H%M)${SMOKE:+-smoke}; mkdir -p $D
exec > >(tee -a $D/log) 2>&1
echo "log $D/log ref=$S label=$L"
EBIN=$B2/bin/erigon-${S:0:12}
if [ ! -x $EBIN ]; then
  w=$(wt $S) || fail WT_FAIL
  flock /tmp/sweep20.lock bash -c "cd $w && timeout 30m make erigon" > $D/build.log 2>&1 && cp $w/build/bin/erigon $EBIN.tmp && mv $EBIN.tmp $EBIN || fail BUILD_FAIL $D/build.log
fi
until flock -n /tmp/sweep20.lock true; do sleep 10; done
ARMS="erigon reth" SWEEP_LIB=1 source /home/erigon/fair4/sweep21.sh
OUT=$D ERIGON_BIN=$EBIN
PORTS="--port=30403 --authrpc.port=8651 --torrent.port=42169"
erigon_up() { systemd-run --user -P -t -G --wait -p MemoryMax=$MEM --unit=erigon-bench \
    taskset -c "$SRV" "$ERIGON_BIN" --datadir "$DD" --chain=mainnet --prune.mode=full \
    --prune.experimental.include-commitment-history --private.api.addr=127.0.0.1:9195 \
    --externalcl --nodiscover --maxpeers=0 --no-downloader --txpool.disable $PORTS \
    --http.port=$EP --http.api=eth,debug,trace,net,web3 --log.console.verbosity=warn \
    --pprof --pprof.addr=127.0.0.1 --pprof.port=6070 > "$OUT/erigon-$1.log" 2>&1 < /dev/null & ERUN=$!; }
reth_up() { systemctl --user reset-failed reth-bench 2>/dev/null
  systemd-run --user -t -G -p MemoryMax=$MEM --unit=reth-bench taskset -c "$SRV" \
    "$HOME/rethmain/reth" node --full --datadir "$RD" --http --http.addr 127.0.0.1 --http.port $RP \
    --http.api eth,debug,trace,net,web3,txpool --max-peers 0 --disable-discovery --port 30413 --authrpc.port 8661 \
    --rpc-cache.max-blocks 16 > "$OUT/reth-$1.log" 2>&1 & }
echo "vm-bench $(git -C ~/vm-bench log -1 --format='%h %cd' --date=short) archive-erigon=$(pgrep -cx erigon) load=$(cut -d' ' -f1-3 /proc/loadavg)"
(cd ~/vm-bench && run/calls.py | head -1 | cut -f2) > $D/first-body
measure() { # measure <label> <url> <csv>
  echo "$1 head=$(( $(curl -s -m 10 -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' $2 | jq -r .result) )) $(date -u +%T)"
  taskset -c $LOAD wrk -t4 -c16 -d60s --timeout 30s -s $B2/bodies3.lua $2 -- $D/first-body > $D/warm-$1.txt
  (cd ~/vm-bench && SECS=10 taskset -c $LOAD run/calls.sh $1 $2 > $D/$3 2> $D/$3.err); echo "$1 calls.sh rc=$? rows=$(wc -l < $D/$3) latest=$(grep -c ',latest$' $D/$3) failed=$(grep -c 'call failed' $D/$3.err)"
}
erigon_up calls; wait_stable $EP || { echo NO_RESPONSE erigon; tail -20 $D/erigon-calls.log; echo CALLS_DONE; exit 1; }
echo "erigon $(sha256sum $EBIN | cut -c1-16)"
if [ -n "${SMOKE:-}" ]; then
  u=http://127.0.0.1:$EP/
  (cd ~/vm-bench && run/calls.py | grep div-loop) | while IFS=$'\t' read -r f body latest; do
    printf '%s\n' "$body" > $D/b; at=block
    curl -s -m 60 -H 'Content-Type: application/json' --data-binary @$D/b $u | head -c 300; echo
    curl -s -m 60 -H 'Content-Type: application/json' --data-binary @$D/b $u | grep -q '"result"' || { at=latest; printf '%s\n' "$latest" > $D/b; curl -s -m 60 -H 'Content-Type: application/json' --data-binary @$D/b $u | head -c 300; echo; }
    taskset -c $LOAD wrk -t4 -c16 -d5s --timeout 30s -s $B2/bodies3.lua $u -- $D/b | grep '^{' | jq -c --arg f "$f" --arg at $at '{f: $f, at: $at, rps: ((.requests - .status - .rpc_err) / (.duration_us / 1e6) | floor), err: (.status + .rpc_err)}'
  done
  erigon_down x; echo CALLS_DONE; exit 0
fi
measure $L http://127.0.0.1:$EP/ calls-erigon.csv
erigon_down x
RV=$($HOME/rethmain/reth --version | sed -n '1s/Reth Version: //p')
reth_up x; wait_stable $RP || { echo NO_RESPONSE reth; tail -20 $D/reth-x.log; reth_down x; echo CALLS_DONE; exit 1; }
AT_FROM=$D/calls-erigon.csv measure reth-$RV http://127.0.0.1:$RP/ calls-reth.csv
reth_down x
(cd ~/vm-bench && run/calls-match.py $D/calls-erigon.csv $D/calls-reth.csv > $D/calls.csv)
echo CALLS_DONE
