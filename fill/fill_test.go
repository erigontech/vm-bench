// Package fill turns erigon's BenchmarkTxReplay fixtures into state tests and fills their
// post-state root by running them on erigon:
//
//	VMBENCH_TXREPLAY=/path/to/txs go test ./fill -run TestFill
package fill

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/stretchr/testify/require"

	"github.com/erigontech/vm-bench/statetest"
)

var preSpuriousDragon = map[string]bool{"Frontier": true, "Homestead": true, "EIP150": true}

func TestFill(t *testing.T) {
	src := os.Getenv("VMBENCH_TXREPLAY")
	if src == "" {
		t.Skip("set VMBENCH_TXREPLAY to a directory of BenchmarkTxReplay fixtures")
	}
	paths, err := filepath.Glob(filepath.Join(src, "*.json"))
	require.NoError(t, err)
	require.NotEmpty(t, paths)
	out := filepath.Join("..", "fixtures", "mainnet-edge-cases")
	require.NoError(t, os.MkdirAll(out, 0o755))

	for _, path := range paths {
		name, fx, fork, err := statetest.FromTxReplay(path)
		require.NoError(t, err, path)
		if preSpuriousDragon[fork] {
			t.Logf("skip %s: erigon's commitment cannot hold the empty accounts %s persists", name, fork)
			continue
		}
		t.Run(name, func(t *testing.T) { writeFilled(t, out, name, fx, fork) })
	}
}

// TestFetch builds fixtures for mainnet transactions from an archive node and fills them:
//
//	VMBENCH_FETCH=0xhash[=label],... VMBENCH_RPC=https://eth.drpc.org go test ./fill -run TestFetch
func TestFetch(t *testing.T) {
	txs := os.Getenv("VMBENCH_FETCH")
	if txs == "" {
		t.Skip("set VMBENCH_FETCH to transaction hashes, each with an optional =label")
	}
	url := os.Getenv("VMBENCH_RPC")
	if url == "" {
		url = "https://eth.drpc.org"
	}
	group := os.Getenv("VMBENCH_GROUP")
	if group == "" {
		group = "mainnet-edge-cases"
	}
	out := filepath.Join("..", "fixtures", group)
	require.NoError(t, os.MkdirAll(out, 0o755))
	for _, item := range strings.Split(txs, ",") {
		hash, label, _ := strings.Cut(item, "=")
		name := hash[2:10]
		if label != "" {
			name += "-" + label
		}
		t.Run(name, func(t *testing.T) {
			fx, fork, err := statetest.FromRPC(url, common.HexToHash(hash), name)
			require.NoError(t, err)
			writeFilled(t, out, name, fx, fork)
		})
	}
}

func writeFilled(t *testing.T, out, name string, fx *statetest.Fixture, fork string) {
	require.NoError(t, statetest.Write(out, name, fx))
	_, loaded, loadedFork, err := statetest.Load(filepath.Join(out, name+".json"))
	require.NoError(t, err)
	require.Equal(t, fork, loadedFork)
	root, logs, gasUsed := Fill(t, loaded, fork)
	require.Equal(t, fx.Info.GasUsed, hexutil.EncodeUint64(gasUsed), "gas used must match the mainnet receipt")

	fx.Post[fork][0].Hash = root.Hex()
	fx.Post[fork][0].Logs = logs.Hex()
	require.NoError(t, statetest.Write(out, name, fx))
}

// TestRefill recomputes the post state of every fixture after a format change:
//
//	VMBENCH_REFILL=1 go test ./fill -run TestRefill
func TestRefill(t *testing.T) {
	if os.Getenv("VMBENCH_REFILL") == "" {
		t.Skip("set VMBENCH_REFILL=1 to rewrite fixtures/*/*.json")
	}
	paths, err := filepath.Glob(filepath.Join("..", "fixtures", "*", "*.json"))
	require.NoError(t, err)
	require.NotEmpty(t, paths)
	for _, path := range paths {
		name, fx, fork, err := statetest.Load(path)
		require.NoError(t, err, path)
		t.Run(name, func(t *testing.T) {
			root, logs, gasUsed := Fill(t, fx, fork)
			require.Equal(t, fx.Info.GasUsed, hexutil.EncodeUint64(gasUsed), "gas used must match the recorded receipt")
			fx.Post[fork][0].Hash = root.Hex()
			fx.Post[fork][0].Logs = logs.Hex()
			require.NoError(t, statetest.Write(filepath.Dir(path), name, fx))
		})
	}
}
