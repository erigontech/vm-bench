// Package fill turns erigon's BenchmarkTxReplay fixtures into state tests and fills their
// post-state root by running them on erigon:
//
//	VMBENCH_TXREPLAY=/path/to/txs go test ./fill -run TestFill
package fill

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/erigontech/erigon/common/hexutil"
	"github.com/stretchr/testify/require"

	"github.com/erigontech/vm-bench/statetest"
)

func TestFill(t *testing.T) {
	src := os.Getenv("VMBENCH_TXREPLAY")
	if src == "" {
		t.Skip("set VMBENCH_TXREPLAY to a directory of BenchmarkTxReplay fixtures")
	}
	paths, err := filepath.Glob(filepath.Join(src, "*.json"))
	require.NoError(t, err)
	require.NotEmpty(t, paths)
	out := filepath.Join("..", "fixtures", "mainnet")
	require.NoError(t, os.MkdirAll(out, 0o755))

	for _, path := range paths {
		name, fx, fork, err := statetest.FromTxReplay(path)
		require.NoError(t, err, path)
		t.Run(name, func(t *testing.T) {
			require.NoError(t, statetest.Write(out, name, fx))
			_, loaded, loadedFork, err := statetest.Load(filepath.Join(out, name+".json"))
			require.NoError(t, err)
			require.Equal(t, fork, loadedFork)
			root, logs, gasUsed := Fill(t, loaded, fork)
			require.Equal(t, fx.Info.GasUsed, hexutil.EncodeUint64(gasUsed), "gas used must match the mainnet receipt")

			fx.Post[fork][0].Hash = root.Hex()
			fx.Post[fork][0].Logs = logs.Hex()
			require.NoError(t, statetest.Write(out, name, fx))
		})
	}
}
