package fill

import (
	"bufio"
	"math/big"
	"os"
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

	"github.com/erigontech/vm-bench/statetest"
)

// TestFillBenchmarkoor turns the benchmarkoor compute tests listed in benchmarkoor_tests.txt
// into state tests: the setup payloads run on an empty state with funded senders, the state
// they leave is the prestate, and the first transaction of the benchmark block is the test.
//
//	VMBENCH_BENCHMARKOOR=<blockchain_tests_stateful_engine dir> go test ./fill -run TestFillBenchmarkoor
func TestFillBenchmarkoor(t *testing.T) {
	dir := os.Getenv("VMBENCH_BENCHMARKOOR")
	if dir == "" {
		t.Skip("set VMBENCH_BENCHMARKOOR to the eest-payloads blockchain_tests_stateful_engine directory")
	}
	wanted := readLines(t, "benchmarkoor_tests.txt")
	tests, err := statetest.LoadBenchmarkoor(dir, wanted)
	require.NoError(t, err)
	require.Len(t, tests, len(wanted), "every listed test must have a payload file")
	out := filepath.Join("..", "fixtures", "benchmarkoor")
	require.NoError(t, os.MkdirAll(out, 0o755))

	for _, id := range wanted {
		pt := tests[id]
		name := statetest.FixtureName(id)
		t.Run(name, func(t *testing.T) {
			fork := pt.Network
			cfg, _, err := testutil.GetChainConfig(fork)
			require.NoError(t, err)
			require.Len(t, pt.Bench, 1)
			bench, err := pt.Bench[0].Payload()
			require.NoError(t, err)
			require.NotEmpty(t, bench.Transactions)

			db := temporaltest.NewTestDB(t, datadir.New(t.TempDir()))
			tx, domains := temporaltest.NewTestTxSD(t, db)
			reader := state.NewReaderV3(domains.AsStateGetter(tx, execctxapi.StateGetterOptions{}))
			pre := make(map[string]statetest.Account)

			// Fund every sender at the nonce its first transaction expects.
			var setupTxs []types.Transaction
			senders := map[common.Address]uint64{}
			for _, call := range pt.Setup {
				p, err := call.Payload()
				require.NoError(t, err)
				for _, raw := range p.Transactions {
					txn, err := types.DecodeTransaction(raw)
					require.NoError(t, err)
					setupTxs = append(setupTxs, txn)
					noteSender(t, senders, txn)
				}
			}
			benchTx, err := types.DecodeTransaction(bench.Transactions[0])
			require.NoError(t, err)
			noteSender(t, senders, benchTx)
			alloc := types.GenesisAlloc{}
			for addr, nonce := range senders {
				balance := uint256.MustFromDecimal("1000000000000000000000000000000")
				alloc[addr] = types.GenesisAccount{Balance: balance.ToBig(), Nonce: nonce}
				pre[addr.Hex()] = statetest.Account{Balance: balance.Hex(), Code: "0x", Nonce: hexutil.EncodeUint64(nonce), Storage: map[string]string{}}
			}
			_, err = testutil.MakePreStateInto(&chain.Rules{}, domains, tx, alloc, 1)
			require.NoError(t, err)

			// Run the setup on the materializing path and collect what it leaves behind.
			ibs := state.New(reader)
			defer ibs.Close()
			for i, call := range pt.Setup {
				p, err := call.Payload()
				require.NoError(t, err)
				header := headerOf(p)
				blockCtx := protocol.NewEVMBlockContext(header, noHashes, ethash.NewFaker(), accounts.NilAddress, cfg)
				rules := blockCtx.Rules(cfg)
				for j, txn := range setupTxs {
					if j < txIndexBase(pt.Setup[:i]) || j >= txIndexBase(pt.Setup[:i+1]) {
						continue
					}
					msg, err := txn.AsMessage(*types.LatestSignerForChainID(txn.GetChainID()), header.BaseFee, rules)
					require.NoError(t, err)
					ibs.SetTxContext(header.Number.Uint64(), j)
					evm := vm.NewEVM(blockCtx, protocol.NewEVMTxContext(msg), ibs, cfg, vm.Config{NoReceipts: true, NoBAL: true})
					gp := new(protocol.GasPool).AddGas(msg.Gas()).AddBlobGas(msg.BlobGas())
					res, err := protocol.ApplyMessage(evm, msg, gp, true, false, nil)
					require.NoError(t, err)
					require.False(t, res.Failed(), "setup transaction %d: %v", j, res.Err)
					require.NoError(t, ibs.FinalizeTx(rules, state.NewNoopWriter()))
				}
			}
			capture := &capturingWriter{pre: pre, codes: map[common.Address]string{}, storage: map[common.Address]map[string]string{}}
			lastSetup, err := pt.Setup[len(pt.Setup)-1].Payload()
			require.NoError(t, err)
			lastCtx := protocol.NewEVMBlockContext(headerOf(lastSetup), noHashes, ethash.NewFaker(), accounts.NilAddress, cfg)
			require.NoError(t, ibs.CommitBlock(lastCtx.Rules(cfg), capture))
			capture.finish()

			sender, err := benchTx.Sender(*types.LatestSignerForChainID(benchTx.GetChainID()))
			require.NoError(t, err)
			fx := statetest.FromPayload(bench, benchTx, sender.Value(), pre, fork)
			require.NoError(t, statetest.Write(out, name, fx))

			_, loaded, _, err := statetest.Load(filepath.Join(out, name+".json"))
			require.NoError(t, err)
			root, logs, gasUsed := Fill(t, loaded, fork)
			require.Greater(t, gasUsed, uint64(21000), "the benchmark transaction must execute")
			fx.Info.GasUsed = hexutil.EncodeUint64(gasUsed)
			fx.Post[fork][0].Hash = root.Hex()
			fx.Post[fork][0].Logs = logs.Hex()
			require.NoError(t, statetest.Write(out, name, fx))
		})
	}
}

