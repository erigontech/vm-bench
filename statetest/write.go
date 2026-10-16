// Package statetest writes mainnet transactions as EEST state-test fixtures.
package statetest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/holiman/uint256"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/execution/chain"
	chainspec "github.com/erigontech/erigon/execution/chain/spec"
	"github.com/erigontech/erigon/execution/tests/testutil"
	"github.com/erigontech/erigon/execution/types"
)

func forkConfig(fork string) (*chain.Config, []int, error) { return testutil.GetChainConfig(fork) }

// Fixture is one EEST state test: one transaction over its prestate, with the expected
// post-state root per fork. The sender comes with txbytes, so no secret key is needed.
type Fixture struct {
	Info        Info                   `json:"_info"`
	Config      Config                 `json:"config"`
	Env         Env                    `json:"env"`
	Pre         map[string]Account     `json:"pre"`
	Transaction Transaction            `json:"transaction"`
	Post        map[string][]PostState `json:"post"`
}

type Info struct {
	Source  string `json:"source"`
	TxHash  string `json:"txHash"`
	GasUsed string `json:"gasUsed"`
}

type Env struct {
	Coinbase      string `json:"currentCoinbase"`
	Difficulty    string `json:"currentDifficulty"`
	Random        string `json:"currentRandom,omitempty"`
	GasLimit      string `json:"currentGasLimit"`
	Number        string `json:"currentNumber"`
	Timestamp     string `json:"currentTimestamp"`
	BaseFee       string `json:"currentBaseFee,omitempty"`
	ExcessBlobGas string `json:"currentExcessBlobGas,omitempty"`
}

type Account struct {
	Balance string            `json:"balance"`
	Code    string            `json:"code"`
	Nonce   string            `json:"nonce"`
	Storage map[string]string `json:"storage"`
}

type Transaction struct {
	Nonce                string             `json:"nonce"`
	GasLimit             []string           `json:"gasLimit"`
	To                   string             `json:"to"`
	Data                 []string           `json:"data"`
	Value                []string           `json:"value"`
	GasPrice             string             `json:"gasPrice,omitempty"`
	MaxFeePerGas         string             `json:"maxFeePerGas,omitempty"`
	MaxPriorityFeePerGas string             `json:"maxPriorityFeePerGas,omitempty"`
	AccessLists          []types.AccessList `json:"accessLists,omitempty"`
	AuthorizationList    []Authorization    `json:"authorizationList,omitempty"`
	Sender               string             `json:"sender"`
	SecretKey            string             `json:"secretKey"`
}

type Authorization struct {
	ChainID string `json:"chainId"`
	Address string `json:"address"`
	Nonce   string `json:"nonce"`
	V       string `json:"v"`
	R       string `json:"r"`
	S       string `json:"s"`
}

type PostState struct {
	Indexes Indexes `json:"indexes"`
	Hash    string  `json:"hash"`
	Logs    string  `json:"logs"`
	TxBytes string  `json:"txbytes,omitempty"`
}

type Indexes struct {
	Data  int `json:"data"`
	Gas   int `json:"gas"`
	Value int `json:"value"`
}

// txReplay is the fixture format of erigon's BenchmarkTxReplay: an RPC transaction, its
// receipt, the block header and the prestate the transaction touched.
type txReplay struct {
	Tx      json.RawMessage `json:"tx"`
	Receipt struct {
		GasUsed hexutil.Uint64 `json:"gasUsed"`
	} `json:"receipt"`
	Block    types.Header               `json:"block"`
	Prestate map[string]json.RawMessage `json:"prestate"`
}

type rawAccount struct {
	Balance hexOrDecimal      `json:"balance"`
	Code    string            `json:"code"`
	Nonce   hexOrDecimal      `json:"nonce"`
	Storage map[string]string `json:"storage"`
}

// hexOrDecimal accepts a JSON number or a hex string and keeps it as a hex string.
type hexOrDecimal string

