.PHONY: help build run install clean start stop add remove list

.DEFAULT_GOAL := help

# Detect OS for binary name
ifeq ($(OS),Windows_NT)
    BINARY = livemd.exe
    RM = del /F /Q
else
    BINARY = livemd
    RM = rm -f
endif

# Build the binary
build:
	go build -buildvcs=false -o $(BINARY) .

# Start the server
run: build
	./$(BINARY) start

# Install globally (Unix only)
install: build
ifeq ($(OS),Windows_NT)
	@echo "On Windows, copy $(BINARY) to a directory in your PATH manually"
else
	cp $(BINARY) /usr/local/bin/
endif

# Clean build artifacts
clean:
	$(RM) $(BINARY)

# Server commands
start: build
	./$(BINARY) start

stop:
	./$(BINARY) stop

add:
ifndef FILE
	@echo "Usage: make add FILE=path/to/file.md"
else
	./$(BINARY) add $(FILE)
endif

remove:
ifndef FILE
	@echo "Usage: make remove FILE=path/to/file.md"
else
	./$(BINARY) remove $(FILE)
endif

list:
	./$(BINARY) list

# Show help
help:
	@echo "LiveMD - Live markdown viewer"
	@echo ""
	@echo "Build:"
	@echo "  make build          Build the binary"
	@echo "  make install        Install to /usr/local/bin"
	@echo "  make clean          Remove binary"
	@echo ""
	@echo "Server:"
	@echo "  make start          Start the server"
	@echo "  make stop           Stop the server"
	@echo ""
	@echo "Files:"
	@echo "  make add FILE=x     Add a file to watch"
	@echo "  make remove FILE=x  Remove a file"
	@echo "  make list           List watched files"
