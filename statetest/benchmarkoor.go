package statetest

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
	"github.com/erigontech/erigon/execution/types"
)

// PayloadTest is one benchmarkoor compute test: the payloads that deploy its contracts and
// the benchmark payload whose transactions call them. It carries no prestate; the state
// comes from running the setup.
type PayloadTest struct {
	Network string       `json:"network"`
	Setup   []EngineCall `json:"setupEngineNewPayloads"`
	Bench   []EngineCall `json:"engineNewPayloads"`
	GasUsed string       `json:"benchmarkGasUsed"`
}

type EngineCall struct {
	Params []json.RawMessage `json:"params"`
}

// Payload is the engine_newPayload execution payload, the fields a state test env needs.
type Payload struct {
	FeeRecipient  common.Address  `json:"feeRecipient"`
	BlockNumber   hexutil.Uint64  `json:"blockNumber"`
	GasLimit      hexutil.Uint64  `json:"gasLimit"`
	Timestamp     hexutil.Uint64  `json:"timestamp"`
	BaseFeePerGas string          `json:"baseFeePerGas"`
	PrevRandao    common.Hash     `json:"prevRandao"`
	ExcessBlobGas *hexutil.Uint64 `json:"excessBlobGas"`
	Transactions  []hexutil.Bytes `json:"transactions"`
}

func (c EngineCall) Payload() (*Payload, error) {
	if len(c.Params) == 0 {
		return nil, fmt.Errorf("engine call without params")
	}
	var p Payload
	if err := json.Unmarshal(c.Params[0], &p); err != nil {
		return nil, err
	}
	return &p, nil
}

// LoadBenchmarkoor reads every payload file under dir and returns the tests whose id ends
// with one of the wanted ids.
func LoadBenchmarkoor(dir string, wanted []string) (map[string]*PayloadTest, error) {
	out := make(map[string]*PayloadTest, len(wanted))
	err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".json") || strings.Contains(path, "/pre_run/") {
			return err
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		var tests map[string]*PayloadTest
		if err := json.Unmarshal(raw, &tests); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		for id, t := range tests {
			for _, w := range wanted {
				if strings.HasSuffix(id, w) {
					out[w] = t
				}
			}
		}
		return nil
	})
	return out, err
}

var fixtureNameNoise = regexp.MustCompile(`fork_[A-Za-z]+-blockchain_test_stateful_engine-|-benchmark-gas-value_\d+M|\.py|[\[\]]`)

// FixtureName turns a benchmarkoor test id into a file name:
// test_keccak.py::test_keccak_diff_mem_msg_sizes[...-msg_size_1024-mem_size_0-...] becomes
// bm-keccak_diff_mem_msg_sizes-msg_size_1024-mem_size_0.
func FixtureName(id string) string {
	id = id[strings.LastIndex(id, "::")+2:]
	id = strings.Replace(id, "[", "-", 1)
	id = fixtureNameNoise.ReplaceAllString(id, "")
	id = strings.TrimPrefix(id, "test_")
	return "bm-" + strings.TrimSuffix(id, "-")
}

// FromPayload builds the state test of the benchmark payload's first transaction over pre.
func FromPayload(p *Payload, txn types.Transaction, sender common.Address, pre map[string]Account, fork string) *Fixture {
	env := Env{
		Coinbase:   p.FeeRecipient.Hex(),
		Difficulty: "0x0",
		Random:     p.PrevRandao.Hex(),
		GasLimit:   hexutil.EncodeUint64(uint64(p.GasLimit)),
		Number:     hexutil.EncodeUint64(uint64(p.BlockNumber)),
		Timestamp:  hexutil.EncodeUint64(uint64(p.Timestamp)),
		BaseFee:    p.BaseFeePerGas,
	}
	if p.ExcessBlobGas != nil {
		env.ExcessBlobGas = hexutil.EncodeUint64(uint64(*p.ExcessBlobGas))
	}
	return &Fixture{
		Info:        Info{Source: "benchmarkoor compute suite, first transaction of the benchmark block", TxHash: txn.Hash().Hex()},
		Config:      Config{ChainID: "0x1"},
		Env:         env,
		Pre:         pre,
		Transaction: transactionFields(txn, sender),
		Post:        map[string][]PostState{fork: {{Hash: common.Hash{}.Hex(), Logs: common.Hash{}.Hex()}}},
	}
}
