.PHONY: help build clean install start stop uninstall list watch watch-dir unwatch

.DEFAULT_GOAL := help

# Recipes use unix-style commands (cp/mkdir/rm) — works in MSYS/Git Bash on Windows.
# Native cmd users should use install.ps1.
ifeq ($(OS),Windows_NT)
    BINARY = livemd.exe
    # Forward slashes so MSYS handles paths cleanly.
    INSTALL_DIR ?= $(subst \,/,$(LOCALAPPDATA))/Programs/livemd
else
    BINARY = livemd
    PREFIX ?= $(HOME)/.local
    INSTALL_DIR ?= $(PREFIX)/bin
endif
INSTALLED = $(INSTALL_DIR)/$(BINARY)

# Capture extra arguments for watch/unwatch
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(ARGS):;@:)

# Version from git tag (fallback to dev)
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)

build:
	go build -buildvcs=false -ldflags="-X main.Version=$(VERSION)" -o $(BINARY) .

clean:
	rm -f $(BINARY)

# Install: idempotent. Stops any running daemon, replaces the binary, starts it back.
# First run installs and starts; subsequent runs upgrade in place.
# Pass PORT=N to set the persistent default port.
install: build
	-@test -x "$(INSTALLED)" && "$(INSTALLED)" stop 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@cp $(BINARY) "$(INSTALLED)"
	@rm -f "$(INSTALLED).bak"
ifneq ($(OS),Windows_NT)
	@chmod 755 "$(INSTALLED)"
endif
ifdef PORT
	@"$(INSTALLED)" port $(PORT)
endif
	@echo ""
	@echo "Installed to $(INSTALLED)"
	@"$(INSTALLED)" ensure-path
	@"$(INSTALLED)" start --detach

# Start the daemon (assumes already installed)
start:
	@"$(INSTALLED)" start --detach

# Stop the daemon
stop:
	@"$(INSTALLED)" stop

# Uninstall: stop daemon and remove binary
uninstall:
	-@test -x "$(INSTALLED)" && "$(INSTALLED)" stop 2>/dev/null || true
	@rm -f "$(INSTALLED)"
	@echo "Removed $(INSTALLED)"

list:
	@"$(INSTALLED)" list

watch:
ifeq ($(ARGS),)
	@echo "Usage: make watch file1.md file2.md ..."
else
	@for f in $(ARGS); do "$(INSTALLED)" add $$f; done
endif

watch-dir:
ifeq ($(ARGS),)
	@echo "Usage: make watch-dir ./folder"
else
	@"$(INSTALLED)" add $(firstword $(ARGS)) -r
endif

unwatch:
ifeq ($(ARGS),)
	@echo "Usage: make unwatch file1.md file2.md ..."
else
	@for f in $(ARGS); do "$(INSTALLED)" remove $$f; done
endif

help:
	@echo "LiveMD - Live markdown viewer"
	@echo ""
	@echo "Setup:"
	@echo "  make build              Build $(BINARY) in current directory"
	@echo "  make install            Install + start daemon (idempotent: also updates)"
	@echo "  make install PORT=3001  Install with a specific port"
	@echo "  make uninstall          Stop daemon and remove binary"
	@echo "  make clean              Delete local build"
	@echo ""
	@echo "Daemon:"
	@echo "  make start              Start the daemon"
	@echo "  make stop               Stop the daemon"
	@echo ""
	@echo "Files:"
	@echo "  make watch f1 f2 ...    Add files to watch"
	@echo "  make watch-dir ./dir    Add folder recursively"
	@echo "  make unwatch f1 f2 ...  Remove files"
	@echo "  make list               List watched files"
	@echo ""
	@echo "Install dir: $(INSTALL_DIR)"
