//go:build !windows

package main

import "syscall"

// daemonSysProcAttr returns the SysProcAttr that detaches a child from the
// controlling terminal. Setsid creates a new session so the child survives
// the parent shell exiting.
func daemonSysProcAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{Setsid: true}
}
