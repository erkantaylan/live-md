package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// cmdEnsurePath ensures the directory containing the running binary is on the
// user's PATH. On Windows it edits the registry. On unix it prints a one-line
// instruction if the dir is missing — modifying a user's shell rc is too
// invasive to do silently.
func cmdEnsurePath() {
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot determine executable path: %v\n", err)
		os.Exit(1)
	}
	dir := filepath.Dir(exe)

	added, present, err := addInstallDirToPath(dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error updating PATH: %v\n", err)
		os.Exit(1)
	}

	switch {
	case added:
		fmt.Printf("Added to PATH: %s\n", dir)
		fmt.Println("Open a new terminal for the change to take effect.")
	case present:
		fmt.Printf("Already in PATH: %s\n", dir)
	default:
		// Unix path that's missing: print actionable instruction.
		fmt.Printf("\n  %s is not in your PATH.\n", dir)
		shellRC := "~/.bashrc"
		if runtime.GOOS == "darwin" {
			shellRC = "~/.zshrc"
		}
		fmt.Printf("  Add this line to %s (or your shell's rc file):\n\n", shellRC)
		fmt.Printf("    export PATH=\"%s:$PATH\"\n\n", dir)
	}
}
