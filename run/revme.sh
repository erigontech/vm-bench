#!/usr/bin/env bash
# revm: revme statetest; ns per transaction, execution only (its "Total CPU time"), best of REPEAT.
# install: cargo install --locked --git https://github.com/bluealloy/revm revme
set -euo pipefail
cd "$(dirname "$0")/.."
for f in fixtures/*/*.json; do
	key=${f#fixtures/}; key=${key%.json}
	args=(); for _ in $(seq "${REPEAT:-3}"); do args+=("$f"); done
	ns=$(revme statetest -s --omit-progress "${args[@]}" 2>/dev/null | awk '/Total CPU time/ { t = $NF + 0; if (min == "" || t < min) min = t } END { if (min != "") printf "%.0f", min * 1e9 }')
	[ -n "$ns" ] && echo "$key,revme,$ns" || echo "revme: $key failed" >&2
done
