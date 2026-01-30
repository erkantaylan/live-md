.PHONY: build run install clean dev

# Default file to watch
FILE ?= README.md
PORT ?= 3000

# Build the binary
build:
	go build -o livemd .

# Run with a file (usage: make run FILE=docs/guide.md)
run: build
	./livemd --port $(PORT) $(FILE)

# Install globally
install: build
	cp livemd /usr/local/bin/

# Clean build artifacts
clean:
	rm -f livemd

# Dev: rebuild and run on source changes (requires entr)
dev:
	find . -name '*.go' -o -name '*.html' -o -name '*.css' -o -name '*.js' | entr -r make run FILE=$(FILE)
