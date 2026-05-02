//go:build !windows

package main

import (
	"os"
	"strings"
)

// addInstallDirToPath is a no-op on unix — modifying user shell rc files is
// invasive and shell-specific. Returns (added=false, present, nil); the caller
// prints actionable instructions when present is false.
func addInstallDirToPath(dir string) (bool, bool, error) {
	for _, p := range strings.Split(os.Getenv("PATH"), ":") {
		if p == dir {
			return false, true, nil
		}
	}
	return false, false, nil
}
