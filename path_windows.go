//go:build windows

package main

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows/registry"
)

// addInstallDirToPath persists `dir` in HKCU\Environment\Path and broadcasts
// WM_SETTINGCHANGE so newly-spawned processes pick up the change.
// Returns (added, alreadyPresent, error).
func addInstallDirToPath(dir string) (bool, bool, error) {
	key, err := registry.OpenKey(registry.CURRENT_USER, `Environment`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return false, false, fmt.Errorf("open HKCU\\Environment: %w", err)
	}
	defer key.Close()

	current, valType, err := key.GetStringValue("Path")
	if err != nil && err != registry.ErrNotExist {
		return false, false, fmt.Errorf("read Path: %w", err)
	}
	if valType == 0 {
		valType = registry.EXPAND_SZ
	}

	for _, p := range strings.Split(current, ";") {
		if strings.EqualFold(strings.TrimSpace(p), dir) {
			return false, true, nil
		}
	}

	var newPath string
	if current == "" {
		newPath = dir
	} else {
		newPath = strings.TrimRight(current, ";") + ";" + dir
	}

	// Preserve REG_EXPAND_SZ if the existing value used it; otherwise default to it.
	if valType == registry.EXPAND_SZ {
		if err := key.SetExpandStringValue("Path", newPath); err != nil {
			return false, false, fmt.Errorf("write Path: %w", err)
		}
	} else {
		if err := key.SetStringValue("Path", newPath); err != nil {
			return false, false, fmt.Errorf("write Path: %w", err)
		}
	}

	broadcastEnvChange()
	return true, false, nil
}

// broadcastEnvChange sends WM_SETTINGCHANGE so processes that listen for env
// updates (Explorer, modern terminals) refresh without a logout.
func broadcastEnvChange() {
	user32 := syscall.NewLazyDLL("user32.dll")
	proc := user32.NewProc("SendMessageTimeoutW")
	const (
		hwndBroadcast    = 0xFFFF
		wmSettingChange  = 0x001A
		smtoAbortIfHung  = 0x0002
		broadcastTimeout = 5000
	)
	envPtr, _ := syscall.UTF16PtrFromString("Environment")
	proc.Call(
		uintptr(hwndBroadcast),
		uintptr(wmSettingChange),
		0,
		uintptr(unsafe.Pointer(envPtr)),
		smtoAbortIfHung,
		broadcastTimeout,
		0,
	)
}
