package watch

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

var t0 = time.Unix(1_794_000_000, 0)

func at(s int) time.Time { return t0.Add(time.Duration(s) * time.Second) }

func TestDebounceWaitsForStableFile(t *testing.T) {
	start := Sig{Exists: true, Size: 100, Mod: 1}
	d := NewDebouncer(3*time.Second, start)
	if d.Observe(start, at(0)) || d.Observe(start, at(10)) {
		t.Fatal("reported an unchanged file")
	}
	// The game writes: size and time change over a few polls.
	steps := []Sig{{true, 50, 2}, {true, 120, 3}, {true, 180, 4}}
	for i, s := range steps {
		if d.Observe(s, at(11+i)) {
			t.Fatalf("reported while still changing (step %d)", i)
		}
	}
	final := steps[len(steps)-1]
	if d.Observe(final, at(14)) || d.Observe(final, at(15)) {
		t.Fatal("reported before the settle time")
	}
	if !d.Observe(final, at(16)) {
		t.Fatal("not reported after the settle time")
	}
	if d.Observe(final, at(17)) || d.Observe(final, at(60)) {
		t.Fatal("reported twice")
	}
}

func TestDebounceOneReportForABurst(t *testing.T) {
	d := NewDebouncer(2*time.Second, Sig{Exists: true, Size: 1, Mod: 1})
	reports := 0
	sig := Sig{Exists: true, Size: 1, Mod: 1}
	for s := 0; s < 30; s++ {
		if s < 10 { // a change every second for 10 s
			sig = Sig{Exists: true, Size: int64(s + 2), Mod: int64(s + 2)}
		}
		if d.Observe(sig, at(s)) {
			reports++
		}
	}
	if reports != 1 {
		t.Errorf("%d reports, want 1", reports)
	}
}

func TestDebounceChangeBackIsNoChange(t *testing.T) {
	start := Sig{Exists: true, Size: 10, Mod: 5}
	d := NewDebouncer(time.Second, start)
	d.Observe(Sig{}, at(1)) // briefly missing (replaced)
	d.Observe(start, at(2))
	if d.Observe(start, at(10)) {
		t.Error("reported a file that ended as it started")
	}
	// Missing file: nothing; it comes back changed: reported.
	d.Observe(Sig{}, at(11))
	if d.Observe(Sig{}, at(20)) {
		t.Error("reported a missing file")
	}
	back := Sig{Exists: true, Size: 11, Mod: 6}
	d.Observe(back, at(21))
	if !d.Observe(back, at(22)) {
		t.Error("file that came back not reported")
	}
}

func TestDebounceRetry(t *testing.T) {
	s := Sig{Exists: true, Size: 10, Mod: 5}
	d := NewDebouncer(2*time.Second, Sig{})
	d.Observe(s, at(0))
	if !d.Observe(s, at(2)) {
		t.Fatal("not reported")
	}
	d.Retry(at(3))
	if d.Observe(s, at(4)) {
		t.Error("retry reported before the settle time")
	}
	if !d.Observe(s, at(5)) {
		t.Error("retry not reported")
	}
}

func TestWatcherOnRealFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "CraftWise.lua")
	if err := os.WriteFile(path, []byte("A = 1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	w := New(path, 10*time.Millisecond, 50*time.Millisecond)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	select {
	case <-w.C:
		t.Fatal("reported the file as it was at start")
	case <-time.After(150 * time.Millisecond):
	}
	if err := os.WriteFile(path, []byte("A = 22\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	select {
	case <-w.C:
	case <-time.After(2 * time.Second):
		t.Fatal("change not reported")
	}
}
