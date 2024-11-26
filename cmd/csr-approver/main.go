// main
package main

import (
	"os"

	"github.com/deas/csr-approver/internal/cmd"
)

func main() {
	code := cmd.Run()
	os.Exit(code)
}
