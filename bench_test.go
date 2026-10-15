package vmbench

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/holiman/uint256"
	"github.com/stretchr/testify/require"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/db/datadir"
	"github.com/erigontech/erigon/db/kv/temporal/temporaltest"
	"github.com/erigontech/erigon/db/state/execctx/execctxapi"
	"github.com/erigontech/erigon/execution/chain"
	"github.com/erigontech/erigon/execution/protocol"
	"github.com/erigontech/erigon/execution/protocol/rules/ethash"
	"github.com/erigontech/erigon/execution/state"
	"github.com/erigontech/erigon/execution/tests/testutil"
	"github.com/erigontech/erigon/execution/types"
	"github.com/erigontech/erigon/execution/types/accounts"
	"github.com/erigontech/erigon/execution/vm"
	"github.com/erigontech/erigon/execution/vm/evmtypes"

	"github.com/erigontech/vm-bench/statetest"
)

// BenchmarkFixtures runs every fixture under fixtures/ on erigon's EVM over the versioned
// state path eth_call uses, one transaction per iteration over its prestate.
func BenchmarkFixtures(b *testing.B) {
	paths, err := filepath.Glob(filepath.Join("fixtures", "*", "*.json"))
	require.NoError(b, err)
	for _, path := range paths {
		name := filepath.Base(filepath.Dir(path)) + "/" + strings.TrimSuffix(filepath.Base(path), ".json")
		b.Run(name, func(b *testing.B) {
			r := newRunner(b, path)
			res := r.run(b)
			require.Equal(b, r.gasUsed, res.ReceiptGasUsed, "gas used vs the fixture")
			b.ReportAllocs()
			for b.Loop() {
				r.run(b)
			}
		})
	}
}

type runner struct {
	cfg      *chain.Config
	blockCtx evmtypes.BlockContext
	reader   state.StateReader
	msg      *types.Message
	gasUsed  uint64
}

func newRunner(tb testing.TB, path string) *runner {
	tb.Helper()
	_, fx, fork, err := statetest.Load(path)
	require.NoError(tb, err)
	cfg, err := statetest.Rules(fork)
	require.NoError(tb, err)
	header, err := fx.Env.Header()
	require.NoError(tb, err)
	alloc, err := fx.Alloc()
	require.NoError(tb, err)
	gasUsed, err := hexutil.DecodeUint64(fx.Info.GasUsed)
	require.NoError(tb, err)

	noHashes := func(uint64) (common.Hash, error) { return common.Hash{}, nil }
	blockCtx := protocol.NewEVMBlockContext(header, noHashes, ethash.NewFaker(), accounts.NilAddress, cfg)
	var baseFee *uint256.Int
	if cfg.IsLondon(0) {
		baseFee = header.BaseFee
		if baseFee == nil {
			baseFee = uint256.NewInt(0x0a)
		}
	}
	msg, err := fx.Message(baseFee)
	require.NoError(tb, err)

	db := temporaltest.NewTestDB(tb, datadir.New(tb.TempDir()))
	tx, domains := temporaltest.NewTestTxSD(tb, db)
	_, err = testutil.MakePreStateInto(&chain.Rules{}, domains, tx, alloc, header.Number.Uint64())
	require.NoError(tb, err)

	return &runner{
		cfg:      cfg,
		blockCtx: blockCtx,
		reader:   state.NewReaderV3(domains.AsStateGetter(tx, execctxapi.StateGetterOptions{})),
		msg:      msg,
		gasUsed:  gasUsed,
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
	vmConfig := vm.Config{NoReceipts: true, NoBAL: true}
	evm := vm.NewEVM(r.blockCtx, protocol.NewEVMTxContext(r.msg), ibs, r.cfg, vmConfig)
	gp := new(protocol.GasPool).AddGas(r.msg.Gas()).AddBlobGas(r.msg.BlobGas())
	res, err := protocol.ApplyMessage(evm, r.msg, gp, true, false, nil)
	require.NoError(tb, err)
	return res
}
