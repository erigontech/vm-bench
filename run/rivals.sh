#!/bin/bash
# rivals.sh: BAL-on newPayload (the nodebal set) for the latest main/master images of reth, nethermind and geth, run by the
# nightly only when an image changed since the last measured run (~/vm-bench-rivals.digests); versions.csv names each commit.
set -u
cd "$(dirname "$0")/.."
st=$HOME/vm-bench-rivals.digests new="" changed=0
declare -A REF=([reth]=ethpandaops/reth:main [nethermind]=ethpandaops/nethermind:master [geth]=ethpandaops/geth:master)
for c in reth nethermind geth; do
	docker pull -q "${REF[$c]}" > /dev/null || { echo "rivals: $c pull of ${REF[$c]} failed"; exit 1; }
	dig=$(docker image inspect --format '{{index .RepoDigests 0}}' "${REF[$c]}")
	grep -qxF "$c $dig" "$st" 2> /dev/null || changed=1
	ver=$(docker run --rm --entrypoint "" "${REF[$c]}" sh -c 'for b in reth geth nethermind /nethermind/nethermind; do command -v $b > /dev/null && { $b --version 2>/dev/null || $b version 2>/dev/null; break; }; done' 2> /dev/null | tr '\n' ' ')
	case $c in
	reth) sha=$(grep -oE 'Commit SHA: [0-9a-f]{10}' <<< "$ver" | cut -d' ' -f3) ;;
	geth) sha=$(grep -oE 'unstable-[0-9a-f]{8}' <<< "$ver" | cut -d- -f2) ;;
	nethermind) sha=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${REF[$c]}" | cut -c1-10) ;;
	esac
	export "IMG_$c=$dig" "VER_$c=main-${sha:-unknown} (${dig%%@*}@${dig##*sha256:})"
	new+="$c $dig"$'\n'
	echo "rivals: $c ${sha:-unknown} $dig"
done
[ $changed = 1 ] || { echo "rivals: no new main image since the last run"; exit 0; }
ORDER="reth nethermind geth" run/nodebal.sh || exit 1
printf '%s' "$new" > "$st"
echo RIVALS_DONE
