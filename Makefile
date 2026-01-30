.PHONY: help build run install clean

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

# Show help
help:
	@echo "LiveMD - Live markdown viewer"
	@echo ""
	@echo "Usage:"
	@echo "  make build        Build the binary"
	@echo "  make run          Build and start the server"
	@echo "  make install      Install to /usr/local/bin"
	@echo "  make clean        Remove binary"
	@echo ""
	@echo "CLI Commands:"
	@echo "  livemd start      Start the server"
	@echo "  livemd add FILE   Add a file to watch"
	@echo "  livemd remove FILE Remove a file"
	@echo "  livemd list       List watched files"
	@echo "  livemd stop       Stop the server"
