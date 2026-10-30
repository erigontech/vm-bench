# node-lib.sh: the part run/node.sh and run/nodebal.sh share. Sourced after the caller fills IMG (client -> image reference).
# Env: ERIGON_SRC=<clean erigon checkout> (make erigon at its HEAD) or ERIGON_IMAGE=<image>; ERIGON_LABEL (main|dbg, default main);
# BENCHMARKOOR (binary, default from PATH); WORK (cache, logs and raw results, default results/node); CPUSET (e.g. 0-5:
# full cores, default none); MEMORY (default 32g); BENCH_LOCK (default /tmp/bench.lock); NAME (run name). Relative paths are
# relative to the repo root.
set -uo pipefail
cd "$(dirname "$0")/.."
BENCHMARKOOR=${BENCHMARKOOR:-benchmarkoor} WORK=$(realpath -m "${WORK:-results/node}") MEMORY=${MEMORY:-32g}
ERIGON_BASE=${ERIGON_BASE:-ethpandaops/erigon:glamsterdam-devnet-7@sha256:4023a007fe974301277fdcae8446e4c1c491dfefc92c762a81b70aaadb32d535}
D=$WORK/${NAME:-$TIER-$(date -u +%m%d%H%M)}
declare -A REF
mkdir -p "$D"
exec > >(tee -a "$D/log") 2>&1
fail() { echo "$1"; [ -n "${2:-}" ] && sed "s/\x1b\[[0-9;]*m//g" "$2" | tail -20; exit 1; }
command -v "$BENCHMARKOOR" > /dev/null || fail "no benchmarkoor: set BENCHMARKOOR=<binary>"
echo "log $D/log"
exec 9>"${BENCH_LOCK:-/tmp/bench.lock}"; echo "wait lock $(date -u +%T)"; flock 9; echo "lock $(date -u +%T)"

