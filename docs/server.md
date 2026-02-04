# server.go Documentation

This document provides a line-by-line explanation of `server.go`, the HTTP server and WebSocket handling module for the Live Markdown application.

## Overview

`server.go` implements:
- An HTTP server serving static files and a REST API
- WebSocket connections for real-time browser updates
- A Hub for managing file watchers and connected clients

---

## Package and Imports (Lines 1-19)

```go
package main
```
Declares this as the main package for the executable.

### Standard Library Imports (Lines 4-16)

| Import | Purpose |
|--------|---------|
| `context` | Used for graceful server shutdown |
| `embed` | Embeds static files into the binary |
| `encoding/json` | JSON encoding/decoding for API and WebSocket messages |
| `fmt` | String formatting and error messages |
| `io/fs` | Filesystem abstraction for serving embedded files |
| `log` | Logging errors |
| `net/http` | HTTP server and request handling |
| `os` | File operations and signal handling |
| `os/signal` | Catching OS signals for graceful shutdown |
| `path/filepath` | Cross-platform path manipulation |
| `sync` | Mutex for thread-safe Hub operations |
| `syscall` | Signal constants (SIGINT, SIGTERM) |
| `time` | Timestamps and timeouts |

### External Import (Line 18)

```go
"github.com/gorilla/websocket"
```
Third-party WebSocket library for upgrading HTTP connections to WebSocket.

---

## Embedded Static Files (Lines 21-22)

```go
//go:embed static
var staticFiles embed.FS
```

- The `//go:embed` directive embeds the entire `static/` directory into the binary at compile time
- `staticFiles` is an embedded filesystem containing all files from `static/`
- This allows the binary to be self-contained without needing external static files

---

## Data Structures

### WatchedFile (Lines 24-32)

```go
type WatchedFile struct {
    Path       string    `json:"path"`
    Name       string    `json:"name"`
    TrackTime  time.Time `json:"trackTime"`
    LastChange time.Time `json:"lastChange"`
    HTML       string    `json:"html,omitempty"`
    Active     bool      `json:"active"`
}
```

Represents a markdown file being tracked by the server.

| Field | Type | Description |
|-------|------|-------------|
| `Path` | string | Absolute path to the file on disk |
| `Name` | string | Base filename (e.g., "README.md") |
| `TrackTime` | time.Time | When the file was first registered |
| `LastChange` | time.Time | Last modification time from filesystem |
| `HTML` | string | Rendered HTML content (omitted if empty in JSON) |
| `Active` | bool | Whether fsnotify is actively watching for changes |

### Message (Lines 34-42)

```go
type Message struct {
    Type  string        `json:"type"`
    Files []WatchedFile `json:"files,omitempty"`
    File  *WatchedFile  `json:"file,omitempty"`
    Path  string        `json:"path,omitempty"`
    Log   *LogEntry     `json:"log,omitempty"`
    Logs  []LogEntry    `json:"logs,omitempty"`
}
```

WebSocket message sent to browser clients.

| Field | Type | Used When |
|-------|------|-----------|
| `Type` | string | Always present. Values: "files", "update", "removed", "log", "logs" |
| `Files` | []WatchedFile | Type="files" - full list of tracked files |
| `File` | *WatchedFile | Type="update" - single file that changed |
| `Path` | string | Type="removed" - path of removed file |
| `Log` | *LogEntry | Type="log" - single log entry |
| `Logs` | []LogEntry | Type="logs" - all log entries |

### Client (Lines 44-49)

```go
type Client struct {
    hub  *Hub
    conn *websocket.Conn
    send chan []byte
}
```

Represents a connected browser.

| Field | Type | Description |
|-------|------|-------------|
| `hub` | *Hub | Reference to the central Hub |
| `conn` | *websocket.Conn | WebSocket connection |
| `send` | chan []byte | Buffered channel for outgoing messages (256 buffer) |

### Hub (Lines 51-63)

```go
type Hub struct {
    clients    map[*Client]bool
    broadcast  chan []byte
    register   chan *Client
    unregister chan *Client

    mu       sync.RWMutex
    files    map[string]*WatchedFile
    watchers map[string]*Watcher
    renderer *Renderer
    logger   *Logger
}
```

