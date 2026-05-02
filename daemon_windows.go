//go:build windows

package main

import "syscall"

// Windows process creation flags (not exposed by syscall package).
const (
	detachedProcess       = 0x00000008
	createNewProcessGroup = 0x00000200
)

// daemonSysProcAttr returns SysProcAttr that detaches the child from the
// parent console so the daemon survives the parent shell exiting.
func daemonSysProcAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{
		CreationFlags: detachedProcess | createNewProcessGroup,
		HideWindow:    true,
	}
}