func noHashes(uint64) (common.Hash, error) { return common.Hash{}, nil }

// noteSender records the lowest nonce each sender's transactions start from. The payloads
// are signed for the devnet's chain id, so the sender is recovered with the transaction's own.
func noteSender(t *testing.T, senders map[common.Address]uint64, txn types.Transaction) {
	t.Helper()
	from, err := txn.Sender(*types.LatestSignerForChainID(txn.GetChainID()))
	require.NoError(t, err)
	addr := from.Value()
	if nonce, ok := senders[addr]; !ok || txn.GetNonce() < nonce {
		senders[addr] = txn.GetNonce()
	}
}

func txIndexBase(calls []statetest.EngineCall) int {
	n := 0
	for _, c := range calls {
		p, err := c.Payload()
		if err == nil {
			n += len(p.Transactions)
		}
	}
	return n
}

func headerOf(p *statetest.Payload) *types.Header {
	h := &types.Header{
		Coinbase:      p.FeeRecipient,
		GasLimit:      uint64(p.GasLimit),
		Time:          uint64(p.Timestamp),
		MixDigest:     p.PrevRandao,
		ExcessBlobGas: (*uint64)(p.ExcessBlobGas),
	}
	h.Number.SetUint64(uint64(p.BlockNumber))
	if p.BaseFeePerGas != "" {
		fee, _ := new(big.Int).SetString(strings.TrimPrefix(p.BaseFeePerGas, "0x"), 16)
		h.BaseFee = uint256.MustFromBig(fee)
	}
	return h
}

// capturingWriter records the accounts, code and storage the setup commits.
type capturingWriter struct {
	pre     map[string]statetest.Account
	codes   map[common.Address]string
	storage map[common.Address]map[string]string
}

func (w *capturingWriter) UpdateAccountData(address accounts.Address, _, account *accounts.Account) error {
	addr := address.Value()
	a := w.pre[addr.Hex()]
	a.Balance = account.Balance.Hex()
	a.Nonce = hexutil.EncodeUint64(account.Nonce)
	w.pre[addr.Hex()] = a
	return nil
}

func (w *capturingWriter) UpdateAccountCode(address accounts.Address, _ uint64, _ accounts.CodeHash, code []byte) error {
	w.codes[address.Value()] = hexutil.Encode(code)
	return nil
}

func (w *capturingWriter) DeleteAccount(address accounts.Address, _ *accounts.Account) error {
	delete(w.pre, address.Value().Hex())
	return nil
}

func (w *capturingWriter) WriteAccountStorage(address accounts.Address, _ uint64, key accounts.StorageKey, _, value uint256.Int) error {
	addr := address.Value()
	if w.storage[addr] == nil {
		w.storage[addr] = map[string]string{}
	}
	k := key.Value()
	if value.IsZero() {
		delete(w.storage[addr], common.Hash(k).Hex())
	} else {
		w.storage[addr][common.Hash(k).Hex()] = common.BytesToHash(value.Bytes()).Hex()
	}
	return nil
}

func (w *capturingWriter) CreateContract(accounts.Address) error { return nil }

// finish folds the code and storage into the accounts and fills the fields a state test
// requires on every account.
func (w *capturingWriter) finish() {
	for addr, code := range w.codes {
		a := w.pre[addr.Hex()]
		a.Code = code
		w.pre[addr.Hex()] = a
	}
	for addr, slots := range w.storage {
		a := w.pre[addr.Hex()]
		a.Storage = slots
		w.pre[addr.Hex()] = a
	}
	for k, a := range w.pre {
		if a.Code == "" {
			a.Code = "0x"
		}
		if a.Storage == nil {
			a.Storage = map[string]string{}
		}
		if a.Balance == "" {
			a.Balance = "0x0"
		}
		if a.Nonce == "" {
			a.Nonce = "0x0"
		}
		w.pre[k] = a
	}
}

func readLines(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	require.NoError(t, err)
	defer f.Close()
	var lines []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		if l := strings.TrimSpace(sc.Text()); l != "" && !strings.HasPrefix(l, "#") {
			lines = append(lines, l)
		}
	}
	require.NoError(t, sc.Err())
	return lines
}