Central coordinator managing all state.

| Field | Type | Description |
|-------|------|-------------|
| `clients` | map[*Client]bool | Set of connected clients |
| `broadcast` | chan []byte | Channel for messages to all clients (256 buffer) |
| `register` | chan *Client | Channel for new client connections |
| `unregister` | chan *Client | Channel for client disconnections |
| `mu` | sync.RWMutex | Protects concurrent access to files/watchers |
| `files` | map[string]*WatchedFile | Tracked files keyed by path |
| `watchers` | map[string]*Watcher | File watchers keyed by path |
| `renderer` | *Renderer | Markdown-to-HTML renderer |
| `logger` | *Logger | In-memory log buffer |

---

## Hub Methods

### NewHub (Lines 65-78)

```go
func NewHub() *Hub {
    h := &Hub{
        clients:    make(map[*Client]bool),
        broadcast:  make(chan []byte, 256),
        register:   make(chan *Client),
        unregister: make(chan *Client),
        files:      make(map[string]*WatchedFile),
        watchers:   make(map[string]*Watcher),
        renderer:   NewRenderer(),
        logger:     NewLogger(100),
    }
    h.logger.SetHub(h)
    return h
}
```

Creates and initializes a new Hub:
- Allocates all maps and channels
- Creates a Renderer for markdown processing
- Creates a Logger with 100-entry capacity
- Links the Logger back to Hub for broadcasting log entries

### Run (Lines 80-107)

```go
func (h *Hub) Run() {
    for {
        select {
        case client := <-h.register:
            h.clients[client] = true
            h.logger.Info("Browser connected")
            h.sendFileList(client)

        case client := <-h.unregister:
            if _, ok := h.clients[client]; ok {
                delete(h.clients, client)
                close(client.send)
                h.logger.Info("Browser disconnected")
            }

        case message := <-h.broadcast:
            for client := range h.clients {
                select {
                case client.send <- message:
                default:
                    close(client.send)
                    delete(h.clients, client)
                }
            }
        }
    }
}
```

Main event loop (runs in its own goroutine):

1. **Register** (lines 83-87): When a client connects:
   - Add to clients map
   - Log the connection
   - Send current file list to the new client

2. **Unregister** (lines 89-94): When a client disconnects:
   - Check if client exists (avoid double-close)
   - Remove from map
   - Close send channel
   - Log disconnection

3. **Broadcast** (lines 96-104): When a message needs to go to all clients:
   - Iterate all clients
   - Try non-blocking send to each client's channel
   - If channel is full (client slow), disconnect that client

### sendFileList (Lines 109-126)

```go
func (h *Hub) sendFileList(client *Client) {
    h.mu.RLock()
    files := make([]WatchedFile, 0, len(h.files))
    for _, f := range h.files {
        files = append(files, *f)
    }
    h.mu.RUnlock()

    msg := Message{Type: "files", Files: files}
    data, _ := json.Marshal(msg)
    client.send <- data

    logs := h.logger.GetEntries()
    logsMsg := Message{Type: "logs", Logs: logs}
    logsData, _ := json.Marshal(logsMsg)
    client.send <- logsData
}
```

Sends current state to a single client (used on connect):
- Acquires read lock, copies all files to a slice
- Sends "files" message with full file list
- Sends "logs" message with all log entries

### broadcastFileList (Lines 128-139)

```go
func (h *Hub) broadcastFileList() {
    h.mu.RLock()
    files := make([]WatchedFile, 0, len(h.files))
    for _, f := range h.files {
        files = append(files, *f)
    }
    h.mu.RUnlock()

    msg := Message{Type: "files", Files: files}
    data, _ := json.Marshal(msg)
    h.broadcast <- data
}
```

Sends file list to all connected clients (used when file list changes).

### broadcastFileUpdate (Lines 141-145)

```go
func (h *Hub) broadcastFileUpdate(file *WatchedFile) {
    msg := Message{Type: "update", File: file}
    data, _ := json.Marshal(msg)
    h.broadcast <- data
}
```

Sends a single file update to all clients (used when file content changes).

### broadcastLog (Lines 147-151)

