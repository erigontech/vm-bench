package vmbench

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/db/datadir"
	"github.com/erigontech/erigon/db/kv/temporal/temporaltest"
	"github.com/erigontech/erigon/db/state/execctx/execctxapi"
	"github.com/erigontech/erigon/execution/chain"
	"github.com/erigontech/erigon/execution/protocol"
	"github.com/erigontech/erigon/execution/state"
	"github.com/erigontech/erigon/execution/tests/testutil"
	"github.com/erigontech/erigon/execution/types"
	"github.com/erigontech/erigon/execution/types/accounts"
	"github.com/erigontech/erigon/execution/vm"
	"github.com/erigontech/erigon/execution/vm/evmtypes"
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/require"
)

// BenchmarkMainnet runs every fixture in fixtures/mainnet on erigon's EVM over the versioned
// state path eth_call uses, one transaction per iteration over its prestate.
func BenchmarkMainnet(b *testing.B) {
	paths, err := filepath.Glob(filepath.Join("fixtures", "mainnet", "*.json"))
	require.NoError(b, err)
	for _, path := range paths {
		name := strings.TrimSuffix(filepath.Base(path), ".json")
		b.Run(name, func(b *testing.B) {
			r := newRunner(b, path, name)
			res := r.run(b)
			require.Equal(b, r.gasUsed, res.ReceiptGasUsed, "gas used vs the mainnet receipt")
			b.ReportAllocs()
			for b.Loop() {
				r.run(b)
			}
		})
	}
}

type runner struct {
	cfg      *chain.Config
	rules    *chain.Rules
	blockCtx evmtypes.BlockContext
	reader   state.StateReader
	msg      *types.Message
	gasUsed  uint64
}

func newRunner(tb testing.TB, path, name string) *runner {
	tb.Helper()
	raw, err := os.ReadFile(path)
	require.NoError(tb, err)
	var tests map[string]testutil.StateTest
	require.NoError(tb, json.Unmarshal(raw, &tests))
	var info struct {
		Info struct {
			GasUsed hexutil.Uint64 `json:"gasUsed"`
		} `json:"_info"`
	}
	require.NoError(tb, json.Unmarshal(json.RawMessage(mustInner(tb, raw, name)), &info))
	st := tests[name]
	require.Len(tb, st.Json.Post, 1, "one fork per fixture")
	var fork string
	for fork = range st.Json.Post {
	}
	cfg, _, err := testutil.GetChainConfig(fork)
	require.NoError(tb, err)

	env := st.Json.Env
	header := &types.Header{
		Coinbase:      env.Coinbase,
		GasLimit:      env.GasLimit,
		Time:          env.Timestamp,
		BaseFee:       env.BaseFee,
		ExcessBlobGas: env.ExcessBlobGas,
	}
	header.Number.SetUint64(env.Number)
	if env.Difficulty != nil {
		header.Difficulty.Set(env.Difficulty)
	}
	if env.Random != nil {
		header.MixDigest = env.Random.Bytes32()
	}
	noHashes := func(uint64) (common.Hash, error) { return common.Hash{}, nil }
	blockCtx := protocol.NewEVMBlockContext(header, noHashes, nil, accounts.InternAddress(env.Coinbase), cfg)
	rules := blockCtx.Rules(cfg)

	db := temporaltest.NewTestDB(tb, datadir.New(tb.TempDir()))
	tx, domains := temporaltest.NewTestTxSD(tb, db)
	_, err = testutil.MakePreStateInto(&chain.Rules{}, domains, tx, st.Json.Pre, env.Number)
	require.NoError(tb, err)

	post := st.Json.Post[fork][0]
	signer := types.LatestSignerForChainID(cfg.ChainID)
	txn, err := types.DecodeTransaction(post.Tx)
	require.NoError(tb, err)
	var baseFee *uint256.Int
	if header.BaseFee != nil {
		baseFee = header.BaseFee
	}
	msg, err := txn.AsMessage(*signer, baseFee, rules)
	require.NoError(tb, err)
	msg.SetCheckNonce(false)
	msg.SetCheckTransaction(false)
	msg.SetCheckGas(false)

	return &runner{
		cfg:      cfg,
		rules:    rules,
		blockCtx: blockCtx,
		reader:   state.NewReaderV3(domains.AsStateGetter(tx, execctxapi.StateGetterOptions{})),
		msg:      msg,
		gasUsed:  uint64(info.Info.GasUsed),
	}
}

// run executes the transaction once on a pooled versioned state, as erigon's eth_call does.
func (r *runner) run(tb testing.TB) *evmtypes.ExecutionResult {
	ibs := state.NewPooled(r.reader)
	defer state.ReleasePooled(ibs)
	ibs.SetVersionMap(state.NewVersionMap(nil))
	ibs.SetNoMaterialize(true)
	ibs.SetTxContext(0, 0)
	ibs.SetNoConflictDetection()
	txCtx := protocol.NewEVMTxContext(r.msg)
	vmConfig := vm.Config{NoReceipts: true, NoBAL: true}
	evm := vm.NewEVM(r.blockCtx, txCtx, ibs, r.cfg, vmConfig)
	gp := new(protocol.GasPool).AddGas(r.msg.Gas()).AddBlobGas(r.msg.BlobGas())
	res, err := protocol.ApplyMessage(evm, r.msg, gp, true, false, nil)
	require.NoError(tb, err)
	return res
}

func mustInner(tb testing.TB, raw []byte, name string) []byte {
	tb.Helper()
	var outer map[string]json.RawMessage
	require.NoError(tb, json.Unmarshal(raw, &outer))
	inner, ok := outer[name]
	require.True(tb, ok)
	return inner
}
