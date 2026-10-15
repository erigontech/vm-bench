package statetest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/erigontech/erigon/common"
	"github.com/erigontech/erigon/common/hexutil"
)

// FromRPC builds the fixture of a mainnet transaction from an archive node: the prestate
// comes from debug_traceTransaction's prestateTracer.
func FromRPC(url string, hash common.Hash, name string) (fx *Fixture, fork string, err error) {
	var src txReplay
	if err := rpcCall(url, "eth_getTransactionByHash", &src.Tx, hash); err != nil {
		return nil, "", err
	}
	var receipt struct {
		GasUsed   hexutil.Uint64 `json:"gasUsed"`
		BlockHash common.Hash    `json:"blockHash"`
	}
	if err := rpcCall(url, "eth_getTransactionReceipt", &receipt, hash); err != nil {
		return nil, "", err
	}
	src.Receipt.GasUsed = receipt.GasUsed
	if err := rpcCall(url, "eth_getBlockByHash", &src.Block, receipt.BlockHash, false); err != nil {
		return nil, "", err
	}
	if err := rpcCall(url, "debug_traceTransaction", &src.Prestate, hash, map[string]string{"tracer": "prestateTracer"}); err != nil {
		return nil, "", err
	}
	return fromTxReplay(name, &src)
}

func rpcCall(url, method string, result any, params ...any) error {
	body, err := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
	if err != nil {
		return err
	}
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("%s: %w", method, err)
	}
	defer resp.Body.Close()
	var out struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return fmt.Errorf("%s: %w", method, err)
	}
	if out.Error != nil {
		return fmt.Errorf("%s: %s", method, out.Error.Message)
	}
	return json.Unmarshal(out.Result, result)
}
