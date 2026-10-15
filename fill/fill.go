// Package fill turns transactions into state tests and fills their post-state with erigon.
package fill

import (
	"context"
	"testing"

	"github.com/holiman/uint256"
	"github.com/stretchr/testify/require"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/log/v3"
	"github.com/erigontech/erigon/db/datadir"
	"github.com/erigontech/erigon/db/kv/temporal/temporaltest"
	"github.com/erigontech/erigon/db/snapshotsync/freezeblocks"
	"github.com/erigontech/erigon/db/state/execctx/execctxapi"
	"github.com/erigontech/erigon/execution/chain"
	"github.com/erigontech/erigon/execution/protocol"
	"github.com/erigontech/erigon/execution/protocol/rules/ethash"
	"github.com/erigontech/erigon/execution/state"
	"github.com/erigontech/erigon/execution/tests/testutil"
	"github.com/erigontech/erigon/execution/tracing"
	"github.com/erigontech/erigon/execution/types/accounts"
	"github.com/erigontech/erigon/execution/vm"
	"github.com/erigontech/erigon/rpc/rpchelper"

	"github.com/erigontech/vm-bench/statetest"
)

// Fill runs the fixture's transaction over its prestate on erigon and returns the post-state
// root, the logs hash and the gas used, the way erigon's own state-test runner computes them.
func Fill(tb testing.TB, fx *statetest.Fixture, fork string) (root, logs common.Hash, gasUsed uint64) {
	tb.Helper()
	cfg, err := statetest.Rules(fork)
	require.NoError(tb, err)
	header, err := fx.Env.Header()
	require.NoError(tb, err)
	alloc, err := fx.Alloc()
	require.NoError(tb, err)

	db := temporaltest.NewTestDB(tb, datadir.New(tb.TempDir()))
	tx, domains := temporaltest.NewTestTxSD(tb, db)
	readBlockNr := header.Number.Uint64()
	_, err = testutil.MakePreStateInto(&chain.Rules{}, domains, tx, alloc, readBlockNr)
	require.NoError(tb, err)

	reader := rpchelper.NewLatestStateReader(domains.AsStateGetter(tx, execctxapi.StateGetterOptions{}))
	writer := rpchelper.NewLatestStateWriter(tx, domains, (*freezeblocks.BlockReader)(nil), readBlockNr+1)
	ibs := state.New(reader)
	defer ibs.Close()

	noHashes := func(uint64) (common.Hash, error) { return common.Hash{}, nil }
	blockCtx := protocol.NewEVMBlockContext(header, noHashes, ethash.NewFaker(), accounts.NilAddress, cfg)
	rules := blockCtx.Rules(cfg)
	var baseFee *uint256.Int
	if cfg.IsLondon(0) {
		baseFee = header.BaseFee
		if baseFee == nil {
			baseFee = uint256.NewInt(0x0a)
		}
	}
	msg, err := fx.Message(baseFee)
	require.NoError(tb, err)

	evm := vm.NewEVM(blockCtx, protocol.NewEVMTxContext(msg), ibs, cfg, vm.Config{})
	gp := new(protocol.GasPool).AddGas(header.GasLimit).AddBlobGas(cfg.GetMaxBlobGasPerBlock(header.Time))
	res, err := protocol.ApplyMessage(evm, msg, gp, true, false, nil)
	require.NoError(tb, err)
	require.NoError(tb, ibs.AddBalance(accounts.InternAddress(header.Coinbase), *uint256.NewInt(0), tracing.BalanceChangeUnspecified))
	require.NoError(tb, ibs.FinalizeTx(rules, writer))
	require.NoError(tb, ibs.CommitBlock(rules, writer))
	rootBytes, err := domains.ComputeCommitment(context.Background(), tx, true, readBlockNr, 1, "", nil)
	require.NoError(tb, err)
	log.Root().SetHandler(log.DiscardHandler())
	return common.BytesToHash(rootBytes), ibs.LogsRlpHash(), res.ReceiptGasUsed
}
