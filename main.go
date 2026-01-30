package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func main() {
	port := flag.Int("port", 3000, "port to serve on")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "LiveMD - Live markdown viewer\n\n")
		fmt.Fprintf(os.Stderr, "Usage: livemd [options] <file.md>\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  livemd README.md\n")
		fmt.Fprintf(os.Stderr, "  livemd --port 8080 docs/guide.md\n")
	}
	flag.Parse()

	if flag.NArg() < 1 {
		flag.Usage()
		os.Exit(1)
	}

	filePath := flag.Arg(0)

	// Validate file exists
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		log.Fatalf("Error resolving path: %v", err)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		log.Fatalf("File not found: %s", absPath)
	}

	// Create components
	renderer := NewRenderer()
	hub := NewHub()
	watcher := NewWatcher()

	// Start hub
	go hub.Run()

	// Initial render
	html, err := renderer.Render(absPath)
	if err != nil {
		log.Printf("Warning: initial render failed: %v", err)
	}
	hub.SetContent(filepath.Base(absPath), html)

	// Watch for changes
	onChange := func() {
		html, err := renderer.Render(absPath)
		if err != nil {
			hub.SetError(err.Error())
			return
		}
		hub.SetContent(filepath.Base(absPath), html)
		log.Printf("File updated: %s", filepath.Base(absPath))
	}

	if err := watcher.Watch(absPath, onChange); err != nil {
		log.Fatalf("Error starting watcher: %v", err)
	}

	// Start server
	server := NewServer(hub, *port)

	// Graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		fmt.Println("\nShutting down...")
		watcher.Close()
		server.Shutdown(ctx)
		cancel()
	}()

	fmt.Printf("\n  LiveMD serving %s\n", filepath.Base(absPath))
	fmt.Printf("  http://localhost:%d\n\n", *port)

	if err := server.Start(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