func (h *hexOrDecimal) UnmarshalJSON(b []byte) error {
	s := strings.Trim(string(b), `"`)
	if s == "" {
		s = "0x0"
	}
	if strings.HasPrefix(s, "0x") {
		*h = hexOrDecimal(s)
		return nil
	}
	v, err := uint256.FromDecimal(s)
	if err != nil {
		return err
	}
	*h = hexOrDecimal(v.Hex())
	return nil
}

// revme refuses a transaction without secretKey even when sender is given; every runner here uses sender.
const placeholderSecretKey = "0x0000000000000000000000000000000000000000000000000000000000000000"

const mainnetMergeBlock = 15537394

// forkName names the fork active at a mainnet block, as EEST and the state-test runners do.
func forkName(cfg *chain.Config, num, time uint64) string {
	switch {
	case cfg.IsAmsterdam(time):
		return "Amsterdam"
	case cfg.IsOsaka(time):
		return "Osaka"
	case cfg.IsPrague(time):
		return "Prague"
	case cfg.IsCancun(time):
		return "Cancun"
	case cfg.IsShanghai(time):
		return "Shanghai"
	case num >= mainnetMergeBlock:
		return "Paris"
	case cfg.IsLondon(num):
		return "London"
	case cfg.IsBerlin(num):
		return "Berlin"
	case cfg.IsIstanbul(num):
		return "Istanbul"
	case cfg.IsPetersburg(num):
		return "ConstantinopleFix"
	case cfg.IsByzantium(num):
		return "Byzantium"
	default:
		return "Homestead"
	}
}

// FromTxReplay converts one BenchmarkTxReplay fixture. The post-state root and logs hash
// are left empty: Fill runs the transaction to get them.
func FromTxReplay(path string) (name string, fx *Fixture, fork string, err error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", nil, "", err
	}
	var src txReplay
	if err := json.Unmarshal(raw, &src); err != nil {
		return "", nil, "", err
	}
	name = strings.TrimSuffix(filepath.Base(path), ".json")
	fx, fork, err = fromTxReplay(name, &src)
	return name, fx, fork, err
}

func fromTxReplay(name string, src *txReplay) (fx *Fixture, fork string, err error) {
	txn, err := types.UnmarshalTransactionFromJSON(src.Tx)
	if err != nil {
		return nil, "", err
	}
	var meta struct {
		From common.Address `json:"from"`
		Hash common.Hash    `json:"hash"`
	}
	if err := json.Unmarshal(src.Tx, &meta); err != nil {
		return nil, "", err
	}
	cfg := chainspec.Mainnet.Config
	num, time := src.Block.Number.Uint64(), src.Block.Time
	fork = forkName(cfg, num, time)

	pre := make(map[string]Account, len(src.Prestate))
	for addr, acc := range src.Prestate {
		var a rawAccount
		if err := json.Unmarshal(acc, &a); err != nil {
			return nil, "", fmt.Errorf("%s prestate %s: %w", name, addr, err)
		}
		if a.Code == "" {
			a.Code = "0x"
		}
		if a.Nonce == "" {
			a.Nonce = "0x0"
		}
		if a.Balance == "" {
			a.Balance = "0x0"
		}
		if a.Storage == nil {
			a.Storage = map[string]string{}
		}
		pre[addr] = Account{Balance: string(a.Balance), Code: a.Code, Nonce: string(a.Nonce), Storage: a.Storage}
	}

	env := Env{
		Coinbase:   src.Block.Coinbase.Hex(),
		Difficulty: src.Block.Difficulty.Hex(),
		GasLimit:   hexutil.EncodeUint64(src.Block.GasLimit),
		Number:     hexutil.EncodeUint64(num),
		Timestamp:  hexutil.EncodeUint64(time),
	}
	if src.Block.Difficulty.IsZero() {
		env.Random = src.Block.MixDigest.Hex()
	}
	if src.Block.BaseFee != nil {
		env.BaseFee = src.Block.BaseFee.Hex()
	}
	if src.Block.ExcessBlobGas != nil {
		env.ExcessBlobGas = hexutil.EncodeUint64(*src.Block.ExcessBlobGas)
	}

	tx := transactionFields(txn, meta.From)

	var txBytes bytes.Buffer
	if err := txn.MarshalBinary(&txBytes); err != nil {
		return nil, "", err
	}
	fx = &Fixture{
		Info:        Info{Source: fmt.Sprintf("mainnet block %d", num), TxHash: meta.Hash.Hex(), GasUsed: hexutil.EncodeUint64(uint64(src.Receipt.GasUsed))},
		Config:      Config{ChainID: "0x1"},
		Env:         env,
		Pre:         pre,
		Transaction: tx,
		Post:        map[string][]PostState{fork: {{Hash: common.Hash{}.Hex(), Logs: common.Hash{}.Hex(), TxBytes: hexutil.Encode(txBytes.Bytes())}}},
	}
	return fx, fork, nil
}

