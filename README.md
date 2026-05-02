# LiveMD

Live file viewer with syntax highlighting, powered by CLI file watching.

## Problem

Reading markdown in the terminal is painful - no formatting, code blocks are plain text, tables are unreadable. When AI agents generate markdown files, you want to **see** them properly rendered.

## Solution

LiveMD runs as a persistent server. Add markdown files to watch from the CLI, see them rendered in your browser with live updates.

```
Terminal                              Browser (localhost:3000)
────────────────────────────────────────────────────────────────
$ livemd start                    →   Server started

$ livemd add README.md            →   Sidebar shows README.md
                                      Content rendered on right

$ livemd add docs/guide.md        →   Two files in sidebar
                                      Click to switch

[edit README.md]                  →   Browser updates live
```

## Install

The installers are **idempotent** — re-running them updates an existing install in place. Once livemd is on your machine you can also self-update with `livemd install`.

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/erkantaylan/livemd/master/install.sh | sudo bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/erkantaylan/livemd/master/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\livemd\` and adds it to your user `PATH`. No admin required.

### From source

```bash
git clone https://github.com/erkantaylan/livemd.git
cd livemd
make install              # build, install, start daemon
make install PORT=3001    # same, but on port 3001
```

`make install` works as both first-time install and update — it stops any running daemon, replaces the binary, and starts the new one.

### Custom port

- Make: `make install PORT=3001`
- Curl/iex: `LIVEMD_PORT=3001 curl ... | sudo bash` or `$env:LIVEMD_PORT=3001; irm ... | iex`
- Or set persistently any time: `livemd port 3001`

## Usage

The installer above already starts the server in the background. Otherwise:

```bash
# Start the server (foreground — Ctrl+C to stop)
livemd start

# Or as a background daemon
livemd start --detach

# Add files to watch
livemd add README.md
livemd add docs/guide.md

# Add entire folder recursively
livemd add ./docs -r
livemd add ./src -r --filter "md,go,js"

# List watched files
livemd list

# Remove a file
livemd remove README.md

# Stop the server
livemd stop
```

Open http://localhost:3000 in your browser.

## Make Commands

```
make              Show help
make build        Build the binary in the current directory
make clean        Remove the local build

make install      Build, install, and start daemon (idempotent — also updates)
make install PORT=3001    Same, but on a specific port
make uninstall    Stop daemon and remove binary

make start        Start the daemon (assumes already installed)
make stop         Stop the daemon

make watch f1 f2      Add files to watch
make watch-dir ./dir  Add folder recursively
make unwatch f1       Remove files from watch
make list             List watched files
```

## Features

- **Persistent server** - Start once, add files anytime
- **Tree view sidebar** - Collapsible folder structure like a solution explorer
- **Lazy watching** - Files are registered but only actively watched when selected (saves system resources)
- **Recursive folder watching** - Add entire directories with `livemd add ./folder -r`
- **WebSocket live updates** - No page refresh needed
- **GitHub-flavored markdown** - Tables, task lists, autolinks
- **Syntax highlighting** - Code blocks in markdown and standalone code files (50+ languages)
- **Network access** - Shows all network interface IPs on startup for easy access from other devices
- **Cross-platform** - Works on Linux, macOS, Windows

## Tech Stack

- Go single binary (~15MB)
- [goldmark](https://github.com/yuin/goldmark) for markdown parsing
- [chroma](https://github.com/alecthomas/chroma) for syntax highlighting
- [fsnotify](https://github.com/fsnotify/fsnotify) for file watching
- [gorilla/websocket](https://github.com/gorilla/websocket) for live updates
