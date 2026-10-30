#!/usr/bin/env bash
# EEST benchmark blocks per sub-test: one 150M sub-test per process, wall time minus its no-block twin, best of REPEAT runs,
# arms interleaved per sub-test. Invocations, one exec worker for erigon and the nethermind warm pass are those of run/blocktest.sh.
# usage: run/subtests.sh <arm>...   arm = <name>=<erigon evm binary> | geth | revme | nethermind   (CATS="scenario instruction precompile")
# List erigon arms base build first: the page compares every later erigon arm with the first one.
# prints file,"sub",arm,gas,ms,twin_ms (CSV, the sub-test name may contain commas); builds blocktests/subtests/ with run/subtests-split.py if missing.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || { sed -n 4p "$0" >&2; exit 2; }
names=() bins=()
for a in "$@"; do
	case $a in
	*=*) [ -x "${a#*=}" ] || { echo "${a%%=*}: ${a#*=} is not executable" >&2; exit 2; }; names+=("${a%%=*}") bins+=("${a#*=}") ;;
	geth | revme | nethermind) names+=("$a") bins+=("") ;;
	*) echo "unknown arm $a" >&2; exit 2 ;;
	esac
done
idx=blocktests/subtests/index.tsv
[ -f $idx ] || run/subtests-split.py >&2 || exit 1
exec 9>"${BENCH_LOCK:-/tmp/bench.lock}"; flock 9
export PATH=$HOME/go/bin:$HOME/.cargo/bin:$PATH
export DOTNET_ROOT=${DOTNET_ROOT:-$HOME/.dotnet} NETHTEST=${NETHTEST:-$HOME/nethtest/nethtest}
now() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1e3'; }
# run <arm index> <sub-test> <file to time>: nethermind times the file second in one process, after a pass of the sub-test
run() {
	if [ -n "${bins[$1]}" ]; then env NO_BACKGROUND_E3_BUILD=true EXEC3_WORKERS=1 "${bins[$1]}" blocktest "$3" >/dev/null; return; fi
	case ${names[$1]} in
	geth) evm blocktest "$3" >/dev/null ;;
	revme) revme blockchaintest "$3" >/dev/null ;;
	nethermind) printf '%s\n' "$2" "$3" "" | "$NETHTEST" -b --parallelExecution false -x -j -n | { ! grep -q '"pass": false'; } ;;
	esac
}
best() { local b= s e; for _ in $(seq "${REPEAT:-3}"); do s=$(now); run "$@" 2>/dev/null || return 1; e=$(now); [ -z "$b" ] || [ $((e - s)) -lt "$b" ] && b=$((e - s)); done; echo "$b"; }
for cat in ${CATS:-scenario instruction precompile}; do
	# fd 3, so a client that reads stdin cannot eat the index
	while IFS=$'\t' read -r n c f gas sub <&3; do
		[ "$c" = "$cat" ] || continue
		t=blocktests/subtests/t/$n.json w=blocktests/subtests/w/$n.json
		for i in "${!names[@]}"; do
			ms=$(best "$i" "$t" "$t") || { echo "${names[$i]}: $c/$f $sub failed" >&2; continue; }
			tw=$(best "$i" "$t" "$w") || { echo "${names[$i]}: $c/$f $sub twin failed" >&2; continue; }
			echo "$c/$f,\"${sub//\"/\"\"}\",${names[$i]},$gas,$ms,$tw"
		done
	done 3< $idx
done