```go
func (h *Hub) broadcastLog(entry LogEntry) {
    msg := Message{Type: "log", Log: &entry}
    data, _ := json.Marshal(msg)
    h.broadcast <- data
}
```

Sends a log entry to all clients (called by Logger).

### AddFile (Lines 153-155)

```go
func (h *Hub) AddFile(path string) error {
    return h.AddFileWithActive(path, false)
}
```

Convenience wrapper to add a file without active watching (registered but not watched).

### AddFileWithActive (Lines 157-204)

```go
func (h *Hub) AddFileWithActive(path string, active bool) error {
    h.mu.Lock()

    // Check if already registered (case-insensitive on Windows)
    for existingPath := range h.files {
        if PathsEqual(existingPath, path) {
            h.mu.Unlock()
            return fmt.Errorf("already registered: %s", filepath.Base(existingPath))
        }
    }

    // Get file info
    info, err := os.Stat(path)
    if err != nil {
        h.mu.Unlock()
        return err
    }

    // Render content
    html, err := h.renderer.Render(path)
    if err != nil {
        h.mu.Unlock()
        return err
    }

    file := &WatchedFile{
        Path:       path,
        Name:       filepath.Base(path),
        TrackTime:  time.Now(),
        LastChange: info.ModTime(),
        HTML:       html,
        Active:     active,
    }
    h.files[path] = file

    h.mu.Unlock()

    // Only start watcher if active
    if active {
        h.startWatcher(path)
        h.logger.Info(fmt.Sprintf("Started watching: %s", filepath.Base(path)))
    } else {
        h.logger.Info(fmt.Sprintf("Registered: %s", filepath.Base(path)))
    }

    h.broadcastFileList()
    return nil
}
```

Registers a new file:
1. **Duplicate check** (lines 160-166): Case-insensitive path comparison using `PathsEqual`
2. **File validation** (lines 168-173): Verify file exists via `os.Stat`
3. **Initial render** (lines 175-180): Convert markdown to HTML
4. **Create record** (lines 182-190): Populate `WatchedFile` struct
5. **Start watcher** (lines 194-200): Only if `active=true`
6. **Broadcast** (line 202): Notify all clients of new file

### startWatcher (Lines 206-242)

```go
func (h *Hub) startWatcher(path string) {
    h.mu.Lock()
    if _, exists := h.watchers[path]; exists {
        h.mu.Unlock()
        return
    }

    watcher := NewWatcher()
    h.watchers[path] = watcher
    h.mu.Unlock()

    watcher.Watch(path, func() {
        h.mu.Lock()
        f, exists := h.files[path]
        if !exists || !f.Active {
            h.mu.Unlock()
            return
        }

        html, err := h.renderer.Render(path)
        if err != nil {
            h.logger.Error(fmt.Sprintf("Error rendering %s: %v", filepath.Base(path), err))
            h.mu.Unlock()
            return
        }

        info, _ := os.Stat(path)
        f.HTML = html
        f.LastChange = info.ModTime()
        h.mu.Unlock()

        h.logger.Info(fmt.Sprintf("File changed: %s", filepath.Base(path)))
        h.broadcastFileUpdate(f)
    })
}
```

Starts filesystem watching for a file:
1. **Idempotency check** (lines 207-211): Skip if already watching
2. **Create watcher** (lines 213-216): Instantiate and store
3. **Register callback** (lines 218-241): On file change:
   - Verify file still registered and active
   - Re-render markdown to HTML
   - Update modification time
   - Broadcast to clients

### ActivateFile (Lines 244-287)

```go
func (h *Hub) ActivateFile(path string) error
```

Activates watching for a previously registered (inactive) file:
1. Find file using case-insensitive matching
2. Return error if not found
3. Return early if already active
4. Refresh HTML content
5. Set `Active = true`
6. Start watcher
7. Broadcast updated list

### DeactivateFile (Lines 289-326)

```go
func (h *Hub) DeactivateFile(path string) error
```

Stops watching a file without removing it:
1. Find file using case-insensitive matching
2. Return error if not found
3. Return early if already inactive
4. Set `Active = false`
5. Close and remove watcher
6. Broadcast updated list

### RemoveFile (Lines 328-365)

