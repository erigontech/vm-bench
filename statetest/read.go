package statetest

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"

	"github.com/holiman/uint256"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/execution/chain"
	"github.com/erigontech/erigon/execution/types"
	"github.com/erigontech/erigon/execution/types/accounts"
)

// Load reads a fixture file: one state test, keyed by its name, with one fork in post.
func Load(path string) (name string, fx *Fixture, fork string, err error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", nil, "", err
	}
	var tests map[string]*Fixture
	if err := json.Unmarshal(raw, &tests); err != nil {
		return "", nil, "", fmt.Errorf("%s: %w", path, err)
	}
	name = strings.TrimSuffix(filepath.Base(path), ".json")
	fx, ok := tests[name]
	if !ok {
		return "", nil, "", fmt.Errorf("%s: no test named %s", path, name)
	}
	if len(fx.Post) != 1 {
		return "", nil, "", fmt.Errorf("%s: one fork per fixture, got %d", path, len(fx.Post))
	}
	for fork = range fx.Post {
	}
	return name, fx, fork, nil
}

func parseU256(s string) (*uint256.Int, error) {
	if s == "" {
		return nil, nil
	}
	v, err := uint256.FromHex("0x" + strings.TrimLeft(strings.TrimPrefix(s, "0x"), "0"))
	if strings.Trim(s, "0x") == "" {
		return new(uint256.Int), nil
	}
	if err != nil {
		return nil, fmt.Errorf("%q: %w", s, err)
	}
	return v, nil
}

func parseU64(s string) (uint64, error) {
	if s == "" {
		return 0, nil
	}
	return hexutil.DecodeUint64(s)
}

// Header is the block the env describes, for the EVM block context.
func (e Env) Header() (*types.Header, error) {
	h := &types.Header{Coinbase: common.HexToAddress(e.Coinbase)}
	var err error
	if h.GasLimit, err = parseU64(e.GasLimit); err != nil {
		return nil, err
	}
	if h.Time, err = parseU64(e.Timestamp); err != nil {
		return nil, err
	}
	num, err := parseU64(e.Number)
	if err != nil {
		return nil, err
	}
	h.Number.SetUint64(num)
	diff, err := parseU256(e.Difficulty)
	if err != nil {
		return nil, err
	}
	if diff != nil {
		h.Difficulty.Set(diff)
	}
	if e.Random != "" {
		h.MixDigest = common.HexToHash(e.Random)
	}
	if h.BaseFee, err = parseU256(e.BaseFee); err != nil {
		return nil, err
	}
	if e.ExcessBlobGas != "" {
		v, err := parseU64(e.ExcessBlobGas)
		if err != nil {
			return nil, err
		}
		h.ExcessBlobGas = &v
	}
	return h, nil
}

// Alloc is the prestate as erigon's genesis helpers take it.
func (fx *Fixture) Alloc() (types.GenesisAlloc, error) {
	alloc := make(types.GenesisAlloc, len(fx.Pre))
	for addr, a := range fx.Pre {
		balance, err := parseU256(a.Balance)
		if err != nil {
			return nil, err
		}
		nonce, err := parseU64(a.Nonce)
		if err != nil {
			return nil, err
		}
		code, err := hexutil.Decode(a.Code)
		if err != nil && a.Code != "" {
			return nil, err
		}
		storage := make(map[common.Hash]common.Hash, len(a.Storage))
		for k, v := range a.Storage {
			storage[common.HexToHash(k)] = common.HexToHash(v)
		}
		acc := types.GenesisAccount{Nonce: nonce, Code: code, Storage: storage, Balance: new(big.Int)}
		if balance != nil {
			acc.Balance = balance.ToBig()
		}
		alloc[common.HexToAddress(addr)] = acc
	}
	return alloc, nil
}

// Message builds the transaction's message from the fields and the sender, so a fixture
// needs neither a secret key nor a signature valid for chain id 1.
func (fx *Fixture) Message(baseFee *uint256.Int) (*types.Message, error) {
	tx := fx.Transaction
	if tx.Sender == "" {
		return nil, errors.New("transaction without a sender")
	}
	if len(tx.GasLimit) != 1 || len(tx.Data) != 1 || len(tx.Value) != 1 {
		return nil, errors.New("one data, gas limit and value per fixture")
	}
	nonce, err := parseU64(tx.Nonce)
	if err != nil {
		return nil, err
	}
	gasLimit, err := parseU64(tx.GasLimit[0])
	if err != nil {
		return nil, err
	}
	value, err := parseU256(tx.Value[0])
	if err != nil {
		return nil, err
	}
	if value == nil {
		value = new(uint256.Int)
	}
	data, err := hexutil.Decode(tx.Data[0])
	if err != nil && tx.Data[0] != "" && tx.Data[0] != "0x" {
		return nil, err
	}
	var to accounts.Address
	if tx.To != "" {
		to = accounts.InternAddress(common.HexToAddress(tx.To))
	}
	gasPrice, err := parseU256(tx.GasPrice)
	if err != nil {
		return nil, err
	}
	feeCap, err := parseU256(tx.MaxFeePerGas)
	if err != nil {
		return nil, err
	}
	tipCap, err := parseU256(tx.MaxPriorityFeePerGas)
	if err != nil {
		return nil, err
	}
	switch {
	case baseFee != nil:
		if feeCap == nil {
			feeCap = gasPrice
		}
		if feeCap == nil {
			feeCap = new(uint256.Int)
		}
		if tipCap == nil {
			tipCap = feeCap
		}
		gasPrice = new(uint256.Int).Add(tipCap, baseFee)
		if gasPrice.Gt(feeCap) {
			gasPrice = feeCap
		}
	case gasPrice != nil:
		feeCap, tipCap = gasPrice, gasPrice
	default:
		return nil, errors.New("no gas price")
	}
	var accessList types.AccessList
	if len(tx.AccessLists) > 0 {
		accessList = tx.AccessLists[0]
	}
	msg := types.NewMessage(accounts.InternAddress(common.HexToAddress(tx.Sender)), to, nonce, value, gasLimit,
		gasPrice, feeCap, tipCap, data, accessList, false, false, false, false, nil)
	if len(tx.AuthorizationList) > 0 {
		auths := make([]types.Authorization, len(tx.AuthorizationList))
		for i, a := range tx.AuthorizationList {
			chainID, err := parseU256(a.ChainID)
			if err != nil {
				return nil, err
			}
			n, err := parseU64(a.Nonce)
			if err != nil {
				return nil, err
			}
			v, err := parseU64(a.V)
			if err != nil {
				return nil, err
			}
			r, err := parseU256(a.R)
			if err != nil {
				return nil, err
			}
			s, err := parseU256(a.S)
			if err != nil {
				return nil, err
			}
			auths[i] = types.Authorization{Address: common.HexToAddress(a.Address), Nonce: n, YParity: uint8(v)}
			if chainID != nil {
				auths[i].ChainID = *chainID
			}
			if r != nil {
				auths[i].R = *r
			}
			if s != nil {
				auths[i].S = *s
			}
		}
		msg.SetAuthorizations(auths)
	}
	return msg, nil
}

// Rules is the chain config of the fork, as EEST names it.
func Rules(fork string) (*chain.Config, error) {
	cfg, _, err := forkConfig(fork)
	return cfg, err
}
