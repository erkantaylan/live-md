# LiveMD

**Live markdown viewer powered by CLI file watching**

## Problem

Reading markdown files from the terminal is painful:
- No formatting, headers look like `# text`
- Code blocks are just plain text
- Tables are unreadable
- Images don't render
- Constantly running `cat file.md` to see changes

When AI agents generate or edit markdown files, you want to **see** them properly - not squint at raw text.

## Solution

LiveMD serves markdown files to your browser with live updates. Point it at a file from CLI, see it rendered instantly.

```
Terminal                          Browser (localhost:3000)
─────────────────────────────────────────────────────────────
$ livemd watch README.md      →   [Rendered README.md]
                                  - Headers formatted
                                  - Code highlighted
                                  - Tables rendered
                                  - Live updates on save
```

## How It Works

```
┌─────────────┐    watch     ┌─────────────┐   websocket   ┌─────────────┐
│  CLI        │ ──────────── │  Server     │ ────────────  │  Browser    │
│  livemd     │              │  (Go/Node)  │               │  localhost  │
└─────────────┘              └─────────────┘               └─────────────┘
       │                            │                             │
       │  watch hello.md            │                             │
       │ ─────────────────────────► │  reads file                 │
       │                            │  converts to HTML           │
       │                            │ ───────────────────────────►│ displays
       │                            │                             │
       │  [file changes on disk]    │                             │
       │                            │  detects change             │
       │                            │  sends new HTML             │
       │                            │ ───────────────────────────►│ updates
       │                            │                             │  (no refresh)
```

## CLI Usage

```bash
# Watch a single file
livemd watch README.md

# Watch with custom port
livemd watch README.md --port 8080

# Watch multiple files (future)
livemd watch docs/*.md

# Watch a directory (future)
livemd watch ./docs
```

## Features

### MVP (v0.1)

- [ ] `livemd watch <file.md>` - watch single file
- [ ] Serve on `localhost:3000` by default
- [ ] Convert markdown to HTML with proper styling
- [ ] WebSocket for live updates (no page refresh)
- [ ] File watcher with ~1 second poll interval
- [ ] Syntax highlighting for code blocks
- [ ] Clean, readable default theme

### Future (v0.2+)

- [ ] Watch multiple files
- [ ] File tree sidebar
- [ ] Dark/light theme toggle
- [ ] Custom CSS support
- [ ] Table of contents generation
- [ ] Search within document
- [ ] Print-friendly view
- [ ] `--open` flag to auto-open browser

## Tech Stack Options

### Option A: Go
- Fast binary, no runtime needed
- `fsnotify` for file watching
- `goldmark` for markdown parsing
- `gorilla/websocket` for live updates
- Single binary distribution

### Option B: Node.js
- `chokidar` for file watching
- `marked` or `markdown-it` for parsing
- `ws` for WebSocket
- Requires Node runtime

### Option C: Rust
- Maximum performance
- `notify` for file watching
- `pulldown-cmark` for markdown
- Single binary, fast startup

**Recommendation:** Go - single binary, fast, good ecosystem for this use case.

## Architecture

```
livemd/
├── cmd/
│   └── livemd/
│       └── main.go          # CLI entry point
├── internal/
│   ├── server/
│   │   └── server.go        # HTTP + WebSocket server
│   ├── watcher/
│   │   └── watcher.go       # File system watcher
│   ├── renderer/
│   │   └── markdown.go      # Markdown to HTML conversion
│   └── static/
│       ├── index.html       # Browser template
│       ├── style.css        # Default styling
│       └── client.js        # WebSocket client
└── go.mod
```

## Browser View

```
┌─────────────────────────────────────────────────────────────┐
│  LiveMD                              README.md  [live]  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  # Project Title                                            │
│                                                             │
│  This is the rendered markdown content with proper          │
│  formatting, syntax highlighting, and tables.               │
│                                                             │
│  ```go                                                      │
│  func main() {                                              │
│      fmt.Println("Hello")                                   │
│  }                                                          │
│  ```                                                        │
│                                                             │
│  | Column A | Column B |                                    │
│  |----------|----------|                                    │
│  | Value 1  | Value 2  |                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Use Cases

1. **Watching AI output** - See docs/plans as agents write them
2. **README editing** - Live preview while editing
3. **Documentation review** - Read rendered docs without IDE
4. **Note taking** - Quick markdown notes with live view
5. **Presentations** - Simple markdown slides

## Development Plan

### Phase 1: Core (MVP)
1. CLI with `watch` command
2. HTTP server serving static HTML template
3. WebSocket connection for live updates
4. File watcher detecting changes
5. Markdown to HTML conversion
6. Basic CSS styling

### Phase 2: Polish
1. Syntax highlighting (highlight.js or Prism)
2. Better typography
3. Error handling (file not found, etc.)
4. Graceful shutdown

### Phase 3: Features
1. Multiple file support
2. Directory watching
3. Theme support
4. Configuration file

---

*Project idea for testing with Gas Town multi-agent workflow*
