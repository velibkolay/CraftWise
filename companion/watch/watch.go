// Package watch notices when the game has written a file: it polls the file's size and
// modification time and reports a change once both stayed the same for a settle time, so a file
// still being written is never read (WoW writes SavedVariables on /reload and logout).
package watch

import (
	"context"
	"os"
	"time"
)

// Sig is what is compared between polls.
type Sig struct {
	Exists bool
	Size   int64
	Mod    int64 // modification time, Unix nanoseconds
}

// SigOf reads a file's signature; a missing file has Exists false.
func SigOf(fi os.FileInfo, err error) Sig {
	if err != nil || fi == nil {
		return Sig{}
	}
	return Sig{Exists: true, Size: fi.Size(), Mod: fi.ModTime().UnixNano()}
}

// Debouncer decides when a change is complete. It is pure (no clock, no I/O), for tests.
type Debouncer struct {
	Settle time.Duration

	done      Sig // signature last reported (or the start one)
	seen      Sig // signature at the last observation
	changedAt time.Time
	pending   bool
}

// NewDebouncer starts from the signature the file has now (no report for it).
func NewDebouncer(settle time.Duration, start Sig) *Debouncer {
	return &Debouncer{Settle: settle, done: start, seen: start}
}

// Observe takes the signature seen at now and reports true once a change has been stable for
// Settle. A file that disappears is not reported; it is reported when it comes back.
func (d *Debouncer) Observe(s Sig, now time.Time) bool {
	if s != d.seen {
		d.seen = s
		d.changedAt = now
		d.pending = s.Exists && s != d.done
		return false
	}
	if d.pending && now.Sub(d.changedAt) >= d.Settle {
		d.pending = false
		d.done = s
		return true
	}
	return false
}

// Retry asks for the current signature to be reported again after another settle time (the file
// looked complete but couldn't be read, e.g. still being written in one go).
func (d *Debouncer) Retry(now time.Time) {
	if d.seen.Exists {
		d.done = Sig{}
		d.pending = true
		d.changedAt = now
	}
}

// Watcher polls Path every Poll and sends on C when the file changed and settled.
type Watcher struct {
	Path   string
	Poll   time.Duration
	Settle time.Duration
	C      chan struct{}

	stat  func(string) (os.FileInfo, error)
	deb   *Debouncer
	retry chan struct{}
}

// New watches path; the file's current state counts as already seen.
func New(path string, poll, settle time.Duration) *Watcher {
	w := &Watcher{Path: path, Poll: poll, Settle: settle, C: make(chan struct{}, 1), stat: os.Stat, retry: make(chan struct{}, 1)}
	w.deb = NewDebouncer(settle, SigOf(w.stat(path)))
	return w
}

// Retry reports the file again after the settle time.
func (w *Watcher) Retry() {
	select {
	case w.retry <- struct{}{}:
	default:
	}
}

// Run polls until ctx ends.
func (w *Watcher) Run(ctx context.Context) {
	t := time.NewTicker(w.Poll)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-w.retry:
			w.deb.Retry(time.Now())
		case now := <-t.C:
			if w.deb.Observe(SigOf(w.stat(w.Path)), now) {
				select {
				case w.C <- struct{}{}:
				default:
				}
			}
		}
	}
}
