package main

import (
	"log"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Watcher watches a file for changes with debouncing
type Watcher struct {
	watcher *fsnotify.Watcher
	done    chan struct{}
	mu      sync.Mutex
	timer   *time.Timer
}

func NewWatcher() *Watcher {
	return &Watcher{
		done: make(chan struct{}),
	}
}

func (w *Watcher) Watch(filepath string, onChange func()) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	w.watcher = watcher

	if err := watcher.Add(filepath); err != nil {
		watcher.Close()
		return err
	}

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}

				// Only react to write events
				if event.Op&fsnotify.Write == fsnotify.Write {
					w.debounce(onChange)
				}

				// Handle file recreation (some editors do this)
				if event.Op&fsnotify.Remove == fsnotify.Remove {
					// Re-add the watch after a brief delay
					time.Sleep(100 * time.Millisecond)
					watcher.Add(filepath)
					w.debounce(onChange)
				}

			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Printf("Watcher error: %v", err)

			case <-w.done:
				return
			}
		}
	}()

	return nil
}

func (w *Watcher) debounce(fn func()) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.timer != nil {
		w.timer.Stop()
	}

	w.timer = time.AfterFunc(100*time.Millisecond, fn)
}

func (w *Watcher) Close() error {
	close(w.done)
	if w.watcher != nil {
		return w.watcher.Close()
	}
	return nil
}
