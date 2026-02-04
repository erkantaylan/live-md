# Utility Files

This document describes the utility files used by Live MD.

## pathconv.go - Path Conversion

Handles path conversion between Windows and WSL (Windows Subsystem for Linux) environments.

### Functions

#### `ConvertPath(path string) string`
Main entry point for path conversion. Automatically detects the current OS and converts paths appropriately:
- On Windows: converts Linux/WSL paths to Windows format
- On Linux: converts Windows paths to Linux format

#### `convertToWindowsPath(path string) string`
Converts Linux/WSL paths to Windows paths:
- Passes through paths that are already in Windows format (e.g., `C:\...`)
- Converts `/mnt/x/...` paths to `X:\...` (WSL mounted drives)
- Converts native WSL paths to UNC paths (`\\wsl.localhost\` or `\\wsl$\`)

#### `convertToLinuxPath(path string) string`
Converts Windows paths to Linux/WSL paths:
- Passes through paths that are already in Linux format
- Converts `\\wsl$\` and `\\wsl.localhost\` UNC paths to native paths
- Converts Windows drive paths (`C:\...`) to `/mnt/c/...`

#### `getWSLDistro() string`
Detects the current WSL distribution name:
- First checks the `WSL_DISTRO_NAME` environment variable
- Falls back to querying `wsl -l -q` for the default distro

#### `NormalizePath(path string) string`
Normalizes a path for the current OS by converting and cleaning it.

#### `NormalizePathForComparison(path string) string`
Normalizes a path for comparison purposes. On Windows, converts to lowercase for case-insensitive comparison.

#### `PathsEqual(path1, path2 string) bool`
Checks if two paths refer to the same file, handling case-insensitivity on Windows.

#### `FindPathKey(paths map[string]interface{}, path string) (string, bool)`
Finds the actual key used in a map for a given path, accounting for path normalization.

---

## watcher.go - File Watching

Provides file system watching with debouncing to prevent rapid-fire callbacks.

### Types

#### `Watcher`
A file watcher that monitors a file for changes and calls a callback function with debouncing.

```go
type Watcher struct {
    watcher *fsnotify.Watcher  // Underlying fsnotify watcher
    done    chan struct{}       // Signal channel for shutdown
    mu      sync.Mutex          // Protects timer access
    timer   *time.Timer         // Debounce timer
}
```

### Functions

#### `NewWatcher() *Watcher`
Creates a new Watcher instance.

#### `(w *Watcher) Watch(filepath string, onChange func()) error`
Starts watching a file for changes. The `onChange` callback is called (with debouncing) when:
- The file is written to (`fsnotify.Write`)
- The file is removed and recreated (handles editors that do atomic saves)

The debounce delay is 100ms, preventing multiple rapid callbacks.

#### `(w *Watcher) debounce(fn func())`
Internal debouncing logic. Resets the timer on each call, only executing the callback after 100ms of inactivity.

#### `(w *Watcher) Close() error`
Stops watching and cleans up resources.

---

## logger.go - Logging

Provides an in-memory logger that stores entries and broadcasts them to connected WebSocket clients.

### Types

#### `LogEntry`
Represents a single log entry.

```go
type LogEntry struct {
    Time    time.Time `json:"time"`     // When the log was created
    Level   string    `json:"level"`    // "info", "warn", or "error"
    Message string    `json:"message"`  // The log message
}
```

#### `Logger`
An in-memory logger with a fixed-size buffer and WebSocket broadcasting.

```go
type Logger struct {
    mu      sync.RWMutex   // Protects entries slice
    entries []LogEntry     // Circular buffer of log entries
    maxSize int            // Maximum number of entries to keep
    hub     *Hub           // WebSocket hub for broadcasting
}
```

### Functions

#### `NewLogger(maxSize int) *Logger`
Creates a new Logger with the specified maximum number of entries.

#### `(l *Logger) SetHub(hub *Hub)`
Sets the WebSocket hub for broadcasting log entries to clients.

#### `(l *Logger) Info(message string)`
Logs an info-level message.

#### `(l *Logger) Warn(message string)`
Logs a warning-level message.

#### `(l *Logger) Error(message string)`
Logs an error-level message.

#### `(l *Logger) GetEntries() []LogEntry`
Returns a copy of all stored log entries.

### Behavior
- Log entries are stored in a circular buffer with a configurable maximum size
- When the buffer is full, the oldest entry is discarded
- Each new entry is broadcast to all connected WebSocket clients via the Hub
