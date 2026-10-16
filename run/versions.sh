#!/usr/bin/env bash
# client,version of every installed tool, for the history snapshot.
cd "$(dirname "$0")/.."
echo "erigon,$(go list -m -f '{{.Version}}' github.com/erigontech/erigon)"
[ -x "${ERIGON_EVM:-$HOME/bin/erigon-evm}" ] && echo "erigon-evm,$("${ERIGON_EVM:-$HOME/bin/erigon-evm}" --version 2>/dev/null | awk '{print $NF}')"
command -v evm >/dev/null && echo "geth,$(evm --version | awk '{print $NF}')"
command -v revme >/dev/null && echo "revme,$(cargo install --list 2>/dev/null | grep -o 'revm#[0-9a-f]*' | head -1)"
[ -x "${EVMONE:-}" ] && echo "evmone,$("$EVMONE" --version | awk '{print $2}')"
[ -x "${NETHTEST:-}" ] && echo "nethermind,$("$NETHTEST" --version)"
exit 0