// Write stores the fixture under its name, as EEST does: one test per file.
func Write(dir, name string, fx *Fixture) error {
	fx.normalize()
	out, err := json.MarshalIndent(map[string]*Fixture{name: fx}, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, name+".json"), append(out, '\n'), 0o644)
}

// transactionFields describes a signed transaction the way a state test does, for runners
// that build the message from the fields instead of txbytes.
func transactionFields(txn types.Transaction, sender common.Address) Transaction {
	tx := Transaction{
		Nonce:     hexutil.EncodeUint64(txn.GetNonce()),
		GasLimit:  []string{hexutil.EncodeUint64(txn.GetGasLimit())},
		Data:      []string{hexutil.Encode(txn.GetData())},
		Value:     []string{txn.GetValue().Hex()},
		Sender:    sender.Hex(),
		SecretKey: placeholderSecretKey,
	}
	if to := txn.GetTo(); to != nil {
		tx.To = to.Hex()
	}
	if txn.Type() == types.LegacyTxType || txn.Type() == types.AccessListTxType {
		tx.GasPrice = txn.GetFeeCap().Hex()
	} else {
		tx.MaxFeePerGas = txn.GetFeeCap().Hex()
		tx.MaxPriorityFeePerGas = txn.GetTipCap().Hex()
	}
	if txn.Type() != types.LegacyTxType {
		al := txn.GetAccessList()
		if al == nil {
			al = types.AccessList{}
		}
		tx.AccessLists = []types.AccessList{al}
	}
	for _, a := range txn.GetAuthorizations() {
		tx.AuthorizationList = append(tx.AuthorizationList, Authorization{
			ChainID: a.ChainID.Hex(),
			Address: a.Address.Hex(),
			Nonce:   hexutil.EncodeUint64(a.Nonce),
			V:       hexutil.EncodeUint64(uint64(a.YParity)),
			R:       a.R.Hex(),
			S:       a.S.Hex(),
		})
	}
	return tx
}

// Config names the chain the transactions are signed for.
type Config struct {
	ChainID string `json:"chainid"`
}

// normalize drops accounts that do not exist on chain and pads storage to 32-byte hex,
// which is what evmone's loader and the other runners agree on.
func (fx *Fixture) normalize() {
	if len(fx.Env.Difficulty)%2 == 1 {
		fx.Env.Difficulty = "0x0" + strings.TrimPrefix(fx.Env.Difficulty, "0x")
	}
	for addr, a := range fx.Pre {
		if a.Balance == "0x0" && a.Nonce == "0x0" && a.Code == "0x" && len(a.Storage) == 0 {
			delete(fx.Pre, addr)
			continue
		}
		storage := make(map[string]string, len(a.Storage))
		for k, v := range a.Storage {
			storage[pad32(k)] = pad32(v)
		}
		a.Storage = storage
		fx.Pre[addr] = a
	}
}

func pad32(hex string) string {
	return fmt.Sprintf("0x%064s", strings.TrimPrefix(hex, "0x"))
}
