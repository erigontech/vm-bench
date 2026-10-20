// gevm-blocktest runs blockchain-test files through gevm's spec runner, which executes every block
// and checks the post-state. Exit status 1 if any test fails.
package main

import (
	"fmt"
	"os"

	"github.com/Giulio2002/gevm/tests/spec"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: gevm-blocktest <file.json>...")
		os.Exit(2)
	}
	failed := 0
	for _, path := range os.Args[1:] {
		results, err := spec.RunBlockchainTestFile(path, spec.DefaultBlockchainConfig())
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		for _, r := range results {
			if !r.Pass {
				failed++
				fmt.Fprintf(os.Stderr, "%s: %v %s\n", path, r.Error, r.Detail)
			}
		}
	}
	if failed > 0 {
		os.Exit(1)
	}
}
