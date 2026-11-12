#!/usr/bin/env bash
# Weekly: upgrade every other client to its latest release, record the versions, then measure the other clients in the tiers
# the nightly runs for erigon only (node BAL-off, node BAL-on, sub-tests). The nightly EVM blocks tier runs every client and
# picks up the upgraded tools. A client that fails to upgrade or run is listed in ~/vm-bench-weekly.txt, which A1 reads; a node-tier
# smoke failure lands there (and in the self-check) as soon as it happens.
# crontab (Sunday 16:00 UTC): 0 16 * * 0 BENCH_LOCK=/tmp/bench.lock flock -n /tmp/vmbench-weekly.lock ~/vm-bench/run/weekly.sh >> ~/vm-bench/weekly.log 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=$HOME/go/bin:$HOME/.cargo/bin:$HOME/.dotnet:$PATH DOTNET_ROOT=${DOTNET_ROOT:-$HOME/.dotnet}
export EVMONE=${EVMONE:-$HOME/evmone/bin/evmone} NETHTEST=${NETHTEST:-$HOME/nethtest/nethtest}
export LD_LIBRARY_PATH=$HOME/evmone/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export BENCHMARKOOR=${BENCHMARKOOR:-$HOME/vm-bench-tools/benchmarkoor}
export SMOKE_REPORT=$HOME/vm-bench-weekly.txt
report=$SMOKE_REPORT fails=()
echo "weekly $(date -u +%FT%TZ)" | tee "$report"
git pull -q --ff-only || fails+=("git pull")
latest() { curl -sfL "https://api.github.com/repos/$1/releases/latest" | jq -re .tag_name; }
# Progress goes to stderr: a step can redirect the stdout of its command into a results file.
step() { local what=$1; shift; echo "== $what" >&2; "$@" || { echo "FAILED $what" >&2; fails+=("$what"); return 1; }; }

# EVM tier tools (the nightly runs them)
up_geth() { local t; t=$(latest ethereum/go-ethereum) && go install "github.com/ethereum/go-ethereum/cmd/evm@$t"; }
up_revme() { local t; t=$(latest bluealloy/revm) && cargo install -q --locked --force --git https://github.com/bluealloy/revm --tag "$t" revme; }
up_evmone() {
	local t url tmp; t=$(latest ethereum/evmone) || return 1
	url=$(curl -sfL "https://api.github.com/repos/ethereum/evmone/releases/tags/$t" | jq -re '.assets[] | select(.name | test("linux-x86_64.tar.gz$")) | .browser_download_url') || return 1
	tmp=$HOME/evmone.new; rm -rf "$tmp" && mkdir "$tmp" && curl -sfL --retry 5 --retry-delay 10 "$url" | tar xz -C "$tmp" &&
		LD_LIBRARY_PATH=$tmp/lib "$tmp/bin/evmone" --version > /dev/null && rm -rf "$HOME/evmone" && mv "$tmp" "$HOME/evmone"
}
up_nethtest() {
	local t src=$HOME/nethermind-src; t=$(latest NethermindEth/nethermind) || return 1
	[ -d "$src" ] || git clone -q https://github.com/NethermindEth/nethermind "$src" || return 1
	git -C "$src" fetch -q --tags origin && git -C "$src" checkout -q "$t" &&
		dotnet build "$src/src/Nethermind/Nethermind.Test.Runner" -c Release -o "$HOME/nethtest.new" > "$HOME/nethtest-build.log" 2>&1 &&
		rm -rf "$HOME/nethtest" && mv "$HOME/nethtest.new" "$HOME/nethtest"
}
step "geth evm upgrade" up_geth
step "revme upgrade" up_revme
step "evmone upgrade" up_evmone
step "nethtest upgrade" up_nethtest

# Node BAL-off: each client's latest release image. Node BAL-on: the newest image under each pinned devnet tag.
for x in reth=paradigmxyz/reth=ghcr.io/paradigmxyz/reth nethermind=NethermindEth/nethermind=nethermind/nethermind geth=ethereum/go-ethereum=ethereum/client-go; do
	IFS== read -r c repo img <<< "$x"
	if t=$(latest "$repo"); then export "IMG_$c=$img:$t"; else fails+=("$c latest release"); fi
done
src=${ERIGON_MAIN:-$HOME/erigon-vmb-main}
step "node tier (reth nethermind geth)" env ERIGON_SRC="$src" ORDER="reth nethermind geth" run/node.sh
unset IMG_reth IMG_nethermind IMG_geth
for c in reth nethermind geth besu ethrex nimbus; do
	ref=$(sed -n "s/^\t\[$c\]=\([^@]*\)@.*/\1/p" run/nodebal.sh)
	[ -n "$ref" ] && export "IMG_$c=$ref"
done
step "BAL-on node tier (reth nethermind geth besu ethrex nimbus)" env ERIGON_SRC="$src" BALFIX="${BALFIX:-$HOME/bench/balfix}" ORDER="reth nethermind geth besu ethrex nimbus" run/nodebal.sh

# Sub-tests of the other clients; the nightly erigon run keeps their columns for 8 days.
if step "sub-tests (geth revme nethermind)" run/subtests.sh geth revme nethermind > results/st-weekly.csv 2> results/st-weekly.err; then
	step "sub-tests publish" run/subtests-publish.py results/st-weekly.csv "geth=geth $(evm --version | awk '{print $NF}')" \
		"revme=revm $(cargo install --list | sed -n 's/^revme .*tag=\([^#]*\).*/\1/p')" "nethermind=nethermind $("$NETHTEST" --version)" > /dev/null
fi
# Commit the snapshot alone, rebase it onto main, rebuild the page on the merged tree, push; a rejected push drops only the
# page commit and tries again. The snapshot commit is never dropped.
git checkout -q -- docs
git add history
if git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "weekly: other clients $(date -u +%F)"; then
	pushed=
	for i in 1 2 3; do
		git pull -q --rebase origin main || { git rebase --abort; fails+=("rebase"); break; }
		run/history.py
		git add docs && git -c user.name=vm-bench -c user.email=vm-bench@erigon.tech commit -q -m "page: $(ls history | tail -1)"
		git push -q origin HEAD:main && { pushed=1; break; }
		[[ $(git log -1 --format=%s) == page:* ]] && git reset -q --hard HEAD~1; sleep 30
	done
	[ -n "$pushed" ] || fails+=("push")
fi
while read -r _ _ tier c _; do fails+=("smoke $tier $c"); done < <(grep " SMOKE_FAIL " "$report")
verdict=$([ ${#fails[@]} = 0 ] && echo OK || printf 'FAILED %s; ' "${fails[@]}")
echo "$(date -u +%FT%H:%MZ) $verdict" | tee -a "$report"
