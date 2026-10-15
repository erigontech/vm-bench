// Package fill turns erigon's BenchmarkTxReplay fixtures into state tests and fills their
// post-state root by running them on erigon:
//
//	VMBENCH_TXREPLAY=/path/to/txs go test ./fill -run TestFill
package fill

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/db/datadir"
	"github.com/erigontech/erigon/db/kv/temporal/temporaltest"
	"github.com/erigontech/erigon/execution/tests/testutil"
	"github.com/erigontech/erigon/execution/vm"
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
			st := load(t, filepath.Join(out, name+".json"), name)

			db := temporaltest.NewTestDB(t, datadir.New(t.TempDir()))
			tx, domains := temporaltest.NewTestTxSD(t, db)
			ibs, root, gasUsed, err := st.RunNoVerify(domains, tx, testutil.StateSubtest{Fork: fork, Index: 0}, vm.Config{})
			require.NoError(t, err)
			require.Equal(t, fx.Info.GasUsed, hexutil.EncodeUint64(gasUsed), "gas used must match the mainnet receipt")

			fx.Post[fork][0].Hash = root.Hex()
			fx.Post[fork][0].Logs = ibs.LogsRlpHash().Hex()
			require.NoError(t, statetest.Write(out, name, fx))
		})
	}
}

func load(t *testing.T, path, name string) *testutil.StateTest {
	t.Helper()
	raw, err := os.ReadFile(path)
	require.NoError(t, err)
	var tests map[string]testutil.StateTest
	require.NoError(t, json.Unmarshal(raw, &tests))
	st, ok := tests[name]
	require.True(t, ok, "fixture %s not found in %s", name, path)
	return &st
}