# Sets IMG[erigon] and EV, the erigon cell of versions.csv.
if [ -n "${ERIGON_IMAGE:-}" ]; then
	docker image inspect "$ERIGON_IMAGE" > /dev/null 2>&1 || docker pull -q "$ERIGON_IMAGE" > /dev/null || fail "PULL_FAIL erigon"
	IMG[erigon]=$(docker image inspect --format '{{.Id}}' "$ERIGON_IMAGE") EV=${ERIGON_LABEL:-main}-${ERIGON_IMAGE##*[:/]}
	echo "erigon $ERIGON_IMAGE ${IMG[erigon]}"
else
	[ -d "${ERIGON_SRC:-}" ] || fail "set ERIGON_SRC=<erigon checkout> or ERIGON_IMAGE=<image>"
	git -C "$ERIGON_SRC" diff --quiet HEAD || fail "DIRTY $ERIGON_SRC"
	SE=$(git -C "$ERIGON_SRC" rev-parse HEAD) CTX=$D/ctx
	make -C "$ERIGON_SRC" erigon > "$D/build.log" 2>&1 || fail BUILD_FAIL "$D/build.log"
	mkdir -p "$CTX" && cp "$ERIGON_SRC/build/bin/erigon" "$CTX/"
	printf 'FROM %s\nCOPY --chown=0:0 erigon /usr/local/bin/erigon\n' "$ERIGON_BASE" > "$CTX/Dockerfile"
	docker build --iidfile "$CTX/iid" -t "vm-bench-erigon:${SE:0:12}" "$CTX" > "$D/img.log" 2>&1 || fail IMG_FAIL "$D/img.log"
	IMG[erigon]=$(tr -d '[:space:]' < "$CTX/iid") EV=${ERIGON_LABEL:-main}-${SE:0:10}
	echo "erigon $SE image=${IMG[erigon]:7:12} bin_sha256=$(sha256sum "$CTX/erigon" | cut -c1-16)"
fi
# Pull every other client in ORDER by its pinned reference, log the digest, then run the exact image ID.
for c in $ORDER; do
	[ "$c" = erigon ] && continue
	docker pull -q "${IMG[$c]}" > /dev/null || fail "PULL_FAIL $c"
	echo "$c $(docker image inspect --format '{{index .RepoDigests 0}}' "${IMG[$c]}")"
	REF[$c]=${IMG[$c]} IMG[$c]=$(docker image inspect --format '{{.Id}}' "${IMG[$c]}")
done

summary() { sed "s/\x1b\[[0-9;]*m//g" "$1" | grep -o "failed=[0-9]* .*passed=[0-9]* .*total=[0-9]*" | tail -1 | sed "s/instance=[^ ]* //;s/run_id=[^ ]* //"; }
passed1() { case "$(summary "$D/run-$1.log")" in *failed=0*passed=1\ * | *failed=0*passed=1) return 0 ;; esac; return 1; }
# Other sessions may run benchmarkoor without the lock: wait for them, then reap their orphan containers.
idle() {
	while pgrep -f "benchmarkoor run" > /dev/null; do sleep 15; done
	docker ps -q --filter name=benchmarkoor- | xargs -r docker rm -f > /dev/null
}
instance_extra() { :; } # the caller may print more YAML for the instance of client $1
arm() { # arm <client> <label> <filter> [timeout]: one fresh benchmarkoor run, results in $D/res-<label>
	local out=$D/res-$2 cpu=""
	[ -n "${CPUSET:-}" ] && cpu="        cpuset_topology: full_cores
        cpuset: [$CPUSET]
"
	idle
	rm -rf "$out" && mkdir -p "$out"
	{
		cat << YML
global:
  directories:
    cachedir: $WORK/cache
runner:
  container_runtime: docker
  container_network: benchmarkoor
  cleanup_on_start: false
  live_reporting:
    enabled: false
  benchmark:
    results_dir: $out
    tests:
      filter: "$3"
      source:
        eest_fixtures:
$SOURCE
  client:
    config:
      drop_memory_caches: disabled
      resource_limits:
${cpu}        memory: "$MEMORY"
        swap_disabled: true
  instances:
    - id: $TIER-$1
      client: $1
      image: ${IMG[$1]}
      pull_policy: never
YML
		# erigon answers SYNCING to a newPayload that arrives before its first stage-loop cycle ends.
		[ "$1" = erigon ] && cat << 'YML'
      bootstrap_fcu:
        enabled: true
        max_retries: 120
        backoff: 2s
      retry_new_payloads_syncing_state:
        enabled: true
        max_retries: 240
        backoff: 1s
YML
		instance_extra "$1"
	} > "$D/cfg-$2.yaml"
	BENCHMARKOOR_RUNNER_CLEANUP_ON_START=false timeout "${4:-6h}" "$BENCHMARKOOR" run --config "$D/cfg-$2.yaml" > "$D/run-$2.log" 2>&1
	echo "=== $2 rc=$? $(summary "$D/run-$2.log") $(date -u +%T)"
}
# passes <filter> <client...>: every client in order, then in reverse order, one fresh run each.
passes() {
	local f=$1 c
	shift
	for c in "$@"; do arm "$c" "p1-$c" "$f" "${PASS_TIMEOUT:-6h}"; done
	for c in $(printf '%s\n' "$@" | tac); do arm "$c" "p2-$c" "$f" "${PASS_TIMEOUT:-6h}"; done
}
# snapshot <csv script> "<csv files>" [args...]: release the lock, write the CSVs to $D, copy them to history/<UTC time>/.
snapshot() {
	local py=$1 files=$2 snap f
	shift 2
	exec 9>&-
	python3 "run/$py" "$D/res" "$D" "$@" || fail CSV_FAIL
	snap=history/$(date -u +%Y-%m-%dT%H%M)
	[ -e "$snap" ] && snap=${snap}b
	mkdir -p "$snap"
	for f in versions.csv $files; do cp "$D/$f" "$snap/"; done
	echo "snapshot $snap"
}