```go
func (h *Hub) RemoveFile(path string) error
```

Completely removes a file from tracking:
1. Find file using case-insensitive matching
2. Return error if not found
3. Close watcher if exists
4. Delete from files map
5. Broadcast "removed" message with path

### GetFiles (Lines 367-376)

```go
func (h *Hub) GetFiles() []WatchedFile {
    h.mu.RLock()
    defer h.mu.RUnlock()

    files := make([]WatchedFile, 0, len(h.files))
    for _, f := range h.files {
        files = append(files, *f)
    }
    return files
}
```

Returns a copy of all tracked files (thread-safe).

### Close (Lines 378-385)

```go
func (h *Hub) Close() {
    h.mu.Lock()
    defer h.mu.Unlock()

    for _, w := range h.watchers {
        w.Close()
    }
}
```

Cleanup: closes all file watchers.

---

## Server Struct (Lines 387-392)

```go
type Server struct {
    hub    *Hub
    port   int
    server *http.Server
}
```

| Field | Type | Description |
|-------|------|-------------|
| `hub` | *Hub | Reference to the Hub |
| `port` | int | TCP port number |
| `server` | *http.Server | HTTP server instance |

---

## WebSocket Upgrader (Lines 394-398)

```go
var upgrader = websocket.Upgrader{
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
    CheckOrigin:     func(r *http.Request) bool { return true },
}
```

Configures WebSocket upgrade:
- 1KB read/write buffers
- `CheckOrigin` allows all origins (CORS disabled for simplicity)

---

## HTTP Handlers

### handleWebSocket (Lines 400-438)

```go
func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request)
```

Handles WebSocket connections at `/ws`:

1. **Upgrade** (lines 401-405): Convert HTTP to WebSocket
2. **Create client** (lines 407-411): Initialize Client struct with 256-message buffer
3. **Register** (line 413): Send client to Hub's register channel
4. **Writer goroutine** (lines 415-424):
   - Reads from `client.send` channel
   - Sets 10-second write deadline
   - Writes messages to WebSocket
   - Exits when channel closes
5. **Reader goroutine** (lines 426-437):
   - Reads messages (currently discarded)
   - Detects disconnect when read fails
   - Unregisters client on exit

### handleAddFile (Lines 440-456)

```go
func (s *Server) handleAddFile(w http.ResponseWriter, r *http.Request)
```

Handles `POST /api/watch`:
- Expects JSON body: `{"path": "/path/to/file.md", "active": true}`
- Calls `hub.AddFileWithActive`
- Returns 400 on error, 200 on success

### handleActivateFile (Lines 458-471)

```go
func (s *Server) handleActivateFile(w http.ResponseWriter, r *http.Request)
```

Handles `POST /api/files/activate`:
- Expects query parameter: `?path=/path/to/file.md`
- Calls `hub.ActivateFile`
- Returns 400 on error, 200 on success

### handleDeactivateFile (Lines 473-486)

```go
func (s *Server) handleDeactivateFile(w http.ResponseWriter, r *http.Request)
```

Handles `POST /api/files/deactivate`:
- Expects query parameter: `?path=/path/to/file.md`
- Calls `hub.DeactivateFile`
- Returns 400 on error, 200 on success

### handleRemoveFile (Lines 488-501)

```go
func (s *Server) handleRemoveFile(w http.ResponseWriter, r *http.Request)
```

Handles `DELETE /api/watch` and `DELETE /api/remove`:
- Expects query parameter: `?path=/path/to/file.md`
- Calls `hub.RemoveFile`
- Returns 400 on error, 200 on success

### handleListFiles (Lines 503-507)

```go
func (s *Server) handleListFiles(w http.ResponseWriter, r *http.Request)
```

Handles `GET /api/files`:
- Returns JSON array of all tracked files

### handleLogs (Lines 509-513)

```go
func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request)
```

Handles `GET /api/logs`:
- Returns JSON array of all log entries

---

## StartServer (Lines 515-607)

```go
func StartServer(port int)
```

Main entry point for the HTTP server.

### Initialization (Lines 516-522)

```go
hub := NewHub()
go hub.Run()

s := &Server{
    hub:  hub,
    port: port,
}
```

Creates Hub and starts its event loop in a goroutine.

### Route Configuration (Lines 524-585)

| Route | Method | Handler | Description |
|-------|--------|---------|-------------|
| `/` | GET | inline | Serves `index.html` from embedded files |
| `/static/*` | GET | FileServer | Serves static assets |
| `/ws` | GET | handleWebSocket | WebSocket endpoint |
| `/api/watch` | POST | handleAddFile | Register a file |
| `/api/watch` | DELETE | handleRemoveFile | Unregister a file |
| `/api/files` | GET | handleListFiles | List all files |
| `/api/files/activate` | POST | handleActivateFile | Start watching a file |
| `/api/files/deactivate` | POST | handleDeactivateFile | Stop watching a file |
| `/api/logs` | GET | handleLogs | Get log entries |
| `/api/remove` | DELETE | handleRemoveFile | Alias for DELETE /api/watch |
| `/api/shutdown` | POST | inline | Gracefully shutdown server |

### Root Handler (Lines 527-535)

```go
mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    if r.URL.Path != "/" {
        http.NotFound(w, r)
        return
    }
    data, _ := staticFiles.ReadFile("static/index.html")
    w.Header().Set("Content-Type", "text/html; charset=utf-8")
    w.Write(data)
})
```

Only serves `index.html` at exact path `/`, returns 404 for other paths.

### Static Files (Lines 537-539)

```go
staticFS, _ := fs.Sub(staticFiles, "static")
mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
```

- `fs.Sub` creates a sub-filesystem rooted at `static/`
- `StripPrefix` removes `/static/` prefix before looking up files
- `FileServer` serves files from the embedded filesystem

### Shutdown Handler (Lines 578-585)

```go
mux.HandleFunc("/api/shutdown", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    go func() {
        time.Sleep(100 * time.Millisecond)
        hub.Close()
        s.server.Shutdown(context.Background())
    }()
})
```

- Returns 200 immediately
- Waits 100ms (allows response to be sent)
- Closes all watchers
- Gracefully shuts down HTTP server

### Server Start (Lines 587-606)

```go
s.server = &http.Server{
    Addr:    fmt.Sprintf(":%d", port),
    Handler: mux,
}

sigChan := make(chan os.Signal, 1)
signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

go func() {
    <-sigChan
    fmt.Println("\nShutting down...")
    hub.Close()
    removeLockFile()
    s.server.Shutdown(context.Background())
}()

if err := s.server.ListenAndServe(); err != http.ErrServerClosed {
    log.Fatalf("Server error: %v", err)
}
```

1. **Create server** (lines 587-590): Configure address and handler
2. **Signal handling** (lines 592-602):
   - Listen for SIGINT (Ctrl+C) and SIGTERM
   - On signal: close watchers, remove lock file, shutdown server
3. **Start listening** (lines 604-606):
   - Blocks until shutdown
   - Only logs fatal if error is not normal shutdown

---

## Thread Safety

The Hub uses a `sync.RWMutex` (`h.mu`) to protect concurrent access:

| Operation | Lock Type |
|-----------|-----------|
| Reading files map | RLock |
| Modifying files/watchers | Lock |
| Channel operations | No lock needed (channels are thread-safe) |

The Hub's `Run()` loop is the only writer to the `clients` map, ensuring safe concurrent access.

---

## WebSocket Message Flow

```
Browser                    Server
   |                          |
   |--- HTTP Upgrade -------->|
   |<-- 101 Switching --------|
   |                          |
   |<-- files (JSON) ---------|
   |<-- logs (JSON) ----------|
   |                          |
   |    (file changes)        |
   |<-- update (JSON) --------|
   |                          |
   |    (file removed)        |
   |<-- removed (JSON) -------|
   |                          |
   |    (disconnect)          |
   |--- Close --------------->|
```

---

## Dependencies

- `watcher.go`: `Watcher` type for filesystem monitoring
- `renderer.go`: `Renderer` type for markdown-to-HTML conversion
- `logger.go`: `Logger` type for in-memory logging
- `path.go`: `PathsEqual` function for cross-platform path comparison
- `lock.go`: `removeLockFile` function for cleanup
